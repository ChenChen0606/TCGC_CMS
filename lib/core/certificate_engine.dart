// ─────────────────────────────────────────────────────────────────────────────
//  certificate_engine.dart
//  The clinic's three paper documents, as data, plus the merge that fills them.
//
//  WHY THE FORMS ARE DATA AND NOT WIDGETS
//  A certificate is a legal-ish document: what it says has to be reproducible
//  years later, and the wording has to be the same whether it was printed today
//  or on paper last term. A template made of widgets is reproducible only as long
//  as nobody edits the widget. So a template here is a list of BLOCKS — a
//  heading, a row of label/value pairs, a table, a sentence with {{placeholders}}
//  in it, a signature line — and the engine's only job is to fill the
//  placeholders. Editing the wording becomes a row edit, and an issued document
//  keeps the template version it was generated with.
//
//  WHY RESOLUTION HAPPENS ONCE, IN ONE PLACE
//  The on-screen preview and the PDF both render a [RenderedDocument]. If they
//  each did their own placeholder substitution they would eventually disagree —
//  and the PDF is the one that gets filed. So [DocumentDraft.resolve] is the only
//  place a `{{placeholder}}` becomes text, and both renderers are handed the
//  finished result.
//
//  THE THREE BUILT-INS
//  They are byte-for-byte the rows the migration seeds, and they are the
//  fallback when `public.templates` cannot be read. A missing table must not
//  stop a nurse from issuing a certificate during a clinic.
// ─────────────────────────────────────────────────────────────────────────────

import '../core/patient_directory.dart';
import '../core/visit_details.dart';
import '../core/visit_service_forms.dart';
import '../core/vitals.dart';

// ── TEMPLATE MODEL ──────────────────────────────────────────────────────────

/// Who signs, and under what title. Comes from the template so a re-issue
/// reproduces the same names even if the staff roster changed since.
class DocSignatory {
  const DocSignatory({
    required this.name,
    required this.role,
    this.order = 1,
  });

  final String name;
  final String role;
  final int order;

  Map<String, dynamic> toJson() => {'name': name, 'role': role, 'order': order};

  factory DocSignatory.fromJson(Map<String, dynamic> j) => DocSignatory(
        name: '${j['name'] ?? ''}',
        role: '${j['role'] ?? ''}',
        order: (j['order'] as num?)?.toInt() ?? 1,
      );

  static const DocSignatory nurse = DocSignatory(
    name: 'Francislee N. Famacion, RN',
    role: 'School Nurse',
  );
  static const DocSignatory headNurse = DocSignatory(
    name: 'Francislee N. Famacion, RN',
    role: 'Head, Medical and Dental Clinic',
  );
  static const DocSignatory physician = DocSignatory(
    name: 'Dr. Noriel G. Apao',
    role: 'College Physician',
  );
}

/// What a block does on the page.
enum DocBlockKind {
  /// The document's own title, centred and in caps.
  title,

  /// A sub-heading, e.g. "PHYSICAL EXAMINATION".
  heading,

  /// One line of prose with placeholders in it. Wraps.
  paragraph,

  /// A label on the left and a value on the right, dotted between — the shape
  /// the paper forms use for every detail line.
  field,

  /// A horizontal rule, for the signature block.
  divider,

  /// A signature line with a name and title under it.
  signature,

  /// The thirteen-row physical examination table. Row labels come from
  /// [kPhysicalExamRows] so the printed form and the on-screen one are the same
  /// thirteen rows in the same order.
  examTable,

  /// The generated Visit History printout, one row per past visit.
  historyTable,

  /// Deliberate blank space, so a signature can be signed in pen.
  space,
}

class DocBlock {
  const DocBlock(this.kind,
      {this.text, this.label, this.key, this.placeholder});

  const DocBlock.title(this.text)
      : kind = DocBlockKind.title,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.heading(this.text)
      : kind = DocBlockKind.heading,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.paragraph(this.text)
      : kind = DocBlockKind.paragraph,
        label = null,
        key = null,
        placeholder = null;

  /// A label/value line. [key] is where the answer lives in the draft;
  /// [placeholder] is the `{{...}}` name the auto-fill writes.
  const DocBlock.field(this.label, this.key, {this.placeholder})
      : kind = DocBlockKind.field,
        text = null;

  const DocBlock.signature(this.text)
      : kind = DocBlockKind.signature,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.divider()
      : kind = DocBlockKind.divider,
        text = null,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.examTable()
      : kind = DocBlockKind.examTable,
        text = null,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.historyTable()
      : kind = DocBlockKind.historyTable,
        text = null,
        label = null,
        key = null,
        placeholder = null;
  const DocBlock.space([this.text = ''])
      : kind = DocBlockKind.space,
        label = null,
        key = null,
        placeholder = null;

  final DocBlockKind kind;
  final String? text;
  final String? label;
  final String? key;

  /// The `visitor.full_name`-style name, when the block is filled from a
  /// placeholder rather than from a staff-entered value.
  final String? placeholder;
}

/// One paper document.
class DocTemplate {
  const DocTemplate({
    required this.name,
    required this.type,
    required this.version,
    required this.subtitle,
    required this.blocks,
    this.signatories = const [],
    this.footer = '',
    this.referencePrefix = 'DOC',
  });

  final String name;

  /// 'certificate' | 'certification' | 'client_record' | 'clearance'
  final String type;
  final int version;

  /// The line under the title, e.g. "Medical and Dental Clinic Office".
  final String subtitle;

  final List<DocBlock> blocks;
  final List<DocSignatory> signatories;
  final String footer;

  /// The two letters the reference number starts with, e.g. `MC-2026-0001`.
  final String referencePrefix;

  /// Every `{{placeholder}}` a block mentions, for building the auto-fill list
  /// and for telling the nurse which lines are still blank. The thirteen
  /// examination rows are added because the table block has no placeholders of
  /// its own but the checklist still has to list its thirteen findings.
  List<String> get placeholderNames {
    final out = <String>[];
    void add(String n) {
      if (!out.contains(n)) out.add(n);
    }

    for (final b in blocks) {
      // A field row names its placeholder bare ("vitals.bp"), while a sentence
      // names it inside braces ("{{vitals.bp}}"). Both have to be collected, or
      // the checklist of blank lines quietly omits every detail row on the form.
      final bare = b.placeholder;
      if (bare != null && bare.isNotEmpty) add(bare);
      for (final t in [b.text, b.key]) {
        if (t == null) continue;
        for (final m in RegExp(r'\{\{\s*([a-z0-9_.]+)\s*\}\}').allMatches(t)) {
          add(m.group(1)!);
        }
      }
      if (b.kind == DocBlockKind.examTable) {
        for (final row in kPhysicalExamRows) {
          add('exam.${row.key}');
        }
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'version': version,
        'subtitle': subtitle,
        'blocks': blocks
            .map((b) => {
                  'kind': b.kind.name,
                  if (b.text != null) 'text': b.text,
                  if (b.label != null) 'label': b.label,
                  if (b.key != null) 'key': b.key,
                  if (b.placeholder != null) 'placeholder': b.placeholder,
                })
            .toList(),
        'signatories': signatories.map((s) => s.toJson()).toList(),
        'footer': footer,
        'reference_prefix': referencePrefix,
      };

  /// The clinic's own details, fixed once. Overridable so a future clinic
  /// template does not need a code change, but there is only one clinic.
  static const String clinicName = 'Tangub City Global College';
  static const String clinicDepartment = 'Medical and Dental Clinic Office';
  static const String formerName = 'Tangub City Global College';

  // ── BUILT-IN TEMPLATES ───────────────────────────────────────────────────
  //
  // Identical to the rows the migration seeds. These are what the app uses
  // when `public.templates` is unreadable, so a nurse can always issue.

  static const DocTemplate medicalCertificate = DocTemplate(
    name: 'Medical Certificate',
    type: 'certificate',
    version: 1,
    subtitle: clinicDepartment,
    referencePrefix: 'MC',
    blocks: [
      DocBlock.title('MEDICAL CERTIFICATE'),
      DocBlock.paragraph(
        'This is to certify that {{visitor.full_name}}, {{visitor.age_ordinal}}, '
        'a {{visitor.sex_lower}} of {{visitor.address}}, {{visitor.institute}}, '
        'is clinically evaluated and found to be {{clearance.status_lower}} '
        'to participate in {{visit.purpose_lower}}.',
      ),
      DocBlock.paragraph(
        'Known medical condition(s): {{vitals.asthma}} Asthma — '
        '{{vitals.allergies}} Allergies. Taken medicine for illness? '
        '{{vitals.self_illness}}.',
      ),
      DocBlock.heading('PHYSICAL EXAMINATION'),
      DocBlock.field('Height', 'height_cm', placeholder: 'vitals.height_cm'),
      DocBlock.field('Weight', 'weight_kg', placeholder: 'vitals.weight_kg'),
      DocBlock.field('Blood Pressure', 'bp', placeholder: 'vitals.bp'),
      DocBlock.field('Temperature', 'temperature',
          placeholder: 'vitals.temperature'),
      DocBlock.field('Pulse Rate', 'pulse_rate',
          placeholder: 'vitals.pulse_rate'),
      DocBlock.field('Respiration', 'respiration',
          placeholder: 'vitals.respiration'),
      DocBlock.field('Vision (R/L)', 'vision_rl',
          placeholder: 'vitals.vision_rl'),
      DocBlock.field('Corrected?', 'corrected',
          placeholder: 'vitals.corrected'),
      DocBlock.field('Pupils', 'pupils', placeholder: 'vitals.pupils'),
      DocBlock.examTable(),
      DocBlock.paragraph('{{recommendations}}'),
      DocBlock.divider(),
      DocBlock.signature('signatory.nurse'),
      DocBlock.signature('signatory.physician'),
    ],
    signatories: [DocSignatory.nurse, DocSignatory.physician],
    footer:
        'Lux Mundi, Light of the World · Integrity · Compassion · Excellence',
  );

  static const DocTemplate certification = DocTemplate(
    name: 'Certification',
    type: 'certification',
    version: 1,
    subtitle: clinicDepartment,
    referencePrefix: 'CR',
    blocks: [
      DocBlock.title('CERTIFICATION'),
      DocBlock.paragraph(
        'This is to certify that {{visitor.full_name}}, {{visitor.age_ordinal}}, '
        'is a bona fide student of {{visitor.institute}}. {{pronoun.subject}} '
        '{{pronoun.be}} duly examined and diagnosed to be {{clearance.status_lower}} '
        'on {{issued_on_ordinal}} at {{issued_on_ordinal_place}}.',
      ),
      DocBlock.paragraph(
        '{{pronoun.subject}} is {{excused_for}}. This certification is issued '
        'for whatever legitimate purpose it may serve.',
      ),
      DocBlock.divider(),
      DocBlock.signature('signatory.head'),
    ],
    signatories: [DocSignatory.headNurse],
    footer:
        'Learn Today, Light of the World · Honesty · Compassion · Excellence',
  );

  static const DocTemplate individualClientsRecord = DocTemplate(
    name: 'Individual Clients Record',
    type: 'client_record',
    version: 1,
    subtitle: clinicDepartment,
    referencePrefix: 'ICR',
    blocks: [
      DocBlock.title('INDIVIDUAL CLIENTS RECORD'),
      DocBlock.field('Name', 'full_name', placeholder: 'visitor.full_name'),
      DocBlock.field('Sex', 'sex', placeholder: 'visitor.sex'),
      DocBlock.field('Civil Status', 'civil_status',
          placeholder: 'visitor.civil_status'),
      DocBlock.field('Institute', 'institute',
          placeholder: 'visitor.institute'),
      DocBlock.field('Birthday', 'birthday', placeholder: 'visitor.birthday'),
      DocBlock.field('Age', 'age_ordinal', placeholder: 'visitor.age_ordinal'),
      DocBlock.field('Address', 'address', placeholder: 'visitor.address'),
      DocBlock.paragraph(''),
      DocBlock.historyTable(),
    ],
    signatories: [],
    footer: '$clinicName · $clinicDepartment',
  );

  /// The medical clearance form: the same certificate paper, with a clearance
  /// status and recommendations instead of an examination.
  static const DocTemplate medicalClearance = DocTemplate(
    name: 'Medical Clearance',
    type: 'clearance',
    version: 1,
    subtitle: clinicDepartment,
    referencePrefix: 'MC',
    blocks: [
      DocBlock.title('MEDICAL CLEARANCE'),
      DocBlock.paragraph(
        'This is to certify that {{visitor.full_name}}, {{visitor.age_ordinal}}, '
        'a {{visitor.sex_lower}} of {{visitor.institute}}, has been medically '
        'evaluated on {{visit.date}}.',
      ),
      DocBlock.heading('CLEARANCE'),
      DocBlock.field('Purpose', 'purpose', placeholder: 'visit.purpose'),
      DocBlock.field('Status', 'status', placeholder: 'clearance.status'),
      DocBlock.field('Not Cleared For', 'not_cleared_for',
          placeholder: 'clearance.not_cleared_for'),
      DocBlock.field('Valid Until', 'validity_date',
          placeholder: 'clearance.validity_date'),
      DocBlock.paragraph('{{recommendations}}'),
      DocBlock.divider(),
      DocBlock.signature('signatory.nurse'),
      DocBlock.signature('signatory.physician'),
    ],
    signatories: [DocSignatory.nurse, DocSignatory.physician],
    footer:
        'Lux Mundi, Light of the World · Integrity · Compassion · Excellence',
  );

  /// All four, keyed by document type.
  static const Map<String, DocTemplate> builtIns = {
    'certificate': medicalCertificate,
    'certification': certification,
    'client_record': individualClientsRecord,
    'clearance': medicalClearance,
  };

  /// Rebuilds a template from a `public.templates` row. A row the app does not
  /// understand — because a clinic has added a type the app has not shipped
  /// support for — falls back to the built-in of the same type rather than
  /// failing, so a new template never blocks certificate issuance.
  factory DocTemplate.fromSupabase(Map<String, dynamic> row) {
    final type = '${row['type'] ?? 'certificate'}';
    final fallback = builtIns[type] ?? medicalCertificate;
    final rawBlocks = row['blocks'];

    // Every field is taken from the ROW first, with the built-in only supplying
    // what the row is silent about. A clinic that has edited the wording and
    // the signatories but not the block list still gets its own version, its own
    // footer and its own names — which is the whole point of the table.
    final rawSignatories = row['signatories'];
    final signatories = rawSignatories is List && rawSignatories.isNotEmpty
        ? [
            for (final s in rawSignatories.whereType<Map>())
              DocSignatory.fromJson(s.cast<String, dynamic>()),
          ]
        : fallback.signatories;

    return DocTemplate(
      name: '${row['name'] ?? fallback.name}',
      type: type,
      version: (row['version'] as num?)?.toInt() ?? fallback.version,
      subtitle: '${row['subtitle'] ?? fallback.subtitle}',
      referencePrefix: '${row['reference_prefix'] ?? fallback.referencePrefix}',
      blocks: rawBlocks is List && rawBlocks.isNotEmpty
          ? [
              for (final b in rawBlocks.whereType<Map>())
                // A block kind the app has not shipped support for falls back
                // to the built-in's, rather than dropping the line entirely.
                _blockFromJson(b.cast<String, dynamic>()) ??
                    fallback.blocks.first,
            ]
          : fallback.blocks,
      signatories: signatories,
      footer: '${row['footer'] ?? fallback.footer}',
    );
  }

  static DocBlock? _blockFromJson(Map<String, dynamic> j) {
    final kind =
        DocBlockKind.values.where((k) => k.name == '${j['kind']}').firstOrNull;
    if (kind == null) return null;
    return DocBlock(
      kind,
      text: j['text'] as String?,
      label: j['label'] as String?,
      key: j['key'] as String?,
      placeholder: j['placeholder'] as String?,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ── THE VALUES A DOCUMENT CAN SHOW ──────────────────────────────────────────

/// Everything a placeholder can be filled from, worked out once from the
/// visitor, the visit and the readings.
class DocumentValues {
  DocumentValues._(this._map, {this.history = const []});

  final Map<String, String> _map;

  /// The past visits, carried here rather than on the draft so there is exactly
  /// one place a row can come from. A printout with an empty table is almost
  /// always this having been stored twice and set in only one of them.
  final List<HistoryRow> history;

  String of(String placeholder) => _map[placeholder] ?? '';

  Map<String, String> get all => Map<String, String>.unmodifiable(_map);

  bool isFilled(String placeholder) => of(placeholder).trim().isNotEmpty;

  /// Fills `{{placeholders}}` in [text]. An unknown or empty placeholder
  /// becomes an em dash rather than vanishing, so a missing line is visibly
  /// missing instead of silently absent from a legal document.
  String merge(String text) => text.replaceAllMapped(
        RegExp(r'\{\{\s*([a-z0-9_.]+)\s*\}\}'),
        (m) {
          final v = of(m.group(1)!);
          return v.trim().isEmpty ? '—' : v;
        },
      );
}

/// One past visit, for the Individual Clients Record printout.
class HistoryRow {
  const HistoryRow({
    required this.date,
    required this.chiefComplaint,
    required this.treatment,
  });

  final String date;
  final String chiefComplaint;
  final String treatment;
}

/// Builds the placeholder values for a visit.
class DocumentContext {
  DocumentContext({
    required this.profile,
    required this.visitDate,
    required this.vitals,
    this.civilStatus = '',
    this.purpose = '',
    this.reason = '',
    this.diagnosis = '',
    this.recommendations = '',
    this.excusedFor = '',
    this.clearanceStatus = '',
    this.notClearedFor = '',
    this.validityDate = '',
    this.issuedPlace = '',
    this.history = const [],
    this.examFindings = const {},
  });

  final ClinicProfile profile;
  final DateTime visitDate;
  final VisitVitals vitals;

  /// New on step 3 — there was nowhere to record it before.
  final String civilStatus;

  final String purpose;
  final String reason;
  final String diagnosis;
  final String recommendations;
  final String excusedFor;
  final String clearanceStatus;
  final String notClearedFor;
  final String validityDate;
  final String issuedPlace;

  /// Past visits, newest first, for the Individual Clients Record.
  final List<HistoryRow> history;

  /// The thirteen physical examination findings, keyed as `exam.<key>`.
  final Map<String, String> examFindings;

  /// Age in whole years, or null when the birth date is not on file. A document
  /// with an unknown age says "—"; it does not guess.
  int? get age {
    final bd = profile.birthDate;
    if (bd.isEmpty) return null;
    final b = DateTime.tryParse(bd);
    if (b == null) return null;
    final now = DateTime.now();
    var years = now.year - b.year;
    final hadBirthday =
        now.month > b.month || (now.month == b.month && now.day >= b.day);
    if (!hadBirthday) years -= 1;
    return years < 0 ? null : years;
  }

  /// "21" or "21st" — the paper forms want the ordinal in running text.
  String get ageOrdinal {
    final a = age;
    return a == null ? '' : DocumentWords.ordinal(a);
  }

  /// "she"/"he" from the recorded sex, with a fallback for anything the clinic
  /// has not got a word for. The certification is written in a sentence, so
  /// guessing the wrong pronoun is worse than using a neutral one.
  String get pronounSubject {
    switch (profile.sex.trim().toLowerCase()) {
      case 'female':
      case 'f':
        return 'she';
      case 'male':
      case 'm':
        return 'he';
      default:
        return 'they';
    }
  }

  /// The verb to go with [pronounSubject]. Split out because "they was" is a
  /// sentence the clinic's own name on it cannot carry.
  String get pronounBe => pronounSubject == 'they' ? 'were' : 'was';

  DocumentValues buildValues() {
    final v = vitals;
    final bp = v.bloodPressure;
    final bmi = v.bmi;
    return DocumentValues._(
      {
        'visitor.full_name': profile.fullName,
        'visitor.age': age?.toString() ?? '',
        'visitor.age_ordinal': ageOrdinal,
        'visitor.sex': profile.sex,
        'visitor.sex_lower': _lower(profile.sex),
        'visitor.address': profile.address,
        'visitor.id_no': profile.id,
        'visitor.course':
            profile.program.isEmpty ? profile.programLabel : profile.program,
        'visitor.institute':
            profile.institute.isEmpty ? profile.department : profile.institute,
        'visitor.birthday': profile.birthDate,
        'visitor.civil_status': civilStatus,
        'visit.date': DocumentWords.longDate(visitDate),
        'visit.date_ordinal': DocumentWords.ordinalDate(visitDate),
        'visit.reason': reason,
        'visit.purpose': purpose,
        'visit.purpose_lower': _lower(purpose),
        // A height of 170 must print as "170 cm" and not "170.0 cm": this text
        // ends up on a document somebody keeps for years.
        'vitals.height_cm': _measure(v.heightCm, 'cm'),
        'vitals.weight_kg': _measure(v.weightKg, 'kg'),
        'vitals.bmi': bmi == null ? '' : bmi.toStringAsFixed(1),
        'vitals.bp': bp?.display ?? '',
        'vitals.temperature': v.tempReading?.display ?? '',
        'vitals.pulse_rate': v.heartRateReading?.display ?? '',
        'vitals.respiration': v.respRateReading?.display ?? '',
        'vitals.vision_rl': '',
        'vitals.vision_r': '',
        'vitals.vision_l': '',
        'vitals.corrected': '',
        'vitals.pupils': '',
        'vitals.asthma': '',
        'vitals.allergies': '',
        'vitals.self_illness': '',
        'clearance.status': clearanceStatus,
        'clearance.status_lower': _lower(clearanceStatus),
        'clearance.not_cleared_for': notClearedFor,
        'clearance.validity_date': validityDate,
        'recommendations': recommendations,
        'diagnosis': diagnosis,
        'excused_for': excusedFor,
        'pronoun.subject': pronounSubject,
        'pronoun.be': pronounBe,
        'issued_on_ordinal': DocumentWords.ordinalDate(visitDate),
        'issued_on_ordinal_place': issuedPlace,
        'clinic.name': DocTemplate.clinicName,
        'clinic.address': DocTemplate.clinicDepartment,
        'clinic.former_name': DocTemplate.formerName,
        'footer.motto': '',
        'footer.values': '',
        for (final e in examFindings.entries) 'exam.${e.key}': e.value,
      },
      history: history,
    );
  }

  /// "170 cm", "62.5 kg", or nothing at all when the reading was not taken.
  /// A whole number prints without its decimal point, because a certificate is
  /// not a spreadsheet.
  static String _measure(double? v, String unit) {
    if (v == null) return '';
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    return '$s $unit';
  }

  static String _lower(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toLowerCase() + t.substring(1);
  }
}

// ── THE DRAFT: AUTO-FILLED, AND STILL EDITABLE ──────────────────────────────

/// A document being written. Starts as the auto-fill, and every line stays
/// editable, because the auto-fill only knows what the machine saw.
class DocumentDraft {
  DocumentDraft({
    required this.template,
    required this.values,
    this.issuedBy = '',
    this.saved = false,
  });

  final DocTemplate template;
  final DocumentValues values;

  /// The staff member issuing it, printed on the document.
  final String issuedBy;

  /// Whether the document has already been issued. An issued document is
  /// immutable — correcting one means issuing a new one with a new reference.
  final bool saved;

  /// What the machine knows, keyed by the same names the template's fields use.
  final Map<String, String> overrides = {};

  /// The thirteen exam findings the staff typed, keyed `exam.<key>`.
  final Map<String, String> exam = {};

  /// Staff-entered lines, keyed by the block's `key` (recommendations,
  /// clearance status, and so on).
  String operatorFor(String? key) {
    if (key == null) return '';
    return overrides[key] ?? '';
  }

  /// What a field block prints: the staff's own line if they wrote one, and
  /// otherwise the auto-filled value. Never blank when the machine knows it.
  String valueFor(DocBlock b) {
    final staff = operatorFor(b.key);
    if (staff.trim().isNotEmpty) return staff;
    if (b.placeholder != null) return values.of(b.placeholder!);
    if (b.key != null) return values.of(b.key!);
    return '';
  }

  void setOperator(String key, String value) => overrides[key] = value;

  void setExam(String key, String value) => exam[key] = value;

  String examValue(String key) {
    final typed = exam[key];
    if (typed != null && typed.trim().isNotEmpty) return typed;
    // Nothing typed: fall back to whatever the machine can infer, which for the
    // examination rows is deliberately very little.
    final known = values.of('exam.$key');
    return known.trim().isEmpty ? '' : known;
  }

  /// The auto-filled values with the staff's own lines laid over them.
  ///
  /// This is the only way a value is read, and it is deliberately computed
  /// BEFORE resolution rather than consulted during it: a sentence whose
  /// `{{recommendations}}` lives in a block with no `key` of its own still has
  /// to print what the nurse typed, and doing that inside the merge would mean
  /// the PDF and the preview could resolve it differently.
  DocumentValues get effective {
    final map = Map<String, String>.of(values.all);
    for (final b in template.blocks) {
      final key = b.key;
      if (key == null) continue;
      final staff = (overrides[key] ?? '').trim();
      if (staff.isEmpty) continue;
      if (b.placeholder != null) {
        map[b.placeholder!] = staff;
      } else {
        map[key] = staff;
      }
    }
    // A paragraph that names a placeholder directly, with no block key, is
    // overridden when the staff wrote a line of the same name.
    for (final b in template.blocks) {
      if (b.kind != DocBlockKind.paragraph || b.text == null) continue;
      for (final m
          in RegExp(r'\{\{\s*([a-z0-9_.]+)\s*\}\}').allMatches(b.text!)) {
        final n = m.group(1)!;
        final staff = (overrides[n] ?? '').trim();
        if (staff.isNotEmpty) map[n] = staff;
      }
    }
    for (final e in exam.entries) {
      if (e.value.trim().isEmpty) continue;
      map['exam.${e.key}'] = e.value;
    }
    return DocumentValues._(map, history: values.history);
  }

  /// Which placeholders still have nothing in them. The certificate form shows
  /// this as a checklist so a blank line is a decision, not an oversight.
  List<String> get unfilled => [
        for (final n in template.placeholderNames)
          if (!_isFilled(n)) n,
      ];

  bool _isFilled(String placeholder) {
    if (exam.containsKey(placeholder.replaceFirst('exam.', '')) &&
        (exam[placeholder.replaceFirst('exam.', '')] ?? '').trim().isNotEmpty) {
      return true;
    }
    final key = template.blocks
        .whereType<DocBlock>()
        .where((b) => b.placeholder == placeholder)
        .map((b) => b.key)
        .firstWhere((k) => k != null, orElse: () => null);
    if (key != null && (overrides[key] ?? '').trim().isNotEmpty) return true;
    return values.isFilled(placeholder);
  }

  /// The document as the engine resolved it, ready for the preview widget and
  /// the PDF writer alike. Nothing downstream re-reads the template.
  RenderedDocument resolve() {
    final v = effective;
    return RenderedDocument(
      template: template,
      referenceNo: 'preview',
      issuedBy: issuedBy,
      lines: [
        for (final b in template.blocks) _resolveBlock(b, v),
      ],
      unfilled: unfilled,
    );
  }

  RenderedLine _resolveBlock(DocBlock b, DocumentValues v) {
    switch (b.kind) {
      case DocBlockKind.title:
        return RenderedLine.heading(v.merge(b.text ?? ''));
      case DocBlockKind.heading:
        return RenderedLine.subheading(v.merge(b.text ?? ''));
      case DocBlockKind.paragraph:
        return RenderedLine.paragraph(v.merge(b.text ?? ''));
      case DocBlockKind.field:
        final value = valueFor(b);
        return RenderedLine.field(
          label: b.label ?? '',
          value: value.trim().isEmpty ? '—' : value,
        );
      case DocBlockKind.divider:
        return const RenderedLine.divider();
      case DocBlockKind.signature:
        // The block's text is a `signatory.` name, so a signature line picks the
        // signer whose name key it is, falling back to the only one there is.
        final who = _signatoryFor(b.text ?? '');
        return RenderedLine.signature(
          name: who?.name ?? '—',
          role: who?.role ?? '',
        );
      case DocBlockKind.examTable:
        return RenderedLine.examTable([
          for (final row in kPhysicalExamRows)
            [row.label, _examValue(b, row.key, v)],
        ]);
      case DocBlockKind.historyTable:
        return RenderedLine.historyTable([
          for (final h in v.history) [h.date, h.chiefComplaint, h.treatment],
        ]);
      case DocBlockKind.space:
        return const RenderedLine.space();
    }
  }

  /// The staff's finding if they wrote one, else what was inferred, else blank.
  String _examValue(DocBlock b, String key, DocumentValues v) {
    final typed = exam[key];
    if (typed != null && typed.trim().isNotEmpty) return typed;
    return v.of('exam.$key');
  }

  DocSignatory? _signatoryFor(String key) {
    final wanted = key.replaceFirst('signatory.', '');
    if (template.signatories.length == 1) return template.signatories.first;
    for (final s in template.signatories) {
      if (s.role.toLowerCase().contains(wanted) ||
          s.name.toLowerCase().contains(wanted)) {
        return s;
      }
    }
    return template.signatories.isEmpty ? null : template.signatories.first;
  }
}

// ── THE RESOLVED DOCUMENT ───────────────────────────────────────────────────

/// One resolved line. Both renderers consume only this.
class RenderedLine {
  const RenderedLine._(this.kind,
      {this.text = '', this.label = '', this.value = '', this.rows = const []});

  const RenderedLine.heading(String t) : this._(DocBlockKind.title, text: t);
  const RenderedLine.subheading(String t)
      : this._(DocBlockKind.heading, text: t);
  const RenderedLine.paragraph(String t)
      : this._(DocBlockKind.paragraph, text: t);
  const RenderedLine.field({required String label, required String value})
      : this._(DocBlockKind.field, label: label, value: value);
  const RenderedLine.divider() : this._(DocBlockKind.divider);
  const RenderedLine.signature({required String name, required String role})
      : this._(DocBlockKind.signature, text: name, value: role);
  const RenderedLine.examTable(List<List<String>> rows)
      : this._(DocBlockKind.examTable, rows: rows);
  const RenderedLine.historyTable(List<List<String>> rows)
      : this._(DocBlockKind.historyTable, rows: rows);
  const RenderedLine.space() : this._(DocBlockKind.space);

  final DocBlockKind kind;
  final String text;
  final String label;
  final String value;
  final List<List<String>> rows;
}

class RenderedDocument {
  const RenderedDocument({
    required this.template,
    required this.referenceNo,
    required this.issuedBy,
    required this.lines,
    this.unfilled = const [],
  });

  final DocTemplate template;
  final String referenceNo;
  final String issuedBy;
  final List<RenderedLine> lines;
  final List<String> unfilled;

  String get footer => template.footer;

  /// The body as plain text, for a copy-to-clipboard and for the test suite —
  /// it is the same resolution the PDF uses, so a test that passes here means
  /// the PDF says the right thing.
  String get plainText => [
        for (final l in lines)
          switch (l.kind) {
            DocBlockKind.field => '${l.label}: ${l.value}',
            DocBlockKind.signature => '${l.text} — ${l.value}',
            DocBlockKind.examTable ||
            DocBlockKind.historyTable =>
              l.rows.map((r) => r.join(' | ')).join('\n'),
            DocBlockKind.divider => '—'.padRight(20, '-'),
            _ => l.text,
          },
        if (footer.isNotEmpty) footer,
      ].where((s) => s.trim().isNotEmpty).join('\n');
}

// ── WORDING HELPERS ─────────────────────────────────────────────────────────

/// The small amount of English the paper forms need, in one place, so "21st" is
/// spelled the same way on every document.
class DocumentWords {
  const DocumentWords._();

  static String ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "21 September 2026" — the form's own date style, not the app's.
  static String longDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "21st day of September 2026", for the sentences that read "as of the …".
  static String ordinalDate(DateTime d) =>
      '${ordinal(d.day)} day of ${_months[d.month - 1]} ${d.year}';

  /// `MC-2026-0042` — the shape a reference number takes. The real counter comes
  /// from the database, which allocates it under a lock; this is for the preview
  /// and for making a number legible in a test.
  static String reference(String prefix, DateTime when, int sequence) =>
      '$prefix-${when.year}-${sequence.toString().padLeft(4, '0')}';
}

// ── THE SERVICE-SIDE VALUE OBJECT ───────────────────────────────────────────

/// An issued document, as stored. Immutable by construction: a re-issue is a new
/// one of these.
class IssuedDocument {
  const IssuedDocument({
    required this.id,
    required this.referenceNo,
    required this.templateName,
    required this.templateVersion,
    required this.documentType,
    required this.issuedAt,
    this.pdfUrl,
    this.data = const {},
  });

  final int? id;
  final String referenceNo;
  final String templateName;
  final int templateVersion;
  final String documentType;
  final DateTime? issuedAt;
  final String? pdfUrl;
  final Map<String, dynamic> data;

  factory IssuedDocument.fromSupabase(Map<String, dynamic> row) =>
      IssuedDocument(
        id: (row['id'] as num?)?.toInt(),
        referenceNo: '${row['reference_no'] ?? ''}',
        templateName: '${row['template_name'] ?? ''}',
        templateVersion: (row['template_version'] as num?)?.toInt() ?? 1,
        documentType: '${row['document_type'] ?? 'certificate'}',
        issuedAt: DateTime.tryParse('${row['issued_at'] ?? ''}'),
        pdfUrl: row['pdf_url'] as String?,
        data: (row['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  Map<String, dynamic> toSupabase() => {
        'template_name': templateName,
        'template_version': templateVersion,
        'document_type': documentType,
        'reference_no': referenceNo,
        'data': data,
        if (pdfUrl != null) 'pdf_url': pdfUrl,
      };
}

/// Builds the [DocumentDraft] for the medical-certificate service from the
/// controller's state, so the auto-fill and the form on screen are the same
/// source and cannot drift.
DocumentDraft buildCertificateDraft({
  required DocTemplate template,
  required VisitDetailsController controller,
  required ClinicProfile profile,
  required DateTime visitDate,
  String issuedBy = '',
  String civilStatus = '',
  List<HistoryRow> history = const [],
}) {
  final med = controller.draftFor('medicine_certificate');
  final clearance = controller.draftFor('medical_clearance');
  final consultation = controller.draftFor('medicine_consultation');

  final values = DocumentContext(
    profile: profile,
    visitDate: visitDate,
    vitals: controller.vitals,
    civilStatus: civilStatus,
    purpose: med?.text('purpose') ?? clearance?.text('purpose') ?? '',
    reason:
        med?.text('reason') ?? consultation?.text('complaint_details') ?? '',
    diagnosis: consultation?.text('diagnosis') ?? '',
    recommendations: med?.text('recommendations') ??
        clearance?.text('recommendations') ??
        '',
    excusedFor: med?.text('excused_for') ?? '',
    clearanceStatus:
        med?.text('clearance_status') ?? clearance?.text('status') ?? '',
    notClearedFor: clearance?.text('not_cleared_for') ?? '',
    validityDate: clearance?.text('validity_date') ?? '',
    issuedPlace: DocTemplate.clinicDepartment,
    history: history,
  ).buildValues();

  final draft = DocumentDraft(
    template: template,
    values: values,
    issuedBy: issuedBy.isNotEmpty ? issuedBy : controller.staffName,
  );

  // Carry over anything the nurse already typed on the form, so opening the
  // preview does not wipe a line they wrote two slides ago.
  for (final key in [
    'recommendations',
    'excused_for',
    'clearance_status',
    'reason'
  ]) {
    final v = med?.text(key).trim() ?? '';
    if (v.isNotEmpty) draft.setOperator(key, v);
  }
  return draft;
}
