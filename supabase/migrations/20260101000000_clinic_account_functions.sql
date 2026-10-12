-- ═════════════════════════════════════════════════════════════════════════════
--  TCGC Clinic Management System — account functions
--  Target project: bwhrosebljcdgykreyyp
--
--  ⚠ RUN THESE 6 BLOCKS ONE AT A TIME.  ⚠
--  Do NOT paste the whole file into the SQL editor and press Run. The editor
--  sends it as ONE transaction, so a single failure rolls back every function
--  and you get a confusing "does not exist" error for functions that were
--  never created. Select one block, run it, confirm it succeeded, then move on.
--
--  Creates NO table. Alters NOTHING. Only adds functions, and reads/writes
--  only `auth.*` (required to manage logins) and the existing
--  `public.useraccount`. It does NOT touch patients, visits, medicines,
--  procedures, archive_log or any other table.
--
--  Existing `public.useraccount` columns used here:
--    user_id, fn, mn, ln, username, email, avatar_url, role,
--    is_active, must_change_password, created_at, created_by
-- ═════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 1 of 6 — is_clinic_head()
-- The authorisation gate every admin_* function checks.
-- Run this FIRST; the other admin functions depend on it.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_clinic_head()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.useraccount ua
    where ua.user_id = auth.uid()
      and ua.role = 'Clinic Head'
      and ua.is_active = true
  );
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 2 of 6 — resolve_email_by_username(text)
-- Turns the USERNAME a staff member types into the Auth email, without needing
-- anon to be able to read `useraccount`. Returns NULL for an unknown username.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.resolve_email_by_username(p_username text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ua.email
  from public.useraccount ua
  where lower(ua.username) = lower(trim(p_username))
    and ua.is_active = true
  limit 1;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 3 of 6 — is_username_available(text)
-- Duplicate-username guard for registration.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
    from public.useraccount
    where lower(username) = lower(trim(p_username))
  );
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 4 of 6 — admin_create_user(...)
-- Head creates a fully CONFIRMED account in one step, which is why you do not
-- need to change the "Confirm email" setting.
--
-- Depends on: is_clinic_head()  (Block 1)
--
-- If this block fails with "function extensions.crypt(...) does not exist",
-- pgcrypto is not enabled on the project. Enable it first:
--   Dashboard -> Database -> Extensions -> search "pgcrypto" -> Enable
-- then run this block again.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_create_user(
  p_first_name text,
  p_last_name  text,
  p_username   text,
  p_password   text,
  p_role       text default 'Clinic Staff'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user  text := lower(trim(p_username));
  v_email text := lower(trim(p_username)) || '@clinic.local';
  -- Supplied explicitly: this project's auth.users.id has NO default, so an
  -- insert that omits it fails with 23502 NOT NULL. See 20260110000000.
  v_uid   uuid := gen_random_uuid();
begin
  if not public.is_clinic_head() then
    raise exception 'Not authorised to create accounts' using errcode = '42501';
  end if;

  if p_role not in ('Clinic Staff', 'Clinic Head') then
    raise exception 'Invalid role: %', p_role using errcode = '22023';
  end if;

  if v_user !~ '^[a-z][a-z0-9._-]{2,19}$' then
    raise exception 'Username must be 3-20 characters and start with a letter'
      using errcode = '22023';
  end if;

  if coalesce(length(p_password), 0) < 8 then
    raise exception 'Password must be at least 8 characters' using errcode = '22023';
  end if;

  if exists (select 1 from public.useraccount where lower(username) = v_user) then
    raise exception 'Username already taken' using errcode = '23505';
  end if;

  insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role, created_at, updated_at
  )
  values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'first_name',  trim(coalesce(p_first_name, '')),
      'middle_name', '',
      'last_name',   trim(coalesce(p_last_name, '')),
      'username',    v_user,
      'role',        p_role,
      'is_active',   true,
      'must_change_password', true
    ),
    'authenticated', 'authenticated', now(), now()
  )
  returning id into v_uid;

  insert into auth.identities (
    id, user_id, provider_id, identity_data,
    provider, last_sign_in_at, created_at, updated_at
  )
  values (
    v_uid, v_uid, v_user,
    jsonb_build_object('sub', v_user::text, 'email', v_email, 'phone', ''),
    'email', now(), now(), now()
  );

  insert into public.useraccount (
    user_id, fn, mn, ln, email, username, role,
    is_active, must_change_password, avatar_url, created_at, created_by
  )
  values (
    v_uid,
    trim(coalesce(p_first_name, '')),
    '',
    trim(coalesce(p_last_name, '')),
    v_email, v_user, p_role,
    true, true, '', now(), auth.uid()
  )
  on conflict (user_id) do update set
    fn       = excluded.fn,
    mn       = excluded.mn,
    ln       = excluded.ln,
    email    = excluded.email,
    username = excluded.username,
    role     = excluded.role;

  return v_uid;
exception
  when unique_violation then
    raise exception 'Username or email already taken' using errcode = '23505';
end;
$fn$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 5 of 6 — admin_delete_user(uuid)
-- Removes the Auth user as well as the account row. Deleting only the row
-- would leave a working login behind.
--
-- Depends on: is_clinic_head()  (Block 1)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if not public.is_clinic_head() then
    raise exception 'Not authorised to delete accounts' using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'You cannot delete your own account' using errcode = '22023';
  end if;

  delete from auth.sessions   where user_id = p_user_id;
  delete from auth.identities where user_id = p_user_id;
  delete from auth.users      where id      = p_user_id;
  delete from public.useraccount where user_id = p_user_id;
end;
$fn$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 6 of 6 — admin_reset_password(uuid, text, text)
-- Head issues a one-time temporary password. When p_verifier is supplied the
-- Head's CURRENT password is re-checked here, server-side, before the reset.
--
-- Depends on: is_clinic_head()  (Block 1)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_reset_password(
  p_user_id  uuid,
  p_password text,
  p_verifier text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_head_hash text;
begin
  if not public.is_clinic_head() then
    raise exception 'Not authorised to reset passwords' using errcode = '42501';
  end if;

  if coalesce(length(p_password), 0) < 8 then
    raise exception 'Password must be at least 8 characters' using errcode = '22023';
  end if;

  if p_verifier is not null and p_verifier <> '' then
    select encrypted_password into v_head_hash
    from auth.users
    where id = auth.uid();

    if v_head_hash is null or v_head_hash not like '$2%' then
      raise exception 'Password verification is unavailable' using errcode = '42501';
    end if;

    if extensions.crypt(p_verifier, v_head_hash) <> v_head_hash then
      raise exception 'Verification failed: your password is incorrect'
        using errcode = '42501';
    end if;
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at         = now()
   where id = p_user_id;

  if not found then
    raise exception 'Account not found' using errcode = 'P0002';
  end if;

  update public.useraccount
     set must_change_password = true
   where user_id = p_user_id;

  delete from auth.sessions where user_id = p_user_id;
end;
$fn$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 7 of 6 — PERMISSIONS
--
-- Run this LAST, and only after all six functions above were created
-- successfully. Kept separate on purpose: if a GRANT fails here it cannot
-- roll back the function bodies you just created.
--
-- `resolve_email_by_username` is granted to `anon` because it runs BEFORE
-- sign-in, when the caller has no JWT yet.
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.is_clinic_head()               from public;
revoke all on function public.resolve_email_by_username(text) from public;
revoke all on function public.is_username_available(text)     from public;
revoke all on function public.admin_create_user(text, text, text, text, text) from public;
revoke all on function public.admin_delete_user(uuid)         from public;
revoke all on function public.admin_reset_password(uuid, text, text) from public;

grant execute on function public.is_clinic_head()               to authenticated;
grant execute on function public.resolve_email_by_username(text) to anon, authenticated;
grant execute on function public.is_username_available(text)     to authenticated;
grant execute on function public.admin_create_user(text, text, text, text, text) to authenticated;
grant execute on function public.admin_delete_user(uuid)         to authenticated;
grant execute on function public.admin_reset_password(uuid, text, text) to authenticated;