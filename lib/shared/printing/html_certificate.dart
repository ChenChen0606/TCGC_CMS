// lib/shared/printing/html_certificate.dart
import 'dart:convert' show HtmlEscape;

import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/features/records/services/booklet_print.dart';
import 'package:clinicmanagementsystem/shared/printing/html_sheet.dart';

const double _page = 792 * 1545 / 612; // design page height
const double _row = 68;
const String _green = '#0E6B47';

String _e(String s) => const HtmlEscape().convert(s);
String _u(double v) => 'calc(var(--u) * ${v.toStringAsFixed(2)})';

String _pos(double x, double y, [double? w]) =>
    'left:${_u(x)};top:${_u(y - _row / 2)};height:${_u(_row)};'
    '${w == null ? '' : 'width:${_u(w)};'}';

// Rough glyph width (in em) for Times, used only to pick a font size.
double _est(String t, {bool bold = false}) {
  final caps = t == t.toUpperCase();
  return t.length * (caps ? (bold ? 0.72 : 0.68) : (bold ? 0.5 : 0.45));
}

String _word(double x, double y, String t) =>
    '<div class="w" style="${_pos(x, y)}">${_e(t)}</div>';

String _spread(double x, double y, double w, String t) {
  final words = t.split(RegExp(r'\s+'));
  return '<div class="w sp" style="${_pos(x, y, w)}">'
      '${words.map((e) => '<span>${_e(e)}</span>').join()}</div>';
}

String _fit(double x, double y, double w, String t,
    {bool bold = false, String color = '#000'}) {
  final size = (w / _est(t, bold: bold)).clamp(10, 120).toDouble();
  return '<svg class="a" style="${_pos(x, y, w)}" viewBox="0 0 $w $_row">'
      '<text x="${w / 2}" y="${_row / 2}" text-anchor="middle" '
      'dominant-baseline="central" fill="$color" font-size="$size" '
      'font-weight="${bold ? 'bold' : 'normal'}" textLength="$w" '
      'lengthAdjust="spacingAndGlyphs">${_e(t)}</text></svg>';
}

String _blank(double x, double y, double w, String v) {
  var size = 36.0;
  var squeeze = false;
  if (v.isNotEmpty) {
    final natural = _est(v) * 36;
    if (natural > w) {
      size = 36 * w / natural;
      if (size < 20) {
        size = 20;
        squeeze = _est(v) * 20 > w;
      }
    }
  }
  return '<svg class="a" style="${_pos(x, y, w)}" viewBox="0 0 $w $_row">'
      '<rect x="0" y="49" width="$w" height="2" fill="#000"/>'
      '${v.isEmpty ? '' : '<text x="${w / 2}" y="${_row / 2}" text-anchor="middle" '
          'dominant-baseline="central" font-size="$size" fill="#000" '
          '${squeeze ? 'textLength="$w" lengthAdjust="spacingAndGlyphs"' : ''}>'
          '${_e(v)}</text>'}</svg>';
}

Future<String> buildCertificateHtml(RenderedDocument document) async {
  final headerSvg = await BookletPrint.headerSvg();
  final footerSvg = await BookletPrint.footerSvg();

  final values = <String, String>{
    for (final line in document.lines)
      for (final s in line.segments)
        if (s.blank && s.name.isNotEmpty) s.name: s.text.trim(),
  };
  String v(String k) => values[k] ?? '';

  final sex = v('visitor.sex_or_prompt');
  final sheOrHe = sex.trim().toLowerCase() == 'male' ? 'he' : 'she';

  var title = 'CERTIFICATION';
  var signName = DocSignatory.tcgcHead.name;
  var signRole = DocSignatory.tcgcHead.role;
  for (final line in document.lines) {
    if (line.kind == DocBlockKind.title && line.text.trim().isNotEmpty) {
      title = line.text.trim().toUpperCase();
    } else if (line.kind == DocBlockKind.signature) {
      if (line.text.trim().isNotEmpty) signName = line.text.trim();
      if (line.value.trim().isNotEmpty) signRole = line.value.trim();
    }
  }

  double fb(double d) => _page - d;

  final body = [
    _fit(415, 317, 737, DocTemplate.clinicDepartment.toUpperCase(),
        bold: true, color: _green),
    _fit(636, 362, 279, 'Maloro, Tangub City', color: _green),
    _fit(510, 562, 530, title, bold: true, color: _green),
    _spread(218, 728, 374, 'This is to certify that'),
    _blank(613, 728, 784, v('visitor.full_name')),
    _word(1399, 728, ','),
    _blank(137, 795, 700, v('visitor.age')),
    _spread(863, 795, 534,
        'years old, ${sex.isEmpty ? 'female/male' : sex} from'),
    _blank(137, 860, 658, v('visitor.address')),
    _word(797, 860, ','),
    _spread(825, 860, 215, 'appeared last'),
    _blank(1058, 860, 339, v('visit.date')),
    _spread(137, 928, 721, 'at TCGC Medical and Dental Clinic due to'),
    _blank(878, 928, 519, v('visit.reason')),
    _word(1399, 928, '.'),
    _spread(218, 1062, 1194,
        'This certification is issued upon the request of the above name person for'),
    _spread(137, 1130, 1275,
        'whatever legal purpose may serve so that $sheOrHe will be excused for'),
    _blank(137, 1197, 598, v('excused_for')),
    _word(737, 1197, '.'),
    _spread(218, 1332, 176, 'Issued this'),
    _blank(413, 1332, 132, v('issued.day')),
    _spread(567, 1332, 106, 'day of'),
    _blank(693, 1332, 292, v('issued.month')),
    _word(987, 1332, ','),
    _blank(1012, 1332, 126, v('issued.year')),
    _spread(1160, 1332, 252, 'at Tangub City,'),
    _word(137, 1395, 'Philippines.'),
    '<div class="a" style="left:${_u(137)};top:${_u(fb(398) - 1)};'
        'width:${_u(623)};height:${_u(2)};background:#000"></div>',
    _fit(233, fb(362), 464, signName.toUpperCase(), bold: true, color: _green),
    _fit(235, fb(319), 489, signRole.toUpperCase(), color: _green),
  ].join('\n');

  return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Medical Certificate</title>
<style>
@page { size: auto; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #fff;
  font-family: "Times New Roman", Times, serif;
  -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page { --u: calc(100vw / 1545); position: relative; width: 100vw;
  height: calc(100vw * 792 / 612 - 2px); overflow: hidden;
  font-size: calc(var(--u) * 36); color: #000; break-inside: avoid; }
.hd svg { display: block; width: 100%; height: auto; overflow: visible; }
.w { position: absolute; display: flex; align-items: center;
  white-space: nowrap; line-height: 1; }
.sp { justify-content: space-between; }
.a { position: absolute; overflow: visible; }
.foot { position: fixed; left: 0; right: 0; bottom: 12px; width: 100%;
  height: auto; display: block; }
</style></head><body>
<div class="page">
<div class="hd">$headerSvg</div>
$body
</div>
<img class="foot" alt="" src="${footerDataUri(footerSvg)}">
</body></html>''';
}