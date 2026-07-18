# Self-hosting Kabanchiki

Kabanchiki is designed to run entirely on **your own** accounts. No data or
configuration is shared with the original developer, and no source edits are
needed — you connect your services from the apps themselves.

Each family runs its own Supabase project. That project *is* the isolation
boundary: there is no shared multi-tenant server.

## What you need

- A **Supabase** project (free plan is enough to start).
- A **Firebase** project for push notifications (optional but recommended).
- A **Telegram bot** if you want the Mini App (optional).
- A Windows PC to run the owner app and to deploy the backend once.

## Order of setup

1. **Supabase** — [setup/supabase.md](setup/supabase.md). Create the project,
   deploy the schema and Edge Functions with `supabase/deploy/deploy.ps1`, and
   create your first owner with `supabase/deploy/create_owner.ps1`.
2. **Firebase** — [setup/firebase.md](setup/firebase.md). Create the project and
   feed the service-account file to the deploy script so push works.
3. **Desktop app** — download the release, run it, and on the first screen paste
   your Supabase **Project URL** and **anon key**. The app tests the connection
   before saving, then you sign in as the owner you created.
4. **Telegram** (optional) — [setup/telegram.md](setup/telegram.md). Create a bot,
   save its token from the desktop settings, publish the Mini App, and link your
   Telegram account.
5. **Google Drive** (optional) — [setup/google-drive.md](setup/google-drive.md).
   Connect your own Drive to store photos there instead of Supabase.
6. **Android app** — hand out the APK to the assignees. Build it yourself
   ([developer/build-apk.md](developer/build-apk.md)) or share a published
   release.

## Where secrets live

- The **service_role key** and the Supabase **Access Token** are used only on the
  machine you deploy from — never shipped in any app or committed to git.
- The **Project URL** and **anon key** are public client settings (protected by
  row-level security). They are entered in the desktop first-run screen and, for
  the Mini App, either committed as `telegram/config.js` or injected at deploy
  time from the `KABANCHIKI_SUPABASE_URL` / `KABANCHIKI_SUPABASE_ANON_KEY`
  repository Variables.
- The **bot token**, **Google Drive tokens** and the **FCM service account** are
  stored server-side in Supabase (`app_secrets` / function secrets); clients
  never see them.
- The owner's **session** is kept in Windows Credential Manager on the desktop.
- The Android **signing key** stays out of git; see
  [developer/build-apk.md](developer/build-apk.md).

## Verifying a fresh install

After setup, confirm: the desktop app signs in; an assignee signs in on Android
and sees their data; a push notification arrives; and (if configured) the Mini
App opens inside Telegram. The apps never crash on missing configuration — they
guide you to the piece that is not set up yet.
