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

-- ---------- beta testers: section numbers (1a, 2b, ...) shown in the app ----------
-- profiles.beta: only the admin can change it (set_user_beta); users can read their own row but can't update profiles at all.
-- Added 2026-11-18. The first time the column is created, everyone already approved (the invited testers, incl. the admin) becomes a beta tester.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'beta') then
    alter table public.profiles add column beta boolean not null default false;
    update public.profiles set beta = true where status = 'approved';
  end if;
end $$;
create or replace function public.set_user_beta(target_id uuid, beta_on boolean) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  update public.profiles set beta = coalesce(beta_on, false) where id = target_id returning * into p;
  if p.id is null then raise exception 'no such user'; end if;
  return p;
end $$;
revoke all on function public.set_user_beta(uuid, boolean) from public, anon;
grant execute on function public.set_user_beta(uuid, boolean) to authenticated;

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
--   update public.profiles set role = 'admin', status = 'approved', beta = true, decided_at = now() where username = 'zee';
--   select username, status, role from public.profiles;

-- Pin search_path on trigger function (Supabase advisor)
alter function public.user_records_before_write() set search_path = public, pg_temp;

-- ---------- beta suggestions (testers send notes to the admin) ----------
-- Screenshots live in the private Storage bucket 'suggestions' (per-user folders).
-- Only approved signed-in users can insert their own rows and upload files.
-- Only an approved admin can select or update suggestions, or read screenshots.
-- Push subscriptions are admin-only. The notify trigger calls the notify-suggestion
-- Edge Function via pg_net when Vault has project_url + suggestion_webhook_secret.
-- Those Vault secrets are set once on the hosted project (not in this file).

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.suggestions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade default auth.uid(),
  username        text not null,
  section         text not null check (char_length(section) between 1 and 80),
  message         text not null check (char_length(message) between 1 and 4000),
  screenshot_path text check (screenshot_path is null or char_length(screenshot_path) between 1 and 400),
  created_at      timestamptz not null default now(),
  read_at         timestamptz
);
create index if not exists suggestions_created on public.suggestions (created_at desc);
create index if not exists suggestions_unread on public.suggestions (created_at desc) where read_at is null;

create table if not exists public.push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  endpoint   text not null unique check (char_length(endpoint) between 8 and 2000),
  p256dh     text not null check (char_length(p256dh) between 8 and 200),
  auth       text not null check (char_length(auth) between 8 and 200),
  user_agent text not null default '' check (char_length(user_agent) <= 400),
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create index if not exists push_subscriptions_user on public.push_subscriptions (user_id);

create or replace function public.suggestions_before_write() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare uname text;
begin
  if not public.is_approved() then raise exception 'not approved' using errcode = '42501'; end if;
  new.user_id := auth.uid();
  select username into uname from public.profiles where id = auth.uid();
  if uname is null then raise exception 'no profile' using errcode = '42501'; end if;
  new.username := uname;
  new.section := left(btrim(new.section), 80);
  new.message := left(btrim(new.message), 4000);
  if new.section = '' or new.message = '' then raise exception 'section and message are required'; end if;
  new.created_at := now();
  new.read_at := null;
  if new.screenshot_path is not null and new.screenshot_path !~ ('^' || auth.uid()::text || '/[A-Za-z0-9._-]+$') then
    raise exception 'bad screenshot path' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists suggestions_bw on public.suggestions;
create trigger suggestions_bw before insert on public.suggestions for each row execute function public.suggestions_before_write();

-- Admins may only change read_at (mark read / unread). Everything else stays as submitted.
create or replace function public.suggestions_before_update() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  new.id := old.id;
  new.user_id := old.user_id;
  new.username := old.username;
  new.section := old.section;
  new.message := old.message;
  new.screenshot_path := old.screenshot_path;
  new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists suggestions_bu on public.suggestions;
create trigger suggestions_bu before update on public.suggestions for each row execute function public.suggestions_before_update();
revoke all on function public.suggestions_before_write() from public, anon, authenticated;
revoke all on function public.suggestions_before_update() from public, anon, authenticated;

alter table public.suggestions enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "suggestions: approved user inserts own" on public.suggestions;
create policy "suggestions: approved user inserts own" on public.suggestions for insert to authenticated
  with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "suggestions: admins read all" on public.suggestions;
create policy "suggestions: admins read all" on public.suggestions for select to authenticated
  using (public.is_admin());
drop policy if exists "suggestions: admins update read_at" on public.suggestions;
create policy "suggestions: admins update read_at" on public.suggestions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "push: admin reads own" on public.push_subscriptions;
create policy "push: admin reads own" on public.push_subscriptions for select to authenticated
  using (public.is_admin() and user_id = auth.uid());
drop policy if exists "push: admin inserts own" on public.push_subscriptions;
create policy "push: admin inserts own" on public.push_subscriptions for insert to authenticated
  with check (public.is_admin() and user_id = auth.uid());
drop policy if exists "push: admin updates own" on public.push_subscriptions;
create policy "push: admin updates own" on public.push_subscriptions for update to authenticated
  using (public.is_admin() and user_id = auth.uid()) with check (public.is_admin() and user_id = auth.uid());
drop policy if exists "push: admin deletes own" on public.push_subscriptions;
create policy "push: admin deletes own" on public.push_subscriptions for delete to authenticated
  using (public.is_admin() and user_id = auth.uid());

revoke all on public.suggestions from anon;
revoke all on public.push_subscriptions from anon;
grant insert, select, update on public.suggestions to authenticated;
grant select, insert, update, delete on public.push_subscriptions to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant all on table public.suggestions, public.push_subscriptions to service_role;
  end if;
end $$;


-- Realtime (hosted project only; no-op when the publication is missing, e.g. local schema tests)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.suggestions';
    exception when duplicate_object then null;
    end;
  end if;
end $$;

-- Private screenshot bucket. Upload: approved owner, own folder. Read: admin only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('suggestions', 'suggestions', false, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set public = false, file_size_limit = 8388608, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];

drop policy if exists "suggestions files: approved owner uploads" on storage.objects;
create policy "suggestions files: approved owner uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'suggestions' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());
drop policy if exists "suggestions files: admins read" on storage.objects;
create policy "suggestions files: admins read" on storage.objects for select to authenticated
  using (bucket_id = 'suggestions' and public.is_admin());
drop policy if exists "suggestions files: approved owner deletes own" on storage.objects;
create policy "suggestions files: approved owner deletes own" on storage.objects for delete to authenticated
  using (bucket_id = 'suggestions' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());

-- Service-role helpers for the Edge Function (Vault keys are never granted to anon/authenticated)
create or replace function private.get_suggestion_webhook_secret() returns text
language plpgsql security definer set search_path = pg_temp as $$
declare s text;
begin
  begin
    execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into s using 'suggestion_webhook_secret';
  exception when undefined_table or undefined_object or invalid_schema_name then
    return null;
  end;
  return s;
end $$;
create or replace function private.get_vapid_keys() returns table (public_key text, private_key text)
language plpgsql security definer set search_path = pg_temp as $$
begin
  begin
    return query execute $q$
      select
        (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public_key' limit 1),
        (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private_key' limit 1)
    $q$;
  exception when undefined_table or undefined_object or invalid_schema_name then
    return query select null::text, null::text;
  end;
end $$;
create or replace function private.set_vapid_keys(new_public text, new_private text) returns text
language plpgsql security definer set search_path = pg_temp as $$
declare existing text;
begin
  if new_public is null or new_private is null or length(new_public) < 20 or length(new_private) < 20 then
    raise exception 'bad vapid keys';
  end if;
  begin
    execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into existing using 'vapid_public_key';
  exception when undefined_table or undefined_object or invalid_schema_name then
    return null;
  end;
  if existing is not null then return existing; end if;
  execute 'select vault.create_secret($1, $2)' using new_public, 'vapid_public_key';
  execute 'select vault.create_secret($1, $2)' using new_private, 'vapid_private_key';
  return new_public;
end $$;
revoke all on function private.get_suggestion_webhook_secret() from public, anon, authenticated;
revoke all on function private.get_vapid_keys() from public, anon, authenticated;
revoke all on function private.set_vapid_keys(text, text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema private to service_role;
    grant execute on function private.get_suggestion_webhook_secret() to service_role;
    grant execute on function private.get_vapid_keys() to service_role;
    grant execute on function private.set_vapid_keys(text, text) to service_role;
  end if;
end $$;

-- After insert: notify the Edge Function (no-op if pg_net or Vault secrets are missing)
create or replace function public.notify_suggestion_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare proj text; secret text;
begin
  begin
    execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into proj using 'project_url';
    execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into secret using 'suggestion_webhook_secret';
  exception when undefined_table or undefined_object or invalid_schema_name then
    return new;
  end;
  if proj is null or secret is null or to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') is null then
    return new;
  end if;
  perform net.http_post(
    url := rtrim(proj, '/') || '/functions/v1/notify-suggestion',
    body := jsonb_build_object(
      'type', tg_op, 'table', tg_table_name, 'schema', tg_table_schema,
      'record', to_jsonb(new), 'old_record', null
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 4000
  );
  return new;
end $$;
revoke all on function public.notify_suggestion_push() from public, anon, authenticated;
drop trigger if exists suggestions_notify_push on public.suggestions;
create trigger suggestions_notify_push after insert on public.suggestions
  for each row execute function public.notify_suggestion_push();
