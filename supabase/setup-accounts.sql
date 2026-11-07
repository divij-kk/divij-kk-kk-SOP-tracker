-- =====================================================================
-- KK Daily Tasks · create the admin login + 18 manager logins
-- Run once, AFTER schema.sql and admin-functions.sql.
--
-- BEFORE RUNNING: replace  CHANGE-ME  below with the admin password you want
-- (at least 8 characters). That is the password for kkumbrellas@gmail.com.
--
-- When it finishes, the results table shows every manager's PIN.
-- Copy them somewhere safe; they are not shown again.
-- Safe to re-run: logins that already exist are skipped (their PINs don't change).
-- =====================================================================

create temp table if not exists _kk_new_pins (manager text, pin text);
truncate _kk_new_pins;

do $$
declare
  admin_password text := 'CHANGE-ME';   -- <<< put the admin password here
  domain text := 'staff.kkumbrellas.com';
  names text[] := array[
    'ANANDMOY BANERJEE','ANUP ROY','AVINASH SHAW','BACHU BAKULI','BOLAI SANTRA',
    'HIMANSHU KUMAR','ISHAN CHATERJEE','JOYDIP BAL','JOYESH GHOSH','LAKSHMIKANTA KARMAKAR',
    'MAINAK GANGULY','MOLOY DHARA','RAJU SANTRA','SOUMITRO DE','SUBRATA CHAKRABORTY',
    'SUROJIT CHAKRABORTY','TRIDIB MANDAL','UMA CHINA'];
  n text; v_email text; v_pin text;
begin
  -- admin
  if not exists (select 1 from auth.users where lower(email) = 'kkumbrellas@gmail.com') then
    if admin_password = 'CHANGE-ME' or length(admin_password) < 8 then
      raise exception 'Set the admin password first: replace CHANGE-ME near the top with a password of at least 8 characters, then run again.';
    end if;
    perform public._kk_create_login('kkumbrellas@gmail.com', admin_password, 'KK Admin', null);
    insert into _kk_new_pins values ('ADMIN (kkumbrellas@gmail.com)', 'password you set');
  end if;

  -- managers
  foreach n in array names loop
    v_email := trim(both '.' from regexp_replace(lower(n), '[^a-z0-9]+', '.', 'g')) || '@' || domain;
    if not exists (select 1 from auth.users where lower(email) = v_email) then
      v_pin := (100000 + floor(random() * 900000))::int::text;
      perform public._kk_create_login(v_email, v_pin, n, null);
      insert into _kk_new_pins values (n, v_pin);
    end if;
  end loop;
end $$;

select manager, pin from _kk_new_pins order by manager;
