-- ═════════════════════════════════════════════════════════════════════════════
--  bmi_visit_rls.sql
--  Target project: bwhrosebljcdgykreyyp
--
--  WHAT THIS FIXES
--    The Clinic Visit → BMI flow, end to end.
--    The three tables already exist with the exact columns the Dart client
--    writes (`visit_service.dart`, `visit_details_service.dart`,
--    `service_detail_records.dart`), but each has RLS enabled with no policy
--    for the `authenticated` role, so every INSERT/UPDATE returns
--      42501 new row violates row-level security policy for table "..."
--    and nothing is saved.
--
--      clinic_visits          the visit header
--      clinic_visit_services  "a BMI service was worked on this visit"
--      bmi_records            the height / weight / bmi readings
--
--  WHAT THIS DOES (inventory-style policy; creates/alts NO table or column)
--    * enables RLS on the three tables (already on — harmless to repeat)
--    * one `for all to authenticated` policy per table, gated on a signed-in
--      user
--    * a read-only SELECT policy on `service_types`, because `saveAll` resolves
--      the BMI service's type id by reading it and writes nothing if the read
--      comes back empty
--    * table grants for the three tables and `service_types`
--
--    No helper function and no sequence grants: every primary key on these
--    tables is a UUID defaulted with gen_random_uuid(), so there is no
--    sequence to grant. (Medicines needed one because its id is SERIAL.)
--
--  NOT included here: the OTHER service detail tables (bp_readings,
--  temperature_records, wound_dressing_records, …) and the medication tables.
--  A visit that records only BMI touches only the three tables above. Add the
--  same policy for each extra table when that service is brought online.
--
--  ⚠ RUN THE WHOLE FILE AS ONE BLOCK in Supabase → SQL Editor.
--    Expected: "Success. No rows returned."
-- ═════════════════════════════════════════════════════════════════════════════

alter table public.clinic_visits         enable row level security;
alter table public.clinic_visit_services enable row level security;
alter table public.bmi_records           enable row level security;

-- ── clinic_visits ────────────────────────────────────────────────────────────
drop policy if exists clinic_visits_staff_all on public.clinic_visits;
create policy clinic_visits_staff_all on public.clinic_visits
  for all to authenticated
  using      (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ── clinic_visit_services ────────────────────────────────────────────────────
drop policy if exists clinic_visit_services_staff_all on public.clinic_visit_services;
create policy clinic_visit_services_staff_all on public.clinic_visit_services
  for all to authenticated
  using      (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ── bmi_records ──────────────────────────────────────────────────────────────
drop policy if exists bmi_records_staff_all on public.bmi_records;
create policy bmi_records_staff_all on public.bmi_records
  for all to authenticated
  using      (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ── service_types (read-only reference) ──────────────────────────────────────
-- `saveAll` resolves the BMI service's `service_type_id` by reading this table,
-- and silently writes NOTHING if the read is empty. So the BMI flow needs
-- read access here even though it never writes it.
alter table public.service_types enable row level security;
drop policy if exists service_types_read_all on public.service_types;
create policy service_types_read_all on public.service_types
  for select to authenticated
  using (true);

-- ── Grants ───────────────────────────────────────────────────────────────────
grant select, insert, update, delete on table public.clinic_visits         to authenticated;
grant select, insert, update, delete on table public.clinic_visit_services to authenticated;
grant select, insert, update, delete on table public.bmi_records           to authenticated;
grant select                           on table public.service_types        to authenticated;
