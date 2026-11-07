-- =====================================================================
-- KK Daily Tasks · admin tools (run AFTER schema.sql, once)
-- Lets the admin add a manager, give a new PIN, or switch a login off,
-- straight from the app. Only an admin can call these.
-- Safe to re-run.
-- =====================================================================

-- Creates a login (auth user + email identity). Used by the admin tools and setup.
create or replace function public._kk_create_login(p_email text, p_password text, p_full_name text, p_department text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_id uuid := gen_random_uuid();
begin
  if exists (select 1 from auth.users where lower(email) = lower(p_email)) then
    raise exception 'A login for % already exists.', p_full_name;
  end if;
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    lower(p_email), extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name, 'department', p_department),
    now(), now(), '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', lower(p_email), 'email_verified', true),
    'email', now(), now(), now()
  );
  return v_id;  -- the profiles row is made by the on_auth_user_created trigger
end $$;
revoke all on function public._kk_create_login(text, text, text, text) from public, anon, authenticated;

-- Admin: add a manager
create or replace function public.admin_create_manager(p_full_name text, p_department text, p_email text, p_pin text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'Only the admin can do this.'; end if;
  if p_pin !~ '^\d{6}$' then raise exception 'The PIN must be 6 digits.'; end if;
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Enter the manager''s name.'; end if;
  return public._kk_create_login(p_email, p_pin, upper(trim(p_full_name)), nullif(trim(p_department), ''));
end $$;

-- Admin: give a manager a new PIN
create or replace function public.admin_reset_pin(p_user_id uuid, p_pin text)
returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'Only the admin can do this.'; end if;
  if p_pin !~ '^\d{6}$' then raise exception 'The PIN must be 6 digits.'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and role = 'manager') then
    raise exception 'Manager not found.';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')), updated_at = now()
  where id = p_user_id;
end $$;

-- Admin: switch a manager's login off / on (history is kept)
create or replace function public.admin_set_active(p_user_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'Only the admin can do this.'; end if;
  update public.profiles set active = p_active where id = p_user_id and role = 'manager';
  if not found then raise exception 'Manager not found.'; end if;
  update auth.users set banned_until = case when p_active then null else 'infinity'::timestamptz end, updated_at = now()
  where id = p_user_id;
end $$;

revoke all on function public.admin_create_manager(text, text, text, text) from public, anon;
revoke all on function public.admin_reset_pin(uuid, text) from public, anon;
revoke all on function public.admin_set_active(uuid, boolean) from public, anon;
grant execute on function public.admin_create_manager(text, text, text, text) to authenticated;
grant execute on function public.admin_reset_pin(uuid, text) to authenticated;
grant execute on function public.admin_set_active(uuid, boolean) to authenticated;
