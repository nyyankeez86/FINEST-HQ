# Patrol Schedule: go-live setup

Short steps you can do on a phone. Nothing has been created, deployed or pushed for you.
Until config.js is filled in (step 3), the app runs **local-only**: no sign-in, nothing leaves the phone.

## 1. Create a Supabase project
1. Go to **supabase.com** → sign in → **New project**.
2. Name: `patrol-schedule`. Region: **East US (North Virginia)**. Free plan is fine.
3. Tap **Generate a password**, save it in your password manager.
4. Under **Security options**, leave **Enable Data API** ON.
5. Tap **Create new project**. Wait about 2 minutes.

## 2. Run schema.sql
1. Left menu → **SQL Editor** → **+ New query**.
2. Paste the **whole** `supabase/schema.sql` file.
3. Tap **Run**. Expect "Success. No rows returned".
   It's safe to run again later (it never deletes users or data).

## 3. Copy the Project URL and the public key into config.js
1. **Project Settings** (gear icon) → **Data API** (older menus: **API**) → copy the **Project URL**.
2. **Project Settings** → **API Keys** → copy the **Publishable key** (`sb_publishable_...`).
   If you only see "Legacy API keys", copy the **anon public** key instead. Both work.
   **Never** copy the **secret** or **service_role** key. The app refuses to use it.
3. Open `site/config.js`. It's the only file with these values. Replace the two placeholders:
   ```js
   SUPABASE_URL: 'https://<your-project>.supabase.co',   // <-- 1. Project URL
   SUPABASE_ANON_KEY: 'sb_publishable_...',             // <-- 2. Publishable / anon public key
   ```
   Leave `USERNAME_EMAIL_DOMAIN` as it is.

## 4. Auth settings
1. Left menu → **Authentication** → **Sign In / Providers**.
   - **Allow new users to sign up**: **ON** ("Request beta access" uses it; new accounts start *pending* and see no data).
   - **Confirm email**: **OFF**. Tap **Save**.
     Why: usernames become `username@users.patrol-schedule.invalid`, which can't receive mail. With Confirm email
     on, sign-up would try to send a confirmation and fail.
   - **Allow anonymous sign-ins**: leave **OFF**.
   - Under **Email**, keep the provider **enabled**.
2. **Authentication** → **URL Configuration** → **Site URL**: your GitHub Pages address,
   e.g. `https://<github-user>.github.io/<repo>/`. Tap **Save**.

## 5. Make Zee admin (after signing up)
1. Open the app → **Request beta access** → pick your username (e.g. `zee`) and a password (8+ characters).
   You'll see "Waiting for approval".
2. Supabase → **SQL Editor** → **+ New query** → paste (change `zee` if you picked another username) → **Run**:
   ```sql
   update public.profiles set role = 'admin', status = 'approved', decided_at = now() where username = 'zee';
   select username, status, role from public.profiles;
   ```
   The result should show `zee | approved | admin`.
3. In the app tap **Check again**. Then **Settings → Account → Admin: beta users** lists requests with **Approve / Deny**
   (and **Revoke** for approved users).

## 6. Publish on GitHub Pages
1. Upload the **contents of `site/`** to a GitHub repo: `index.html`, `config.js`, `manifest.webmanifest`, `sw.js`,
   `icons/`, `.nojekyll` (the other files are optional).
2. Repo **Settings → Pages → Deploy from a branch** → branch `main`, folder `/ (root)` → **Save**.
3. On the iPhone open the Pages URL in Safari → **Share → Add to Home Screen**.
4. After any change to `index.html`, run `node tools/build-site.js` again (it keeps your `config.js`) and re-upload `index.html` and `sw.js`.

## What leaves the phone
- **Synced** (approved users only, only to your Supabase project, only their own rows): schedule, overrides,
  assignments, OT, leave, settings and slip PDFs.
- **Never synced:** tax number, reference number, shield number, home address and Google Maps key. The app strips
  them, and the database strips them again if they ever arrive.
- **Nobody sees anyone else's data**, admin included. The admin only sees usernames, names, commands and status.
- **Address autocomplete** sends only the text typed in an address field:
  - NYC GeoSearch (NYC Planning, free, no key).
  - Photon / OpenStreetMap, only when NYC has fewer than 5 matches. Free, "please be fair".
  - Google Places, only if you add your own Maps key in Settings.
