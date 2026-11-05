# KK Daily Tasks — managers' daily task tracker

A phone-first web app for the 18 floor managers at Kendo Sales, plus an admin dashboard.
Same stack as the KK ERP: **Supabase** (database, logins, photo storage) + **Cloudflare Pages** (hosting). Both free tiers are enough.

**Try it first without setting anything up:** open `index.html` in a browser. With no Supabase keys filled in it runs in demo mode with sample data (any PIN works; admin tab works with any password).

## What's in the folder

| File | What it is |
|---|---|
| `index.html` | The whole app (manager screens + admin). This is what gets hosted. |
| `supabase/schema.sql` | Tables, security rules, photo bucket. Run once. |
| `supabase/functions/manage-manager/index.ts` | Lets the admin add managers, reset PINs, switch logins off. |
| `scripts/create-accounts.mjs` | One-time: creates the admin login and all 18 manager logins with PINs. |

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

## Setup (about 20 minutes)

### 1. Supabase
1. Create a new project at supabase.com (region: Mumbai). Or reuse the ERP project — the table names don't clash.
2. **SQL Editor → New query** → paste all of `supabase/schema.sql` → Run.
3. **Authentication → Providers → Email**: keep Email on, turn **Confirm email off**.
4. **Authentication → Sign In / Providers**: turn **Allow new users to sign up off** (only the admin creates accounts).
5. **Project Settings → API**: copy the *Project URL*, the *anon public* key and the *service_role* key (keep that one secret).

### 2. Admin + manager logins
On your computer, in this folder:
```bash
npm install @supabase/supabase-js
SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=YOUR-SERVICE-ROLE-KEY \
ADMIN_PASSWORD='a-strong-password' \
node scripts/create-accounts.mjs
```
It prints each manager's PIN and saves `manager-pins.csv`. Hand out the PINs, then delete the file.

### 3. The admin function (for adding managers / new PINs from the app)
```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy manage-manager
```

### 4. Point the app at Supabase
In `index.html`, near the top, fill in:
```js
SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
SUPABASE_ANON_KEY: "YOUR-ANON-KEY",
```
(The anon key is meant to be public; the database rules do the protecting.)

### 5. Host on Cloudflare Pages
Cloudflare dashboard → **Workers & Pages → Create → Pages → Upload assets** → upload just `index.html` → name it e.g. `kk-tasks`. You get `https://kk-tasks.pages.dev`. Optionally attach `tasks.kkumbrellas.com`.
Or put this folder in a GitHub repo and connect it, like the ERP — every push redeploys.

On each manager's phone: open the link in Chrome → menu → **Add to Home screen**, so it opens like an app.

## Rules worth knowing
- Times are always India time, whatever the phone's clock is set to.
- Managers can fill or correct the last **7 days**; change `BACKFILL_DAYS` in `index.html` (and the `- 7` in the `comp_*` policies in `schema.sql`) to change that.
- Photos can only be added for today, and a manager can delete only today's photos. Photos are private — the admin sees them through short-lived links.
- More admins: create their login in Supabase (Authentication → Add user), then in SQL Editor: `update profiles set role='admin' where email='them@example.com';`
- Manager logins use made-up emails like `anup.roy@staff.kkumbrellas.com`; no mail is ever sent to them.
