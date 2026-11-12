# KK Daily Tasks — managers' daily task tracker

A phone-first web app for the 18 floor managers at Kendo Sales, plus an admin dashboard.
Same stack as the KK ERP: **GitHub** (code) + **Supabase** (database, logins, photo storage) + **Cloudflare Pages** (hosting). Free tiers are enough.

**Demo mode:** add `?demo` to the app's address to try it with sample data (any PIN works).

## What's in the folder

| File | What it is |
|---|---|
| `index.html` | The whole app (manager screens + admin). Hosted on Cloudflare Pages. |
| `supabase/schema.sql` | Tables, security rules, photo bucket. Run once. |
| `supabase/admin-functions.sql` | Admin tools: add manager, new PIN, switch login off. Run once. |
| `supabase/setup-accounts.sql` | Creates the admin login + all 18 manager logins and shows their PINs. Run once. |
| `supabase/load-tasks-from-sop.sql` | Loads every task from the SOP - FACTORY sheet (TASK LISTS tab) as daily tasks. Safe to re-run. |

## How it works

**Managers** open the link on their phone, pick their name, enter their 6-digit PIN.
- The umbrella at the top fills one panel per task done; next to it: "X tasks left today".
- Tap a task → **Done now** (records the current time) or enter the time it was actually done.
- Earlier days: if anything from the last 7 days wasn't filled in, a banner says how many and opens that day. Past days need a time entered; entries made on a later day are flagged "Entered late" to the admin.
- **Unit photos** tab: opens the phone camera; photos are shrunk before upload. After 4 pm the tab shows a "!" if no photo yet.
- Each manager only ever sees his own tasks and photos (enforced in the database, not just the screen).

**Admin** (`kkumbrellas@gmail.com` + password):
- **Overview** — any date: % done, tasks left, who finished everything, who sent a unit photo, 7- or 30-day completion per manager, late entries. Lowest performers at the top. Click a manager for a 30-day chart, task-by-task reliability and usual completion time, and 14 days of photos.
- **Tasks** — assign to one, several or all managers at once:
  - **Daily** — every day (optional end date, optional "done by" time)
  - **Recurring** — weekly on chosen days, or monthly on chosen dates (incl. "last day"), every 1/2/4 weeks or 1/2/3/6/12 months
  - **One-off** (ad-hoc) — due on a date; carries over as "overdue" until done
  - **Project** — milestone with a project name and due date (e.g. *New KK website → Shortlist vendors*)
  - **Add many at once** — paste one task per line (`Check attendance | 09:30`) to set up daily lists quickly.
  - Pause a task (keeps history) or delete it.
- **Unit photos** — all photos for a date, grouped by manager, with the list of units missing a photo.
- **Managers** — set departments, add a manager (PIN generated and shown once), give a new PIN, switch a login off.

## Setup (all in the Supabase dashboard, no terminal)

1. **SQL Editor → New query** → paste `supabase/schema.sql` → **Run**.
2. **New query** → paste `supabase/admin-functions.sql` → **Run**.
3. **New query** → paste `supabase/setup-accounts.sql`, replace `CHANGE-ME` with the admin password → **Run**. The results table lists every manager's PIN; copy it somewhere safe.
4. **Authentication → Sign In / Providers**: *Allow new users to sign up* OFF, *Confirm email* OFF.
5. **Cloudflare → Workers & Pages → Create → Pages → Connect to Git** → pick this repo → no build command, output directory `/` → Deploy. Every push to `main` redeploys.

## Excel import / export (admin → Tasks)

- **Export Excel** downloads the current tasks in the same layout as the SOP - FACTORY sheet: a `TASK LISTS` sheet, manager names in row 1, each manager's tasks listed under their name.
- **Import Excel** reads the `TASK LISTS` sheet of an .xlsx file, shows what will change, and applies it only when you click **Apply changes**:
  - a task in the sheet that the manager doesn't have → added as a daily task;
  - a task the manager has that's no longer in their column → deleted (its past ticks too);
  - matching ignores capitals and extra spaces; a task listed twice counts once;
  - a manager whose column is missing from the sheet is left unchanged; a column with the name but no tasks removes all of that manager's tasks;
  - names in row 1 must match the manager names in the app.
- Weekly, monthly, one-off and project tasks keep their settings as long as their name stays in the sheet.
- Any task can also be deleted with its **Delete** button (Tasks tab, or a manager's page). It disappears from that manager's list.

## Rules worth knowing
- Times are always India time, whatever the phone's clock is set to.
- Managers can fill or correct the last **7 days**; change `BACKFILL_DAYS` in `index.html` (and the `- 7` in the `comp_*` policies in `schema.sql`) to change that.
- Photos can only be added for today, and a manager can delete only today's photos. Photos are private — the admin sees them through short-lived links.
- More admins: create their login in Supabase (Authentication → Add user, tick auto-confirm), then in SQL Editor: `update profiles set role='admin' where email='them@example.com';`
- Manager logins use made-up emails like `anup.roy@staff.kkumbrellas.com`; no mail is ever sent to them.
