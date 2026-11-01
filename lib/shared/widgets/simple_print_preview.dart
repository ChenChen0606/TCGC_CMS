import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/shared/printing/document_template.dart';
import 'package:clinicmanagementsystem/shared/printing/print_service.dart';

class SimplePrintPreview extends StatefulWidget {
  const SimplePrintPreview({
    super.key,
    required this.document,
    required this.fileName,
    required this.title,
    this.requirements = const <PrintRequirement>[],
  });

  final RenderedDocument document;
  final String fileName;
  final String title;

  final List<PrintRequirement> requirements;

  static Future<void> show(
    BuildContext context, {
    required RenderedDocument document,
    required String fileName,
    required String title,
    List<PrintRequirement> requirements = const <PrintRequirement>[],
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SimplePrintPreview(
        document: document,
        fileName: fileName,
        title: title,
        requirements: requirements,
      ),
    );
  }

  @override
  State<SimplePrintPreview> createState() => _SimplePrintPreviewState();
}

class _SimplePrintPreviewState extends State<SimplePrintPreview> {
  bool _printing = false;

  PdfPageFormat get _format => PaperFormat.formatFor('Letter', false);

  Future<Uint8List> _build(PdfPageFormat paper) =>
      renderDocumentPdf(widget.document, pageFormat: paper);

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await Printing.layoutPdf(
        name: '${widget.fileName}.pdf',
        format: _format,
        dynamicLayout: true,
        onLayout: (paper) => _build(paper),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not print the certificate: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: AppColors.bgAlt,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textMain,
          elevation: 0.5,
          titleSpacing: 20,
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close preview',
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: _printing ? null : _print,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: PdfPreviewCustom(
          pageFormat: _format,
          build: _build,
          pagesBuilder: _fitPages,
        ),
      ),
    );
  }

  Widget _fitPages(BuildContext context, List<PdfPreviewPageData> pages) {
    const gap = 16.0;
    const pad = 16.0;
    if (pages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final availW =
          (constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0) -
              2 * pad;
      final availH =
          (constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0) -
              2 * pad;
      if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

      final n = pages.length;
      var cols = 1;
      while (cols * cols < n) {
        cols++;
      }
      final rows = (n + cols - 1) ~/ cols;

      var cellW = (availW - gap * (cols - 1)) / cols;
      var cellH = cellW / pages.first.aspectRatio;
      final rowH = (availH - gap * (rows - 1)) / rows;
      if (cellH > rowH) {
        cellH = rowH;
        cellW = cellH * pages.first.aspectRatio;
      }
      if (cellW <= 0 || cellH <= 0) return const SizedBox.shrink();

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final page in pages)
                Container(
                  width: cellW,
                  height: cellH,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFDADADA)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        offset: Offset(0, 3),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image(
                      image: page.image,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
