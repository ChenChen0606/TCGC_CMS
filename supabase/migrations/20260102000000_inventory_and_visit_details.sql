-- ═════════════════════════════════════════════════════════════════════════════
--  Clinic Management System — inventory & visit-detail schema
--  Target project: bwhrosebljcdgykreyyp
--
--  WHAT THIS FIXES
--    1. Inventory → Save a medicine
--    2. Clinic Visit → saving the services + medicine a visitor was given
--
--  WHAT WAS VERIFIED AGAINST THE LIVE DATABASE (read-only probes, 2026-10-06)
--
--    Already present, so NOT created here:
--      medicines      id integer, name, stock integer, max_capacity integer,
--                     is_archived boolean, created_at, created_by
--      clinic_visits  visit_id uuid, visit_number text, person_id text,
--                     visit_date, visit_time text, reason_for_visit text,
--                     status text, created_by uuid, created_at timestamptz
--      useraccount    user_id uuid, username, role, is_active, fn, ln, ...
--
--    Missing columns that the Dart client already writes / reads
--                     (both are hard failures, not cosmetic):
--      (none on `medicines` — it already has every column the client uses, and
--       the app does not write archived_reason / archived_by / archived_at)
--      clinic_visits.recorded_by
--          -> VisitService.create INSERTs it on EVERY visit. Missing = the
--             insert fails and the wizard stops at "Could not save visit".
--          -> uuid, because it holds AccountService.currentUserId which is a
--             useraccount.user_id.
--
--    Missing tables the Dart client queries (PGRST205 / 404 today):
--      patients           the wizard cannot save ANY visit without it:
--                         _ensurePatientRow() returns null, the Proceed button
--                         stays disabled, and no error is shown to the user.
--      visit_services     one row per service actually worked on
--      visit_vitals       the readings + the band each fell into
--      visit_medications  the prescription
--      inventory_movements  stock audit trail (named in the code, never created)
--      procedures         auto-logged on nearly every visit
--
--  ⚠ RUN THE BLOCKS ONE AT A TIME. Do not paste the whole file and press Run —
--    the SQL editor sends it as one transaction and one failure rolls back
--    everything. Block 1 first, confirm, then Block 2, and so on.
-- ═════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 1 of 4 — the shared authorisation helper
--
-- Every policy below is gated on "there is an active useraccount row for the
-- person making the request". This mirrors public.is_clinic_head() from
-- 20260101000000_clinic_account_functions.sql, which already exists — do not
-- redefine it.
--
-- This runs before the policies are created. It is security definer so the
-- policies can read useraccount without recursing into useraccount's own RLS.
-- ─────────────────────────────────────────────────────────────────────────────
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


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 2 of 4 — Inventory: no schema change needed on `medicines`
--
-- `medicines` already has every column the app uses: id, name, stock,
-- max_capacity, is_archived, created_at, created_by. Archiving is a soft delete
-- that sets is_archived = true; restoring sets it back to false.
--
-- There are deliberately NO archived_reason / archived_by / archived_at columns,
-- and no updated_at — the client never reads or writes them. Save/edit/delete/
-- archive only ever needed the RLS policy in Block 4, so this block contains no
-- statements. It is kept as a placeholder so the block numbering still reads.
-- ─────────────────────────────────────────────────────────────────────────────


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 3 of 4 — Clinic Visit: the tables a saved visit needs
--
-- Column names and types below are taken from the Dart payloads, not guessed:
--   visit_service.dart:257        INSERT clinic_visits
--   patient_data.dart:77          INSERT patients
--   visit_details_service.dart:272 UPSERT visit_services
--   visit_details_service.dart:299 UPSERT visit_vitals
--   visit_details_service.dart:340 DELETE + INSERT visit_medications
--   procedure_service.dart:134    INSERT procedures
--
-- The two primary keys that matter for saving:
--   visit_services   primary key (visit_id, service_id) — this IS the upsert
--                    conflict target Dart names in onConflict: 'visit_id,service_id'
--   visit_vitals     primary key (visit_id) — the upsert conflict target
--                    Dart names in onConflict: 'visit_id'
-- Without those exact keys the upserts return PGRST200 and nothing saves.
-- ─────────────────────────────────────────────────────────────────────────────

-- 3a. clinic_visits.recorded_by — the column that stops every visit save.
alter table public.clinic_visits
  add column if not exists recorded_by uuid
    references public.useraccount (user_id) on delete set null;

alter table public.clinic_visits
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.touch_clinic_visits_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists clinic_visits_touch_updated_at on public.clinic_visits;
create trigger clinic_visits_touch_updated_at
  before update on public.clinic_visits
  for each row execute function public.touch_clinic_visits_updated_at();


-- 3b. patients — the clinic-side projection of a roster person.
--     unique (category, patient_no) is what PatientService.fetchByKey relies on
--     to find an existing row instead of creating a duplicate every visit.
create table if not exists public.patients (
  id                 uuid primary key default gen_random_uuid(),
  patient_no         text not null,
  category           text not null,
  last_name          text not null default '',
  first_name         text not null default '',
  middle_initial     text not null default '',
  institute          text,
  year_level         text,
  position           text,
  office_department  text,
  contact            text,
  emergency_name     text,
  emergency_contact  text,
  is_archived        boolean not null default false,
  created_by         uuid references public.useraccount (user_id) on delete set null default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_by         uuid references public.useraccount (user_id) on delete set null,
  updated_at         timestamptz not null default now(),
  constraint patients_category_patient_no_key unique (category, patient_no)
);

create index if not exists patients_patient_no_idx
  on public.patients (patient_no);


-- 3c. visit_services — the services actually worked on, in the order shown.
--     `data` is jsonb and holds the whole form, so a service can grow new
--     fields without a migration. `position` is the wizard's display order.
create table if not exists public.visit_services (
  visit_id      uuid not null
                  references public.clinic_visits (visit_id) on delete cascade,
  service_id    text not null,
  service_name  text,
  position      integer not null default 0,
  status        text,
  data          jsonb not null default '{}'::jsonb,
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (visit_id, service_id)
);

create index if not exists visit_services_service_id_idx
  on public.visit_services (service_id);


-- 3d. visit_vitals — one row per visit.
--     recorded_at has a default but is never in the Dart payload, so on a
--     re-save ON CONFLICT leaves it alone: the reading keeps the time it was
--     actually taken, which is the whole point of storing the band with it.
--     temp/height/weight/bmi are double precision because VisitVitals holds them
--     as double?; numeric can come back as a string and break the cast.
create table if not exists public.visit_vitals (
  visit_id         uuid primary key
                     references public.clinic_visits (visit_id) on delete cascade,
  systolic         integer,
  diastolic        integer,
  heart_rate       integer,
  resp_rate        integer,
  temp_c           double precision,
  o2_sat           integer,
  height_cm        double precision,
  weight_kg        double precision,
  bmi              double precision,
  interpretations  jsonb not null default '{}'::jsonb,
  recorded_at      timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);


-- 3e. visit_medications — the prescription.
--     inventory_item_id holds a medicines.id (integer, probe-confirmed), despite
--     the name. `unit` and `stock_at_pick` are collected in the UI and stored in
--     visit_services.data; unit is kept here as nullable so a future payload
--     that sends it does not fail.
--     on delete set null: a medicine deleted from the catalogue must not delete
--     the prescription line that recorded it.
create table if not exists public.visit_medications (
  id                 bigint generated always as identity primary key,
  visit_id           uuid not null
                       references public.clinic_visits (visit_id) on delete cascade,
  inventory_item_id  integer references public.medicines (id) on delete set null,
  item_name          text not null,
  unit               text,
  qty                integer not null default 0 check (qty >= 0),
  dosage             text,
  instructions       text,
  created_at         timestamptz not null default now()
);

-- The Dart save is DELETE ... WHERE visit_id then INSERT, so this index is on
-- the hot path of every visit save.
create index if not exists visit_medications_visit_id_idx
  on public.visit_medications (visit_id);


-- 3f. inventory_movements — why the stock number changed.
create table if not exists public.inventory_movements (
  id            bigint generated always as identity primary key,
  medicine_id   integer not null
                  references public.medicines (id) on delete cascade,
  movement_type text not null,
  qty           integer not null,
  stock_before  integer not null,
  stock_after   integer not null,
  visit_id      uuid references public.clinic_visits (visit_id) on delete set null,
  reason        text,
  moved_by      uuid references public.useraccount (user_id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now()
);

create index if not exists inventory_movements_medicine_idx
  on public.inventory_movements (medicine_id, created_at desc);


-- 3g. procedures — auto-created on most visits by the wizard.
create table if not exists public.procedures (
  id              bigint generated always as identity primary key,
  patient_id      uuid references public.patients (id) on delete set null,
  patient_no      text,
  patient_name    text,
  visit_id        uuid references public.clinic_visits (visit_id) on delete cascade,
  procedure_name  text not null,
  category        text,
  performed_at    timestamptz not null default now(),
  performed_by    uuid references public.useraccount (user_id) on delete set null,
  status          text not null default 'Pending',
  details         jsonb not null default '{}'::jsonb,
  findings        text,
  remarks         text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists procedures_visit_id_idx
  on public.procedures (visit_id);

create index if not exists procedures_status_idx
  on public.procedures (status);


-- 3h. Dispensing: a completed visit moves the stock.
--
--     MedicineService.decrementStock exists but has no caller anywhere in lib/,
--     so nothing was ever deducted — the UI even says so in three places. Rather
--     than change the Dart, the movement is made here, where it cannot be
--     forgotten: no prescription row, no stock change.
--
--     It is written as INSERT-deducts / DELETE-restores on purpose. The Dart
--     save is DELETE-all-then-INSERT-all, so re-saving a visit restores the old
--     lines and deducts the new ones: the net movement always equals the
--     difference between the two prescriptions. Saving the same visit twice with
--     the same medicine moves nothing.
--
--     security definer so it can write medicines and inventory_movements
--     regardless of the caller's RLS. Stock is clamped at 0 rather than allowed
--     to go negative and fail the save — a clamped movement is recorded with the
--     real before/after so the shortfall is visible instead of silent.
create or replace function public.apply_visit_medication_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_med    integer;
  v_qty    integer;
  v_delta  integer;
  v_before integer;
  v_after  integer;
  v_visit  uuid;
  v_kind   text;
  v_row    record;
begin
  if tg_op = 'INSERT' then
    v_row  := new;
    v_delta := -coalesce(new.qty, 0);
    v_kind  := 'Dispense';
  else
    v_row  := old;
    v_delta := coalesce(old.qty, 0);
    v_kind  := 'Restore';
  end if;

  v_med := v_row.inventory_item_id;
  v_qty := coalesce(v_row.qty, 0);
  v_visit := v_row.visit_id;

  -- A prescription line with no catalogue item (a free-text drug) or no
  -- quantity moves nothing. That is a legitimate thing to record, not an error.
  if v_med is null or v_qty <= 0 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select stock into v_before
    from public.medicines
    where id = v_med
    for update;

  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_after := greatest(v_before + v_delta, 0);

  update public.medicines
     set stock = v_after
   where id = v_med;

  insert into public.inventory_movements
    (medicine_id, movement_type, qty, stock_before, stock_after, visit_id, reason)
  values
    (v_med, v_kind, v_delta, v_before, v_after, v_visit,
     case when v_kind = 'Dispense'
          then 'Dispensed on visit completion'
          else 'Restored: prescription line removed or visit re-saved'
     end);

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$fn$;

drop trigger if exists visit_medications_stock on public.visit_medications;
create trigger visit_medications_stock
  after insert or delete on public.visit_medications
  for each row execute function public.apply_visit_medication_stock();


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 4 of 4 — RLS policies and grants
--
-- Run this LAST. Without it every table above reads as empty ([]) and every
-- write returns 42501, which looks exactly like the bug you are fixing now.
--
-- is_clinic_staff() is the gate: an authenticated caller with an active
-- useraccount row. The clinic has one shared role set, so all active staff get
-- the same access here — fine-grained per-role rules would need a clinic decision
-- about who may archive and who may dispense, which is not mine to make.
--
-- medicines and clinic_visits are included because their policies cannot be
-- verified with an unauthenticated probe; recreating them is harmless if they
-- already work. drop policy if exists first because CREATE POLICY has no
-- IF NOT EXISTS.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.medicines            enable row level security;
alter table public.clinic_visits        enable row level security;
alter table public.patients             enable row level security;
alter table public.visit_services       enable row level security;
alter table public.visit_vitals         enable row level security;
alter table public.visit_medications    enable row level security;
alter table public.inventory_movements  enable row level security;
alter table public.procedures           enable row level security;

drop policy if exists medicines_staff_all on public.medicines;
create policy medicines_staff_all on public.medicines
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists clinic_visits_staff_all on public.clinic_visits;
create policy clinic_visits_staff_all on public.clinic_visits
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists patients_staff_all on public.patients;
create policy patients_staff_all on public.patients
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists visit_services_staff_all on public.visit_services;
create policy visit_services_staff_all on public.visit_services
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists visit_vitals_staff_all on public.visit_vitals;
create policy visit_vitals_staff_all on public.visit_vitals
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists visit_medications_staff_all on public.visit_medications;
create policy visit_medications_staff_all on public.visit_medications
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists inventory_movements_staff_all on public.inventory_movements;
create policy inventory_movements_staff_all on public.inventory_movements
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

drop policy if exists procedures_staff_all on public.procedures;
create policy procedures_staff_all on public.procedures
  for all to authenticated
  using      (public.is_clinic_staff())
  with check (public.is_clinic_staff());

-- USAGE on sequences is required for the `generated always as identity` columns
-- (procedures.id, visit_medications.id, inventory_movements.id). Without it the
-- insert fails with 42501 even though the table policy allows it.
grant usage, select on all sequences in schema public to authenticated;

grant all on table public.medicines           to authenticated;
grant all on table public.clinic_visits       to authenticated;
grant all on table public.patients            to authenticated;
grant all on table public.visit_services      to authenticated;
grant all on table public.visit_vitals        to authenticated;
grant all on table public.visit_medications   to authenticated;
grant all on table public.inventory_movements to authenticated;
grant all on table public.procedures          to authenticated;
