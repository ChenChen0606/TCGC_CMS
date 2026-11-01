import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';

class PrintRequirement {
  const PrintRequirement(this.key, this.label);

  final String key;

  final String label;
}

const List<PrintRequirement> medicalCertificateRequirements =
    <PrintRequirement>[
  PrintRequirement('visitor.full_name', 'Patient name'),
  PrintRequirement('visitor.age', 'Age'),
  PrintRequirement('visitor.address', 'Address'),
  PrintRequirement('visit.date', 'Clinic visit date'),
  PrintRequirement('visit.reason', 'Reason for the visit'),
  PrintRequirement('excused_for', 'Purpose'),
];
