-- ═════════════════════════════════════════════════════════════════════════════
--  TCGC Clinic Management System — FIX account registration + login
--  Target project: bwhrosebljcdgykreyyp
--
--  PART A — registration could not save (fixed earlier)
--  ----------------------------------------------------
--  `public.admin_create_user` inserted into `auth.users` without `id`; this
--  project's `auth.users.id` has no default, so the insert failed with
--
--    null value in column "id" of relation "users"  (code 23502)
--
--  The function below supplies `id gen_random_uuid()`.
--
--  PART B — the account saved but could NOT log in (this file's new fix)
--  --------------------------------------------------------------------
--  GoTrue creates the `auth.users` text columns `confirmation_token`,
--  `recovery_token`, `email_change` and `email_change_token_new` WITHOUT a
--  default. A direct SQL insert leaves them NULL, but the Auth service reads
--  them as strings and fails — surfacing to the app as a generic
--  "Incorrect username or password" even though the password hash is correct.
--  (Supabase troubleshoot: "Database error saving new user" / "direct insert
--  can leave required columns as NULL when the Auth service expects ''.)
--
--  This file therefore ALSO:
--    1. backfills the four NULL token columns to '' on every existing row,
--    2. repairs the matching `auth.identities` row (provider_id / sub must be
--       the user UUID, not the username), and
--    3. writes '' for the token columns on every NEW account.
--
--  What this file touches: FUNCTIONS only. No table/column is created, dropped
--  or altered. The two UPDATEs below only normalise NULLs inside Auth's own
--  pre-existing columns.
--
--  HOW TO RUN: Supabase Dashboard → SQL Editor → New query → paste this WHOLE
--  file → Run. Expected: "Success. No rows returned."
--  (Safe to run more than once.)
-- ═════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Backfill: turn the NULL token columns into '' for accounts already
--    created, so they can log in too. (No-op for rows that are already fine.)
-- ─────────────────────────────────────────────────────────────────────────────
update auth.users
   set confirmation_token     = coalesce(confirmation_token, ''),
       recovery_token         = coalesce(recovery_token, ''),
       email_change           = coalesce(email_change, ''),
       email_change_token_new = coalesce(email_change_token_new, '')
 where confirmation_token     is null
    or recovery_token         is null
    or email_change           is null
    or email_change_token_new is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0b. Repair identities: for the email provider, `provider_id` and
--     identity_data.sub must be the user's UUID.
-- ─────────────────────────────────────────────────────────────────────────────
update auth.identities i
   set provider_id   = i.user_id::text,
       identity_data = jsonb_build_object(
                         'sub',            i.user_id::text,
                         'email',          u.email,
                         'email_verified', true,
                         'phone_verified', false)
  from auth.users u
 where i.user_id = u.id
   and i.provider = 'email'
   and (i.provider_id is distinct from i.user_id::text
        or i.identity_data ->> 'sub' is distinct from i.user_id::text);

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Remove the old 5-argument signature so there is only ONE admin_create_user.
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.admin_create_user(text, text, text, text, text);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. admin_create_user — Head-only, creates a CONFIRMED Auth user + account row.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_create_user(
  p_first_name text,
  p_last_name  text,
  p_username   text,
  p_password   text,
  p_role       text default 'Clinic Staff',
  p_email      text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user  text := lower(trim(p_username));
  v_email text;
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

  -- A real email, when given, must look like one; otherwise fall back to the
  -- hidden, non-deliverable sign-in identity built from the username.
  if coalesce(btrim(p_email), '') <> '' then
    if btrim(p_email) !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'Invalid email address' using errcode = '22023';
    end if;
    v_email := lower(btrim(p_email));
  else
    v_email := v_user || '@clinic.local';
  end if;

  if exists (select 1 from public.useraccount where lower(username) = v_user) then
    raise exception 'Username already taken' using errcode = '23505';
  end if;

  -- The four token columns are set to '' (NOT left NULL): GoTrue reads them as
  -- strings and rejects the account for login when they are NULL.
  insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    is_super_admin,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    created_at, updated_at
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
      'email',       v_email,
      'role',        p_role,
      'is_active',   true,
      'must_change_password', true
    ),
    'authenticated', 'authenticated',
    false,
    '', '', '', '',
    now(), now()
  );

  -- provider_id and identity_data.sub must be the UUID, not the username.
  insert into auth.identities (
    id, user_id, provider_id, identity_data,
    provider, last_sign_in_at, created_at, updated_at
  )
  values (
    v_uid, v_uid, v_uid::text,
    jsonb_build_object(
      'sub',            v_uid::text,
      'email',          v_email,
      'email_verified', true,
      'phone_verified', false),
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
-- 3. Grants — the DROP above removed the old function's privileges, so the new
--    signature needs them again. Only a signed-in user (authenticated) may call
--    it, and the function itself re-checks is_clinic_head().
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function
  public.admin_create_user(text, text, text, text, text, text) from public;
grant execute on function
  public.admin_create_user(text, text, text, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3b. update_own_email — lets a signed-in user change their OWN email, writing
--     Auth (users + identities) and `useraccount` together so login-by-username
--     keeps resolving to the right address. Optionally re-checks the password.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.update_own_email(
  p_email    text,
  p_verifier text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_hash  text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  if coalesce(btrim(p_email), '') = '' then
    raise exception 'Email is required' using errcode = '22023';
  end if;

  if btrim(p_email) !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Invalid email address' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_email));

  if coalesce(length(p_verifier), 0) > 0 then
    select encrypted_password into v_hash from auth.users where id = v_uid;
    if v_hash is null or v_hash not like '$2%' then
      raise exception 'Password verification is unavailable' using errcode = '42501';
    end if;
    if extensions.crypt(p_verifier, v_hash) <> v_hash then
      raise exception 'Verification failed: your password is incorrect'
        using errcode = '42501';
    end if;
  end if;

  update auth.users
     set email = v_email, updated_at = now()
   where id = v_uid;

  update auth.identities
     set provider_id   = v_uid::text,
         identity_data = jsonb_build_object(
                            'sub',            v_uid::text,
                            'email',          v_email,
                            'email_verified', true,
                            'phone_verified', false)
   where user_id = v_uid and provider = 'email';

  update public.useraccount
     set email = v_email
   where user_id = v_uid;
exception
  when unique_violation then
    raise exception 'That email is already used by another account'
      using errcode = '23505';
end;
$fn$;

revoke all on function public.update_own_email(text, text) from public;
grant execute on function public.update_own_email(text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. handle_new_user() — repointed from the deleted `public.profiles` to
--    `public.useraccount`. Only fires (if at all) for already-confirmed users,
--    and never overwrites an existing row.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email_confirmed_at is not null then
    insert into public.useraccount (
      user_id, fn, mn, ln, email, username, role,
      is_active, must_change_password, avatar_url, created_at, created_by
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data ->> 'first_name', ''),
      coalesce(new.raw_user_meta_data ->> 'middle_name', ''),
      coalesce(new.raw_user_meta_data ->> 'last_name', ''),
      new.email,
      lower(coalesce(nullif(new.raw_user_meta_data ->> 'username', ''),
                     split_part(coalesce(new.email, ''), '@', 1))),
      case
        when new.raw_user_meta_data ->> 'role' in ('Clinic Head', 'Clinic Staff')
          then new.raw_user_meta_data ->> 'role'
        else 'Clinic Staff'
      end,
      true, true, '', now(), null
    )
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Ask PostgREST to reload its schema cache so the new admin_create_user
--    signature (and the email argument) are available immediately.
-- ─────────────────────────────────────────────────────────────────────────────
notify pgrst, 'reload schema';
