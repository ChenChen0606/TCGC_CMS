// ─────────────────────────────────────────────────────────────────────────────
//  visit_review_card.dart
//  The frame a visit's record is printed inside.
//
//  WHY THIS IS A SEPARATE FILE AND NOT A WIDGET IN ONE SCREEN
//  Two places print one visit:
//    * step 4 of the Clinic Visit wizard, where the nurse checks what she is
//      about to save, and
//    * the Records Booklet, where somebody opens a visit that was saved days ago
//      and has to find the same thing she saw.
//
//  The wording of a service's answers is already shared — it comes from
//  `serviceSummary` (core/visit_service_summary.dart). What was not shared was
//  the frame around it, and a frame written twice is a frame that is a few weeks
//  out of date in one of the two places: the booklet grew a Status line, or a
//  heading stopped being capitalised, and step 4 kept saying it the old way.
//  Nothing in a medical record should be able to drift like that, so the frame
//  lives here too, and both screens draw it.
//
//  This file knows about panels, padding and fonts. It knows nothing about
//  visits, Supabase, or which screen is asking — that is what the callers bring.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/visit_details.dart';
import '../core/visit_service_summary.dart';
import '../core/vitals.dart';
import 'app_colors.dart';

/// One line of a visit record.
///
/// Encoded as a type rather than as a marker string so that a service the nurse
/// named "— Cleaning Performed" cannot break the card that lists it.
class VisitReviewLine {
  const VisitReviewLine.pair(this.label, this.value) : heading = null;
  const VisitReviewLine.heading(this.heading)
      : label = '',
        value = '';
  const VisitReviewLine.plain(this.value)
      : heading = null,
        label = '';

  /// Set on a sub-heading, which names the form slide the lines under it came
  /// from. Null on every line that carries an answer.
  final String? heading;

  final String label;
  final String value;
}

/// One `label: value` line, with a fixed gutter in front of the label so that
/// every value on the card starts in the same place and a card reads as a column
/// rather than as ragged sentences.
class VisitReviewRow extends StatelessWidget {
  const VisitReviewRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:',
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(
              // A dash rather than a blank: an empty cell in a record reads as
              // something that failed to render.
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line with nothing to label it — a service in a list, or a note about a
/// service that has no answers yet. Full width, because a hundred-pixel gutter
/// in front of a sentence that is the whole line reads as a missing label.
class VisitReviewText extends StatelessWidget {
  const VisitReviewText(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        value,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMain,
            height: 1.3),
      ),
    );
  }
}

/// A titled card of lines. The shape every block of a visit record takes: the
/// visitor, the services, one card per service, the record itself.
class VisitReviewCard extends StatelessWidget {
  const VisitReviewCard({
    super.key,
    required this.title,
    required this.lines,
    this.trailing,
  });

  final String title;
  final List<VisitReviewLine> lines;

  /// An optional status chip in the title row — used by the booklet to put each
  /// service's state next to its name, which is the one thing a reader of a
  /// stored record is looking for.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                      letterSpacing: 0.2),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines) ...[
            if (line.heading != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  line.heading!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSub,
                  ),
                ),
              )
            else if (line.label.isEmpty)
              VisitReviewText(line.value)
            else
              VisitReviewRow(line.label, line.value),
          ],
        ],
      ),
    );
  }
}

/// One service's answers, flattened to the lines a review card draws, with the
/// form's slides named as sub-headings so a long form reads as the sections the
/// nurse filled rather than one undifferentiated wall.
///
/// The Status line is first because it is the question being asked of a stored
/// record before anything else: what state was this left in.
List<VisitReviewLine> visitReviewLines(ServiceDraft draft, VisitVitals vitals) {
  final sections = serviceSummary(draft, vitals);
  if (sections.isEmpty) {
    return const [
      VisitReviewLine.plain('Nothing entered on this service yet.')
    ];
  }
  final lines = <VisitReviewLine>[
    VisitReviewLine.pair('Status', draft.status.label),
  ];
  for (final section in sections) {
    if (section.title.trim().isNotEmpty) {
      lines.add(VisitReviewLine.heading(section.title));
    }
    for (final r in section.rows) {
      lines.add(r.label.isEmpty
          ? VisitReviewLine.plain(r.value)
          : VisitReviewLine.pair(r.label, r.value));
    }
  }
  return lines;
}

/// The same lines without the Status row.
///
/// Used by a caller that puts the state in the card's title row instead — the
/// booklet does, because a list of five services reads better with the state
/// beside each name than with a Status line repeating it twice.
List<VisitReviewLine> visitReviewAnswerLines(
    ServiceDraft draft, VisitVitals vitals) {
  final sections = serviceSummary(draft, vitals);
  if (sections.isEmpty) {
    return const [
      VisitReviewLine.plain('Nothing entered on this service yet.')
    ];
  }
  final lines = <VisitReviewLine>[];
  for (final section in sections) {
    if (section.title.trim().isNotEmpty) {
      lines.add(VisitReviewLine.heading(section.title));
    }
    for (final r in section.rows) {
      lines.add(r.label.isEmpty
          ? VisitReviewLine.plain(r.value)
          : VisitReviewLine.pair(r.label, r.value));
    }
  }
  return lines;
}
