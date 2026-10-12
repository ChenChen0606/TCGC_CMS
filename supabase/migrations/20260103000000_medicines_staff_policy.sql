-- ═════════════════════════════════════════════════════════════════════════════
--  medicines_staff_policy.sql
--  Target project: bwhrosebljcdgykreyyp
--
--  WHAT THIS FIXES
--    Medicine Inventory → Save / Update.
--    `medicines` has RLS enabled but no policy for the `authenticated` role,
--    so every INSERT/UPDATE returns
--      `42501 new row violates row-level security policy for table "medicines"`
--    and the inventory never persists. This is the only thing missing — the
--    Flutter service (`MedicineService`) is already correct.
--
--  WHAT THIS DOES (inventory only — creates/alts NO table or column)
--    * one helper function `is_clinic_staff()` (SECURITY DEFINER, so the
--      policy can read `useraccount` without recursing into its own RLS)
--    * one RLS policy on `public.medicines`
--    * the grants the policy needs (table + sequences)
--
--  It does NOT create `patients`, `visits`, `visit_services`, `procedures` or
--  any other table. Those are a separate decision (Clinic Visit saving).
--
--  ⚠ RUN THE WHOLE FILE AS ONE BLOCK in Supabase → SQL Editor.
--    Expected: "Success. No rows returned."
-- ═════════════════════════════════════════════════════════════════════════════

-- ── 1. Authorisation helper ──────────────────────────────────────────────────
-- An active `useraccount` row for the signed-in Auth user. Security definer so
-- the policy below can read useraccount regardless of useraccount's own RLS.
create or replace function public.is_clinic_staff()
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
      and ua.is_active = true
  );
$$;

revoke all on function public.is_clinic_staff() from public;
grant execute on function public.is_clinic_staff() to authenticated;

-- ── 2. RLS policy on medicines ───────────────────────────────────────────────
alter table public.medicines enable row level security;

drop policy if exists medicines_staff_all on public.medicines;
create policy medicines_staff_all on public.medicines
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

-- ── 3. Grants ────────────────────────────────────────────────────────────────
-- The table grant may already exist (Supabase default privileges), but it is
-- harmless to repeat. Sequence usage is required because `medicines.id` is a
-- SERIAL — without it the INSERT fails with "permission denied for sequence".
grant select, insert, update, delete on table public.medicines to authenticated;
grant usage, select on all sequences in schema public to authenticated;
