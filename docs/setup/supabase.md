# Supabase setup

Kabanchiki keeps all of your family's data in **your own** Supabase project.
Nothing is shared with anyone else — every family runs its own project.

## 1. Create the project (~5 minutes)

1. Go to <https://supabase.com> → **Start your project** and sign in.
2. **New project**:
   - **Name:** `kabanchiki` (any name works).
   - **Database Password:** choose one and store it in your password manager —
     you need it to deploy the database.
   - **Region:** pick the one closest to your family.
   - The Free plan is enough to start.
3. Wait 1–2 minutes for the project to finish provisioning.

## 2. Collect the values you need

Open **Project Settings** (the gear icon):

| Value | Where to find it | Used for |
|---|---|---|
| **Project URL** | Settings → Data API → Project URL (`https://xxxx.supabase.co`) | Entered in the desktop app's first-run screen; published to the Mini App |
| **anon / publishable key** | Settings → API Keys → `anon` `public` | Same as above. Safe to ship in a client — every table is protected by row-level security |
| **service_role / secret key** | Settings → API Keys → `service_role` `secret` | **Secret.** Only used on your machine to deploy the backend — never shipped in any app |
| **Access Token** | Account → Access Tokens → **Generate new token** | **Secret.** Lets the Supabase CLI deploy the schema and Edge Functions |

> The `service_role` key and the Access Token are secrets. They stay on the
> machine you deploy from and are never committed to git or placed in any app.

## 3. Deploy the backend

From a clean checkout, run the one-shot deploy script. It links the project,
renders the webhook trigger (with your secret), pushes every migration, sets the
function secrets and deploys the Edge Functions:

```powershell
supabase/deploy/deploy.ps1 `
    -ProjectRef  <your-project-ref> `
    -DbPassword  '<database password from step 1>' `
    -AccessToken '<access token from step 2>' `
    -FcmServiceAccountPath 'C:\path\to\firebase-adminsdk.json'
```

The Firebase service-account file is created in [firebase.md](firebase.md) (push
notifications). If you do not need push yet, you can deploy the schema alone with
`supabase db push` and add push later.

## 4. What you get

- Tables (`profiles`, `parents`, `tasks`, `jobs`, `job_members`, `job_sessions`,
  `ledger_entries`, `withdrawals`, `attachments`, `notifications_outbox`, …), all
  under row-level security.
- SECURITY DEFINER RPCs: children can only act through them (start/finish tasks,
  request withdrawals), so a rate or amount can never be forged.
- Realtime publication on the main tables.
- Storage buckets: `task-photos`, `proof-photos`, `avatars`, `app-releases`.
- Edge Functions: `send-push` (FCM), `admin`, `tg-auth`, `tg-notify`, `tg-bot`,
  `drive`.

## 5. Create the first owner

A fresh project has no owner yet. Create the first one with the CLI (it uses your
Access Token), then sign in with that email and password in the desktop app:

```powershell
supabase/deploy/create_owner.ps1 -ProjectRef <ref> -Email you@example.com
```

The script prints a one-time password; change it from the desktop app after your
first sign-in (Settings → Account → Change password).
