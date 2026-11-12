-- =====================================================================
-- KK Daily Tasks · Google Sheet → app sync
-- Run once in Supabase → SQL Editor (after schema.sql and admin-functions.sql).
-- At the end it shows your SYNC CODE: paste it into the Google Apps Script.
-- Safe to re-run (the sync code stays the same).
--
-- Rules the sync follows, per manager column in the TASK LISTS sheet:
--   * task in DAILY REPETITIVE column      → daily task in the app
--   * task in NON-DAILY column             → added but hidden until the admin sets
--                                            a schedule (weekly / monthly / one-off / project)
--   * sheet task no longer in the sheet    → paused (history kept); comes back if re-added
--   * tasks created in the app             → never touched by the sync
--   * manager missing from the sheet       → left unchanged
-- =====================================================================

-- 1. Extra task columns
alter table public.tasks add column if not exists source text not null default 'app';
alter table public.tasks add column if not exists needs_schedule boolean not null default false;
alter table public.tasks add column if not exists sheet_removed boolean not null default false;
do $$ begin
  alter table public.tasks add constraint tasks_source_chk check (source in ('app','sheet'));
exception when duplicate_object then null; end $$;

-- 2. Secret sync code (readable only by these functions)
create table if not exists public.app_secrets (name text primary key, value text not null);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;
insert into public.app_secrets (name, value)
values ('sheet_sync_code', encode(extensions.gen_random_bytes(24), 'hex'))
on conflict (name) do nothing;

-- 3. Helpers
create or replace function public._kk_norm(t text) returns text
language sql immutable as $$ select lower(regexp_replace(trim(coalesce(t, '')), '\s+', ' ', 'g')) $$;

-- 4. The sync itself. p_sheet = [{"manager":"ANUP ROY","daily":[...],"nondaily":[...]}, ...]
--    p_apply = false only reports what would change (used for the preview in the app).
create or replace function public._kk_sync_tasks(p_sheet jsonb, p_apply boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  col jsonb; v_mid uuid; v_name text; v_kind text; v_title text; v_pos int; t record;
  seen text[]; done_ids uuid[] := '{}';
  m_added jsonb; m_removed jsonb; m_restored jsonb; m_needs jsonb; m_daily jsonb; m_kept int;
  out_managers jsonb := '[]'; out_unknown jsonb := '[]';
  n_added int := 0; n_removed int := 0; n_restored int := 0; n_needs int := 0; n_daily int := 0;
begin
  if p_sheet is null or jsonb_typeof(p_sheet) <> 'array' then raise exception 'The sheet data is not in the expected format.'; end if;

  for col in select value from jsonb_array_elements(p_sheet) loop
    v_name := upper(regexp_replace(trim(coalesce(col->>'manager', '')), '\s+', ' ', 'g'));
    continue when v_name = '';
    select id into v_mid from public.profiles
      where role = 'manager' and upper(regexp_replace(trim(full_name), '\s+', ' ', 'g')) = v_name;
    if v_mid is null then out_unknown := out_unknown || to_jsonb(col->>'manager'); continue; end if;
    continue when v_mid = any(done_ids);          -- same name twice: first column wins
    done_ids := done_ids || v_mid;

    seen := '{}'; v_pos := 0; m_kept := 0;
    m_added := '[]'; m_removed := '[]'; m_restored := '[]'; m_needs := '[]'; m_daily := '[]';

    for v_kind, v_title in
      select k, x from (
        select 'daily' as k, e.value as x, e.ord as o
          from jsonb_array_elements_text(coalesce(col->'daily', '[]'::jsonb)) with ordinality e(value, ord)
        union all
        select 'nondaily', e.value, 100000 + e.ord
          from jsonb_array_elements_text(coalesce(col->'nondaily', '[]'::jsonb)) with ordinality e(value, ord)
      ) s order by o
    loop
      v_title := regexp_replace(trim(v_title), '\s+', ' ', 'g');
      continue when v_title = '' or public._kk_norm(v_title) = any(seen);
      seen := seen || public._kk_norm(v_title);

      select * into t from public.tasks
        where manager_id = v_mid and public._kk_norm(title) = public._kk_norm(v_title)
        order by (source = 'sheet') desc, active desc, created_at
        limit 1;

      if not found then
        if v_kind = 'daily' then
          m_added := m_added || to_jsonb(v_title); n_added := n_added + 1;
        else
          m_needs := m_needs || to_jsonb(v_title); n_needs := n_needs + 1;
        end if;
        if p_apply then
          insert into public.tasks (manager_id, title, task_type, priority, repeat_every, sort_order,
                                    start_date, active, source, needs_schedule)
          values (v_mid, v_title, 'daily', 'normal', 1, v_pos, public.ist_today(),
                  v_kind = 'daily', 'sheet', v_kind = 'nondaily');
        end if;

      elsif v_kind = 'daily' then
        if t.task_type <> 'daily' or t.needs_schedule then
          m_daily := m_daily || to_jsonb(t.title); n_daily := n_daily + 1;
        elsif t.sheet_removed then
          m_restored := m_restored || to_jsonb(t.title); n_restored := n_restored + 1;
        else
          m_kept := m_kept + 1;
        end if;
        if p_apply then
          update public.tasks set
            task_type = 'daily', repeat_unit = null, repeat_days = null, repeat_every = 1,
            due_date = null, project_name = null,
            active = case when needs_schedule or sheet_removed or task_type <> 'daily' then true else active end,
            needs_schedule = false, sheet_removed = false, source = 'sheet', sort_order = v_pos
          where id = t.id;
        end if;

      else  -- non-daily
        if t.task_type = 'daily' and not t.needs_schedule then
          m_needs := m_needs || to_jsonb(t.title); n_needs := n_needs + 1;
          if p_apply then
            update public.tasks set needs_schedule = true, active = false, sheet_removed = false,
                                    source = 'sheet', sort_order = v_pos where id = t.id;
          end if;
        else
          if t.sheet_removed then m_restored := m_restored || to_jsonb(t.title); n_restored := n_restored + 1;
          else m_kept := m_kept + 1; end if;
          if p_apply then
            update public.tasks set
              active = case when sheet_removed and not needs_schedule then true else active end,
              sheet_removed = false, source = 'sheet', sort_order = v_pos
            where id = t.id;
          end if;
        end if;
      end if;
      v_pos := v_pos + 1;
    end loop;

    -- sheet tasks that are no longer in this manager's columns → pause (history kept)
    for t in select * from public.tasks
             where manager_id = v_mid and source = 'sheet' and not sheet_removed
               and (active or needs_schedule)
               and not (public._kk_norm(title) = any(seen))
    loop
      m_removed := m_removed || to_jsonb(t.title); n_removed := n_removed + 1;
      if p_apply then update public.tasks set active = false, sheet_removed = true where id = t.id; end if;
    end loop;

    out_managers := out_managers || jsonb_build_object(
      'manager_id', v_mid,
      'manager', (select full_name from public.profiles where id = v_mid),
      'added', m_added, 'removed', m_removed, 'restored', m_restored,
      'needs_schedule', m_needs, 'made_daily', m_daily, 'kept', m_kept);
  end loop;

  return jsonb_build_object(
    'applied', p_apply,
    'managers', out_managers,
    'unknown', out_unknown,
    'totals', jsonb_build_object('added', n_added, 'removed', n_removed, 'restored', n_restored,
                                 'needs_schedule', n_needs, 'made_daily', n_daily));
end $$;
revoke all on function public._kk_sync_tasks(jsonb, boolean) from public, anon, authenticated;

-- 5. Called by the Google Sheet (with the sync code)
create or replace function public.sync_tasks_from_sheet(p_token text, p_sheet jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_token is null or p_token <> (select value from public.app_secrets where name = 'sheet_sync_code') then
    raise exception 'Wrong sync code. Copy it again from Supabase into the Apps Script.';
  end if;
  return public._kk_sync_tasks(p_sheet, true);
end $$;
revoke all on function public.sync_tasks_from_sheet(text, jsonb) from public;
grant execute on function public.sync_tasks_from_sheet(text, jsonb) to anon, authenticated;

-- 6. Called by the admin's "Import Excel" button (preview, then apply)
create or replace function public.admin_sync_tasks(p_sheet jsonb, p_apply boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only the admin can do this.'; end if;
  return public._kk_sync_tasks(p_sheet, p_apply);
end $$;
revoke all on function public.admin_sync_tasks(jsonb, boolean) from public, anon;
grant execute on function public.admin_sync_tasks(jsonb, boolean) to authenticated;

-- 7. Your sync code (paste into the Apps Script)
select value as "SYNC CODE — copy this into the Apps Script" from public.app_secrets where name = 'sheet_sync_code';
