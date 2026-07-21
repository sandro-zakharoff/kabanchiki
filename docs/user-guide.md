# User guide

Kabanchiki is a family task-and-reward system. Parents (owners) hand out tasks
and hourly jobs; children (assignees) complete them and earn acorns — the
app's own currency, always a whole number, never a fraction. Everyone sees
the same data in real time.

The interface is available in English and Ukrainian.

## The three apps

| App | Who it's for | What it does |
|---|---|---|
| **Windows app** | Owners (parents) | The control center: manage assignees, tasks, jobs, approvals, balances, payouts and all settings |
| **Android app** | Assignees (children) | Do tasks, run the timer on hourly jobs, attach photo proof, watch the balance grow, request payouts |
| **Telegram Mini App** | Owners (parents) | The same management as the desktop, from a phone inside Telegram |

## Roles

- **Owner** — full access from the desktop app and the Telegram Mini App. Signs
  in with an email and password. A family can have several owners.
- **Assignee** — a child's account. Signs in on the Android app with a username
  and password created by an owner. Sees only their own data.

## Everyday flow

### Tasks (one-off chores)

1. An owner creates a task for an assignee, with a reward and an optional
   deadline. A task can require a timer, or be marked done in one tap.
2. The assignee does it, optionally attaches photo proof, and submits it.
3. The owner reviews: **approve** (the reward is added to the balance),
   **send back for rework**, or **decline**.

### Hourly jobs

1. An owner creates a job with an hourly rate and assigns people to it.
2. The assignee starts the timer when they begin and stops it when they finish;
   earnings accrue from the server clock, so a closed app never loses time.
3. Earnings land in the personal balance automatically.

### Balances and payouts

- Every assignee has a personal balance backed by an append-only ledger, so the
  history of every credit and debit is always visible.
- The assignee can request a payout (if enabled), or an owner can pay one out
  directly — by card (with a receipt) or in cash. The assignee confirms cash
  payouts on their phone.
- Owners can also add a manual adjustment (a bonus or a correction) with a
  required comment.

### Bonuses and the journal

- Owners can grant bonuses at any time.
- The journal shows every action across all three apps, with filters by
  assignee, type and period.

## Notifications

Assignees get push notifications (new task, approval, payout, deadline reminder)
with the app's own sound. Owners get Telegram messages for actions that need
their attention, with inline buttons to approve or pay right from the chat.

## Installing the Android app

The Android app is distributed as an APK (no Play Market needed). Install the
first APK by hand; after that the app checks for updates itself and offers an
in-app **Update** banner whenever an owner publishes a new version.
