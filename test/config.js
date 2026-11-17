// =====================================================================================================
//  PATROL SCHEDULE: CLOUD CONFIG. THIS IS THE ONLY PLACE TO PUT THE SUPABASE VALUES.
//  Paste the two values from Supabase (SETUP.md, step 3) between the quotes, replacing the YOUR-... text.
//    SUPABASE_URL       Project URL, like https://abcdefghijklmnop.supabase.co
//    SUPABASE_ANON_KEY  the PUBLIC key: "Publishable key" (sb_publishable_...) or the legacy "anon public" key (eyJ...)
//  NEVER paste the secret / service_role key here.
//  The public key is meant to be in the app: Row Level Security in supabase/schema.sql protects the data.
//  While these still say YOUR-..., the app runs local-only (no sign-in, nothing leaves the device).
// =====================================================================================================
window.PATROL_CLOUD = {
  SUPABASE_URL: 'https://lgcsfdfdkzrzcefhpsqv.supabase.co',   // <-- 1. Project URL
  SUPABASE_ANON_KEY: 'sb_publishable_rIVT3EukkFgR7FCalcMkXw_ZxTH4zSR',                 // <-- 2. Publishable / anon public key
  // Leave this as is. Usernames become <username>@<this domain> for Supabase Auth; ".invalid" can never receive mail.
  USERNAME_EMAIL_DOMAIN: 'users.patrol-schedule.invalid'
};
