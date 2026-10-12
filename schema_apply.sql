-- 1. SERVICE TYPES (fixed list, no add in system)
CREATE TABLE IF NOT EXISTS service_types (
  service_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name    TEXT UNIQUE NOT NULL,
  service_code    TEXT UNIQUE NOT NULL,
  description     TEXT
);

INSERT INTO service_types (service_name, service_code)
VALUES
  ('BP Taking', 'BP_TAKING'),
  ('Temperature Checking', 'TEMP_CHECKING'),
  ('BMI', 'BMI'),
  ('Wound Dressing', 'WOUND_DRESSING'),
  ('First Aid Treatment', 'FIRST_AID'),
  ('Health Counselling', 'COUNSELLING'),
  ('Prenatal', 'PRENATAL'),
  ('Medication', 'MEDICATION'),
  ('Medical Consultation', 'MED_CONSULT'),
  ('Medical Certificate', 'MED_CERT'),
  ('Medical Clearance', 'MED_CLEAR')
ON CONFLICT (service_name) DO NOTHING;

-- 2. CLINIC VISITS
CREATE TABLE IF NOT EXISTS clinic_visits (
  visit_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_number     TEXT UNIQUE NOT NULL,
  person_id        UUID NOT NULL REFERENCES individual_records(person_id),
  visit_date       DATE NOT NULL,
  visit_time       TIME NOT NULL,
  reason_for_visit TEXT,
  status           TEXT,
  recorded_by      UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. CLINIC VISIT SERVICES
CREATE TABLE IF NOT EXISTS clinic_visit_services (
  visit_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id         UUID NOT NULL REFERENCES clinic_visits(visit_id) ON DELETE CASCADE,
  service_type_id  UUID NOT NULL REFERENCES service_types(service_type_id),
  status           TEXT,
  performed_by     UUID,
  started_at       TIMESTAMPTZ,
  completed_at     TIMESTAMPTZ,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. DETAIL TABLES
CREATE TABLE IF NOT EXISTS bp_readings (
  bp_reading_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  systolic         NUMERIC,
  diastolic        NUMERIC,
  pulse_rate       NUMERIC,
  position         TEXT,
  arm              TEXT,
  assessment       TEXT,
  recorded_at      TIMESTAMPTZ,
  notes            TEXT
);

CREATE TABLE IF NOT EXISTS temperature_records (
  temperature_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id      UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  temperature           NUMERIC,
  unit                  TEXT,
  method                TEXT,
  site                  TEXT,
  assessment            TEXT,
  notes                 TEXT
);

CREATE TABLE IF NOT EXISTS bmi_records (
  bmi_record_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  height_cm        NUMERIC,
  weight_kg        NUMERIC,
  bmi              NUMERIC,
  classification   TEXT,
  notes            TEXT
);

CREATE TABLE IF NOT EXISTS wound_dressing_records (
  wound_dressing_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id    UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  wound_location      TEXT,
  wound_type          TEXT,
  wound_condition     TEXT,
  cleaning_performed  TEXT,
  antiseptic_used     TEXT,
  dressing_material   TEXT,
  assessment_findings TEXT,
  next_dressing_date  DATE,
  notes               TEXT
);

CREATE TABLE IF NOT EXISTS first_aid_records (
  first_aid_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id         UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  incident_type            TEXT,
  body_location            TEXT,
  pain_level               TEXT,
  condition_after_treatment TEXT,
  disposition              TEXT,
  notes                    TEXT
);

CREATE TABLE IF NOT EXISTS first_aid_conditions (
  condition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_aid_id UUID NOT NULL REFERENCES first_aid_records(first_aid_id) ON DELETE CASCADE,
  condition    TEXT
);

CREATE TABLE IF NOT EXISTS first_aid_treatments (
  treatment_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_aid_id  UUID NOT NULL REFERENCES first_aid_records(first_aid_id) ON DELETE CASCADE,
  treatment_type TEXT,
  details        TEXT
);

CREATE TABLE IF NOT EXISTS counselling_records (
  counselling_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id           UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  topic                      TEXT,
  other_topic                TEXT,
  reason_or_concern          TEXT,
  counselling_provided       TEXT,
  counsellor_id              UUID,
  follow_up_needed           TEXT,
  follow_up_date             DATE,
  follow_up_reason           TEXT,
  additional_service_needed  TEXT,
  additional_service_type_id UUID REFERENCES service_types(service_type_id),
  additional_service_reason  TEXT,
  notes                      TEXT
);

CREATE TABLE IF NOT EXISTS prenatal_records (
  prenatal_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  gravida          TEXT,
  para             TEXT,
  lmp              DATE,
  edd              DATE,
  gestational_age  TEXT,
  blood_pressure   TEXT,
  weight_kg        NUMERIC,
  fundal_height_cm NUMERIC,
  fetal_heart_rate NUMERIC,
  fetal_movement   TEXT,
  assessment       TEXT,
  action_taken     TEXT,
  follow_up_date   DATE,
  notes            TEXT
);

CREATE TABLE IF NOT EXISTS medical_consultations (
  consultation_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id         UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  chief_complaint          TEXT,
  history_of_present_illness TEXT,
  physical_examination     TEXT,
  assessment               TEXT,
  treatment_management     TEXT,
  follow_up_needed         TEXT,
  follow_up_date           DATE,
  referral_needed          TEXT,
  referral_reason          TEXT,
  notes                    TEXT
);

-- Medicines inventory
CREATE TABLE IF NOT EXISTS medicines (
  id            SERIAL PRIMARY KEY,
  name          TEXT UNIQUE NOT NULL,
  stock         INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  max_capacity  INTEGER NOT NULL DEFAULT 0 CHECK (max_capacity >= 0),
  is_archived   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by    UUID REFERENCES useraccount(user_id),
  CONSTRAINT chk_medicines_capacity CHECK (stock <= max_capacity)
);

-- Medication record tied to a visit service
CREATE TABLE IF NOT EXISTS medication_services (
  medication_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_service_id      UUID NOT NULL REFERENCES clinic_visit_services(visit_service_id) ON DELETE CASCADE,
  -- Optional: denormalize for easier history queries (can also join)
  visit_id              UUID REFERENCES clinic_visits(visit_id) ON DELETE SET NULL,
  reason                TEXT,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by            UUID REFERENCES useraccount(user_id)
);

-- Items dispensed/administered for a medication service
CREATE TABLE IF NOT EXISTS medication_service_items (
  medication_item_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  medication_service_id UUID NOT NULL REFERENCES medication_services(medication_service_id) ON DELETE CASCADE,
  medicine_id           INT  NOT NULL REFERENCES medicines(id),
  dose                  TEXT,
  quantity              NUMERIC NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit                  TEXT, 
  frequency             TEXT,                -- useful for "when visitor asks for medicine"
  action                TEXT,                -- e.g. Given, Not Given, Held, Refused
  response              TEXT,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by            UUID REFERENCES useraccount(user_id),
  CONSTRAINT chk_med_item_action CHECK (
    action IS NULL OR action IN ('Given','Not Given','Held','Refused','Partially Given')
  )
);