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

class _Line {
  const _Line(this.code, this.label, this.findings, this.action, {this.flat});
  final String code;
  final String label;
  final String findings;
  final String action;

  final String? flat;

  String get stacked =>
      flat ??
      (action.isEmpty
          ? findings
          : (findings.isEmpty ? action : '$findings | $action'));
}

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

String _woundSize(ServiceDraft d) {
  final l = _first(d, ['wound_length_cm']);
  final w = _first(d, ['wound_width_cm']);
  if (l.isEmpty && w.isEmpty) return '';
  return w.isEmpty ? l : '$l×$w';
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

class _Spec {
  const _Spec(this.headers, this.flex, this.cells);
  final List<String> headers;
  final List<double> flex;
  final List<String> Function(_Ctx x) cells;
}

String _lines(Iterable<String> parts) => parts.join('\n');

final Map<String, _Spec> _specs = {
  'vital_signs': _Spec(
    ['BP', 'PR', 'RR', 'TEMP', 'SpO2', 'ACTION TAKEN'],
    [1, .8, .8, .9, .8, 3.2],
    (x) => [
      _bp(x.c),
      _pr(x),
      _rr(x),
      _temp(x),
      _spo2(x),
      _first(x.d, ['action_taken'], '; '),
    ],
  ),
  'bpi': _Spec(
    ['HT (cm)', 'WT (kg)', 'BMI', 'BMI INDICATOR'],
    [1, 1, 1, 2],
    (x) => [_height(x), _weight(x), _bmi(x), _bmiClass(x)],
  ),
  'wound_dressing': _Spec(
    ['SITE', 'TYPE', 'CLEANED WITH', 'MEDICINE', 'DRESSING'],
    [1.3, 1.2, 1.8, 1.8, 1.8],
    (x) => [
      _first(x.d, ['wound_location']),
      _first(x.d, ['wound_type']),
      _first(x.d, ['cleaning_performed']),
      _first(x.d, ['medication_applied']),
      _first(x.d, ['dressing_applied']),
    ],
  ),
  'first_aid_treatment': _Spec(
    ['INCIDENT', 'BODY PART', 'TREATMENT GIVEN', 'CONDITION AFTER'],
    [1.5, 1.3, 3, 1.5],
    (x) => [
      _first(x.d, ['incident']),
      _first(x.d, ['body_part', 'affected_area', 'injury_site', 'site']),
      _first(
          x.d,
          ['treatment_given', 'first_aid_given', 'treatment', 'action_taken'],
          '; '),
      _first(x.d, ['condition_after', 'patient_condition', 'outcome']),
    ],
  ),
  'health_counselling': _Spec(
    ['SESSION', 'SESSION TYPE', 'DURATION', 'FOLLOW-UP DATE'],
    [1.2, 1.6, 1.2, 1.6],
    (x) => [
      'Session held',
      _first(x.d, ['session_type', 'counselling_type', 'counsellor_type']),
      _first(x.d, ['duration', 'duration_min', 'session_duration']),
      _pretty(_first(x.d, ['follow_up_date'])),
    ],
  ),
  'prenatal': _Spec(
    ['AOG', 'BP', 'FHT', 'EDEMA', 'GIVEN THIS VISIT', 'ACTION / FOLLOW-UP'],
    [.9, .9, .8, .9, 2, 2.4],
    (x) => [
      _aog(x),
      _bp(x.c),
      _first(x.d, ['fht', 'fetal_heart_tone', 'fetal_heart_rate']),
      _first(x.d, ['edema']),
      _first(
          x.d, ['given_this_visit', 'supplements_given', 'medications_given']),
      _first(x.d, ['follow_up', 'follow_up_instructions', 'next_visit_date'],
          '; '),
    ],
  ),
  'medication': _Spec(
    ['MEDICINE', 'QTY', 'FREQUENCY'],
    [3, .8, 2],
    (x) => [
      _lines(x.d.medicines.map((m) => m.name)),
      _lines(x.d.medicines.map((m) => _num(m.quantity))),
      _lines(x.d.medicines.map((m) => '${m.frequency}')),
    ],
  ),
  'medicine_consultation': _Spec(
    [
      'REASON',
      'IMPRESSION',
      'TREATMENT',
      'MEDICATION',
      'FOLLOW-UP / DISPOSITION'
    ],
    [1.8, 1.8, 1.6, 1.8, 1.8],
    (x) => [
      _first(x.d, ['REASON']),
      _first(x.d, ['clinical_impression']),
      _first(x.d, ['treatment'], '; '),
      _first(x.d, ['medication_summary']),
      _first(x.d, ['follow_up_instructions', 'disposition']),
    ],
  ),
  'medicine_certificate': _Spec(
    ['EXCUSED FOR', 'DAYS', 'ISSUED ON'],
    [3, .8, 1.5],
    (x) => [
      _first(x.d, ['excused_for']),
      _first(x.d, ['days', 'excused_days', 'number_of_days']),
      _pretty(_first(x.d, ['cert_issued_on'])),
    ],
  ),
};

_Spec? _specFor(String id) => _specs[id == 'bp_tracking' ? 'vital_signs' : id];

List<_Line> _linesFor(_Ctx x, bool impression) {
  final d = x.d;
  final code = kServiceCodes[d.serviceId] ?? _codeFromLabel(d.label);
  switch (d.serviceId) {
    case 'vital_signs':
    case 'bp_tracking':
      final bp = _bp(x.c),
          pr = _pr(x),
          t = _temp(x),
          rr = _rr(x),
          sp = _spo2(x);
      return [
        _Line(
          code,
          x.label,
          [
            if (bp.isNotEmpty)
              '$bp${_bpClass(x).isEmpty ? '' : ' (${_bpClass(x)})'}',
            if (pr.isNotEmpty) 'PR $pr',
            if (t.isNotEmpty) 'T $t',
            if (rr.isNotEmpty) 'RR $rr',
            if (sp.isNotEmpty) 'SpO2 $sp',
          ].join(' · '),
          _first(d, ['action_taken'], '; '),
        ),
      ];
    case 'bpi':
      final h = _height(x), w = _weight(x), b = _bmi(x), k = _bmiClass(x);
      return [
        _Line(
          code,
          x.label,
          [
            if (h.isNotEmpty) 'Height $h cm',
            if (w.isNotEmpty) 'Weight $w kg',
            if (b.isNotEmpty) 'BMI $b${k.isEmpty ? '' : ' ($k)'}',
          ].join(' · '),
          '',
        ),
      ];
    case 'wound_dressing':
      final what = [
        _first(d, ['wound_location']),
        _first(d, ['wound_type']),
        _woundSize(d),
      ].where((e) => e.isNotEmpty).join(' ');
      final act = [
        _first(d, ['cleaning_performed']),
        _first(d, ['medication_applied']),
        _first(d, ['dressing_applied']),
      ].where((e) => e.isNotEmpty).join(', ');
      return [_Line(code, x.label, what, act)];
    case 'first_aid_treatment':
      final what = [
        _first(d, ['incident']),
        _first(d, ['body_part', 'affected_area', 'injury_site', 'site']),
      ].where((e) => e.isNotEmpty).join(', ');
      final tx = _first(
          d,
          ['treatment_given', 'first_aid_given', 'treatment', 'action_taken'],
          '; ');
      final after =
          _first(d, ['condition_after', 'patient_condition', 'outcome']);
      return [
        _Line(
            code,
            x.label,
            what,
            [tx, if (after.isNotEmpty) '> $after']
                .where((e) => e.isNotEmpty)
                .join(' ')),
      ];
    case 'medication':
      if (d.medicines.isEmpty) return [_Line(code, x.label, '', '')];
      final why = _first(d, ['reason']);
      return [
        for (final m in d.medicines)
          _Line(
            code,
            x.label,
            why.isEmpty ? '' : 'Reason: $why',
            '${m.name}${_num(m.quantity).isEmpty ? '' : ' x${_num(m.quantity)}'}'
            '${'${m.frequency}'.trim().isEmpty ? '' : ', ${m.frequency}'}'
            '${'${m.action}'.trim().isEmpty ? '' : ' (${m.action})'}',
            flat:
                '${m.name}${_num(m.quantity).isEmpty ? '' : ' x${_num(m.quantity)}'}'
                '${'${m.frequency}'.trim().isEmpty ? '' : ' ${m.frequency}'}'
                '${'${m.action}'.trim().isEmpty ? '' : ' (${m.action})'}',
          ),
      ];
    case 'medicine_consultation':
      final cc = _first(d, ['REASON']);
      final imp = _first(d, ['clinical_impression']);
      final tx = [
        _first(d, ['treatment'], '; '),
        _first(d, ['medication_summary']),
      ].where((e) => e.isNotEmpty).join('; ');
      final findings = [
        cc,
        if (impression && imp.isNotEmpty) 'Imp: $imp',
      ].where((e) => e.isNotEmpty).join(' · ');
      return [_Line(code, x.label, findings, tx)];
    case 'health_counselling':
      final type =
          _first(d, ['session_type', 'counselling_type', 'counsellor_type']);
      final dur = _first(d, ['duration', 'duration_min', 'session_duration']);
      final fu = _pretty(_first(d, ['follow_up_date']), 'MMM d');
      final fuLong = _pretty(_first(d, ['follow_up_date']));
      return [
        _Line(
          code,
          x.label,
          [
            'Session held',
            if (dur.isNotEmpty)
              dur.contains(RegExp(r'[a-zA-Z]')) ? dur : '$dur min'
          ].join(' · '),
          fuLong.isEmpty ? '[restricted]' : 'Follow-up $fuLong   [restricted]',
          flat: [
                if (type.isNotEmpty) type else 'Session held',
                if (dur.isNotEmpty)
                  dur.contains(RegExp(r'[a-zA-Z]')) ? dur : '$dur min',
                if (fu.isNotEmpty) 'f/u $fu',
              ].join(' · ') +
              ' (restricted)',
        ),
      ];
    case 'prenatal':
      final f = [
        if (_aog(x).isNotEmpty) _aog(x),
        if (_bp(x.c).isNotEmpty) _bp(x.c),
        if (_first(d, ['fht', 'fetal_heart_tone', 'fetal_heart_rate'])
            .isNotEmpty)
          'FHT ${_first(d, ['fht', 'fetal_heart_tone', 'fetal_heart_rate'])}',
        if (_first(d, ['edema']).isNotEmpty) 'edema ${_first(d, ['edema'])}',
      ].join(' · ');
      final a = [
        _first(
            d, ['given_this_visit', 'supplements_given', 'medications_given']),
        _first(d, ['follow_up', 'follow_up_instructions', 'next_visit_date'],
            '; '),
      ].where((e) => e.isNotEmpty).join('; ');
      return [_Line(code, x.label, f, a)];
    case 'medicine_certificate':
      final days = _first(d, ['days', 'excused_days', 'number_of_days']);
      final on = _pretty(_first(d, ['cert_issued_on']), 'MMM d');
      return [
        _Line(
          code,
          x.label,
          [
            'Excused: ${_first(d, ['excused_for'])}',
            if (days.isNotEmpty) '$days d',
          ].join(' · '),
          on.isEmpty ? '' : 'Issued $on',
        ),
      ];
    default:
      return [_Line(code, x.label, '', '')];
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
      lines.add(_Line(c, label, '', ''));
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

pw.Widget _nameCell(_V v) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(v.name,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text(v.id, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );

pw.Widget _linesCell(List<_Line> ls) {
  if (ls.isEmpty) return _cell('—');
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in ls)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(l.label,
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                if (l.stacked.isNotEmpty)
                  pw.Text(l.stacked,
                      style: const pw.TextStyle(fontSize: 8.5)),
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
const List<double> _svcFlex = [1, 2, 2];

pw.Widget _svcTable(List<List<String>> rows,
    {bool header = false, double minHeight = 0}) {
  return pw.Table(
    columnWidths: {
      for (var i = 0; i < 3; i++) i: pw.FlexColumnWidth(_svcFlex[i]),
    },
    border: pw.TableBorder(
      verticalInside: const pw.BorderSide(color: PdfColors.black, width: 0.6),
      horizontalInside: header
          ? pw.BorderSide.none
          : const pw.BorderSide(color: PdfColors.grey500, width: 0.4),
    ),
    children: [
      for (final r in rows)
        pw.TableRow(children: [
          for (final t in r)
            pw.Container(
              height: minHeight > 0 ? minHeight : null,
              child: _cell(t, bold: header, center: header, size: 8.5),
            ),
        ]),
    ],
  );
}

pw.Widget _individualTable(List<_V> vs, bool blankRows) {
  const heads = [
    'NO',
    'DATE',
    'TIME IN',
    'TIME OUT',
    'REASON/COMPLAINT',
    null,
  ];

  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _headFill),
      verticalAlignment: pw.TableCellVerticalAlignment.full,
      children: [
        for (final h in heads)
          h == null
              ? _svcTable([
                  ['SERVICE', 'FINDINGS', 'TREATMENT / ACTION']
                ], header: true)
              : _cell(h, bold: true, center: true, size: 8.5),
      ],
    ),
  ];

  for (var i = 0; i < vs.length; i++) {
    final v = vs[i];
    rows.add(pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.full,
      children: [
        _cell('${i + 1}', center: true),
        _cell(_pretty(v.date), center: true),
        _cell(v.tin, center: true),
        _cell(v.tout, center: true),
        _cell(v.complaint.isEmpty ? '-' : v.complaint),
        _svcTable(v.lines.isEmpty
            ? [
                ['-', '-', '-']
              ]
            : [
                for (final l in v.lines)
                  [
                    l.label,
                    l.findings.isEmpty ? '-' : l.findings,
                    l.action.isEmpty ? '-' : l.action,
                  ]
              ]),
      ],
    ));
  }

  if (blankRows) {
    for (var i = 0; i < 6; i++) {
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          for (var c = 0; c < 6; c++)
            c == 5
                ? _svcTable([
                    ['', '', '']
                  ], minHeight: 24)
                : pw.SizedBox(height: 24),
        ],
      ));
    }
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
    columnWidths: {
      for (var i = 0; i < _indFlex.length; i++)
        i: pw.FlexColumnWidth(_indFlex[i]),
    },
    children: rows,
  );
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

pw.Widget _totalBox(String text) => pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
        ),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
    );

// ---------------------------------------------------------------------------
// HTML helpers (used by BookletPrint.buildHtml)
// ---------------------------------------------------------------------------

String _e(String s) => const HtmlEscape().convert(s);

String _hTd(String t, {bool center = false, bool bold = false}) =>
    '<td class="${center ? 'c ' : ''}${bold ? 'b' : ''}">${_e(t)}</td>';

String _hRaw(String inner, [String cls = '']) => '<td class="$cls">$inner</td>';

String _hName(_V v) =>
    _hRaw('<b>${_e(v.name)}</b><div class="sm">${_e(v.id)}</div>');

String _hLines(List<_Line> ls) {
  if (ls.isEmpty) return _hTd('—');
  final b = StringBuffer();
  for (final l in ls) {
    b.write('<div class="ln"><b>${_e(l.label)}</b>');
    if (l.stacked.isNotEmpty) b.write('<div>${_e(l.stacked)}</div>');
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

String _hSub(List<List<String>> rows) =>
    '<table class="sub">${_hCols(_svcFlex)}${rows.map((r) => '<tr>${r.map((t) => '<td>${_e(t)}</td>').join()}</tr>').join()}</table>';

String _hIndividual(List<_V> vs, bool blankRows) {
  const heads = ['NO', 'DATE', 'TIME IN', 'TIME OUT', 'REASON/COMPLAINT'];
  final head = StringBuffer();
  for (final h in heads) {
    head.write('<th>${_e(h)}</th>');
  }
  head.write('<th class="nopad"><table class="sub">${_hCols(_svcFlex)}'
      '<tr><th>SERVICE</th><th>FINDINGS</th><th>TREATMENT / ACTION</th></tr>'
      '</table></th>');

  final body = StringBuffer();
  for (var i = 0; i < vs.length; i++) {
    final v = vs[i];
    final sub = v.lines.isEmpty
        ? [
            ['-', '-', '-']
          ]
        : [
            for (final l in v.lines)
              [
                l.label,
                l.findings.isEmpty ? '-' : l.findings,
                l.action.isEmpty ? '-' : l.action,
              ]
          ];
    body.write('<tr>${_hTd('${i + 1}', center: true)}'
        '${_hTd(_pretty(v.date), center: true)}'
        '${_hTd(v.tin, center: true)}${_hTd(v.tout, center: true)}'
        '${_hTd(v.complaint.isEmpty ? '-' : v.complaint)}'
        '<td class="nopad">${_hSub(sub)}</td></tr>');
  }
  if (blankRows) {
    for (var i = 0; i < 6; i++) {
      body.write(
          '<tr class="blank"><td></td><td></td><td></td><td></td><td></td>'
          '<td class="nopad"><table class="sub">${_hCols(_svcFlex)}'
          '<tr><td></td><td></td><td></td></tr></table></td></tr>');
    }
  }
  return '<table class="t">${_hCols(_indFlex)}'
      '<thead><tr>$head</tr></thead><tbody>$body</tbody></table>';
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
        _service(body, vs, selected);
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
      BookletReportKind.service => _serviceHtml(vs, selected),
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

  static String _serviceHtml(List<_V> vs, Set<String> selected) {
    if (selected.length == 1) {
      ServiceDraft? sample;
      outer:
      for (final v in vs) {
        for (final d in v.drafts) {
          sample = d;
          break outer;
        }
      }
      final spec = sample == null ? null : _specFor(sample.serviceId);
      if (spec != null) {
        final rows = <List<String>>[];
        for (var i = 0; i < vs.length; i++) {
          final v = vs[i];
          final sessions = v.parts ?? [v];
          final per = [
            for (final s in sessions)
              (s.drafts.isEmpty || s.vc == null)
                  ? List<String>.filled(spec.headers.length, '')
                  : spec.cells(_Ctx(
                      s.drafts.first, s.vc!, s.when, s.drafts.first.label)),
          ];
          rows.add([
            _hTd('${i + 1}', center: true),
            _hTd(_pretty(v.date, 'MMM d'), center: true),
            _hTd(v.tin, center: true),
            _hTd(v.tout, center: true),
            _hName(v),
            _hTd(v.inst, center: true),
            for (var c = 0; c < spec.headers.length; c++)
              _hTd(per
                  .map((p) => p[c].isEmpty && per.length > 1 ? '-' : p[c])
                  .join('\n')),
          ]);
        }
        return _hTable(
          ['NO', 'DATE', 'IN', 'OUT', 'NAME', 'INSTITUTE', ...spec.headers],
          [.45, .85, .8, .8, 1.9, .9, ...spec.flex],
          rows,
        );
      }
    }
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
        'SERVICES & RESULTS'
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
        'NAME / ID',
        'INST',
        'REASON / COMPLAINT',
        'SERVICES & RESULTS'
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
        'SERVICES & RESULT'
      ],
      [.45, 1.5, 1.6, 1.1, .6, 2.2, 3.7],
      rows,
    );
  }

  static void _service(List<pw.Widget> out, List<_V> vs, Set<String> selected) {
    if (selected.length == 1) {
      ServiceDraft? sample;
      for (final v in vs) {
        for (final d in v.drafts) {
          sample = d;
          break;
        }
        if (sample != null) break;
      }
      final spec = sample == null ? null : _specFor(sample.serviceId);
      if (spec != null) {
        final rows = <List<pw.Widget>>[];
        for (var i = 0; i < vs.length; i++) {
          final v = vs[i];
          // A merged row (AM + PM) shows one line per visit inside each cell.
          final sessions = v.parts ?? [v];
          final per = [
            for (final s in sessions)
              (s.drafts.isEmpty || s.vc == null)
                  ? List<String>.filled(spec.headers.length, '')
                  : spec.cells(_Ctx(
                      s.drafts.first, s.vc!, s.when, s.drafts.first.label)),
          ];
          final cells = [
            for (var c = 0; c < spec.headers.length; c++)
              per
                  .map((p) => p[c].isEmpty && per.length > 1 ? '-' : p[c])
                  .join('\n'),
          ];
          rows.add([
            _cell('${i + 1}', center: true),
            _cell(_pretty(v.date, 'MMM d'), center: true),
            _cell(v.tin, center: true),
            _cell(v.tout, center: true),
            _nameCell(v),
            _cell(v.inst, center: true),
            for (final c in cells) _cell(c),
          ]);
        }
        out.add(_table(
          [
            'NO',
            'DATE',
            'IN',
            'OUT',
            'NAME',
            'INSTITUTE',
            ...spec.headers
          ],
          [.45, .85, .8, .8, 1.9, .9, ...spec.flex],
          rows,
        ));
        return;
      }
    }

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
        'SERVICES & RESULTS'
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
        'NAME / ID',
        'INST',
        'REASON / COMPLAINT',
        'SERVICES & RESULTS'
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
        'SERVICES & RESULT'
      ],
      [.45, 1.5, 1.6, 1.1, .6, 2.2, 3.7],
      rows,
    ));
  }
}