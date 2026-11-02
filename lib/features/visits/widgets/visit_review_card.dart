import 'package:flutter/material.dart';

import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_summary.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

class VisitReviewLine {
  const VisitReviewLine.pair(this.label, this.value) : heading = null;
  const VisitReviewLine.heading(this.heading)
      : label = '',
        value = '';
  const VisitReviewLine.plain(this.value)
      : heading = null,
        label = '';

  final String? heading;

  final String label;
  final String value;
}

class VisitReviewRow extends StatelessWidget {
  const VisitReviewRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? '—' : value;
    const labelStyle = TextStyle(fontSize: 12.5, color: AppColors.textSub);
    const valueStyle = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textMain,
        height: 1.3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label:', style: labelStyle),
              const SizedBox(height: 2),
              Text(shown, style: valueStyle),
            ],
          );
        }
        final labelWidth = (c.maxWidth * 0.34).clamp(120.0, 230.0).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text('$label:', style: labelStyle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(shown, style: valueStyle, softWrap: true),
            ),
          ],
        );
      }),
    );
  }
}

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

class VisitReviewCard extends StatelessWidget {
  const VisitReviewCard({
    super.key,
    required this.title,
    required this.lines,
    this.trailing,
  });

  final String title;
  final List<VisitReviewLine> lines;

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

List<VisitReviewLine> visitReviewLines(ServiceDraft draft, VisitVitals vitals,
    {bool canSeeRestricted = true}) {
  final sections =
      serviceSummary(draft, vitals, canSeeRestricted: canSeeRestricted);
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

List<VisitReviewLine> visitReviewAnswerLines(
    ServiceDraft draft, VisitVitals vitals,
    {bool canSeeRestricted = true}) {
  final sections =
      serviceSummary(draft, vitals, canSeeRestricted: canSeeRestricted);
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
