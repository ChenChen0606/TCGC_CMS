// ─────────────────────────────────────────────────────────────────────────────
//  bp_guide_overlay.dart
//  The guide that explains the BP Taking form's own numbers.
//
//  This file used to hold slides 2 and 3 of the form — the other signs and the
//  symptoms, and the technique checklist — alongside this overlay. The form is
//  one screen now, those two slides are no longer part of any spec, and the
//  respiratory rate and oxygen saturation they collected are not fields the form
//  declares, so nothing could reach them. They were deleted rather than left
//  parked: a second, older copy of the BP rules in the tree is how a form ends
//  up banding the same reading two different ways.
//
//  What is left is the guide, because the rules the result card applies are not
//  the rules anyone was trained on, and a nurse taking a reading has to be able
//  to see the band table and check them against it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/core/vitals_interpretation.dart';
import 'package:clinicmanagementsystem/screen/app_colors.dart';
import 'package:clinicmanagementsystem/screen/bp_form_kit.dart';
import 'package:flutter/material.dart';

/// Opens the BP guide over the form.
///
/// An overlay on the card's own area rather than a dialog: a dialog dims the
/// whole screen and hides the reading the guide is explaining, so the nurse
/// cannot check the two against each other.
class BpGuideOverlay extends StatelessWidget {
  const BpGuideOverlay({
    super.key,
    required this.current,
    required this.onClose,
  });

  /// The severity to highlight, or null when nothing has been read yet.
  final BpSeverity? current;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final rows = bpGuideRows();
    return Stack(
      key: const ValueKey('bp/guide'),
      children: [
        // Tapping outside closes it, which is what a nurse expects of a panel
        // that appeared over the form they were using.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: const Color(0x66101828)),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: bpPanel(
              tint: AppColors.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                // No scroll view, deliberately. The guide has to be readable in
                // one look at 1366x768: a scrollbar inside a reference panel
                // means the nurse has to stop reading to find what they have not
                // read, and they do not. If this ever outgrows the screen, the
                // fix is to shorten the text — not to hand back a scrollbar.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 460,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Blood Pressure Guide',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMain,
                                ),
                              ),
                            ),
                            InkWell(
                              key: const ValueKey('bp/guide_close'),
                              onTap: onClose,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close,
                                    size: 17, color: AppColors.textSub),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          kBpGuideHowToRead,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: AppColors.textSub,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _table(rows),
                        const SizedBox(height: 8),
                        const Text(
                          kBpGuideTableNote,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _Section(
                          title: 'Taking an accurate reading',
                          body: kBpGuideAccurateReading,
                        ),
                        const SizedBox(height: 10),
                        const _Section(
                          title: 'Important',
                          body: kBpGuideImportant,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'For clinic reference only.',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _table(List<BpGuideRow> rows) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.bgAlt,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            children: [
              Expanded(flex: 5, child: _Th('Category')),
              Expanded(flex: 3, child: _Th('Systolic')),
              Expanded(flex: 3, child: _Th('Diastolic')),
            ],
          ),
        ),
        for (final row in rows)
          _row(row.severity, row.systolicRange, row.diastolicRange),
      ],
    );
  }

  Widget _row(BpSeverity severity, String sys, String dia) {
    final isCurrent = severity == current;
    final colors = bpSeverityColors(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isCurrent ? colors.bg : null,
        border: isCurrent
            ? Border.all(color: colors.fg.withValues(alpha: 0.35))
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    severity.phishLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? colors.fg : AppColors.textMain,
                    ),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.fg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(flex: 3, child: _Td(sys, isCurrent, colors.fg)),
          Expanded(flex: 3, child: _Td(dia, isCurrent, colors.fg)),
        ],
      ),
    );
  }
}

class _Th extends StatelessWidget {
  const _Th(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSub,
        ),
      );
}

class _Td extends StatelessWidget {
  const _Td(this.text, this.bold, this.color);
  final String text;
  final bool bold;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: bold ? color : AppColors.textMain,
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSub,
          ),
        ),
      ],
    );
  }
}
