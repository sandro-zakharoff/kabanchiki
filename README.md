# Kabanchiki

A family task-and-reward system. Parents (owners) hand out tasks and hourly jobs
from a Windows app or a Telegram Mini App; children (assignees) complete them in
an Android app and earn acorns — the app's own currency, always whole.
Everything syncs in real time through Supabase, with push notifications and
server-authoritative timers.

The apps ship in English and Ukrainian.

## The three apps

| Folder | App | Stack |
|---|---|---|
| [`desktop/`](desktop/) | Owner app — the control center | Python + PySide6 (QML), Windows |
| [`android/`](android/) | Assignee app | Kotlin + Jetpack Compose, APK |
| [`telegram/`](telegram/) | Owner Mini App | Vanilla JS + Telegram WebApp SDK, static hosting |
| [`supabase/`](supabase/) | Backend | Postgres migrations, RLS, RPC, Edge Functions |

## Architecture principles

- **The server is the source of truth.** Timers and money are computed only from
  database timestamps against the server clock (`server_now()`). Clients merely
  render the ticking values, so a closed app never breaks anything.
- **Assignees never write to tables directly.** Every child action goes through a
  SECURITY DEFINER RPC with checks in Postgres, so a rate or a payout amount can
  never be forged.
- **Row-level security everywhere.** Children see only their own rows. Owners
  sign in with email and password and act through parent RLS; the privileged
  `service_role` key stays on the server, never on a client.
- **Personal balances on an append-only ledger.** Every credit and debit is a
  ledger entry — balances are always reconstructable and auditable.
- **Push via an outbox.** Database triggers write to `notifications_outbox`; a
  webhook calls the `send-push` Edge Function, which sends an FCM data message
  the app renders itself (localized, with the channel's custom sound).

## Self-hosting

Kabanchiki runs entirely on your own accounts — no source edits required. The
desktop app asks for your Supabase project on first run and tests the connection
before saving.

Start here: **[docs/self-hosting.md](docs/self-hosting.md)**.

## Using the apps

See the **[user guide](docs/user-guide.md)** for how tasks, hourly jobs,
approvals, balances and payouts work across the three apps.

## Developing

- Desktop: Python 3.13+, `pip install -r desktop/requirements.txt`, then
  `python desktop/src/main.py`.
- Android: JDK 17 and Android SDK Platform 35; build with `android/gradlew`.
- Backend: Supabase CLI 2.x for migrations and Edge Functions.
- Run every check locally with `pwsh -File scripts/check.ps1` (lint, format,
  tests, secret scan).

More in **[docs/developer/](docs/developer/)**. Full documentation index:
**[docs/README.md](docs/README.md)**.

## License and attribution

© Oleksandr Zakharov (Zakharoff).
