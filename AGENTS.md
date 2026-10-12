# AGENTS.md — Clinic Management System (Flutter + Supabase)

Read this before touching anything. Most of what is here was verified against the
live database with read-only probes; it is not a guess and should not be
re-derived by trial and error.

## Hard rules

- **Do NOT create, alter or drop any table, column or function in Supabase.**
  The user has asked for this explicitly. Probing is fine; DDL is not.
- **Never** put a Personal Access Token in `.env` or any file. The Flutter key
  (`sb_publishable_…`) is the only key that belongs in the repo.
- **`lib/screen/individual_record_screen.dart` is untracked** and is the largest
  hand-written file (~5 100 lines). `git checkout` will delete it. Do not run
  git commands that could restore or discard untracked files.
- **Use the edit tools, not PowerShell `Get-Content`/`Set-Content`**, for editing
  files. An earlier attempt to rewrite a file that way corrupted its UTF-8 and
  mangled every comment. `ReadAllText`/`WriteAllText` with an explicit
  `UTF8Encoding($false)` is acceptable for inspection only.

## Live database facts

Project: `https://bwhrosebljcdgykreyyp.supabase.co`

**RLS hides every row from the publishable key.** A publishable-key read returns
`[]` or `count: 0` for *all* tables, including `useraccount`, which definitely has
rows. Do **not** conclude a table is empty from a publishable-key read. That
mistake was made earlier in this project and was wrong.

### `individual_records`

| Column | Notes |
|---|---|
| `person_id` | **Primary key, and it is also the printed number.** There is no separate uuid and no `record_no`. |
| `person_type` | The category: `Student` / `Faculty` / `Staff` |
| `fn`, `mn`, `ln` | First / middle / last name |
| `suffix`, `sex` | |
| `date_of_birth` | Not `birth_date` |
| `contact_number` | Not `contact` |
| `email`, `address` | |
| `userid` | FK to `useraccount.user_id`. Duplicate of `created_by` in purpose; unused by the app. |
| `created_by` | FK to `useraccount.user_id`. **With the underscore.** |
| `created_at` | |

**Does NOT exist:** `id`, `uuid`, `record_no`, `category`, `first_name`,
`middle_name`, `last_name`, `birth_date`, `contact`, `status`, `updated_at`,
`updated_by`.

Using any of those spellings raises
`PostgrestException(column individual_records_1.id does not exist, code: 42703)`.
That error was the original bug. Do not "tidy" the short names back to long form.

### `person_type` is capitalised — do not lower-case it

```
chk_person_type    CHECK (person_type = ANY (ARRAY['Student','Faculty','Staff']))
chk_person_id_prefix CHECK (person_type = 'Student'
                            OR (person_type = 'Faculty' AND person_id ~~ 'F%')
                            OR (person_type = 'Staff'   AND person_id ~~ 'S%'))
chk_sex            CHECK (sex IS NULL OR sex = ANY ('Male','Female'))
uq_individual_email UNIQUE (lower(btrim(email))) WHERE email IS NOT NULL
uq_individual_identity UNIQUE (ln, fn, mn, suffix, date_of_birth)
                      WHERE date_of_birth IS NOT NULL
```

Both CHECKs compare case-sensitively, so `'faculty'` is not merely unmatched —
it is **rejected**. Code that lower-cased `person_type` broke the roster twice
over at once: every `person_type` filter matched no row (empty Faculty and Staff
tabs while the records sat in the database) and every INSERT raised
`chk_person_type` (nothing could be saved, in any category).
`personTypeForStorage` in `individual_record_data.dart` is the single place that
spells this column; it returns the exact CHECK spelling. Do not "normalise" it.

`uq_individual_email` is `WHERE email IS NOT NULL`, and an empty string is not
null — so a blank email box used to be written as a real value and the *second*
person with a blank box failed on a field nobody had filled in. `personPayload`
sends NULL, not `''`, for every optional field.

### Enrolment status is derived from the term, not stored adrift

`individual_academic_records.status` is **not** a mirror of
`academic_periods.status`, and must not be made into one:

- `academic_periods.status` = "this is the term the school is running".
- `individual_academic_records.status` = "this person is still here this term".

Someone who resigns mid-term leaves the roster while the term carries on being
current; only this column can record that, and it is what `deactivate` writes.
It also carries a third value, `Archived`, that describes a person removed by an
administrator and that no term ever has. Dropping the column would throw away
the mid-term departures and the archive with them.

The rule, in one place — `IndividualRecordService.statusForTerm`: an enrolment is
Active **iff** it is filed under the term currently being run. `create` and
`createAll` apply it unconditionally; `update` applies it when the record was
moved to a different term and otherwise leaves the stored status alone, so
correcting an address does not enrol somebody who resigned.

`update` upserts on `(person_id, academic_period_id)` via `.select()`: an empty
result means the term changed and no row exists for it yet, so one is inserted.
A bare UPDATE there silently discarded every affiliation field and still reported
success.

Closing a term must also retire its enrolments. `setActivePeriod` and the
"carry roster forward" branch of `addPeriod` both call `_retirePeriod` — after
`_copyRoster`, never before, because the copy reads the outgoing term's **Active**
enrolments and retiring first copies nothing.

### `individual_academic_records`

`academic_record_id`, `person_id`, `academic_period_id`, `institute_id` (correct
spelling — **not** `insitute_id`), `program_id`, `year_level`,
`department_office_id`, `position_id`, `status`, `userid`, `created_by`,
`created_at`.

**Does NOT exist:** `academic_person_id`, `status_reason`, `status_changed_by`,
`status_changed_at`.

### Consequence: no person-level status

`individual_records` has no status column. "On the roster" and "archived" are
both facts about the enrolments. `archivePerson` therefore archives by setting
`status = 'Archived'` on every enrolment for that person; `fetchArchivedPatients`
finds archived people by asking the enrolment table for ids whose rows are all
Archived. Never filter on `person.status`.

### Reference tables

| Table | Columns |
|---|---|
| `academic_periods` | `academic_period_id`, `acad_year`, `semester`, `status`, `created_at` |
| `institutes` | `institute_id`, `code`, `name`, `created_at` |
| `program` | `program_id`, `code`, `name`, `institute_id`, `created_at` |
| `departments_offices` | `department_office_id`, `name`, `created_at` (**no `code`**) |
| `positions` | `position_id`, `name`, `created_at` (**no `code`**) |

`academic_periods.status` is the active-period flag (`'Active'` / `'Inactive'`).
There is no `is_active`. Note `status` is also a column on
`individual_academic_records` — same name, different table, different meaning.

### RPCs that do NOT exist

All of these return `404 PGRST202` and have been replaced with direct writes:

- `generate_person_id` → random candidate + `idExists` check, bounded at 40
  attempts. Safe because `person_id` is the PK, so a race is rejected by the
  database rather than producing two people with one number.
- `archive_person`, `restore_person` → UPDATE on enrolments by `person_id`
- `add_academic_period`, `set_active_period` → direct INSERT/UPDATE
- `add_program_with_institute` → INSERT institute, then INSERT program
- `roll_forward_period` → `_copyRoster`: read active enrolments of the outgoing
  term, insert copies under the incoming term, dropping `academic_record_id`

## PostgREST gotchas that cost real time

- **`or=` cannot reference a column of an embedded resource.** `or=(person.ln.ilike.*x*)`
  fails with `PGRST100 failed to parse logic tree`. This is why roster search is
  two queries: resolve `person_id`s from `individual_records` first, then filter
  the enrolment query with `or=(year_level.ilike.*x*,person_id.in.(…))` — both
  root columns.
- **The Dart client's `.or()` supplies the parentheses**, producing `or=(…)`. A
  bare `or=col.op.value` without parens is mis-parsed as a column named
  `or<something>`. When testing filters with curl, include the parens explicitly.
- **A column that does not exist gives `42703` with a JSON body naming it. A
  column that fails some other way gives `400` with an EMPTY body.** Don't read
  an empty 400 as "column exists".
- PowerShell mangles `&or=` in `Invoke-WebRequest`. Use `curl.exe` for filter
  testing.

## Still outstanding

1. **`visits`, `procedures`, `visit_services`, `visit_vitals`,
   `visit_medications`, `medicines`, `patients` do not exist** in this project.
   Clinic Visit saving cannot work until they are added. SQL has not been written
   — the user has been asked and has not yet approved a migration.
2. **`data_cleanup_service.dart` was deleted** because it queried those missing
   `visits`/`procedures` tables on every Clinic Visit load (`PGRST205`).
3. **`userid` vs `created_by` is a genuine duplicate** on both tables. Harmless
   today; worth dropping, but that is DDL and needs the user's approval.

## Verification

`dart format lib` then `flutter analyze lib`. Current state: **0 errors**, 1
warning (`lib/screen/clinic_dashboard_screen.dart:4:8`, unused import, pre-existing
and unrelated).

To re-verify a query against the live schema, probe read-only:

```powershell
$u="https://bwhrosebljcdgykreyyp.supabase.co"
$k="<publishable key from .env>"
$sel=[uri]::EscapeDataString('col_a,col_b,person:individual_records!left(person_id,fn)')
curl.exe -s -w "`nHTTP %{http_code}" -H "apikey: $k" -H "Authorization: Bearer $k" `
  "$u/rest/v1/individual_academic_records?select=$sel&limit=1"
```

`200` means the columns and all FK relationships resolve. A `200` with `[]` is
expected — that is RLS, not an empty table.

## Layout notes

- `individual_record_data.dart` — model, payloads, roster filtering, import staging.
  Shared by the service layer, which is why it is not inside the 5 000-line screen.
- `services/individual_record_service.dart` — all Supabase CRUD for the roster.
- `services/reference_data_service.dart` — the five reference tables plus
  `ReferenceCatalog`, a static catalog that screens subscribe to.
- `core/patient_directory.dart` — in-memory clinic-side projection.
- `screen/individual_record_screen.dart` — the roster UI.

## UI conventions already established

- Reference adds go through one button labelled **"Save to database"**, with an X.
  The Cancel button beside it was removed: it did exactly what X does, and having
  both made one look broken.
- `_AddProgramDialog` is a **single path**: an Institute dropdown with a
  `+ New institute` entry that reveals two extra fields. The previous three-mode
  chip selector was removed — three ways to reach two tables, with one button
  meaning three different writes.
- After any successful write, `_showSavedDialog(...)` confirms it. A dialog closing
  must never be indistinguishable from a cancel.
- `_dropValue(...)` guards every `DropdownButtonFormField` whose options can be
  empty. Never pass a possibly-stale value straight into a dropdown; it throws.