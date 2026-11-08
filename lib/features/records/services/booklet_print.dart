import 'dart:convert' show HtmlEscape;

import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';

import 'package:clinicmanagementsystem/shared/printing/document_template.dart';
import 'package:clinicmanagementsystem/shared/printing/html_sheet.dart';

enum BookletReportKind { service, individual, daily, byInstitute }

const bool kShowImpressionOnDailyAndInstitute = false;

const Map<String, String> kServiceCodes = {
  'vital_signs': 'VS',
  'bp_tracking': 'VS',
  'bpi': 'BMI',
  'wound_dressing': 'WD',
  'first_aid_treatment': 'FA',
  'medication': 'MED',
  'medicine_consultation': 'CONS',
  'health_counselling': 'CNS',
  'prenatal': 'PN',
  'medicine_certificate': 'CERT',
};

const PdfColor _green = PdfColor.fromInt(0xFF0E6B47);
const PdfColor _headFill = PdfColor.fromInt(0xFFE7EFEA);

/// Signature of the callback the app passes in so the printed service names
/// match the booklet table (BP Taking, Temperature Checking, ...).
typedef DraftLabelFn = String Function(
    ServiceDraft draft, VisitDetailsController controller);

class _Ctx {
  _Ctx(this.d, this.c, this.when, this.label);
  final ServiceDraft d;
  final VisitDetailsController c;
  final DateTime? when;

  /// Display name of the service (e.g. "BP Taking" instead of "Vital signs").
  final String label;
}

/// One service in the "SERVICE & FINDING" column: a bold service name and
/// labeled detail rows underneath (Height: 160 cm, Weight: 55 kg, ...).
class _Line {
  const _Line(this.code, this.label, this.rows);
  final String code;
  final String label;
  final List<(String, String)> rows;
}

List<(String, String)> _rows(List<(String, String)> r) => [
      for (final e in r)
        if (e.$2.trim().isNotEmpty) (e.$1, e.$2.trim()),
    ];
/// Short labels used in the SERVICE & FINDING column.
const Map<String, String> _abbr = {
  // vitals
  'BP': 'BP',
  'Pulse rate': 'PR',
  'Temperature': 'T',
  'Respiratory rate': 'RR',
  'SpO2': 'SpO2',
  'Position / Arm': 'Pos/Arm',
  'Action taken': 'Act',
  'Referred to': 'Ref',
  'Referral reason': 'Ref Rsn',
  // bmi
  'Height': 'H',
  'Weight': 'W',
  'BMI': 'BMI',
  'Notes': 'Note',
  'Note': 'Note',
  // wound / first aid
  'When': 'When',
  'How': 'How',
  'Location': 'Loc',
  'Wound type': 'Type',
  'Burn degree': 'Burn',
  'Condition': 'Cond',
  'Bleeding': 'Bleed',
  'Tetanus shot': 'TT',
  'Findings': 'Fnd',
  'Cleaned with': 'Clean',
  'Dressing': 'Dsg',
  'Medicine': 'Med',
  'Next dressing': 'Next Dsg',
  'Incident': 'Inc',
  'Where': 'Where',
  'Body part': 'Part',
  'Pain level': 'Pain',
  'Head injury signs': 'Head Inj',
  'Consciousness': 'LOC',
  'First aid given': 'FA',
  'Minutes rested': 'Rest',
  'Condition after': 'Cond After',
  'Disposition': 'Dispo',
  'Sent home with': 'Sent',
  'Follow-up': 'F/U',
  // medication / consultation
  'Reason': 'Rsn',
  'Chief complaint': 'CC',
  'Complaint category': 'Cat',
  'Duration': 'Dur',
  'Danger signs': 'DS',
  'Impression': 'Imp',
  'Treatment': 'Tx',
  // counselling / prenatal / cert
  'Session': 'Sess',
  'AOG': 'AOG',
  'FHT': 'FHT',
  'Fetal movement': 'FM',
  'Edema': 'Edema',
  'Urine protein': 'U-Prot',
  'Service': 'Svc',
  'Given this visit': 'Given',
  'Action': 'Act',
  'Excused for': 'Excused',
  'Days': 'Days',
  'Issued': 'Issued',
};

String _short(String label) => _abbr[label] ?? label;

/// Detail items for one service, e.g. ["H: 147 cm", "W: 43 kg", ...].
List<String> _items(_Line l) => [
      for (final r in l.rows) '${_short(r.$1)}: ${r.$2}',
    ];

String _txt(Object? raw, [String sep = ', ']) {
  if (raw == null) return '';
  if (raw is Iterable) {
    return raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).join(sep);
  }
  return '$raw'.trim();
}

String _first(ServiceDraft d, List<String> keys, [String sep = ', ']) {
  for (final k in keys) {
    final t = _txt(d.data[k], sep);
    if (t.isNotEmpty) return t;
  }
  return '';
}

/// Value of a field, with the word "Other" replaced by what was typed.
String _v(ServiceDraft d, String key, [String sep = ', ']) {
  final other = _txt(d.data['${key}_other']);
  final raw = d.data[key];
  final items = raw is Iterable ? raw.map((e) => '$e'.trim()) : [_txt(raw)];
  return items
      .where((e) => e.isNotEmpty)
      .map((e) => (e == 'Other' && other.isNotEmpty) ? other : e)
      .join(sep);
}

/// Adds a unit unless the value already carries one.
String _u(String v, String unit) => v.isEmpty
    ? ''
    : (RegExp(r'[a-zA-Z%°]').hasMatch(v) ? v : '$v $unit');

String _num(Object? n) {
  if (n == null) return '';
  if (n is num) {
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }
  return '$n'.trim();
}

String _pick(String a, String b) => a.isNotEmpty ? a : b;

String _pretty(String iso, [String f = 'MMM d, yyyy']) {
  final d = DateTime.tryParse(iso.trim());
  return d == null ? iso.trim() : DateFormat(f).format(d);
}

String _bp(VisitDetailsController c) {
  final v = c.vitals;
  if (v.systolic == null || v.diastolic == null) return '';
  return '${v.systolic}/${v.diastolic}';
}

String _reading(VisitDetailsController c, List<String> needles) {
  for (final r in c.vitals.readings) {
    final l = '${r.label}'.toLowerCase();
    if (needles.any(l.contains)) return '${r.display}';
  }
  return '';
}

String _pr(_Ctx x) =>
    _pick(_num(x.c.vitals.heartRate), _reading(x.c, ['pulse', 'heart']));
String _rr(_Ctx x) =>
    _pick(_first(x.d, ['resp_rate']), _reading(x.c, ['resp', 'rr']));
String _temp(_Ctx x) => _pick(_first(x.d, ['temp_c']), _reading(x.c, ['temp']));
String _spo2(_Ctx x) => _pick(
    _first(x.d, ['spo2', 'o2_sat']), _reading(x.c, ['o2', 'spo', 'oxygen']));

String _height(_Ctx x) => _pick(
    _pick(_first(x.d, ['height_cm', 'height']), _num(x.c.vitals.heightCm)),
    _reading(x.c, ['height']));
String _weight(_Ctx x) =>
    _pick(_num(x.c.vitals.weightKg), _reading(x.c, ['weight']));
String _bmi(_Ctx x) {
  final b = x.c.vitals.bmi;
  return b == null ? '' : b.toStringAsFixed(1);
}

String _bmiClass(_Ctx x) => '${x.c.vitals.bmiReading?.category ?? ''}';

String _bpClass(_Ctx x) {
  final s = x.c.vitals.systolic, d = x.c.vitals.diastolic;
  if (s == null || d == null) return '';
  if (s > 180 || d > 120) return 'Hypertensive Crisis';
  if (s >= 140 || d >= 90) return 'Hypertension Stage 2';
  if (s >= 130 || d >= 80) return 'Hypertension Stage 1';
  if (s >= 120) return 'Elevated';
  if (s < 90 || d < 60) return 'Low';
  return 'Normal';
}

String _aog(_Ctx x) {
  final lmp = DateTime.tryParse(_first(x.d, ['lmp']));
  final at = x.when;
  if (lmp == null || at == null) return '';
  final days = at.difference(lmp).inDays;
  if (days < 0) return '';
  return '${days ~/ 7}w ${days % 7}d';
}

String _codeFromLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('certificate')) return 'CERT';
  if (l.contains('vital') || l.contains('bp')) return 'VS';
  if (l.contains('bmi') || l.contains('body mass')) return 'BMI';
  if (l.contains('wound')) return 'WD';
  if (l.contains('first aid')) return 'FA';
  if (l.contains('consult')) return 'CONS';
  if (l.contains('counsel')) return 'CNS';
  if (l.contains('prenatal')) return 'PN';
  if (l.contains('medication')) return 'MED';
  final t = label.trim();
  return t.length <= 3 ? t.toUpperCase() : t.substring(0, 3).toUpperCase();
}

List<_Line> _linesFor(_Ctx x, bool impression) {
  final d = x.d;
  final code = kServiceCodes[d.serviceId] ?? _codeFromLabel(d.label);
  List<_Line> one(List<(String, String)> r) => [_Line(code, x.label, _rows(r))];

  switch (d.serviceId) {
    case 'vital_signs':
    case 'bp_tracking':
      final bp = _bp(x.c);
      final cls = _bpClass(x);
      final temp = _temp(x);
      final method = _v(d, 'method');
      return one([
        (
          'BP',
          bp.isEmpty ? '' : '${_u(bp, 'mmHg')}${cls.isEmpty ? '' : ' ($cls)'}'
        ),
        ('Pulse rate', _u(_pr(x), 'bpm')),
        (
          'Temperature',
          '${_u(temp, '°C')}${temp.isEmpty || method.isEmpty ? '' : ' ($method)'}'
        ),
        ('Respiratory rate', _u(_rr(x), '/min')),
        ('SpO2', _u(_spo2(x), '%')),
        (
          'Position / Arm',
          [_v(d, 'position'), _v(d, 'arm_used')]
              .where((e) => e.isNotEmpty)
              .join(' / ')
        ),
        ('Action taken', _v(d, 'action_taken', '; ')),
        ('Referred to', _v(d, 'referred_to')),
        ('Referral reason', _v(d, 'referral_reason')),
      ]);
    case 'bpi':
      final k = _bmiClass(x);
      final b = _bmi(x);
      return one([
        ('Height', _u(_height(x), 'cm')),
        ('Weight', _u(_weight(x), 'kg')),
        ('BMI', b.isEmpty ? '' : '$b${k.isEmpty ? '' : ' ($k)'}'),
        ('Notes', _v(d, 'notes')),
      ]);
    case 'wound_dressing':
      return one([
        ('When', _v(d, 'injury_timing')),
        ('How', _v(d, 'injury_cause')),
        ('Location', _v(d, 'wound_location')),
        ('Wound type', _v(d, 'wound_type')),
        ('Burn degree', _v(d, 'burn_degree')),
        ('Condition', _v(d, 'wound_condition')),
        ('Bleeding', _v(d, 'bleeding')),
        ('Tetanus shot', _v(d, 'tetanus_status')),
        ('Findings', _v(d, 'assessment')),
        ('Cleaned with', _v(d, 'cleaning_performed')),
        ('Dressing', _v(d, 'dressing_applied')),
        ('Medicine', d.medicines.map((m) => m.name).join(', ')),
        ('Action taken', _v(d, 'action_taken', '; ')),
        ('Referred to', _v(d, 'referred_to')),
        ('Next dressing', _pretty(_first(d, ['next_dressing_date']))),
        ('Notes', _v(d, 'notes')),
      ]);
    case 'first_aid_treatment':
      return one([
        ('Incident', _v(d, 'incident')),
        ('When', _v(d, 'incident_timing')),
        ('Where', _v(d, 'incident_place')),
        ('How', _v(d, 'incident_cause')),
        ('Body part', _v(d, 'body_part')),
        ('Findings', _v(d, 'findings')),
        ('Pain level', _u(_v(d, 'pain_level'), '/10')),
        ('Head injury signs', _v(d, 'head_injury_signs')),
        ('Consciousness', _v(d, 'consciousness')),
        ('First aid given', _v(d, 'treatment', '; ')),
        ('Medicine', _v(d, 'medication_given')),
        ('Minutes rested', _v(d, 'observation_minutes')),
        ('Condition after', _v(d, 'condition_after')),
        ('Disposition', _v(d, 'disposition')),
        ('Referred to', _v(d, 'referred_to_where')),
        ('Sent home with', _v(d, 'sent_to')),
        ('Follow-up', _pretty(_first(d, ['follow_up_date']))),
        ('Notes', _v(d, 'notes')),
      ]);
    case 'medication':
      final why = _v(d, 'reason_common');
      return one([
        ('Reason', why),
        for (final m in d.medicines)
          (
            m.name,
            [
              if (_num(m.quantity).isNotEmpty) 'Qty ${_num(m.quantity)}',
              if (m.frequency.trim().isNotEmpty) m.frequency.trim(),
              if (m.action.trim().isNotEmpty) '(${m.action.trim()})',
            ].join(', ')
          ),
      ]);
    case 'medicine_consultation':
      return one([
        ('Chief complaint', _v(d, 'chief_complaint')),
        ('Complaint category', _v(d, 'symptoms')),
        (
          'Duration',
          [_v(d, 'duration_onset_choice'), _v(d, 'duration_onset')]
              .where((e) => e.isNotEmpty)
              .join(', ')
        ),
        ('Danger signs', _v(d, 'red_flags')),
        if (impression) ('Impression', _v(d, 'clinical_impression')),
        ('Treatment', _v(d, 'treatment', '; ')),
        ('Disposition', _v(d, 'disposition')),
        ('Referred to', _v(d, 'referred_to')),
        ('Follow-up', _pretty(_first(d, ['follow_up_date']))),
      ]);
    case 'health_counselling':
      // Restricted: the booklet stays minimal on purpose.
      final type = _v(d, 'session_type');
      return one([
        ('Session', type.isEmpty ? 'Session held' : type),
        ('Duration', _u(_first(d, ['duration_minutes', 'duration']), 'min')),
        ('Follow-up', _pretty(_first(d, ['follow_up_date']))),
        ('Note', 'Restricted'),
      ]);
    case 'prenatal':
      return one([
        ('AOG', _aog(x)),
        ('BP', _u(_bp(x.c), 'mmHg')),
        ('FHT', _u(_first(d, ['fetal_heart_tone']), 'bpm')),
        ('Fetal movement', _v(d, 'fetal_movement')),
        ('Edema', _v(d, 'edema')),
        ('Urine protein', _v(d, 'urine_protein')),
        ('Danger signs', _v(d, 'danger_signs')),
        ('Service', _v(d, 'service_provided', '; ')),
        ('Given this visit', _v(d, 'given_this_visit')),
        ('Action', _v(d, 'action_taken', '; ')),
        ('Referred to', _v(d, 'referred_to')),
        ('Follow-up', _pretty(_first(d, ['follow_up_date']))),
      ]);
    case 'medicine_certificate':
      return one([
        ('Excused for', _first(d, ['excused_for'])),
        ('Days', _first(d, ['days', 'excused_days', 'number_of_days'])),
        ('Issued', _pretty(_first(d, ['cert_issued_on']))),
      ]);
    default:
      return one(const []);
  }
}

DateTime? _t(String s) {
  final v = s.trim();
  if (v.isEmpty || v == '-' || v == '—') return null;
  for (final f in const ['hh:mm a', 'h:mm a', 'HH:mm:ss', 'HH:mm']) {
    final d = DateFormat(f).tryParse(v);
    if (d != null) return d;
  }
  return null;
}

String _stay(String tin, String tout) {
  final a = _t(tin), b = _t(tout);
  if (a == null || b == null) return '—';
  var m = b.difference(a).inMinutes;
  if (m < 0) m += 1440;
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

class _V {
  _V({
    required this.record,
    required this.name,
    required this.id,
    required this.inst,
    required this.group,
    required this.year,
    required this.type,
    required this.complaint,
    required this.date,
    required this.tin,
    required this.tout,
    required this.stay,
    required this.open,
    required this.by,
    required this.lines,
    required this.codes,
    required this.drafts,
    required this.vc,
    required this.when,
    this.parts,
  });
  final Map<String, String> record;
  final String name, id, inst, group, year, type, complaint, date;
  final String tin, tout, stay, by;
  final bool open;
  final List<_Line> lines;
  final List<String> codes;
  final List<ServiceDraft> drafts;
  final VisitDetailsController? vc;
  final DateTime? when;

  /// When AM and PM visits of the same person on the same date are merged
  /// into one row, the original visits are kept here.
  final List<_V>? parts;
}

String _idOf(Map<String, String> r) {
  final p = (r['personId'] ?? '').trim();
  return p.isNotEmpty ? p : (r['id'] ?? '').trim();
}

String _nameOf(Map<String, String> r, Map<String, IndividualRecord> roster) {
  final p = roster[_idOf(r)];
  if (p != null && p.lastName.trim().isNotEmpty) {
    final mid = p.middleName.trim();
    return '${p.lastName.trim()}, ${p.firstName.trim()}'
        '${mid.isEmpty ? '' : ' ${mid[0]}.'}';
  }
  return (r['name'] ?? '').trim();
}

_V _visit(
  Map<String, String> r,
  VisitDetailsController? vc,
  Map<String, IndividualRecord> roster,
  Set<String> selected,
  bool impression,
  DraftLabelFn draftLabel,
) {
  final when = DateTime.tryParse(r['date'] ?? '');
  final lines = <_Line>[];
  final codes = <String>[];
  final used = <ServiceDraft>[];
  final drafts = vc?.drafts ?? const <ServiceDraft>[];

  if (vc != null && drafts.isNotEmpty) {
    for (final d in drafts) {
      final shown = draftLabel(d, vc);
      if (selected.isNotEmpty &&
          !selected.contains(shown.trim().toLowerCase()) &&
          !selected.contains(d.label.trim().toLowerCase())) {
        continue;
      }
      codes.add(kServiceCodes[d.serviceId] ?? _codeFromLabel(d.label));
      used.add(d);
      lines.addAll(_linesFor(_Ctx(d, vc, when, shown), impression));
    }
  } else {
    for (final n in (r['complaint'] ?? '').split(',')) {
      final label = n.trim();
      if (label.isEmpty) continue;
      if (selected.isNotEmpty && !selected.contains(label.toLowerCase())) {
        continue;
      }
      final c = _codeFromLabel(label);
      codes.add(c);
      lines.add(_Line(c, label, const []));
    }
  }

  final tin = (r['time'] ?? '').trim();
  final rawOut = (r['timeOut'] ?? '').trim();
  final open = _t(rawOut) == null;
  final reason = (r['reason'] ?? '').trim();
  final program = (r['program'] ?? '').trim();
  final group = program.isNotEmpty
      ? program
      : [r['department'], r['institute'], r['dept']]
          .map((e) => (e ?? '').trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => 'Other');

  return _V(
    record: r,
    name: _nameOf(r, roster),
    id: _idOf(r),
    inst: (r['dept'] ?? '').trim(),
    group: group,
    year: (r['year'] ?? '').trim(),
    type: (r['type'] ?? '').trim(),
    complaint: reason.isNotEmpty ? reason : (r['complaint'] ?? '').trim(),
    date: r['date'] ?? '',
    tin: tin,
    tout: open ? '—' : rawOut,
    stay: open ? '—' : _stay(tin, rawOut),
    open: open,
    by: (r['createdBy'] ?? '').trim(),
    lines: lines,
    codes: codes,
    drafts: used,
    vc: vc,
    when: when,
  );
}

/// Same person + same date = ONE row (AM and PM visits together),
/// exactly like the table on the screen.
List<_V> _mergeSameDay(List<_V> vs) {
  final order = <String>[];
  final groups = <String, List<_V>>{};
  for (final v in vs) {
    final key = '${v.id}|${v.date.trim()}';
    if (!groups.containsKey(key)) order.add(key);
    groups.putIfAbsent(key, () => []).add(v);
  }
  return [
    for (final k in order)
      groups[k]!.length == 1 ? groups[k]!.first : _combine(groups[k]!),
  ];
}

_V _combine(List<_V> g) {
  final f = g.first;
  final complaints = <String>[];
  for (final v in g) {
    if (v.complaint.isNotEmpty && !complaints.contains(v.complaint)) {
      complaints.add(v.complaint);
    }
  }
  return _V(
    record: f.record,
    name: f.name,
    id: f.id,
    inst: f.inst,
    group: f.group,
    year: f.year,
    type: f.type,
    complaint: complaints.join(' / '),
    date: f.date,
    tin: g.map((v) => v.tin).join('\n'),
    tout: g.map((v) => v.tout).join('\n'),
    stay: '—',
    open: g.any((v) => v.open),
    by: f.by,
    lines: [for (final v in g) ...v.lines],
    codes: [for (final v in g) ...v.codes],
    drafts: [for (final v in g) ...v.drafts],
    vc: f.vc,
    when: f.when,
    parts: g,
  );
}

pw.Widget _cell(String t,
    {bool bold = false, bool center = false, double size = 9}) {
  return pw.Container(
    alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(
      t,
      textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// Name only. The ID number is intentionally not printed.
pw.Widget _nameCell(_V v) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(v.name,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );

/// The single "SERVICE & FINDING" cell.
pw.Widget _linesCell(List<_Line> ls) {
  if (ls.isEmpty) return _cell('—');
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in ls)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Service name on its own line
                pw.Text(l.label,
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                // Details in one flowing line: A | B | C
                if (_items(l).isNotEmpty)
                  pw.RichText(
                    text: pw.TextSpan(
                      style: const pw.TextStyle(fontSize: 8.5),
                      children: [
                        for (final (i, t) in _items(l).indexed) ...[
                          pw.TextSpan(text: t),
                          if (i < _items(l).length - 1)
                            const pw.TextSpan(text: '  |  '),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _table(
    List<String> headers, List<double> flex, List<List<pw.Widget>> rows) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
    columnWidths: {
      for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i]),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _headFill),
        children: [
          for (final h in headers)
            _cell(h, bold: true, center: true, size: 8.5),
        ],
      ),
      for (final r in rows) pw.TableRow(children: r),
    ],
  );
}

// ---------------------------------------------------------------------------
// Individual Client Record table (no STAY column)
// ---------------------------------------------------------------------------

const List<double> _indFlex = [.4, 1.2, .8, .8, 1.8, 5.7];

pw.Widget _individualTable(List<_V> vs, bool blankRows) {
  const heads = [
    'NO',
    'DATE',
    'TIME IN',
    'TIME OUT',
    'REASON/COMPLAINT',
    'SERVICE & FINDING',
  ];
  final rows = <List<pw.Widget>>[
    for (var i = 0; i < vs.length; i++)
      [
        _cell('${i + 1}', center: true),
        _cell(_pretty(vs[i].date), center: true),
        _cell(vs[i].tin, center: true),
        _cell(vs[i].tout, center: true),
        _cell(vs[i].complaint.isEmpty ? '-' : vs[i].complaint),
        _linesCell(vs[i].lines),
      ],
    if (blankRows)
      for (var i = 0; i < 6; i++)
        [for (var c = 0; c < 6; c++) pw.SizedBox(height: 24)],
  ];
  return _table(heads, _indFlex, rows);
}

pw.Widget _signatures({required bool withRoles}) {
  pw.Widget block(String label, String role) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('$label:', style: const pw.TextStyle(fontSize: 11)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.SizedBox(height: 13),
                      pw.SizedBox(height: 1),
                      pw.Container(height: 0.8, color: PdfColors.black),
                    ],
                  ),
                ),
              ],
            ),
            if (withRoles) ...[
              pw.SizedBox(height: 3),
              pw.Text(role,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ],
        ),
      );
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      block('Prepared by', '(Clinic Nurse)'),
      pw.SizedBox(width: 30),
      block('Noted by', '(Clinic Head / Physician)'),
    ],
  );
}

// ---------------------------------------------------------------------------
// HTML helpers (used by BookletPrint.buildHtml)
// ---------------------------------------------------------------------------

String _e(String s) => const HtmlEscape().convert(s);

String _hTd(String t, {bool center = false, bool bold = false}) =>
    '<td class="${center ? 'c ' : ''}${bold ? 'b' : ''}">${_e(t)}</td>';

String _hRaw(String inner, [String cls = '']) => '<td class="$cls">$inner</td>';

/// Name only. The ID number is intentionally not printed.
String _hName(_V v) => _hRaw('<b>${_e(v.name)}</b>');

/// The single "SERVICE & FINDING" cell.
String _hLines(List<_Line> ls) {
  if (ls.isEmpty) return _hTd('—');
  final b = StringBuffer();
  for (final l in ls) {
    b.write('<div style="margin-bottom:4px"><b>${_e(l.label)}</b>');
    final items = _items(l);
    if (items.isNotEmpty) {
      // Short items stay together; long ones (e.g. Action) may wrap.
      final parts = [
        for (final t in items)
          t.length <= 24
              ? '<span style="white-space:nowrap">${_e(t)}</span>'
              : _e(t),
      ];
      b.write('<div>${parts.join(' &nbsp;|&nbsp; ')}</div>');
    }
    b.write('</div>');
  }
  return _hRaw(b.toString());
}

String _hCols(List<double> flex) {
  final sum = flex.fold<double>(0, (a, b) => a + b);
  return '<colgroup>${[
    for (final f in flex)
      '<col style="width:${(f / sum * 100).toStringAsFixed(2)}%">'
  ].join()}</colgroup>';
}

String _hTable(
    List<String> headers, List<double> flex, List<List<String>> rows) {
  final head = headers.map((h) => '<th>${_e(h)}</th>').join();
  final body = rows.map((r) => '<tr>${r.join()}</tr>').join();
  return '<table class="t">${_hCols(flex)}'
      '<thead><tr>$head</tr></thead><tbody>$body</tbody></table>';
}

String _hIndividual(List<_V> vs, bool blankRows) {
  final rows = <List<String>>[
    for (var i = 0; i < vs.length; i++)
      [
        _hTd('${i + 1}', center: true),
        _hTd(_pretty(vs[i].date), center: true),
        _hTd(vs[i].tin, center: true),
        _hTd(vs[i].tout, center: true),
        _hTd(vs[i].complaint.isEmpty ? '-' : vs[i].complaint),
        _hLines(vs[i].lines),
      ],
    if (blankRows)
      for (var i = 0; i < 6; i++)
        [for (var c = 0; c < 6; c++) '<td style="height:24px"></td>'],
  ];
  return _hTable(
    [
      'NO',
      'DATE',
      'TIME IN',
      'TIME OUT',
      'REASON/COMPLAINT',
      'SERVICE & FINDING'
    ],
    _indFlex,
    rows,
  );
}

String _hSignatures({required bool withRoles}) {
  String block(String label, String role) => '<div><div class="line">'
      '<span>$label:</span><i></i></div>'
      '${withRoles ? '<div class="role">$role</div>' : ''}</div>';
  return '<div class="sig">${block('Prepared by', '(Clinic Nurse)')}'
      '${block('Noted by', '(Clinic Head / Physician)')}</div>';
}

abstract final class BookletPrint {
  // The header/footer artwork never changes, so it is loaded once and reused
  // every time the preview or the printer rebuilds the PDF.
  static String? _headerCache;
  static String? _footerCache;

  static Future<String> _footerSvg() async =>
      _footerCache ??= (await loadSheetFooterSvg())
          .replaceFirst(
              'textLength="215" lengthAdjust="spacingAndGlyphs">LEARN TODAY',
              'textLength="170" lengthAdjust="spacingAndGlyphs">LUX MUNDI')
          .replaceFirst('HONESTY', 'INTEGRITY');
  static Future<String> headerSvg() async =>
      _headerCache ??= await loadSheetHeaderSvg();
  static Future<String> footerSvg() => _footerSvg();

  /// [dateLine]      e.g. "NOV 2, 2026", "November 2-8, 2026",
  ///                 "October 28 - November 3, 2026", "SY 2025-2026 · Summer".
  /// [nameLine]      patient name (Individual Client Record only).
  /// [instituteLine] Individual: institute under the name.
  ///                 Other reports: centered under the title; pass '' when
  ///                 "All Institutes" so nothing is printed.
  /// [draftLabel]    maps a service draft to its display name
  ///                 (BP Taking, Temperature Checking, ...).
  static Future<pw.Document> build({
    required BookletReportKind kind,
    required String title,
    required String dateLine,
    required String nameLine,
    required String instituteLine,
    required List<Map<String, String>> records,
    required VisitDetailsController? Function(Map<String, String>) visitFor,
    required Map<String, IndividualRecord> roster,
    required PdfPageFormat pageFormat,
    required DraftLabelFn draftLabel,
    List<String> serviceLabels = const [],
    bool blankRows = false,
  }) async {
    final f = pageFormat.portrait;
    final m = DocMetrics(f);
    final hang = f.width * 0.04;

    final headerSvg = _headerCache ??= await loadSheetHeaderSvg();
    final footerSvg = await _footerSvg();

    final selected = serviceLabels.map((e) => e.trim().toLowerCase()).toSet();

    final impression = switch (kind) {
      BookletReportKind.service || BookletReportKind.individual => true,
      _ => kShowImpressionOnDailyAndInstitute,
    };

    // Same person + same date (AM and PM) become ONE row, like the screen.
    var vs = _mergeSameDay([
      for (final r in records)
        _visit(r, visitFor(r), roster, selected, impression, draftLabel),
    ]);
    if (kind == BookletReportKind.individual) vs = vs.reversed.toList();

    final body = <pw.Widget>[];
    switch (kind) {
      case BookletReportKind.service:
        _service(body, vs);
      case BookletReportKind.daily:
        _daily(body, vs);
      case BookletReportKind.individual:
        body.add(_individualTable(vs, blankRows));
      case BookletReportKind.byInstitute:
        _institute(body, vs);
    }

    final anyOpen = vs.any((v) => v.open);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: f,
        margin: pw.EdgeInsets.fromLTRB(hang, 0, hang, 0),
        theme: serifTheme(),
        maxPages: 300,
        header: (c) => c.pageNumber == 1
            ? sheetHeader(m, headerSvg, hang)
            : pw.SizedBox(height: 12),
        footer: (c) => sheetFooter(m, footerSvg, hang),
        build: (c) => [
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('MEDICAL AND DENTAL CLINIC OFFICE',
                style: pw.TextStyle(
                    fontSize: 13.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _green)),
          ),
          pw.Center(
            child: pw.Text('Maloro, Tangub City',
                style: pw.TextStyle(fontSize: 10, color: _green)),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _green)),
          ),
          pw.SizedBox(height: 4),

          // Institute: centered under the title, full name
          if (instituteLine.isNotEmpty)
            pw.Center(
              child: pw.Text(instituteLine,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: _green)),
            ),
          pw.SizedBox(height: 8),

          // Name (individual only) on the left, Date on the right
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (kind == BookletReportKind.individual)
                pw.Expanded(
                  child: pw.Text('Name: $nameLine',
                      style: const pw.TextStyle(fontSize: 10)),
                )
              else
                pw.Spacer(),
              pw.Text('Date: $dateLine',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 8),

          ...body,
          if (anyOpen)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text('—  visit still open (no time out yet)',
                  style: pw.TextStyle(
                      fontSize: 8, fontStyle: pw.FontStyle.italic)),
            ),
          pw.SizedBox(height: 18),
          _signatures(withRoles: kind == BookletReportKind.daily),
        ],
      ),
    );
    return doc;
  }

  /// Same report as [build], but as an HTML page for Chrome to print.
  /// Chrome lays it out for the paper size picked in its print dialog.
  static Future<String> buildHtml({
    required BookletReportKind kind,
    required String title,
    required String dateLine,
    required String nameLine,
    required String instituteLine,
    required List<Map<String, String>> records,
    required VisitDetailsController? Function(Map<String, String>) visitFor,
    required Map<String, IndividualRecord> roster,
    required DraftLabelFn draftLabel,
    List<String> serviceLabels = const [],
    bool blankRows = false,
  }) async {
    final headerSvg = _headerCache ??= await loadSheetHeaderSvg();
    final footerSvg = await _footerSvg();

    final selected = serviceLabels.map((e) => e.trim().toLowerCase()).toSet();
    final impression = switch (kind) {
      BookletReportKind.service || BookletReportKind.individual => true,
      _ => kShowImpressionOnDailyAndInstitute,
    };

    var vs = _mergeSameDay([
      for (final r in records)
        _visit(r, visitFor(r), roster, selected, impression, draftLabel),
    ]);
    if (kind == BookletReportKind.individual) vs = vs.reversed.toList();

    final table = switch (kind) {
      BookletReportKind.service => _serviceHtml(vs),
      BookletReportKind.daily => _dailyHtml(vs),
      BookletReportKind.individual => _hIndividual(vs, blankRows),
      BookletReportKind.byInstitute => _instituteHtml(vs),
    };

    final anyOpen = vs.any((v) => v.open);
    final body = '''
<div class="ttl">
  <div class="office">MEDICAL AND DENTAL CLINIC OFFICE</div>
  <div class="loc">Maloro, Tangub City</div>
  <div class="title">${_e(title)}</div>
  ${instituteLine.isEmpty ? '' : '<div class="inst">${_e(instituteLine)}</div>'}
</div>
<div class="meta">
  <span>${kind == BookletReportKind.individual ? 'Name: ${_e(nameLine)}' : ''}</span>
  <span>Date: ${_e(dateLine)}</span>
</div>
$table
${anyOpen ? '<div class="note">—  visit still open (no time out yet)</div>' : ''}
${_hSignatures(withRoles: kind == BookletReportKind.daily)}
''';

    return sheetDocument(
      title: title,
      headerSvg: headerSvg,
      footerSvg: footerSvg,
      bodyHtml: body,
      repeatHeader: true,
    );
  }

  static String _serviceHtml(List<_V> vs) {
    final rows = <List<String>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      rows.add([
        _hTd('${i + 1}', center: true),
        _hTd(_pretty(v.date, 'MMM d'), center: true),
        _hTd(v.tin, center: true),
        _hTd(v.tout, center: true),
        _hName(v),
        _hTd(v.inst, center: true),
        _hTd(v.complaint),
        _hLines(v.lines),
      ]);
    }
    return _hTable(
      [
        'NO',
        'DATE',
        'IN',
        'OUT',
        'NAME',
        'INST',
        'REASON/COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.45, .8, .8, .8, 1.7, .7, 2.2, 4.0],
      rows,
    );
  }

  static String _dailyHtml(List<_V> vs) {
    final rows = <List<String>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      rows.add([
        _hTd('${i + 1}', center: true),
        _hTd(v.tin, center: true),
        _hTd(v.tout, center: true),
        _hName(v),
        _hTd(v.inst, center: true),
        _hTd(v.complaint),
        _hLines(v.lines),
      ]);
    }
    return _hTable(
      [
        'NO',
        'IN',
        'OUT',
        'NAME',
        'INST',
        'REASON / COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.4, .8, .8, 1.6, .55, 2.0, 3.6],
      rows,
    );
  }

  static String _instituteHtml(List<_V> vs) {
    final rows = <List<String>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      final times = v.parts == null
          ? '${v.tin} - ${v.tout}'
          : v.parts!.map((p) => '${p.tin} - ${p.tout}').join('\n');
      rows.add([
        _hTd('${i + 1}', center: true),
        _hTd(times, center: true),
        _hTd(v.name),
        _hTd(v.group),
        _hTd(v.year, center: true),
        _hTd(v.complaint),
        _hLines(v.lines),
      ]);
    }
    return _hTable(
      [
        'NO',
        'TIME IN / OUT',
        'NAME',
        'PROGRAM',
        'YL',
        'REASON/COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.45, 1.5, 1.6, 1.1, .6, 2.2, 3.7],
      rows,
    );
  }

  static void _service(List<pw.Widget> out, List<_V> vs) {
    final rows = <List<pw.Widget>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      rows.add([
        _cell('${i + 1}', center: true),
        _cell(_pretty(v.date, 'MMM d'), center: true),
        _cell(v.tin, center: true),
        _cell(v.tout, center: true),
        _nameCell(v),
        _cell(v.inst, center: true),
        _cell(v.complaint),
        _linesCell(v.lines),
      ]);
    }
    out.add(_table(
      [
        'NO',
        'DATE',
        'IN',
        'OUT',
        'NAME',
        'INST',
        'REASON/COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.45, .8, .8, .8, 1.7, .7, 2.2, 4.0],
      rows,
    ));
  }

  /// Daily Clinic Visit Report: no STAY column, no totals.
  static void _daily(List<pw.Widget> out, List<_V> vs) {
    final rows = <List<pw.Widget>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      rows.add([
        _cell('${i + 1}', center: true),
        _cell(v.tin, center: true),
        _cell(v.tout, center: true),
        _nameCell(v),
        _cell(v.inst, center: true, size: 8),
        _cell(v.complaint),
        _linesCell(v.lines),
      ]);
    }
    out.add(_table(
      [
        'NO',
        'IN',
        'OUT',
        'NAME',
        'INST',
        'REASON / COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.4, .8, .8, 1.6, .55, 2.0, 3.6],
      rows,
    ));
  }

  /// Visits by Institute: ONE table, program shown as a column,
  /// no per-program sections, no summary box.
  static void _institute(List<pw.Widget> out, List<_V> vs) {
    final rows = <List<pw.Widget>>[];
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      // Merged rows list each visit's time on its own line.
      final times = v.parts == null
          ? '${v.tin} - ${v.tout}'
          : v.parts!.map((p) => '${p.tin} - ${p.tout}').join('\n');
      rows.add([
        _cell('${i + 1}', center: true),
        _cell(times, center: true),
        _cell(v.name),
        _cell(v.group),
        _cell(v.year, center: true),
        _cell(v.complaint),
        _linesCell(v.lines),
      ]);
    }
    out.add(_table(
      [
        'NO',
        'TIME IN / OUT',
        'NAME',
        'PROGRAM',
        'YL',
        'REASON/COMPLAINT',
        'SERVICE & FINDING'
      ],
      [.45, 1.5, 1.6, 1.1, .6, 2.2, 3.7],
      rows,
    ));
  }
}