-- =====================================================================
-- KK Umbrellas · Manager Daily Task Tracker
-- Run this once in Supabase → SQL Editor (new project or existing one).
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE where possible.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- Factory "today" is always India time, whatever the server clock says.
create or replace function public.ist_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;

-- ---------------------------------------------------------------------
-- 1. People: one row per login (managers + admin)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text not null,
  email        text,                       -- login email (synthetic for managers)
  role         text not null default 'manager' check (role in ('manager','admin')),
  department   text,                       -- unit / department the manager runs
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- Emails that become admin automatically when their account is created.
create or replace function public.admin_emails() returns text[]
language sql immutable as $$ select array['kkumbrellas@gmail.com'] $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role, department)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    new.email,
    case when lower(new.email) = any (public.admin_emails()) then 'admin' else 'manager' end,
    new.raw_user_meta_data->>'department'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and active)
$$;

-- Login screen needs the list of manager names before anyone is signed in.
-- Only names + login emails are exposed, nothing else.
create or replace function public.list_managers()
returns table (id uuid, full_name text, login_email text, department text)
language sql stable security definer set search_path = public as $$
  select id, full_name, email, department
  from public.profiles
  where role = 'manager' and active
  order by full_name
$$;
grant execute on function public.list_managers() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Tasks assigned to managers
--    task_type:
--      daily     – every day from start_date
--      recurring – weekly or monthly (repeat_unit), on repeat_days,
--                  every repeat_every weeks/months (2 = fortnightly, 3 = quarterly…)
--      adhoc     – one-off, due on due_date, carries over until done
--      project   – milestone of a project (project_name), due on due_date
-- ---------------------------------------------------------------------
create table if not exists public.tasks (
  id            uuid primary key default gen_random_uuid(),
  manager_id    uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  description   text,
  task_type     text not null check (task_type in ('daily','recurring','adhoc','project')),
  repeat_unit   text check (repeat_unit in ('weekly','monthly')),
  repeat_days   int[],          -- weekly: 0=Sun … 6=Sat · monthly: 1…31 (31 = last day)
  repeat_every  int not null default 1 check (repeat_every between 1 and 12),
  project_name  text,
  priority      text not null default 'normal' check (priority in ('low','normal','high')),
  target_time   time,           -- "should be done by" (optional)
  start_date    date not null default public.ist_today(),
  due_date      date,           -- adhoc / project
  end_date      date,           -- optional stop date for daily / recurring
  sort_order    int not null default 0,
  active        boolean not null default true,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint recurring_needs_rule check (
    task_type <> 'recurring' or (repeat_unit is not null and coalesce(array_length(repeat_days,1),0) > 0)
  ),
  constraint oneoff_needs_due check (task_type not in ('adhoc','project') or due_date is not null)
);
create index if not exists tasks_manager_idx on public.tasks (manager_id) where active;

-- ---------------------------------------------------------------------
-- 3. Completions: one row per task per day it was done
--    entry_mode 'tick'   = ticked live in the app (time = when ticked)
--    entry_mode 'manual' = manager typed the time it was actually done
-- ---------------------------------------------------------------------
create table if not exists public.task_completions (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references public.tasks(id) on delete cascade,
  manager_id    uuid not null references public.profiles(id) on delete cascade,
  for_date      date not null,
  completed_at  timestamptz not null default now(),
  entry_mode    text not null default 'tick' check (entry_mode in ('tick','manual')),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (task_id, for_date)
);
create index if not exists completions_mgr_date_idx on public.task_completions (manager_id, for_date);

-- ---------------------------------------------------------------------
-- 4. End-of-day cleanliness photos of each manager's unit
-- ---------------------------------------------------------------------
create table if not exists public.unit_photos (
  id            uuid primary key default gen_random_uuid(),
  manager_id    uuid not null references public.profiles(id) on delete cascade,
  for_date      date not null default public.ist_today(),
  storage_path  text not null,
  caption       text,
  created_at    timestamptz not null default now()
);
create index if not exists photos_mgr_date_idx on public.unit_photos (manager_id, for_date);

-- keep updated_at fresh
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch before update on public.tasks for each row execute function public.touch_updated_at();
drop trigger if exists completions_touch on public.task_completions;
create trigger completions_touch before update on public.task_completions for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- 5. Row-level security
--    Managers see and write only their own rows; admin sees everything.
--    Managers can fill / correct entries for today and the previous 7 days.
-- ---------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.tasks             enable row level security;
alter table public.task_completions  enable row level security;
alter table public.unit_photos       enable row level security;

drop policy if exists profiles_read  on public.profiles;
drop policy if exists profiles_admin on public.profiles;
create policy profiles_read  on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_admin on public.profiles for all    using (public.is_admin()) with check (public.is_admin());

drop policy if exists tasks_read  on public.tasks;
drop policy if exists tasks_admin on public.tasks;
create policy tasks_read  on public.tasks for select using (manager_id = auth.uid() or public.is_admin());
create policy tasks_admin on public.tasks for all    using (public.is_admin()) with check (public.is_admin());

drop policy if exists comp_read   on public.task_completions;
drop policy if exists comp_insert on public.task_completions;
drop policy if exists comp_update on public.task_completions;
drop policy if exists comp_delete on public.task_completions;
drop policy if exists comp_admin  on public.task_completions;
create policy comp_read on public.task_completions for select
  using (manager_id = auth.uid() or public.is_admin());
create policy comp_insert on public.task_completions for insert
  with check (
    manager_id = auth.uid()
    and for_date between public.ist_today() - 7 and public.ist_today()
    and exists (select 1 from public.tasks t where t.id = task_id and t.manager_id = auth.uid())
  );
create policy comp_update on public.task_completions for update
  using (manager_id = auth.uid() and for_date >= public.ist_today() - 7)
  with check (manager_id = auth.uid() and for_date between public.ist_today() - 7 and public.ist_today());
create policy comp_delete on public.task_completions for delete
  using (manager_id = auth.uid() and for_date >= public.ist_today() - 7);
create policy comp_admin on public.task_completions for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists photo_read   on public.unit_photos;
drop policy if exists photo_insert on public.unit_photos;
drop policy if exists photo_delete on public.unit_photos;
drop policy if exists photo_admin  on public.unit_photos;
create policy photo_read   on public.unit_photos for select using (manager_id = auth.uid() or public.is_admin());
create policy photo_insert on public.unit_photos for insert
  with check (manager_id = auth.uid() and for_date = public.ist_today());
create policy photo_delete on public.unit_photos for delete
  using (manager_id = auth.uid() and for_date = public.ist_today());
create policy photo_admin  on public.unit_photos for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. Photo storage bucket (private). Files live at  <manager_id>/<date>/<file>.jpg
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('unit-photos', 'unit-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists unit_photos_read   on storage.objects;
drop policy if exists unit_photos_upload on storage.objects;
drop policy if exists unit_photos_delete on storage.objects;
create policy unit_photos_read on storage.objects for select
  using (bucket_id = 'unit-photos'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy unit_photos_upload on storage.objects for insert
  with check (bucket_id = 'unit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy unit_photos_delete on storage.objects for delete
  using (bucket_id = 'unit-photos'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
