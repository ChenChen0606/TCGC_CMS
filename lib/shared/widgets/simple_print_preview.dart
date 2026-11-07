import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:clinicmanagementsystem/shared/widgets/zoomable_pdf_pages.dart';
import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/shared/printing/document_template.dart';
import 'package:clinicmanagementsystem/shared/printing/print_service.dart';
import 'package:clinicmanagementsystem/shared/printing/html_print.dart';
import 'package:clinicmanagementsystem/shared/printing/html_certificate.dart';
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
}) async {
  // Web: same as the Records Booklet, open Chrome's print dialog.
  if (htmlPrintSupported) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final html = await buildCertificateHtml(document);
      await printHtml(html, title: fileName);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not print the certificate: $e')),
      );
    }
    return;
  }
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
          pagesBuilder: zoomablePagesBuilder,
        ),
      ),
    );
  }

}
