import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/shared/printing/document_assets.dart';

abstract final class DocPalette {
  static const PdfColor orange = PdfColor.fromInt(0xFFED7D22);
  static const PdfColor darkGreen = PdfColor.fromInt(0xFF144728);
  static const PdfColor accentGreen = PdfColor.fromInt(0xFF2F7A4D);
  static const PdfColor ink = PdfColor.fromInt(0xFF1F2A25);
  static const PdfColor muted = PdfColor.fromInt(0xFF5B6660);
  static const PdfColor rule = PdfColor.fromInt(0xFFC9D3CD);
  static const PdfColor tableHead = PdfColor.fromInt(0xFFE7EFEA);
  static const PdfColor onDark = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor onDarkSoft = PdfColor.fromInt(0xFFCFE0D6);
}

abstract final class PaperFormat {
  static const List<String> sizes = ['A4', 'Letter', 'Legal'];

  static PdfPageFormat formatFor(String key, bool landscape) {
    final base = switch (key) {
      'A4' => PdfPageFormat.a4,
      'Legal' => PdfPageFormat.legal,
      _ => PdfPageFormat.letter,
    };
    return landscape ? base.landscape : base.portrait;
  }
}

enum DocMargin {
  narrow('Narrow', 0.55),
  normal('Normal', 1.0),
  wide('Wide', 1.6);

  const DocMargin(this.label, this.factor);

  final String label;

  final double factor;
}

class DocPageRange {
  const DocPageRange(this.first, this.last);

  final int first;

  final int last;

  int get count => last - first + 1;

  String get label => first == last ? '$first' : '$first-$last';

  bool contains(int sheet) => sheet >= first && sheet <= last;

  static DocPageRange? parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final parts = raw.split(RegExp(r'\s*-\s*'));
    if (parts.length == 1) {
      final n = int.tryParse(parts[0]);
      if (n == null || n < 1) return null;
      return DocPageRange(n, n);
    }
    if (parts.length != 2) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null || a < 1 || b < 1) return null;
    return a <= b ? DocPageRange(a, b) : DocPageRange(b, a);
  }
}

class DocMetrics {
  DocMetrics(this.pageFormat, {this.margin = DocMargin.normal});

  final PdfPageFormat pageFormat;

  final DocMargin margin;

  double get pageWidth => pageFormat.width;

  double get pageHeight => pageFormat.height;

  bool get isLandscape => pageWidth > pageHeight;

  double get headerH => pageHeight * (isLandscape ? 0.21 : 0.17);

  double get footerH => pageHeight * (isLandscape ? 0.115 : 0.085);

  double get designSide => pageWidth * (isLandscape ? 0.06 : 0.085);

  double get designTextWidth => pageWidth - 2 * designSide;

  double get sideMargin => designSide * margin.factor;

  double get contentWidth => pageWidth - 2 * sideMargin;

  double get bodyScale =>
      (contentWidth / designTextWidth).clamp(0.80, 1.10).toDouble();

  double get sealSize => footerH * 0.74;

  double get logoSize => math.min(headerH * 0.34, pageWidth * 0.12);

  double get continuationH => headerH * 0.24;
}

Future<Uint8List> renderDocumentPdf(
  RenderedDocument document, {
  PdfPageFormat pageFormat = PdfPageFormat.letter,
  DocMargin margin = DocMargin.normal,
  int copies = 1,
  DocPageRange? pages,
}) async {
  final m = DocMetrics(pageFormat, margin: margin);
  final fill = document.template.fillInBlanks;

  if (fill) {
    return _renderCertificateSheet(document, m, copies, pages);
  }

  final logo = await _loadLogo(m.logoSize);

  final pdf = pw.Document(
    title: document.template.name,
    author: document.issuedBy,
  );

  final sheets = copies < 1 ? 1 : copies;
  for (var copy = 1; copy <= sheets; copy++) {
    final firstPage = pdf.document.pdfPageList.pages.length + 1;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.fromLTRB(m.sideMargin, 0, m.sideMargin, 0),
        theme: serifTheme(),
        maxPages: 40,
        header: (context) => context.pageNumber == firstPage
            ? _header(m, logo)
            : _continuationHeader(m),
        footer: (context) => _footer(m, document.footer),
        build: (context) => _body(document, m),
      ),
    );
  }

  return pdf.save();
}

Future<Uint8List> _renderCertificateSheet(
  RenderedDocument document,
  DocMetrics m,
  int copies,
  DocPageRange? pages,
) async {
  final headerSvg = await loadSheetHeaderSvg();
  final footerSvg = await loadSheetFooterSvg();

  final pdf = pw.Document(
    title: document.template.name,
    author: document.issuedBy,
  );

  final sheets = copies < 1 ? 1 : copies;
  for (var copy = 1; copy <= sheets; copy++) {
    if (pages != null && !pages.contains(copy)) continue;
    final firstPage = pdf.document.pdfPageList.pages.length + 1;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: m.pageFormat,
        margin: pw.EdgeInsets.fromLTRB(m.sideMargin, 0, m.sideMargin, 0),
        theme: serifTheme(),
        maxPages: 40,
        header: (context) => context.pageNumber == firstPage
            ? sheetHeader(m, headerSvg, m.sideMargin)
            : _continuationHeader(m),
        footer: (context) => sheetFooter(m, footerSvg, m.sideMargin),
        build: (context) => [_sheetBody(context, document, m)],
      ),
    );
  }

  return pdf.save();
}

pw.ThemeData serifTheme() => pw.ThemeData.withFont(
      base: DocumentAssets.serif(),
      bold: DocumentAssets.serifBold(),
      italic: DocumentAssets.serifItalic(),
      boldItalic: DocumentAssets.serifBoldItalic(),
    );

Future<pw.Widget> _loadLogo(double size) async {
  final bytes = await DocumentAssets.logoBytes();
  if (bytes.isEmpty) return pw.SizedBox(width: size, height: size);
  return pw.Image(
    pw.MemoryImage(bytes),
    width: size,
    height: size,
    fit: pw.BoxFit.contain,
  );
}

List<pw.Widget> _body(RenderedDocument document, DocMetrics m) {
  return [
    pw.SizedBox(height: 14),
    _officeTitle(m),
    pw.SizedBox(height: 20),
    for (final line in document.lines) ...[
      _line(line, m),
      pw.SizedBox(height: 7),
    ],
    pw.SizedBox(height: 16),
  ];
}

pw.Widget _officeTitle(DocMetrics m) {
  final department = DocTemplate.clinicDepartment;
  return pw.SizedBox(
    width: m.contentWidth,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          department,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.8,
            lineSpacing: 2,
            color: DocPalette.darkGreen,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Maloro, Tangub City',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9,
            letterSpacing: 0.6,
            color: DocPalette.muted,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _line(RenderedLine line, DocMetrics m) {
  switch (line.kind) {
    case DocBlockKind.title:
      return pw.SizedBox(
        width: m.contentWidth,
        child: pw.Text(
          line.text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
            lineSpacing: 3,
            color: DocPalette.darkGreen,
          ),
        ),
      );
    case DocBlockKind.heading:
      return pw.Text(
        line.text,
        style: pw.TextStyle(
          fontSize: 11.5,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.4,
          color: DocPalette.darkGreen,
        ),
      );
    case DocBlockKind.paragraph:
      return pw.SizedBox(
        width: m.contentWidth,
        child: pw.Text(
          line.text,
          textAlign: pw.TextAlign.justify,
          style: pw.TextStyle(
            fontSize: 11,
            lineSpacing: 3,
            color: DocPalette.ink,
          ),
        ),
      );
    case DocBlockKind.field:
      return _field(line, m);
    case DocBlockKind.divider:
      return pw.Divider(
        height: 10,
        thickness: 0.5,
        color: DocPalette.rule,
      );
    case DocBlockKind.signature:
      return _signature(line);
    case DocBlockKind.examTable:
    case DocBlockKind.historyTable:
      return _table(line);
    case DocBlockKind.space:
      return pw.SizedBox(height: 10);
  }
}

const double _sheetRow = 68;
const double _sheetBodySize = 36;
const double _sheetRuleTop = 49;
const double _sheetRule = 2;

const double _sheetDesignPage = 792 / (612 / 1545);
final double _sheetDesignFoot =
    (138 * (612 / 1545) + 792 * 0.04) / (612 / 1545);

double _sheetHeaderHeight(DocMetrics m) => m.pageWidth * 300 / 1545;

double _sheetFooterHeight(DocMetrics m) {
  const overhang = 18.0;
  const art = 120.0;
  final unit = m.pageWidth / 1545;
  return m.isLandscape
      ? m.footerH
      : (overhang + art) * unit + m.pageHeight * 0.04;
}

const PdfColor _sheetGreen = PdfColor.fromInt(0xFF0E6B47);

pw.Widget _sheetBody(
  pw.Context context,
  RenderedDocument document,
  DocMetrics m,
) {
  final designUnit = m.pageWidth / 1545;
  final unit = designUnit * m.bodyScale;
  final centre = m.pageWidth / 2;

  double px(double x) => centre + (x * designUnit - centre) * m.bodyScale;

  final headerH = _sheetHeaderHeight(m);
  final bodyH = m.pageHeight - headerH - _sheetFooterHeight(m) - 1;
  final row = _sheetRow * unit;

  final values = <String, String>{
    for (final line in document.lines)
      for (final s in line.segments)
        if (s.blank && s.name.isNotEmpty) s.name: s.text.trim(),
  };

  final sex = values['visitor.sex_or_prompt'] ?? '';
  final sheOrHe = sex.trim().toLowerCase() == 'male' ? 'he' : 'she';

  var title = 'CERTIFICATION';
  var signatoryName = DocSignatory.tcgcHead.name;
  var signatoryRole = DocSignatory.tcgcHead.role;
  for (final line in document.lines) {
    if (line.kind == DocBlockKind.title && line.text.trim().isNotEmpty) {
      title = line.text.trim().toUpperCase();
    } else if (line.kind == DocBlockKind.signature) {
      if (line.text.trim().isNotEmpty) signatoryName = line.text.trim();
      if (line.value.trim().isNotEmpty) signatoryRole = line.value.trim();
    }
  }

  final regular = DocumentAssets.serif();
  final bold = DocumentAssets.serifBold();

  double filled(pw.Font font, String text, double width) {
    final em = font.getFont(context).stringMetrics(text).width;
    if (text.isEmpty || em <= 0 || !em.isFinite) return _sheetBodySize * unit;
    return (width / em).clamp(1, 200).toDouble();
  }

  final double actualPage = m.pageHeight / designUnit;
  final double actualFoot = _sheetFooterHeight(m) / designUnit;
  final double designBand = (_sheetDesignPage - _sheetDesignFoot) - 300;
  final double actualBand = (actualPage - actualFoot) - 300;
  final double stretch = designBand <= 0 ? 1 : actualBand / designBand;

  double placed(double pageY) => 300 + (pageY - 300) * stretch;

  double local(double y) => (placed(y) - 300) * designUnit;

  double top(double y) => local(y) - row / 2;

  double fromBottom(double d) => _sheetDesignPage - d;

  pw.TextStyle style(pw.Font font, bool isBold, double size, PdfColor color) =>
      pw.TextStyle(
        font: font,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontSize: size,
        color: color,
      );

  pw.Widget word(double x, double y, String text) {
    return pw.Positioned(
      left: px(x) - m.sideMargin,
      top: top(y),
      child: pw.SizedBox(
        height: row,
        child: pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            text,
            softWrap: false,
            style:
                style(regular, false, _sheetBodySize * unit, PdfColors.black),
          ),
        ),
      ),
    );
  }

  pw.Widget spread(double x, double y, double width, String text) {
    final words = text.split(RegExp(r'\s+'));
    return pw.Positioned(
      left: px(x) - m.sideMargin,
      top: top(y),
      child: pw.SizedBox(
        width: width * unit,
        height: row,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            for (final w in words)
              pw.Text(
                w,
                softWrap: false,
                style: style(
                    regular, false, _sheetBodySize * unit, PdfColors.black),
              ),
          ],
        ),
      ),
    );
  }

  pw.Widget heading(
    double x,
    double y,
    double width,
    String text, {
    bool isBold = false,
    PdfColor color = PdfColors.black,
  }) {
    final font = isBold ? bold : regular;
    return pw.Positioned(
      left: px(x) - m.sideMargin,
      top: top(y),
      child: pw.SizedBox(
        height: row,
        child: pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            text,
            softWrap: false,
            style: style(font, isBold, filled(font, text, width * unit), color),
          ),
        ),
      ),
    );
  }

  pw.Widget blank(String name, double x, double y, double width) {
    final boxWidth = width * unit;
    final text = values[name] ?? '';
    var value = text;
    var size = _sheetBodySize * unit;
    final minimum = 20 * unit;
    if (text.isNotEmpty) {
      size = (boxWidth / regular.getFont(context).stringMetrics(text).width)
          .clamp(minimum, _sheetBodySize * unit)
          .toDouble();
      if (size <= minimum) {
        var cut = text;
        while (cut.isNotEmpty &&
            regular.getFont(context).stringMetrics('$cut...').width * minimum >
                boxWidth) {
          cut = cut.substring(0, cut.length - 1);
        }
        if (cut.length < text.length) value = cut.isEmpty ? '' : '$cut...';
        size = minimum;
      }
    }
    return pw.Positioned(
      left: px(x) - m.sideMargin,
      top: top(y),
      child: pw.SizedBox(
        width: boxWidth,
        height: row,
        child: pw.Stack(
          overflow: pw.Overflow.visible,
          children: [
            pw.Positioned(
              left: 0,
              right: 0,
              top: _sheetRuleTop * unit,
              child: pw.SizedBox(
                height: _sheetRule * unit,
                child: pw.Container(color: PdfColors.black),
              ),
            ),
            if (value.isNotEmpty)
              pw.Positioned.fill(
                child: pw.Container(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    value,
                    softWrap: false,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: size,
                      color: PdfColors.black,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  return pw.SizedBox(
    width: m.contentWidth,
    height: bodyH,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        heading(415, 317, 737, DocTemplate.clinicDepartment.toUpperCase(),
            isBold: true, color: _sheetGreen),
        heading(636, 362, 279, 'Maloro, Tangub City', color: _sheetGreen),
        heading(510, 562, 530, title, isBold: true, color: _sheetGreen),
        spread(218, 728, 374, 'This is to certify that'),
        blank('visitor.full_name', 613, 728, 784),
        word(1399, 728, ','),
        blank('visitor.age', 137, 795, 700),
        spread(863, 795, 534,
            'years old, ${sex.isEmpty ? 'female/male' : sex} from'),
        blank('visitor.address', 137, 860, 658),
        word(797, 860, ','),
        spread(825, 860, 215, 'appeared last'),
        blank('visit.date', 1058, 860, 339),
        spread(137, 928, 721, 'at TCGC Medical and Dental Clinic due to'),
        blank('visit.reason', 878, 928, 519),
        word(1399, 928, '.'),
        spread(
            218,
            1062,
            1194,
            'This certification is issued upon the request of the above name '
            'person for'),
        spread(
            137,
            1130,
            1275,
            'whatever legal purpose may serve so that $sheOrHe will be '
            'excused for'),
        blank('excused_for', 137, 1197, 598),
        word(737, 1197, '.'),
        spread(218, 1332, 176, 'Issued this'),
        blank('issued.day', 413, 1332, 132),
        spread(567, 1332, 106, 'day of'),
        blank('issued.month', 693, 1332, 292),
        word(987, 1332, ','),
        blank('issued.year', 1012, 1332, 126),
        spread(1160, 1332, 252, 'at Tangub City,'),
        word(137, 1395, 'Philippines.'),
        pw.Positioned(
          left: px(137) - m.sideMargin,
          top: local(fromBottom(398)) - _sheetRule * unit / 2,
          child: pw.SizedBox(
            width: 623 * unit,
            height: _sheetRule * unit,
            child: pw.Container(color: PdfColors.black),
          ),
        ),
        heading(233, fromBottom(362), 464, signatoryName.toUpperCase(),
            isBold: true, color: _sheetGreen),
        heading(235, fromBottom(319), 489, signatoryRole.toUpperCase(),
            color: _sheetGreen),
      ],
    ),
  );
}

pw.Widget _field(RenderedLine line, DocMetrics m) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: m.contentWidth * 0.30,
            child: pw.Text(
              line.label.isEmpty ? '' : '${line.label}:',
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.3,
                color: DocPalette.muted,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              line.value,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: DocPalette.ink,
              ),
            ),
          ),
        ],
      ),
      pw.Divider(
        height: 7,
        thickness: 0.5,
        color: DocPalette.rule,
      ),
    ],
  );
}

pw.Widget _signature(RenderedLine line) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 10),
      pw.SizedBox(
        width: 160,
        child: pw.Divider(
          height: 8,
          thickness: 0.7,
          color: DocPalette.rule,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        line.text,
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: DocPalette.ink,
        ),
      ),
      if (line.value.isNotEmpty)
        pw.Text(
          line.value,
          style: pw.TextStyle(
            fontSize: 9,
            color: DocPalette.muted,
          ),
        ),
    ],
  );
}

pw.Widget _table(RenderedLine line) {
  final exam = line.kind == DocBlockKind.examTable;
  final headers = exam
      ? const ['PHYSICAL EXAMINATION', 'FINDINGS']
      : const ['DATE', 'CHIEF COMPLAINT', 'TREATMENT RECORDS'];
  final data = line.rows.isEmpty
      ? <List<String>>[List<String>.filled(headers.length, '')]
      : line.rows;
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerDecoration: const pw.BoxDecoration(color: DocPalette.tableHead),
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.4,
      color: DocPalette.darkGreen,
    ),
    cellStyle: pw.TextStyle(
      fontSize: 9.5,
      lineSpacing: 1.6,
      color: DocPalette.ink,
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    border: pw.TableBorder.all(color: DocPalette.rule, width: 0.4),
    columnWidths: {
      for (int i = 0; i < headers.length; i++)
        i: pw.FlexColumnWidth(i == 0 ? 3 : 2),
    },
  );
}

const String _sheetHeaderSvg =
    '''<svg viewBox="0 0 1545 300" width="100%" xmlns="http://www.w3.org/2000/svg">
  <polygon points="232,42 868,42 780,188 232,188" fill="#D95F0E"/>
  <polygon points="232,188 780,188 752,237 232,237" fill="#0E6B47"/>
  <polygon points="897,45 943,45 873,162 825,162" fill="#0E6B47"/>
  <polygon points="945,67 1505,67 1505,158 903,158" fill="#0E6B47"/>
  <circle cx="160" cy="150" r="125" fill="#FFFFFF"/>
  <image href="LOGO_ASSET" x="40" y="30" width="240" height="240" preserveAspectRatio="xMidYMid meet"/>
  <text x="952" y="118" fill="#FFFFFF" font-family="Times New Roman, serif" font-weight="bold" font-size="32" textLength="534" lengthAdjust="spacingAndGlyphs">TANGUB CITY GLOBAL COLLEGE</text>
  <text x="1486" y="146" text-anchor="end" fill="#FFFFFF" font-family="Times New Roman, serif" font-style="italic" font-size="21">Formerly GADC</text>
</svg>''';

Future<String> loadSheetHeaderSvg() async {
  final logo = await DocumentAssets.logoDataUri();
  if (logo.isEmpty) return _sheetHeaderSvg;
  return _sheetHeaderSvg.replaceFirst('LOGO_ASSET', logo);
}

pw.Widget sheetHeader(DocMetrics m, String svg, double hang) {
  final height = _sheetHeaderHeight(m);
  return pw.SizedBox(
    height: height,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        pw.Positioned(
          left: -hang,
          right: -hang,
          top: 0,
          child: pw.SvgImage(
            svg: svg,
            width: m.pageWidth,
            height: height,
            customFontLookup: _sheetHeaderFont,
          ),
        ),
      ],
    ),
  );
}

pw.Font? _sheetHeaderFont(String family, String style, String weight) {
  if (!family.toLowerCase().contains('serif')) return null;
  final bold = weight == 'bold' || weight == 'bolder';
  final italic = style == 'italic' || style == 'oblique';
  if (bold && italic) return DocumentAssets.serifBoldItalic();
  if (bold) return DocumentAssets.serifBold();
  if (italic) return DocumentAssets.serifItalic();
  return DocumentAssets.serif();
}

pw.Widget _header(DocMetrics m, pw.Widget logo) {
  return pw.SizedBox(
    height: m.headerH,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        pw.Positioned(
          left: -m.sideMargin,
          right: -m.sideMargin,
          top: 0,
          bottom: 0,
          child: _pageArt(m, logo),
        ),
      ],
    ),
  );
}

pw.Widget _pageArt(DocMetrics m, pw.Widget logo) {
  final w = m.pageWidth;
  final h = m.headerH;
  PdfPoint p(double x, double y) => PdfPoint(x * w, y * h);

  final bannerLeft = w * (m.isLandscape ? 0.40 : 0.44);
  final bannerHeight = h * 0.36;

  return pw.Stack(
    children: [
      pw.Positioned.fill(
        child: pw.Polygon(
          fillColor: DocPalette.orange,
          points: [
            p(0, 0),
            p(1, 0),
            p(1, 0.44),
            p(0, 0.66),
          ],
        ),
      ),
      pw.Positioned.fill(
        child: pw.Polygon(
          fillColor: DocPalette.darkGreen,
          points: [
            p(0, 0.66),
            p(1, 0.44),
            p(1, 0.78),
            p(0, 1),
          ],
        ),
      ),
      pw.Positioned.fill(
        child: pw.Polygon(
          fillColor: DocPalette.accentGreen,
          points: [
            p(0.50, 0.475),
            p(1, 0.365),
            p(1, 0.425),
            p(0.50, 0.535),
          ],
        ),
      ),
      pw.Positioned.fill(
        child: pw.Polygon(
          fillColor: DocPalette.accentGreen,
          points: [
            p(0.58, 0.6424),
            p(1, 0.55),
            p(1, 0.605),
            p(0.58, 0.6974),
          ],
        ),
      ),
      pw.Positioned(
        left: bannerLeft,
        right: 0,
        top: h * 0.08,
        bottom: h * 0.56,
        child: _banner(bannerHeight),
      ),
      pw.Positioned(
        left: m.sideMargin,
        top: h * 0.06,
        child: logo,
      ),
    ],
  );
}

pw.Widget _banner(double height) {
  final nameSize = height * 0.26;
  final formerSize = height * 0.13;
  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: pw.Padding(
      padding: const pw.EdgeInsets.only(left: 16, right: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.max,
        children: [
          pw.Text(
            DocTemplate.clinicName.toUpperCase(),
            style: pw.TextStyle(
              fontSize: nameSize,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
              lineSpacing: 2,
              color: DocPalette.onDark,
            ),
          ),
          pw.SizedBox(height: nameSize * 0.2),
          pw.Text(
            'Formerly ${DocTemplate.formerName}',
            style: pw.TextStyle(
              fontSize: formerSize,
              fontStyle: pw.FontStyle.italic,
              color: DocPalette.onDarkSoft,
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _continuationHeader(DocMetrics m) {
  final h = m.continuationH;
  return pw.SizedBox(
    height: h,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        pw.Positioned(
          left: -m.sideMargin,
          right: -m.sideMargin,
          top: 0,
          bottom: 0,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Container(color: DocPalette.darkGreen),
              ),
              pw.Positioned(
                left: m.sideMargin,
                right: m.sideMargin,
                top: 0,
                bottom: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      DocTemplate.clinicName,
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                        color: DocPalette.onDark,
                      ),
                    ),
                    pw.Text(
                      DocTemplate.clinicDepartment,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: DocPalette.onDarkSoft,
                      ),
                    ),
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

pw.Widget _footer(DocMetrics m, String footerText) {
  final split = _splitFooter(footerText);
  final inset = (m.footerH - m.sealSize) / 2;
  return pw.SizedBox(
    height: m.footerH,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        pw.Positioned(
          left: -m.sideMargin,
          right: -m.sideMargin,
          top: 0,
          bottom: 0,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Container(color: DocPalette.darkGreen),
              ),
              pw.Positioned(
                left: m.sideMargin,
                right: m.sideMargin,
                top: inset,
                bottom: inset,
                child: _sealRing(m.sealSize),
              ),
              pw.Positioned(
                left: m.sideMargin + m.sealSize + 14,
                right: m.sideMargin,
                top: 0,
                bottom: 0,
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.max,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        split.left,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                          color: DocPalette.onDarkSoft,
                          lineSpacing: 1.5,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        split.right,
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 8,
                          letterSpacing: 0.3,
                          color: DocPalette.onDarkSoft,
                          lineSpacing: 1.5,
                        ),
                      ),
                    ),
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

const String _sheetFooterSvg =
    '''<svg viewBox="0 0 1545 120" width="100%" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="sealClip"><circle cx="770" cy="50" r="60"/></clipPath>
  </defs>
  <rect x="45" y="8" width="1452" height="85" fill="#0E6B47"/>
  <circle cx="770" cy="50" r="68" fill="#FFFFFF"/>
  <image href="LOGO_ASSET" x="710" y="-10" width="120" height="120" preserveAspectRatio="xMidYMid slice" clip-path="url(#sealClip)"/>
  <text x="313" y="48" fill="#FFFFFF" font-family="Times New Roman, serif" font-style="italic" font-size="26" textLength="215" lengthAdjust="spacingAndGlyphs">LEARN TODAY</text>
  <text x="305" y="76" fill="#FFFFFF" font-family="Times New Roman, serif" font-style="italic" font-size="26" textLength="230" lengthAdjust="spacingAndGlyphs">Light of the World</text>
  <text x="918" y="60" fill="#FFFFFF" font-family="Times New Roman, serif" font-size="26" textLength="550" lengthAdjust="spacingAndGlyphs">HONESTY • COMPASSION • EXCELLENCE</text>
</svg>''';

Future<String> loadSheetFooterSvg() async {
  final svg = _sheetFooterSvg.replaceAll('\u2022', '\u00b7');
  final logo = await DocumentAssets.logoDataUri();
  if (logo.isEmpty) return svg;
  return svg.replaceFirst('LOGO_ASSET', logo);
}

pw.Widget sheetFooter(DocMetrics m, String svg, double hang) {
  final unit = m.pageWidth / 1545;
  final artHeight = 120 * unit;
  final overhangHeight = 18 * unit;
  return pw.SizedBox(
    height: _sheetFooterHeight(m),
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        pw.Positioned(
          left: -hang,
          right: -hang,
          top: m.isLandscape ? 0 : overhangHeight,
          child: pw.SvgImage(
            svg: svg,
            clip: false,
            width: m.pageWidth,
            height: artHeight,
            customFontLookup: _sheetHeaderFont,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sealRing(double size) {
  final inset = size * 0.13;
  return pw.Stack(
    children: [
      pw.Positioned.fill(
        child: pw.Circle(
          strokeColor: DocPalette.onDark,
          strokeWidth: 1.4,
        ),
      ),
      pw.Positioned(
        left: inset,
        right: inset,
        top: inset,
        bottom: inset,
        child: pw.Circle(
          strokeColor: DocPalette.onDarkSoft,
          strokeWidth: 0.9,
        ),
      ),
    ],
  );
}

({String left, String right}) _splitFooter(String footer) {
  const location = 'Maloro, Tangub City';
  for (final separator in ['•', ' © ', '·', '|']) {
    final at = footer.indexOf(separator);
    if (at < 0) continue;
    final left = footer.substring(0, at).trim();
    final right = footer.substring(at + separator.length).trim();
    if (left.isEmpty && right.isEmpty) continue;
    return (left: left, right: right);
  }
  if (footer.trim().isEmpty) return (left: location, right: '');
  return (left: footer.trim(), right: location);
}
