import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';

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

  static const DocSignatory tcgcHead = DocSignatory(
    name: 'Francislee N. Famacion',
    role: 'Head, Medical and Dental Clinic',
  );
  static const DocSignatory physician = DocSignatory(
    name: 'Dr. Noriel G. Apao',
    role: 'College Physician',
  );
}

enum DocBlockKind {
  title,

  heading,

  paragraph,

  field,

  divider,

  signature,

  examTable,

  historyTable,

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

  final String? placeholder;
}

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
    this.fillInBlanks = false,
  });

  final String name;

  final String type;
  final int version;

  final String subtitle;

  final List<DocBlock> blocks;
  final List<DocSignatory> signatories;
  final String footer;

  final String referencePrefix;

  final bool fillInBlanks;

  List<String> get placeholderNames {
    final out = <String>[];
    void add(String n) {
      if (!out.contains(n)) out.add(n);
    }

    for (final b in blocks) {
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

  DocTemplate withSignatories(List<DocSignatory> signatories) => DocTemplate(
        name: name,
        type: type,
        version: version,
        subtitle: subtitle,
        blocks: blocks,
        signatories: signatories,
        footer: footer,
        referencePrefix: referencePrefix,
        fillInBlanks: fillInBlanks,
      );

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
        'fill_in_blanks': fillInBlanks,
      };

  static const String clinicName = 'Tangub City Global College';
  static const String clinicDepartment = 'Medical and Dental Clinic Office';
  static const String formerName = 'GADC';

  static const DocTemplate medicalCertificate = DocTemplate(
    name: 'Medical Certificate',
    type: 'certificate',
    version: 2,
    subtitle: clinicDepartment,
    referencePrefix: 'MC',
    fillInBlanks: true,
    blocks: [
      DocBlock.title('CERTIFICATION'),
      DocBlock.paragraph(
        'This is to certify that {{visitor.full_name}}, {{visitor.age}} years '
        'old, {{visitor.sex_or_prompt}} from {{visitor.address}}, appeared '
        'last {{visit.date}} at TCGC Medical and Dental Clinic due to '
        '{{visit.reason}}.',
      ),
      DocBlock.paragraph(
        'This certification is issued upon the request of the above name '
        'person for whatever legal purpose may serve so that she will be '
        'excused for {{excused_for}}.',
      ),
      DocBlock.paragraph(
        'Issued this {{issued.day}} day of {{issued.month}}, '
        '{{issued.year}} at Tangub City, Philippines.',
      ),
      DocBlock.space(),
      DocBlock.signature('signatory.head'),
    ],
    signatories: [DocSignatory.tcgcHead],
    footer:
        'Learn Today, Light of the World · Honesty · Compassion · Excellence',
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

  static const Map<String, DocTemplate> builtIns = {
    'certificate': medicalCertificate,
    'certification': certification,
    'client_record': individualClientsRecord,
  };

  factory DocTemplate.fromSupabase(Map<String, dynamic> row) {
    final type = '${row['type'] ?? 'certificate'}';
    final fallback = builtIns[type] ?? medicalCertificate;
    final rawBlocks = row['blocks'];

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
      fillInBlanks: row['fill_in_blanks'] is bool
          ? row['fill_in_blanks'] as bool
          : fallback.fillInBlanks,
      blocks: rawBlocks is List && rawBlocks.isNotEmpty
          ? [
              for (final b in rawBlocks.whereType<Map>())
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

class DocumentValues {
  DocumentValues._(this._map, {this.history = const []});

  final Map<String, String> _map;

  final List<HistoryRow> history;

  String of(String placeholder) => _map[placeholder] ?? '';

  Map<String, String> get all => Map<String, String>.unmodifiable(_map);

  bool isFilled(String placeholder) => of(placeholder).trim().isNotEmpty;

  String merge(String text) => text.replaceAllMapped(
        RegExp(r'\{\{\s*([a-z0-9_.]+)\s*\}\}'),
        (m) {
          final v = of(m.group(1)!);
          return v.trim().isEmpty ? '—' : v;
        },
      );

  List<DocSegment> fill(String text) {
    final out = <DocSegment>[];
    var last = 0;
    for (final m in RegExp(r'\{\{\s*([a-z0-9_.]+)\s*\}\}').allMatches(text)) {
      if (m.start > last) {
        out.add(DocSegment(text.substring(last, m.start)));
      }
      out.add(
          DocSegment(of(m.group(1)!).trim(), blank: true, name: m.group(1)!));
      last = m.end;
    }
    if (last < text.length) out.add(DocSegment(text.substring(last)));
    return out;
  }
}

class DocSegment {
  const DocSegment(this.text, {this.blank = false, this.name = ''});

  final String text;
  final bool blank;

  final String name;
}

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

class DocumentContext {
  DocumentContext({
    required this.profile,
    this.visitDate,
    required this.vitals,
    this.issuedOn,
    this.ageAsOf,
    this.civilStatus = '',
    this.purpose = '',
    this.reason = '',
    this.diagnosis = '',
    this.recommendations = '',
    this.excusedFor = '',
    this.clearanceStatus = '',
    this.issuedPlace = '',
    this.history = const [],
    this.examFindings = const {},
  });

  final ClinicProfile profile;

  final DateTime? visitDate;

  final VisitVitals vitals;

  final DateTime? issuedOn;

  final DateTime? ageAsOf;

  final String civilStatus;

  final String purpose;
  final String reason;
  final String diagnosis;
  final String recommendations;
  final String excusedFor;
  final String clearanceStatus;
  final String issuedPlace;

  final List<HistoryRow> history;

  final Map<String, String> examFindings;

  int? get age {
    final bd = profile.birthDate;
    if (bd.isEmpty) return null;
    final b = DateTime.tryParse(bd);
    if (b == null) return null;
    final asOf = ageAsOf ?? DateTime.now();
    var years = asOf.year - b.year;
    final hadBirthday =
        asOf.month > b.month || (asOf.month == b.month && asOf.day >= b.day);
    if (!hadBirthday) years -= 1;
    return years < 0 ? null : years;
  }

  String get ageOrdinal {
    final a = age;
    return a == null ? '' : DocumentWords.ordinal(a);
  }

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

  String get pronounBe => pronounSubject == 'they' ? 'were' : 'was';

  DocumentValues buildValues() {
    final v = vitals;
    final bp = v.bloodPressure;
    final bmi = v.bmi;
    final visit = visitDate;
    final issued = issuedOn ?? visit ?? DateTime.now();
    return DocumentValues._(
      {
        'visitor.full_name': profile.fullName,
        'visitor.age': age?.toString() ?? '',
        'visitor.age_ordinal': ageOrdinal,
        'visitor.sex': profile.sex,
        'visitor.sex_lower': _lower(profile.sex),
        'visitor.sex_or_prompt':
            profile.sex.trim().isEmpty ? 'female/male' : _lower(profile.sex),
        'visitor.address': profile.address,
        'visitor.id_no': profile.id,
        'visitor.course':
            profile.program.isEmpty ? profile.programLabel : profile.program,
        'visitor.institute':
            profile.institute.isEmpty ? profile.department : profile.institute,
        'visitor.birthday': profile.birthDate,
        'visitor.civil_status': civilStatus,
        'visit.date': visit == null ? '' : DocumentWords.longDate(visit),
        'visit.date_ordinal':
            visit == null ? '' : DocumentWords.ordinalDate(visit),
        'visit.reason': reason,
        'visit.purpose': purpose,
        'visit.purpose_lower': _lower(purpose),
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
        'recommendations': recommendations,
        'diagnosis': diagnosis,
        'excused_for': excusedFor,
        'pronoun.subject': pronounSubject,
        'pronoun.be': pronounBe,
        'issued.date': DocumentWords.longDate(issued),
        'issued.day': '${issued.day}',
        'issued.month': DocumentWords.monthName(issued.month),
        'issued.year2': DocumentWords.twoDigitYear(issued.year),
        'issued.year': '${issued.year}',
        'issued_on_ordinal': DocumentWords.ordinalDate(issued),
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

class DocumentDraft {
  DocumentDraft({
    required this.template,
    required this.values,
    this.issuedBy = '',
    this.saved = false,
  });

  final DocTemplate template;
  final DocumentValues values;

  final String issuedBy;

  final bool saved;

  final Map<String, String> overrides = {};

  final Map<String, String> exam = {};

  String operatorFor(String? key) {
    if (key == null) return '';
    return overrides[key] ?? '';
  }

  String valueFor(DocBlock b) {
    final staff = operatorFor(b.key);
    if (staff.trim().isNotEmpty) return staff;
    if (b.placeholder != null) return values.of(b.placeholder!);
    if (b.key != null) return values.of(b.key!);
    return '';
  }

  void setOperator(String key, String value) => overrides[key] = value;

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
        if (template.fillInBlanks) {
          return RenderedLine.fillParagraph(v.fill(b.text ?? ''));
        }
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

class RenderedLine {
  const RenderedLine._(this.kind,
      {this.text = '',
      this.label = '',
      this.value = '',
      this.rows = const [],
      this.segments = const []});

  const RenderedLine.heading(String t) : this._(DocBlockKind.title, text: t);
  const RenderedLine.subheading(String t)
      : this._(DocBlockKind.heading, text: t);
  const RenderedLine.paragraph(String t)
      : this._(DocBlockKind.paragraph, text: t);

  RenderedLine.fillParagraph(List<DocSegment> segments)
      : this._(
          DocBlockKind.paragraph,
          text: [for (final s in segments) s.text].join(),
          segments: segments,
        );

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

  final List<DocSegment> segments;
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
}

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

  static String longDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String monthName(int month) =>
      (month >= 1 && month <= 12) ? _months[month - 1] : '';

  static String twoDigitYear(int year) =>
      (year % 100).toString().padLeft(2, '0');

  static String ordinalDate(DateTime d) =>
      '${ordinal(d.day)} day of ${_months[d.month - 1]} ${d.year}';
}

DocumentDraft buildCertificateDraft({
  required DocTemplate template,
  required VisitDetailsController controller,
  required ClinicProfile profile,
  DateTime? clinicVisitDate,
  required DateTime issuedOn,
  String issuedBy = '',
  String civilStatus = '',
  String visitReason = '',
  String signatoryName = '',
  String signatoryRole = '',
  List<HistoryRow> history = const [],
}) {
  final med = controller.draftFor('medicine_certificate');
  final consultation = controller.draftFor('medicine_consultation');

  final named = signatoryName.trim();
  final sheet = named.isEmpty
      ? template
      : template.withSignatories([
          DocSignatory(
            name: named,
            role: signatoryRole.trim().isNotEmpty
                ? signatoryRole.trim()
                : (template.signatories.isEmpty
                    ? DocSignatory.tcgcHead.role
                    : template.signatories.first.role),
          ),
        ]);

  final typedReason = (med?.text('reason') ?? '').trim();
  final String reason;
  if (typedReason.isNotEmpty) {
    reason = typedReason;
  } else if (visitReason.trim().isNotEmpty) {
    reason = visitReason.trim();
  } else if (consultation == null) {
    reason = '';
  } else {
    reason = consultationComplaintDetails(consultation.data);
  }

  final values = DocumentContext(
    profile: profile,
    visitDate: clinicVisitDate,
    issuedOn: issuedOn,
    ageAsOf: clinicVisitDate ?? issuedOn,
    vitals: controller.vitals,
    civilStatus: civilStatus,
    purpose: med?.text('purpose') ?? '',
    reason: reason,
    diagnosis: med?.text('diagnosis') ??
        (consultation == null
            ? null
            : consultationDiagnosis(consultation.data)) ??
        consultation?.text('diagnosis') ??
        '',
    recommendations: med?.text('recommendations') ?? '',
    excusedFor: med?.text('excused_for') ?? '',
    clearanceStatus: med?.text('clearance_status') ?? '',
    issuedPlace: DocTemplate.clinicDepartment,
    history: history,
  ).buildValues();

  final draft = DocumentDraft(
    template: sheet,
    values: values,
    issuedBy: issuedBy.isNotEmpty ? issuedBy : controller.staffName,
  );

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
