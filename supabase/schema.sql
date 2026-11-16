-- Patrol Schedule: beta accounts with approval + cloud saving (Supabase / Postgres)
-- Run this whole file once in Supabase -> SQL Editor -> New query -> Run. It is safe to run again (idempotent).
-- What it creates:
--   * public.profiles      one row per account: username, status (pending/approved/denied/revoked), role (user/admin)
--   * public.user_records  each user's synced entries (one row per record, last-write-wins by client timestamp)
--   * a trigger that creates a 'pending' profile when someone requests beta access (signs up)
--   * Row Level Security: only APPROVED users can read/write THEIR OWN data; only admins can change approval status
--   * private Storage bucket 'slips' (court / certification slip PDFs) with per-user folders
--   * functions: push_records (sync upload), set_user_status (admin only)
-- Privacy: the app never sends tax number, reference number, shield number, home address or the Google Maps key.
--          As a second line of defence, a trigger strips the profile fields if they ever arrive.

-- ---------- tables ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,23}$'),
  full_name   text not null default '' check (char_length(full_name) <= 80),
  command     text not null default '' check (char_length(command) <= 120),
  status      text not null default 'pending' check (status in ('pending', 'approved', 'denied', 'revoked')),
  role        text not null default 'user' check (role in ('user', 'admin')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid references auth.users(id)
);

create table if not exists public.user_records (
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  kind       text not null check (kind ~ '^[a-z0-9_]{1,24}$'),
  key        text not null check (char_length(key) between 1 and 120),
  data       jsonb,
  deleted    boolean not null default false,
  client_ts  bigint not null,                      -- client clock (ms) of the last edit: decides last-write-wins
  server_ts  timestamptz not null default now(),   -- set by the server on every write: used as the pull cursor
  primary key (user_id, kind, key)
);
create index if not exists user_records_pull on public.user_records (user_id, server_ts);

-- ---------- helper functions (security definer so policies can use them without recursion) ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and status = 'approved');
$$;
create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'approved');
$$;

-- ---------- new sign-up -> pending profile ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare u text := lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)));
begin
  insert into public.profiles (id, username, full_name, command, status, role)
  values (new.id, u,
          left(coalesce(new.raw_user_meta_data->>'full_name', ''), 80),
          left(coalesce(new.raw_user_meta_data->>'command', ''), 120),
          'pending', 'user');                       -- everyone starts pending; nobody can sign up as admin
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- record writes: server timestamp + privacy scrub ----------
create or replace function public.user_records_before_write() returns trigger
language plpgsql as $$
begin
  new.server_ts := clock_timestamp();
  if new.kind = 'profile' and new.data is not null then
    new.data := new.data - 'taxNumber' - 'refNumber' - 'shieldNumber' - 'homeAddress';
  end if;
  if new.kind = 'settings' and new.data is not null then
    new.data := new.data - 'mapsKey';
  end if;
  return new;
end $$;
drop trigger if exists user_records_bw on public.user_records;
create trigger user_records_bw before insert or update on public.user_records for each row execute function public.user_records_before_write();

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.user_records enable row level security;

drop policy if exists "profiles: read own" on public.profiles;
create policy "profiles: read own" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "profiles: admins read all" on public.profiles;
create policy "profiles: admins read all" on public.profiles for select to authenticated using (public.is_admin());
-- No insert/update/delete policies on profiles: rows are created by the trigger, status/role change only through set_user_status (admins).

drop policy if exists "records: approved owner reads" on public.user_records;
create policy "records: approved owner reads" on public.user_records for select to authenticated using (user_id = auth.uid() and public.is_approved());
drop policy if exists "records: approved owner inserts" on public.user_records;
create policy "records: approved owner inserts" on public.user_records for insert to authenticated with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "records: approved owner updates" on public.user_records;
create policy "records: approved owner updates" on public.user_records for update to authenticated using (user_id = auth.uid() and public.is_approved()) with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "records: approved owner deletes" on public.user_records;
create policy "records: approved owner deletes" on public.user_records for delete to authenticated using (user_id = auth.uid() and public.is_approved());

revoke all on public.profiles from anon;
revoke all on public.user_records from anon;
revoke insert, update, delete, truncate, references, trigger on public.profiles from authenticated; -- Supabase grants everything by default
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.user_records to authenticated;

-- ---------- sync upload: last-write-wins per record ----------
-- records: [{ "kind": "...", "key": "...", "data": {...} | null, "deleted": false, "client_ts": 1731740000000 }, ...]
-- A row is written only if it is newer than (or as new as) what the server has. Returns what was applied.
create or replace function public.push_records(records jsonb)
returns table (kind text, key text, applied boolean, client_ts bigint)
language plpgsql security invoker set search_path = public as $$
#variable_conflict use_column
declare r jsonb; n int;
begin
  if not public.is_approved() then raise exception 'not approved' using errcode = '42501'; end if;
  if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) > 500 then raise exception 'bad batch'; end if;
  for r in select * from jsonb_array_elements(records) loop
    insert into public.user_records as t (user_id, kind, key, data, deleted, client_ts)
    values (auth.uid(), r->>'kind', r->>'key', case when coalesce((r->>'deleted')::boolean, false) then null else r->'data' end,
            coalesce((r->>'deleted')::boolean, false), (r->>'client_ts')::bigint)
    on conflict (user_id, kind, key) do update
      set data = excluded.data, deleted = excluded.deleted, client_ts = excluded.client_ts
      where t.client_ts <= excluded.client_ts;
    get diagnostics n = row_count;
    kind := r->>'kind'; key := r->>'key'; applied := n > 0; client_ts := (r->>'client_ts')::bigint;
    return next;
  end loop;
end $$;
revoke all on function public.push_records(jsonb) from public, anon;
grant execute on function public.push_records(jsonb) to authenticated;

-- ---------- admin ----------
create or replace function public.set_user_status(target_id uuid, new_status text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  if new_status not in ('pending', 'approved', 'denied', 'revoked') then raise exception 'bad status'; end if;
  if target_id = auth.uid() then raise exception 'you cannot change your own status'; end if;
  update public.profiles set status = new_status, decided_at = now(), decided_by = auth.uid() where id = target_id returning * into p;
  if p.id is null then raise exception 'no such user'; end if;
  return p;
end $$;
revoke all on function public.set_user_status(uuid, text) from public, anon;
grant execute on function public.set_user_status(uuid, text) to authenticated;

-- ---------- slips: private Storage bucket, one folder per user (<user id>/<date>.pdf) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('slips', 'slips', false, 10485760, array['application/pdf', 'image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 10485760, allowed_mime_types = array['application/pdf', 'image/jpeg'];

drop policy if exists "slips: approved owner reads" on storage.objects;
create policy "slips: approved owner reads" on storage.objects for select to authenticated
  using (bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());
drop policy if exists "slips: approved owner uploads" on storage.objects;
create policy "slips: approved owner uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());
drop policy if exists "slips: approved owner updates" on storage.objects;
create policy "slips: approved owner updates" on storage.objects for update to authenticated
  using (bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved())
  with check (bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());
drop policy if exists "slips: approved owner deletes" on storage.objects;
create policy "slips: approved owner deletes" on storage.objects for delete to authenticated
  using (bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());

-- ---------- make the owner an admin (run AFTER you have requested access in the app with your username) ----------
-- Replace zee with your username, then run just these two lines:
--   update public.profiles set role = 'admin', status = 'approved', decided_at = now() where username = 'zee';
--   select username, status, role from public.profiles;

-- Pin search_path on trigger function (Supabase advisor)
alter function public.user_records_before_write() set search_path = public, pg_temp;
