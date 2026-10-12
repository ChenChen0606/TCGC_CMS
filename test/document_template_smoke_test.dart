import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:clinicmanagementsystem/core/certificate_engine.dart';
import 'package:clinicmanagementsystem/screen/document_template.dart';

const _template = DocTemplate(
  name: 'Certificate of Fitness',
  type: 'certificate',
  version: 1,
  subtitle: 'Medical and Dental Clinic Office',
  blocks: <DocBlock>[],
  footer: 'Lux Mundi, Light of the World · Integrity · Compassion · Excellence',
);

const _short = RenderedDocument(
  template: _template,
  referenceNo: 'preview',
  issuedBy: 'clinic',
  lines: <RenderedLine>[
    RenderedLine.heading('CERTIFICATE OF FITNESS'),
    RenderedLine.subheading('PHYSICAL EXAMINATION'),
    RenderedLine.paragraph(
        'This is to certify that the person named below has been examined on '
        'this day and is fit to resume normal activity, with every finding '
        'recorded exactly as it is stated here.'),
    RenderedLine.field(label: 'Name', value: 'Juan Dela Cruz D. Santos Jr.'),
    RenderedLine.field(label: 'Date of birth', value: 'January 01, 2005'),
    RenderedLine.field(label: 'Sex', value: 'Male'),
    RenderedLine.field(label: 'Contact', value: '0917 123 4567'),
    RenderedLine.divider(),
    RenderedLine.examTable(<List<String>>[
      <String>['Height', '170 cm'],
      <String>['Weight', '60 kg'],
      <String>['Vision', '20/20'],
    ]),
    RenderedLine.historyTable(<List<String>>[
      <String>['Date', 'Purpose'],
      <String>['2026-01-05', 'Annual'],
      <String>['2025-08-14', 'Return check'],
    ]),
    RenderedLine.space(),
    RenderedLine.signature(name: 'Dr. Maria Reyes', role: 'Clinic Physician'),
    RenderedLine.signature(name: 'Dr. Jose Ramos', role: 'Dentist'),
  ],
);

RenderedDocument _longDocument() => RenderedDocument(
      template: _template,
      referenceNo: 'preview',
      issuedBy: 'clinic',
      lines: <RenderedLine>[
        const RenderedLine.heading('CERTIFICATE OF FITNESS'),
        for (var i = 0; i < 45; i++)
          RenderedLine.paragraph(
              'Paragraph ${i + 1}: a long body of prose that repeats often '
              'enough to push past one sheet of paper, so that the second page '
              'and its continuation heading are exercised as well.'),
        const RenderedLine.signature(
            name: 'Dr. Maria Reyes', role: 'Clinic Physician'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final paper in <String>['A4', 'Letter', 'Legal']) {
    for (final landscape in <bool>[false, true]) {
      final label = '$paper ${landscape ? 'landscape' : 'portrait'}';

      test('renders the one-page document on $label', () async {
        final bytes = await renderDocumentPdf(
          _short,
          pageFormat: PaperFormat.formatFor(paper, landscape),
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
        File('C:/Users/CHEN~1/AppData/Local/Temp/opencode/'
                'short_$label.pdf')
            .writeAsBytesSync(bytes);
      });

      test('spans multiple pages on $label', () async {
        final short = await renderDocumentPdf(
          _short,
          pageFormat: PaperFormat.formatFor(paper, landscape),
        );
        final long = await renderDocumentPdf(
          _longDocument(),
          pageFormat: PaperFormat.formatFor(paper, landscape),
        );
        expect(long, isNotEmpty);
        expect(long.length, greaterThan(short.length));
        File('C:/Users/CHEN~1/AppData/Local/Temp/opencode/'
                'doc_${paper}_$label.pdf')
            .writeAsBytesSync(long);
        File('C:/Users/CHEN~1/AppData/Local/Temp/opencode/'
                'short_${paper}_$label.pdf')
            .writeAsBytesSync(short);
        final pages = RegExp(r'/Type/Page(?!s)').allMatches(
          String.fromCharCodes(long),
        );
        expect(pages.length, greaterThan(1), reason: 'expected a second page');
      });
    }
  }
}
