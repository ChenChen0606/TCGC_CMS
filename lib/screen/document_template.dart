import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/certificate_engine.dart';
import 'app_colors.dart';

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

class DocMetrics {
  DocMetrics(this.pageFormat);

  final PdfPageFormat pageFormat;

  double get pageWidth => pageFormat.width;

  double get pageHeight => pageFormat.height;

  bool get isLandscape => pageWidth > pageHeight;

  double get headerH => pageHeight * (isLandscape ? 0.21 : 0.17);

  double get footerH => pageHeight * (isLandscape ? 0.115 : 0.085);

  double get _side => pageWidth * (isLandscape ? 0.06 : 0.085);

  double get contentWidth => math.min(pageWidth - 2 * _side, 510);

  double get sideMargin => (pageWidth - contentWidth) / 2;

  double get sealSize => footerH * 0.74;

  double get logoSize => math.min(headerH * 0.34, pageWidth * 0.12);

  double get continuationH => headerH * 0.24;
}

Future<Uint8List> renderDocumentPdf(
  RenderedDocument document, {
  PdfPageFormat pageFormat = PdfPageFormat.letter,
}) async {
  final m = DocMetrics(pageFormat);
  final logo = await _loadLogo(m.logoSize);

  final pdf = pw.Document(
    title: document.template.name,
    author: document.issuedBy,
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.fromLTRB(m.sideMargin, 0, m.sideMargin, 0),
      theme: _serifTheme(),
      maxPages: 40,
      header: (context) =>
          context.pageNumber == 1 ? _header(m, logo) : _continuationHeader(m),
      footer: (context) => _footer(m, document.footer),
      build: (context) => _body(document, m),
    ),
  );

  return pdf.save();
}

pw.ThemeData _serifTheme() => pw.ThemeData.withFont(
      base: pw.Font.times(),
      bold: pw.Font.timesBold(),
      italic: pw.Font.timesItalic(),
      boldItalic: pw.Font.timesBoldItalic(),
    );

Future<pw.Widget> _loadLogo(double size) async {
  try {
    final data = await rootBundle.load('asset/tcgc.png');
    return pw.Image(
      pw.MemoryImage(data.buffer.asUint8List()),
      width: size,
      height: size,
      fit: pw.BoxFit.contain,
    );
  } catch (_) {
    return pw.SizedBox(width: size, height: size);
  }
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
  return pw.SizedBox(
    width: m.contentWidth,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          DocTemplate.clinicDepartment,
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
            DocTemplate.clinicName,
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
  for (final separator in ['•', ' A© ', '·', '|']) {
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

class PaperFormatPicker extends StatelessWidget {
  const PaperFormatPicker({
    super.key,
    required this.paperKey,
    required this.landscape,
    required this.onPaper,
    required this.onOrientation,
  });

  final String paperKey;
  final bool landscape;
  final ValueChanged<String> onPaper;
  final ValueChanged<bool> onOrientation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _label('Paper size'),
          for (final key in PaperFormat.sizes)
            _chip(key, paperKey == key, () => onPaper(key)),
          const SizedBox(width: 10),
          _label('Layout'),
          _chip('Portrait', !landscape, () => onOrientation(false)),
          _chip('Landscape', landscape, () => onOrientation(true)),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSub,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textMain,
          ),
        ),
      ),
    );
  }
}
