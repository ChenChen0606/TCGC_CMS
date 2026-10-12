// ─────────────────────────────────────────────────────────────────────────────
//  visit_service_summary.dart
//  One service, printed back as plain rows.
//
//  WHY THIS IS A SEPARATE FILE AND NOT A WIDGET
//  Two screens have to say the same thing about the same answers: the review
//  slide every service ends on in step 3, and step 4's whole-visit summary. When
//  each built its own rows they were two descriptions of one record that could
//  disagree, and the disagreement would not show up until a nurse read a visit
//  back and found a field that step 3 had shown and step 4 had dropped.
//
//  So the reading lives here, once, and returns data. Nothing in this file knows
//  about panels, padding or fonts - a screen that wants the rows draws them in
//  its own house style.
//
//  The rules it holds to:
//    - Built from the spec, so what is printed is whatever boxes the form
//      actually has. A service nobody has touched prints almost nothing rather
//      than a page of dashes.
//    - A field with no answer is not printed. A summary full of "-" tells a
//      nurse nothing about which blanks were deliberate and which were missed.
//    - The shared vital strip is never printed twice: a service that reads the
//      visit's temperature does not own a temperature box to print.
//    - The visit's own readings are printed once, at the end, for any service
//      whose form reads them.
// ─────────────────────────────────────────────────────────────────────────────

import 'visit_details.dart';
import 'visit_service_forms.dart';
import 'vitals.dart';

/// One line of a summary: the box's own label and what was put in it.
///
/// An empty [label] means the line stands on its own — the medicine rows, where
/// the line is already the whole sentence, name and all.
class SummaryRow {
  const SummaryRow(this.label, this.value);

  final String label;
  final String value;
}

/// A named group of rows - the form's slides are the natural grouping, and a
/// nurse checking a form back reads it in the order the work was done.
class SummarySection {
  const SummarySection(this.title, this.rows);

  final String title;
  final List<SummaryRow> rows;
}

/// Everything [draft] holds, as printable sections.
///
/// Returns an empty list for a service nobody has started: an empty section
/// carries no information, and printing one per service would turn step 4 into a
/// stack of blank cards.
List<SummarySection> serviceSummary(ServiceDraft draft, VisitVitals vitals) {
  final sections = <SummarySection>[];

  for (final slide in draft.spec.slides) {
    // The review slide is where this is being printed, so it has nothing to say
    // about itself.
    if (slide.custom?.id == 'form_review') continue;
    final rows = <SummaryRow>[];
    for (final f in slide.fields) {
      // The shared strip is a pointer to readings another service owns; it is
      // not an answer, and printing it would put a value in this service's
      // record that this service never took.
      if (f.kind == ServiceFieldKind.sharedVitals) continue;
      final value = summaryValue(draft, f);
      if (value.trim().isEmpty) continue;
      rows.add(SummaryRow(f.label, value));
    }
    if (rows.isNotEmpty) sections.add(SummarySection(slide.title, rows));
  }

  if (draft.medicines.isNotEmpty) {
    // Unlabelled: [MedicineDose.summary] is already a whole line - name,
    // quantity, dosage, instructions - and prefixing it with its own name would
    // print "Paracetamol" twice on every prescription line.
    sections.add(SummarySection('Medicines', [
      for (final m in draft.medicines) SummaryRow('', m.summary),
    ]));
  }

  final wantsVitals = draft.spec.slides.any((s) => s.fields
      .any((f) => f.kind == ServiceFieldKind.sharedVitals || f.vital != null));
  if (wantsVitals) {
    final readings = <SummaryRow>[
      for (final r in [
        vitals.bloodPressure,
        vitals.heartRateReading,
        vitals.respRateReading,
        vitals.tempReading,
        vitals.o2Reading,
        vitals.bmiReading,
      ])
        if (r != null) SummaryRow(r.label, r.display),
    ];
    if (readings.isNotEmpty) {
      sections.add(SummarySection('Visit Vitals', readings));
    }
  }

  return sections;
}

/// The value a field has been answered with, written the way a person would read
/// it off the record: ticked boxes joined by a middot, a measurement with its
/// unit, anything else as it stands.
String summaryValue(ServiceDraft draft, ServiceField field) {
  switch (field.kind) {
    case ServiceFieldKind.checkboxes:
    case ServiceFieldKind.chips:
    case ServiceFieldKind.multiselect:
    // Whatever was taken off the shelf is a list of names, and a list printed
    // raw comes out as "[Povidone-Iodine]" - the brackets and the comma are the
    // record's business, not the nurse's.
    case ServiceFieldKind.inventoryPick:
      return draft.chosen(field.key).join(' · ');
    case ServiceFieldKind.number:
      final v = draft.text(field.key).trim();
      if (v.isEmpty) return '';
      final unit = field.unit?.trim() ?? '';
      return unit.isEmpty ? v : '$v $unit';
    default:
      return draft.text(field.key).trim();
  }
}
