-- ═════════════════════════════════════════════════════════════════════════════
--  all_table_rls.sql
--  Target project: bwhrosebljcdgykreyyp
--
--  WHY
--    Every table below has Row Level Security enabled and no policy that lets
--    the signed-in app role (`authenticated`) through. With RLS on, a read made
--    without a matching policy is not an error — it is HTTP 200 with an empty
--    list — and a write is rejected with
--        42501 new row violates row-level security policy for table "..."
--    So the roster, the inventory and the clinic visit all look "empty" or
--    "unsavable" until each table has a policy for `authenticated`.
--
--  WHAT THIS DOES (same function-free pattern that fixed `medicines` and then
--  let `clinic_visits` save; it creates/alts NO table or column)
--    For each existing table the app touches:
--      * enable row level security (idempotent — already on for all of these)
--      * one `for all to authenticated` policy gated on a signed-in user
--      * select/insert/update/delete grant for `authenticated`
--    Plus a schema-wide sequence grant, so any SERIAL id (medicines.id is one)
--    can be assigned.
--
--  TABLES THE APP TOUCHES THAT DO **NOT** EXIST (a policy cannot fix these —
--  they need a CREATE TABLE, which is DDL and needs your approval):
--      vital_signs, procedures, patients, visits, archive_log
--  Consequence today, regardless of this file:
--      * the Vital Signs service cannot save (no `vital_signs` table)
--      * the Procedures feature cannot save (no `procedures` table)
--      * the archive log cannot be written (no `archive_log` table)
--  Say the word and I will write the CREATE TABLE migration for those.
--
--  ⚠ RUN THE WHOLE FILE AS ONE BLOCK in Supabase → SQL Editor.
--    Expected: "Success. No rows returned."
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Sequences (covers SERIAL ids such as medicines.id) ───────────────────────
grant usage, select on all sequences in schema public to authenticated;

-- ── Core / roster ────────────────────────────────────────────────────────────
alter table public.useraccount                 enable row level security;
alter table public.individual_records          enable row level security;
alter table public.individual_academic_records enable row level security;

drop policy if exists useraccount_staff_all on public.useraccount;
create policy useraccount_staff_all on public.useraccount
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists individual_records_staff_all on public.individual_records;
create policy individual_records_staff_all on public.individual_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists individual_academic_records_staff_all on public.individual_academic_records;
create policy individual_academic_records_staff_all on public.individual_academic_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

-- ── Reference data ───────────────────────────────────────────────────────────
alter table public.academic_periods    enable row level security;
alter table public.institutes          enable row level security;
alter table public.program             enable row level security;
alter table public.departments_offices enable row level security;
alter table public.positions           enable row level security;
alter table public.service_types       enable row level security;

drop policy if exists academic_periods_staff_all on public.academic_periods;
create policy academic_periods_staff_all on public.academic_periods
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists institutes_staff_all on public.institutes;
create policy institutes_staff_all on public.institutes
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists program_staff_all on public.program;
create policy program_staff_all on public.program
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists departments_offices_staff_all on public.departments_offices;
create policy departments_offices_staff_all on public.departments_offices
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists positions_staff_all on public.positions;
create policy positions_staff_all on public.positions
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists service_types_staff_all on public.service_types;
create policy service_types_staff_all on public.service_types
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

-- ── Inventory ────────────────────────────────────────────────────────────────
alter table public.medicines enable row level security;

drop policy if exists medicines_staff_all on public.medicines;
create policy medicines_staff_all on public.medicines
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

-- ── Clinic visits (header + service rows) ────────────────────────────────────
alter table public.clinic_visits         enable row level security;
alter table public.clinic_visit_services enable row level security;

drop policy if exists clinic_visits_staff_all on public.clinic_visits;
create policy clinic_visits_staff_all on public.clinic_visits
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists clinic_visit_services_staff_all on public.clinic_visit_services;
create policy clinic_visit_services_staff_all on public.clinic_visit_services
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

-- ── Service detail tables ────────────────────────────────────────────────────
alter table public.bp_readings             enable row level security;
alter table public.temperature_records     enable row level security;
alter table public.bmi_records             enable row level security;
alter table public.wound_dressing_records  enable row level security;
alter table public.first_aid_records       enable row level security;
alter table public.first_aid_conditions    enable row level security;
alter table public.first_aid_treatments    enable row level security;
alter table public.counselling_records     enable row level security;
alter table public.prenatal_records        enable row level security;
alter table public.medical_consultations   enable row level security;
alter table public.medication_services     enable row level security;
alter table public.medication_service_items enable row level security;

drop policy if exists bp_readings_staff_all on public.bp_readings;
create policy bp_readings_staff_all on public.bp_readings
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists temperature_records_staff_all on public.temperature_records;
create policy temperature_records_staff_all on public.temperature_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists bmi_records_staff_all on public.bmi_records;
create policy bmi_records_staff_all on public.bmi_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists wound_dressing_records_staff_all on public.wound_dressing_records;
create policy wound_dressing_records_staff_all on public.wound_dressing_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists first_aid_records_staff_all on public.first_aid_records;
create policy first_aid_records_staff_all on public.first_aid_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists first_aid_conditions_staff_all on public.first_aid_conditions;
create policy first_aid_conditions_staff_all on public.first_aid_conditions
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists first_aid_treatments_staff_all on public.first_aid_treatments;
create policy first_aid_treatments_staff_all on public.first_aid_treatments
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists counselling_records_staff_all on public.counselling_records;
create policy counselling_records_staff_all on public.counselling_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists prenatal_records_staff_all on public.prenatal_records;
create policy prenatal_records_staff_all on public.prenatal_records
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists medical_consultations_staff_all on public.medical_consultations;
create policy medical_consultations_staff_all on public.medical_consultations
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists medication_services_staff_all on public.medication_services;
create policy medication_services_staff_all on public.medication_services
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists medication_service_items_staff_all on public.medication_service_items;
create policy medication_service_items_staff_all on public.medication_service_items
  for all to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

-- ── Grants ───────────────────────────────────────────────────────────────────
grant select, insert, update, delete on table public.useraccount                  to authenticated;
grant select, insert, update, delete on table public.individual_records           to authenticated;
grant select, insert, update, delete on table public.individual_academic_records  to authenticated;
grant select, insert, update, delete on table public.academic_periods             to authenticated;
grant select, insert, update, delete on table public.institutes                   to authenticated;
grant select, insert, update, delete on table public.program                      to authenticated;
grant select, insert, update, delete on table public.departments_offices          to authenticated;
grant select, insert, update, delete on table public.positions                    to authenticated;
grant select, insert, update, delete on table public.service_types                to authenticated;
grant select, insert, update, delete on table public.medicines                    to authenticated;
grant select, insert, update, delete on table public.clinic_visits                to authenticated;
grant select, insert, update, delete on table public.clinic_visit_services        to authenticated;
grant select, insert, update, delete on table public.bp_readings                  to authenticated;
grant select, insert, update, delete on table public.temperature_records          to authenticated;
grant select, insert, update, delete on table public.bmi_records                  to authenticated;
grant select, insert, update, delete on table public.wound_dressing_records       to authenticated;
grant select, insert, update, delete on table public.first_aid_records            to authenticated;
grant select, insert, update, delete on table public.first_aid_conditions         to authenticated;
grant select, insert, update, delete on table public.first_aid_treatments         to authenticated;
grant select, insert, update, delete on table public.counselling_records          to authenticated;
grant select, insert, update, delete on table public.prenatal_records             to authenticated;
grant select, insert, update, delete on table public.medical_consultations        to authenticated;
grant select, insert, update, delete on table public.medication_services          to authenticated;
grant select, insert, update, delete on table public.medication_service_items     to authenticated;
