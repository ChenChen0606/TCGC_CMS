-- ═════════════════════════════════════════════════════════════════════════════
--  Clinic Management System — vital signs + structured service records
--  Target project: bwhrosebljcdgykreyyp
--
--  WHAT THIS FIXES
--    1. A new "Vital Signs" service (the fixed last slot in the clinical order)
--       that captures BP, pulse, temperature (method), respiratory rate, SpO2,
--       symptoms, assessment and follow-up in one record.
--    2. Every worked service now keeps a structured row in its own detail table
--       (bp_readings, temperature_records, bmi_records, first_aid_records, …)
--       so a saved visit can be read back into the form that produced it.
--       A handful of those tables were missing columns the form collects, so
--       this migration adds them, and gives the record a Vital Signs row to
--       live in.
--
--  COLUMNS ARE THE FORM'S, VERBATIM
--    The Dart client (lib/services/service_detail_records.dart) writes these
--    exactly, so a typo here is a silent "row never saved" — the client swallows
--    the write failure rather than block a visit on a detail row.
--
--  WHY VITAL_SIGNS HAS NO RLS
--    Every one of the existing detail tables (bp_readings, temperature_records,
--    bmi_records, first_aid_records, ...) is open to the `authenticated` role
--    without row level security — they were created before the RLS pass and no
--    policy has ever been added to them. The new table mirrors them exactly:
--    no RLS, plus the same plain `grant all ... to authenticated`. Adding RLS
--    now would make this one table read empty to the app that writes the others,
--    which is the exact failure mode this project has burned hours on.
--
--  ⚠ RUN THE BLOCKS ONE AT A TIME, as the SQL editor is one transaction per run.
-- ═════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 1 — the "Vital Signs" service type
--
-- service_types is scanned by code on every load of a saved visit
-- (visit_details_service.dart maps service_type_id -> service_code and back), so
-- the row has to be insertable exactly once no matter how often the file runs.
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.service_types (service_name, service_code)
select 'Vital Signs', 'VITAL_SIGNS'
where not exists (
  select 1 from public.service_types where service_code = 'VITAL_SIGNS'
);


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 2 — the vital_signs detail table
--
-- One row per Vital Signs service, keyed by the clinic_visit_services row it
-- records. `numerics` for the readings (the same type the other detail tables
-- use), TEXT for every answer cell.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.vital_signs (
  vital_sign_id     uuid primary key default gen_random_uuid(),
  visit_service_id  uuid not null
                      references public.clinic_visit_services (visit_service_id)
                      on delete cascade,
  systolic          numeric,
  diastolic         numeric,
  pulse_rate        numeric,
  temperature       numeric,
  temp_method       text,
  respiratory_rate  numeric,
  spo2              numeric,
  bp_classification text,
  symptoms          text,
  assessment        text,
  follow_up         text,
  notes             text,
  recorded_at       timestamptz not null default now()
);

create index if not exists vital_signs_visit_service_idx
  on public.vital_signs (visit_service_id);

grant all on table public.vital_signs to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCK 3 — columns the other detail tables were missing
--
-- Each of these is a field already on the service's form that had nowhere to be
-- stored, so read-back dropped it. TEXT, not jsonb, matching the table's style;
-- list-answer cells (service_provided, given_this_visit, action_taken) store
-- the JSON the client already sends and decodes.
-- ─────────────────────────────────────────────────────────────────────────────

-- 3a. wound_dressing_records — the size of the wound, in cm.
alter table public.wound_dressing_records
  add column if not exists wound_length_cm numeric;

alter table public.wound_dressing_records
  add column if not exists wound_width_cm numeric;

-- 3b. first_aid_records — why the person was referred (shown only when the
--     disposition says "Referred to …").
alter table public.first_aid_records
  add column if not exists referral_reason text;

-- 3c. counselling_records — who counselled, and where the additional-service
--     answer points (the table already had the reason, but not the name).
alter table public.counselling_records
  add column if not exists counsellor_name text;

alter table public.counselling_records
  add column if not exists additional_service_name text;

-- 3d. prenatal_records — the shared vitals captured alongside the check-up, and
--     the checklist answers that were being thrown away.
alter table public.prenatal_records
  add column if not exists temperature numeric;

alter table public.prenatal_records
  add column if not exists pulse_rate numeric;

alter table public.prenatal_records
  add column if not exists service_provided text;

alter table public.prenatal_records
  add column if not exists given_this_visit text;

alter table public.prenatal_records
  add column if not exists presentation text;

alter table public.prenatal_records
  add column if not exists edema text;

alter table public.prenatal_records
  add column if not exists urine_protein text;

-- 3e. medical_consultations — who the examiner was (the form pre-fills it, the
--     record should say it).
alter table public.medical_consultations
  add column if not exists attending text;

-- 3f. medication_services — the outcome of the prescription. Medication Action
--     is a REQUIRED answer on the form ("this service existing does not mean
--     anybody was given anything") and until now it had nowhere to be stored.
--     `action` is the single action chosen; the form runs its details off it.
alter table public.medication_services
  add column if not exists action text;

alter table public.medication_services
  add column if not exists action_reason text;

alter table public.medication_services
  add column if not exists response text;

alter table public.medication_services
  add column if not exists additional_service_needed text;

alter table public.medication_services
  add column if not exists referral_service text;

alter table public.medication_services
  add column if not exists referral_reason text;