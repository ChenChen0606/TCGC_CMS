// ─────────────────────────────────────────────────────────────────────────────
//  bp_form_kit.dart
//  The shared pieces the BP Taking form is built from.
//
//  They live in their own file because the form and the guide are two files'
//  worth of UI and a private helper in one of them is invisible to the other.
//  The alternative — one enormous file — is worse: it is what made this form's
//  renderer hard to navigate before it was split at all.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/core/vitals_bands.dart';
import 'package:clinicmanagementsystem/core/vitals_interpretation.dart';
import 'package:clinicmanagementsystem/screen/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The colours a blood pressure CATEGORY is shown in, taken from the severity
/// rather than from the shared band.
///
/// Six categories need six colours, and the shared [VitalBand] only has four —
/// which is why "High-Normal" and "Grade 1" used to be drawn the same amber, and
/// why "Grade 2" was the same red as "Severely High". On a result card whose
/// whole job is "how bad is this, at a glance", those two pairs cannot look the
/// same. Keyed on the severity, which is what the clinic's rule actually
/// produces, so the card, the guide's highlighted row and the pills cannot drift.
({Color fg, Color bg}) bpSeverityColors(BpSeverity severity) =>
    switch (severity) {
      BpSeverity.low => (
          fg: const Color(0xFF1D4ED8),
          bg: const Color(0xFFDBEAFE)
        ),
      BpSeverity.normal => (
          fg: AppColors.success,
          bg: AppColors.successContainer
        ),
      BpSeverity.highNormal => (
          fg: const Color(0xFF92400E),
          bg: const Color(0xFFFEF3C7)
        ),
      BpSeverity.grade1 => (
          fg: const Color(0xFFC2410C),
          bg: const Color(0xFFFFEDD5)
        ),
      BpSeverity.grade2 => (
          fg: const Color(0xFF9A3412),
          bg: const Color(0xFFFED7AA)
        ),
      BpSeverity.severe => (
          fg: const Color(0xFF991B1B),
          bg: const Color(0xFFFECACA)
        ),
    };

/// The colours of a plain [VitalBand] — the five states every other rate on the
/// visit uses, as opposed to the six blood-pressure severities above.
///
/// Here, next to [bpSeverityColors], because these two used to be written out
/// again in each file that needed them, and a band that is amber on the BP form
/// and yellow on the pulse pill is a band a nurse has to read.
({Color fg, Color bg}) bpVitalBandColors(VitalBand band) => switch (band) {
      VitalBand.low => (
          fg: const Color(0xFF1D4ED8),
          bg: const Color(0xFFDBEAFE)
        ),
      VitalBand.normal => (
          fg: AppColors.success,
          bg: AppColors.successContainer
        ),
      VitalBand.watch => (fg: AppColors.warning, bg: const Color(0xFFFEF3C7)),
      VitalBand.high => (fg: AppColors.danger, bg: AppColors.dangerContainer),
      VitalBand.critical => (
          fg: const Color(0xFF991B1B),
          bg: const Color(0xFFFECACA)
        ),
    };

/// A rounded white box with a hairline border — the one container the whole
/// form is built from, so a reading and a note are visibly the same kind of
/// thing.
Widget bpPanel(
    {required Widget child, Color? tint, EdgeInsets? padding, Key? key}) {
  return Container(
    key: key,
    width: double.infinity,
    padding: padding ?? const EdgeInsets.fromLTRB(12, 7, 12, 7),
    decoration: BoxDecoration(
      color: tint ?? AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

/// The number box every reading on this form uses.
///
/// One implementation rather than a copy per slide, because the font, the fill
/// and the focus ring are what make the three boxes on slide 1 read as one
/// control. Three copies of an InputDecoration is three chances for them to
/// stop matching.
TextField bpNumberInput({
  Key? key,
  required TextEditingController controller,
  required FocusNode focusNode,
  required ValueChanged<String> onChanged,
  ValueChanged<String>? onSubmitted,
  TextInputAction action = TextInputAction.next,
  double fontSize = 17,
  String hint = '—',
}) {
  return TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    textInputAction: action,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: AppColors.textMain,
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      ),
      isDense: true,
      // 8, not 12. A blood pressure box on this form sits in a 330px column
      // alongside a live result and a note, and two of these share a row. The
      // number still reads at 17px; it just stops costing a line of its own.
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      filled: true,
      fillColor: AppColors.fieldFill,
      border: bpBorder(AppColors.border),
      enabledBorder: bpBorder(AppColors.border),
      focusedBorder: bpBorder(AppColors.primary, width: 1.6),
    ),
  );
}

/// The box every BP text field on the form wears, so the numbers and the note
/// are the same shape to the eye.
///
/// The counter is suppressed here rather than left on: a `maxLength` counter
/// drawn by Flutter sits in the padding BELOW the box, and this form already
/// prints its own `12/500` on the label row above the note. Two counters, one of
/// them hidden until the field is focused, is a form that disagrees with itself.
///
/// `maxLines` and `minLines` are set on the [TextField] itself, not here — they
/// are TextField properties, and a decoration that carried them would be a lie.
InputDecoration bpInputDecoration({
  String? hint,
  double fontSize = 12.5,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: fontSize,
      color: AppColors.textMuted,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    filled: true,
    fillColor: AppColors.fieldFill,
    border: bpBorder(AppColors.border),
    enabledBorder: bpBorder(AppColors.border),
    focusedBorder: bpBorder(AppColors.primary, width: 1.6),
    counterText: '',
  );
}

OutlineInputBorder bpBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// The ⓘ beside a field, which explains it in a sentence rather than making the
/// nurse leave the form to find out. Taps as well as hovers, because this is a
/// form people use with a finger.
Widget bpInfoDot(String help, [VoidCallback? onTap]) {
  return Tooltip(
    message: help,
    triggerMode: TooltipTriggerMode.tap,
    preferBelow: false,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.info_outline, size: 13, color: AppColors.textMuted),
      ),
    ),
  );
}

/// The amber dot on a symptom that means "now" rather than "noted".
///
/// It is a plain dot rather than a bolded word because the list is read at a
/// glance and a colour is faster than a font weight.
Widget bpWarningDot() {
  return Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.only(right: 5),
    decoration: const BoxDecoration(
      color: AppColors.warning,
      shape: BoxShape.circle,
    ),
  );
}

/// A small coloured label, used for every verdict pill on the form.
Widget bpVerdictPill(String label, {required Color fg, required Color bg}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

/// A red banner, for the sentences that mean act now.
Widget bpAlert(String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.dangerContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded,
            size: 15, color: Color(0xFF991B1B)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Color(0xFF991B1B),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A tappable chip. [selected] is the only thing that changes about it, so the
/// two states cannot disagree about their size.
Widget bpChoiceChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  Widget? leading,
}) {
  return Material(
    color: selected ? AppColors.primaryContainer : AppColors.surface,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) leading,
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primaryDeep : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
