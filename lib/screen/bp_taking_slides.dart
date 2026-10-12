// ─────────────────────────────────────────────────────────────────────────────
//  bp_taking_slides.dart
//  The hand-built slides of the BP Taking form: the reading, and the printed
//  form it is checked against.
//
//  WHY THIS IS NOT A LIST OF BOXES
//  Everything a plain field grid cannot do is on this form: two numbers that are
//  one measurement and share a box, a verdict that changes as the nurse types, a
//  reading that can be taken up to three times and averaged, a guide that
//  explains the numbers, and a sheet that prints the whole visit back. Each of
//  those is UI, not data, so it belongs here. The detail behind the reading —
//  position, arm, the action taken — is a plain list of boxes and is declared in
//  `visit_service_forms.dart` instead.
//
//  WHAT IT DOES NOT DO
//  It does not decide anything. Every number it shows is asked of
//  `vitals_interpretation.dart` and every bound it enforces of `BpLimits`, so
//  the form and the rest of the app cannot disagree about what 150/95 means.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/core/visit_details.dart';
import 'package:clinicmanagementsystem/core/visit_service_forms.dart';
import 'package:clinicmanagementsystem/core/vitals_interpretation.dart';
import 'package:clinicmanagementsystem/screen/app_colors.dart';

import 'bp_form_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The colour a category is shown in, everywhere on this form.
///
/// Lives here rather than on [BpSeverity] because that enum is deliberately free
/// of Flutter: it is the clinic's rulebook, and the rulebook should not know
/// what colour a widget is.
// ── THE BODY: EVERYTHING, IN ONE CARD ────────────────────────────────────────

/// Blood pressure as one box with two numbers in it, the pulse beside it, and
/// the verdict underneath.
class BpReadingSlide extends StatefulWidget {
  const BpReadingSlide({
    super.key,
    required this.controller,
    required this.draft,
    required this.onOpenGuide,
  });

  final VisitDetailsController controller;
  final ServiceDraft draft;

  /// Opens the BP guide over the form.
  final VoidCallback onOpenGuide;

  @override
  State<BpReadingSlide> createState() => _BpReadingSlideState();
}

class _BpReadingSlideState extends State<BpReadingSlide> {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _notes = TextEditingController();
  final _sysFocus = FocusNode();
  final _diaFocus = FocusNode();
  final _pulseFocus = FocusNode();
  final _notesFocus = FocusNode();

  /// Which repeat reading the nurse is on, 0 for the first.
  int _reading = 0;

  /// How many readings were recorded last time this widget looked, so it can
  /// tell "the nurse deleted that reading" from "the nurse has not finished
  /// typing it yet" — the only difference between emptying a box and wiping it.
  int _seenReadings = 0;

  /// The numbers as last typed, so [didChangeDependencies] can push loaded
  /// values into the boxes without fighting the nurse for the caret.
  String _lastSys = '';
  String _lastDia = '';
  String _lastPulse = '';

  /// The last pulse value that was actually ACCEPTED and mirrored to the visit,
  /// so a refused one can be told apart from an outside change.
  String _mirroredPulse = '';

  /// The note as last typed, for the same reason as the boxes above.
  String _lastNotes = '';

  @override
  void initState() {
    super.initState();
    // A resumed visit opens on its first reading, so the nurse amends rather
    // than retypes it.
    final first = _readings.isEmpty ? null : _readings.first;
    _sys.text = first == null ? '' : '${first.systolic}';
    _dia.text = first == null ? '' : '${first.diastolic}';
    _pulse.text = widget.draft.text('pulse_bpm');
    _notes.text = widget.draft.text('notes');
    _lastSys = _sys.text;
    _lastDia = _dia.text;
    _lastPulse = _pulse.text;
    _mirroredPulse = _pulse.text;
    _lastNotes = _notes.text;
    _seenReadings = _readings.length;
    // The first box takes the caret as soon as the slide settles, because a
    // nurse taking a reading wants to type it and not go looking for the box.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sysFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant BpReadingSlide old) {
    super.didUpdateWidget(old);
    // The boxes take their numbers from the recorded readings, NOT from the
    // visit's `systolic`/`diastolic` columns. Those columns are this widget's
    // OUTPUT — it writes the average into them — so reading them back would mean
    // clearing a half-typed "150" the moment the last reading was removed, and
    // showing the average in a box the nurse never typed.
    final readings = _readings;
    // The list changes length only from OUTSIDE this widget: _write feeds the
    // boxes and the list at the same time, so a rebuild during typing sees a
    // list that still matches the boxes. That is what makes "amend the stored
    // reading" work — the partial "15" the nurse has typed is nowhere in the
    // list, and nothing here may go looking for it and put the stored "150"
    // back over it.
    //
    // The old version adopted the stored value whenever `_lastSys` disagreed,
    // which it always does the moment the nurse types a digit the stored
    // reading does not yet contain: an amended reading that was only half typed
    // (so the list was untouched) snapped back to the stored number on the very
    // next rebuild, and a reading could not be retyped at all. Only a genuine
    // length change is adopted now — a reading was recorded, removed or added
    // from outside the box.
    if (readings.length != _seenReadings) {
      if (_reading < readings.length) {
        final stored = readings[_reading];
        _lastSys = '${stored.systolic}';
        _lastDia = '${stored.diastolic}';
        _sys.text = _lastSys;
        _dia.text = _lastDia;
      } else {
        // The reading being amended WAS recorded and is now gone — a Clear, or
        // an undo — so its box empties too. Not merely "nothing recorded yet":
        // a half-typed reading is nothing recorded yet, and clearing on that
        // would wipe the "150" out of the box the nurse is still typing into.
        _lastSys = '';
        _lastDia = '';
        if (_sys.text.isNotEmpty) _sys.clear();
        if (_dia.text.isNotEmpty) _dia.clear();
      }
    }
    _seenReadings = readings.length;
    final livePulse = widget.draft.text('pulse_bpm');
    // Adopt unless the draft is simply empty BECAUSE the last thing typed was
    // refused — that is this widget's own doing, not an outside change, and
    // taking it as one would wipe "400" out of the box mid-keystroke. A real
    // Clear leaves the draft empty while the last mirror was a good value, so
    // it still empties the box.
    if (livePulse != _lastPulse && livePulse != _mirroredPulse) {
      _lastPulse = livePulse;
      _pulse.text = livePulse;
    }
    final liveNotes = widget.draft.text('notes');
    if (liveNotes != _lastNotes) {
      _lastNotes = liveNotes;
      _notes.text = liveNotes;
    }
  }

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    _pulse.dispose();
    _notes.dispose();
    _sysFocus.dispose();
    _diaFocus.dispose();
    _pulseFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  /// Every reading recorded so far, in order.
  List<BpReading> get _readings {
    final raw = widget.draft.data['bp_readings'];
    if (raw is! List) return [];
    return [
      for (final r in raw)
        if (BpReading.fromJson(r) case final b?) b
    ];
  }

  /// The verdict the nurse is shown.
  ///
  /// Once there is more than one reading this is the AVERAGE, because that is
  /// the number the visit carries and the number every other service will read.
  /// Basing the verdict on whichever box is being typed would let a nurse type
  /// 180/70 and be told "Severely High" while the visit is quietly recorded as
  /// an average that is only Stage 2.
  ///
  /// While the boxes hold something the form has refused, or only half a
  /// measurement, it falls back to the reading actually recorded — so a nurse who
  /// overtypes 150 into 400 is not shown a verdict for 150 while an error sits
  /// under the box, and is shown nothing at all if there is nothing recorded.
  BpResult? get _result {
    final stored = _readings;
    final average = stored.isEmpty ? null : bpAverage(stored);
    if (average != null && stored.length > 1) {
      return interpretBpReading(average);
    }
    return interpretBP(_sys.text, _dia.text) ?? interpretBpReading(average);
  }

  /// The pulse as a number, or null while it is still being typed.
  int? get _pulseNumber => int.tryParse(_pulse.text.trim());

  void _write({String? sys, String? dia}) {
    final s = sys ?? _sys.text;
    final d = dia ?? _dia.text;
    _lastSys = s;
    _lastDia = d;
    // The numbers on screen are this reading. They are only a reading when BOTH
    // halves are there and inside the limits a cuff can produce — one number on
    // its own is half a measurement, and a reading the form has already refused
    // is not a reading either.
    final typed = interpretBP(s, d);

    // The readings recorded so far, with this one either amending the slot the
    // nurse is on or adding a new slot. Amending in place matters: going back to
    // correct reading 1 must correct reading 1, not overwrite reading 2.
    final readings = _readings;
    final next = <Map<String, dynamic>>[
      for (final r in readings) r.toJson(),
    ];
    if (typed != null) {
      final amend =
          BpReading(systolic: typed.systolic, diastolic: typed.diastolic);
      if (_reading < next.length) {
        next[_reading] = amend.toJson();
      } else {
        next.add(amend.toJson());
      }
    }
    _persist(next);
  }

  /// Writes a whole reading list — and everything derived from it — to the draft.
  ///
  /// One place, so that a list written by [ _write ] and a list shortened by a
  /// remove are stored the same way. Splitting it previously left removes
  /// updating the vitals strip but not the average or the result record, and
  /// rebuilding the list from the draft rather than from the one being written,
  /// so the reading a nurse had just deleted came straight back.
  void _persist(List<Map<String, dynamic>> next) {
    widget.controller.setField(widget.draft.serviceId, 'bp_readings', next);

    // The visit's own vitals take the AVERAGE once there is more than one
    // reading, so a Prenatal box reading this visit shows the number the result
    // card is showing rather than whichever one was typed last.
    //
    // Null when there is nothing to record. Writing a zero here instead would
    // put a blood pressure of 0/0 on the record, and — because the boxes read
    // their own values back from the draft — would then overwrite the half-typed
    // "150" the nurse is still in the middle of entering.
    final average = bpAverage([for (final r in next) BpReading.fromJson(r)!]);
    widget.controller.setVitalRaw(VitalField.systolic, average?.systolic,
        fromServiceId: widget.draft.serviceId);
    widget.controller.setVitalRaw(VitalField.diastolic, average?.diastolic,
        fromServiceId: widget.draft.serviceId);
    widget.controller
        .setField(widget.draft.serviceId, 'bp_average', average?.toJson());

    // What the nurse was SHOWN is recorded, not recalculated on read. A clinic
    // that retunes a band next month must not silently rewrite the verdict
    // printed on the day — same reasoning as the band beside each vital.
    // [setField] above has already updated the draft, so [setState] below
    // rebuilds with these in place.
    final verdict = _result;
    widget.controller
        .setField(widget.draft.serviceId, 'bp_standard', verdict?.standard.id);
    // The version the numbers came from, so a record can still be read against
    // the ladder that produced it after the guideline is reissued.
    widget.controller.setField(
        widget.draft.serviceId, 'bp_thresholds_version', verdict?.version);
    widget.controller.setField(
        widget.draft.serviceId,
        'bp_result',
        verdict == null
            ? null
            : {
                'label': verdict.label,
                'severity': verdict.severity.name,
                'standard': verdict.standard.id,
                'thresholds_version': verdict.version,
                'systolic_band': verdict.systolicSeverity.name,
                'diastolic_band': verdict.diastolicSeverity.name,
                'based_on': verdict.basedOn,
              });
    setState(() {});
  }

  void _writePulse(String v) {
    _lastPulse = v;
    // The vitals strip is shared with every other service and with the visit
    // row, so a number this form has just refused under the box must not reach
    // it — otherwise the box says "between 20 and 250" while the strip shows a
    // pulse of 400. Mirrored as null so a corrected reading replaces it rather
    // than leaving the bad one behind.
    final n = _pulseNumber;
    final accepted = BpLimits.pulse.accepts(n);
    if (accepted) _mirroredPulse = '$n';
    if (accepted) {
      // The form's own field, under the name the clinic uses for it…
      widget.controller.setField(widget.draft.serviceId, 'pulse_bpm', n);
    } else {
      widget.controller.setField(widget.draft.serviceId, 'pulse_bpm', null);
    }
    // …and the shared visit vital every other service reads. Both, or a Medical
    // Certificate filled in afterwards would ask for a pulse the nurse already
    // took.
    widget.controller.setVitalRaw(VitalField.heartRate, accepted ? n : null,
        fromServiceId: widget.draft.serviceId);
    setState(() {});
  }

  /// Keeps the box to whole numbers. A cuff does not read 118.4, and letting a
  /// decimal through would put a reading on the record that no device produced.
  static String _digitsOnly(String raw, int max) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= max ? digits : digits.substring(0, max);
  }

  /// Catches `/` and Enter and hands the nurse the next box.
  ///
  /// `/` is the key a nurse reaches for between the two numbers of a blood
  /// pressure, and Enter is the one they press at the end of every box. Neither
  /// is a character the field can accept, so both are intercepted one level up
  /// and turned into a caret move. The fields are walked in the order they are
  /// read: systolic, diastolic, pulse, notes.
  KeyEventResult _onBpKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final slash =
        event.logicalKey == LogicalKeyboardKey.slash || event.character == '/';
    final enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!slash && !enter) return KeyEventResult.ignored;

    if (node == _sysFocus) {
      _diaFocus.requestFocus();
    } else if (node == _diaFocus) {
      _pulseFocus.requestFocus();
    } else if (node == _pulseFocus) {
      // The last box before the note. Only moves on when the pulse is a pulse —
      // Enter on a half-typed 4 should leave the caret where it is, so 48 can
      // still be typed.
      if (BpLimits.pulse.accepts(_pulseNumber)) {
        _notesFocus.requestFocus();
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  void _onSysChanged(String raw) {
    final v = _digitsOnly(raw, 3);
    if (v != _sys.text) {
      _sys.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    _write(sys: v);
    // Three digits is a real systolic — nobody types a fourth — so the caret
    // moves on by itself and the nurse can keep both hands on the keyboard.
    if (v.length == 3) _diaFocus.requestFocus();
  }

  void _onDiaChanged(String raw) {
    final v = _digitsOnly(raw, 3);
    if (v != _dia.text) {
      _dia.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    _write(dia: v);
    if (v.length == 3) _pulseFocus.requestFocus();
  }

  void _onPulseChanged(String raw) {
    final v = _digitsOnly(raw, 3);
    if (v != _pulse.text) {
      _pulse.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    _writePulse(v);
  }

  /// `/` between the numbers and Enter to move on are the two keys a nurse
  /// actually reaches for, and neither of them should need the mouse.
  void _addRepeatReading() {
    if (_readings.length >= kMaxBpReadings) return;
    setState(() {
      _reading = _readings.length;
      // A repeat reading starts blank, and the boxes have to agree that it does:
      // leaving the last reading's numbers in them would pen the new entry over
      // a value that is already saved. Cleared here AND sent to the stored list,
      // so a rebuild cannot repopulate the box from the reading being replaced.
      _lastSys = '';
      _lastDia = '';
      if (_sys.text.isNotEmpty) _sys.clear();
      if (_dia.text.isNotEmpty) _dia.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sysFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final readings = _readings;
    final canAddRepeat = readings.length < kMaxBpReadings;

    return Column(
      key: const ValueKey('bp/body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _guideRow(),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _bpBox(),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _pulseBox(),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (BpLimits.differenceWarning(_int(_sys.text), _int(_dia.text)) !=
            null)
          _softWarning(BpLimits.unusualDifferenceWarning)
        else if (BpLimits.systolicOk(_int(_sys.text)) &&
            BpLimits.diastolicOk(_int(_dia.text)) &&
            _int(_sys.text)! <= _int(_dia.text)!)
          _softWarning(BpLimits.systolicMustBeHigher, danger: true),
        const SizedBox(height: 4),
        if (result?.severity.urgentBanner != null) ...[
          _urgentBanner(result!.severity.urgentBanner!),
          const SizedBox(height: 4),
        ],
        if (canAddRepeat || readings.length > 1) ...[
          const SizedBox(height: 4),
          _repeatRow(readings, canAddRepeat),
        ],
        const SizedBox(height: 6),
        _notesBox(),
      ],
    );
  }

  /// The red band above the result card when a reading is severely high.
  ///
  /// Above, not inside: a banner that scrolls away with the card it belongs to is
  /// a banner a nurse reads once and then loses, and this is the one line on the
  /// form that means "stop and refer".
  Widget _urgentBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFECACA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF991B1B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emergency_outlined,
              size: 15, color: Color(0xFF991B1B)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Notes / Remarks", a counter, and the button that offers the nurse the
  /// sentence the form has already written for them.
  ///
  /// Three lines, because a note on a blood pressure is usually one sentence and
  /// a box tall enough to hide one behind a scrollbar is a box nobody reads.
  Widget _notesBox() {
    final text = _notes.text;
    final suggestion = _suggestedNote();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Notes / Remarks',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
            const Spacer(),
            // On the label row, not on a row of its own. The button only exists
            // once there is a reading to describe, and giving it its own line
            // meant the form was thirty pixels taller exactly when a nurse had
            // finished typing — which is when the notes box most needs to be
            // visible.
            if (suggestion != null)
              TextButton.icon(
                key: const ValueKey('bp/insert_suggestion'),
                onPressed: _insertSuggestion,
                icon: const Icon(Icons.auto_awesome_outlined, size: 12),
                label: const Text('Insert suggested note',
                    style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 18),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Text(
              '${text.length}/$kBpNotesMaxChars',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('bp/notes'),
          controller: _notes,
          focusNode: _notesFocus,
          maxLines: 3,
          minLines: 2,
          maxLength: kBpNotesMaxChars,
          onChanged: (v) {
            _lastNotes = v;
            widget.controller.setField(widget.draft.serviceId, 'notes', v);
            setState(() {});
          },
          onSubmitted: (_) => _notesFocus.unfocus(),
          style: const TextStyle(fontSize: 12, height: 1.25),
          decoration: bpInputDecoration(
            hint: 'Any comment about this reading',
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// The sentence the clinic's own template would put in the note, or null when
  /// there is not yet a reading to describe.
  String? _suggestedNote() {
    final pulse = _pulseNumber;
    if (!BpLimits.pulseOk(pulse)) return null;
    // No arm, no position, no "rested 5 minutes". The suggestion is written from
    // what the nurse actually typed and nothing else — the same rule the
    // validation follows. A note that claimed the visitor had rested for five
    // minutes, on a form with no field saying so, would be a fabricated finding
    // on the record, and the nurse who reads it back has no way to tell which
    // half of the sentence came from the cuff and which half came from us.
    final note = bpSuggestedNote(bp: _result, pulseBpm: pulse);
    return note.isEmpty ? null : note;
  }

  /// Puts the suggested note in without ever destroying what the nurse wrote.
  ///
  /// Empty box: the sentence goes in. Non-empty: it goes on a new line under
  /// what is already there. It is never replaced, because a note is the nurse's
  /// own words about their own reading and a button that overwrites them is a
  /// button that loses them.
  void _insertSuggestion() {
    final suggestion = _suggestedNote();
    if (suggestion == null) return;
    final existing = _notes.text.trim();
    final next = existing.isEmpty ? suggestion : '$existing\n$suggestion';
    if (next.length > kBpNotesMaxChars) return;
    _notes.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _lastNotes = next;
    widget.controller.setField(widget.draft.serviceId, 'notes', next);
    setState(() {});
  }

  int? _int(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  Widget _guideRow() {
    return Row(
      children: [
        const Icon(Icons.bar_chart_rounded,
            size: 15, color: AppColors.textMain),
        const SizedBox(width: 6),
        const Text(
          'Vital Signs',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const Spacer(),
        bpInfoDot(
          kBpGuideHowToRead,
          () => widget.onOpenGuide(),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: widget.onOpenGuide,
          icon: const Icon(Icons.info_outline_rounded, size: 14),
          label: const Text('BP Guide', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            // 22, not 26. This row is a section heading, so its height is set by
            // the button on the right of it — and the heading has to share a
            // ~330px column with a live result, three readings and a note.
            minimumSize: const Size(0, 18),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  /// The two numbers in one box, because they are one measurement. Typing the
  /// top one and pressing `/` puts the caret in the bottom one.
  ///
  /// The two [Focus] wrappers are what catch the `/`: the fields have no way to
  /// accept a character they have no field for, so the key is intercepted one
  /// level up and turned into a caret move.
  Widget _bpBox() {
    final sysError = _error(BpLimits.systolic, _sys.text);
    final diaError = _error(BpLimits.diastolic, _dia.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel(
          'Blood Pressure (mmHg)',
          kVitalFieldHelp['pulse_bpm'] ?? kBpGuideHowToRead,
          required: true,
        ),
        const SizedBox(height: 4),
        // Side by side, not stacked. They are one measurement but they are two
        // numbers, and stacking them cost this form fifty-two pixels it does not
        // have at 1366x768 — which is the difference between the notes box
        // being on screen and being below the fold. The `/` between them is the
        // character a nurse writes between the two numbers anyway.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (_, event) => _onBpKey(_sysFocus, event),
                child: bpNumberInput(
                  key: const ValueKey('bp/systolic'),
                  controller: _sys,
                  focusNode: _sysFocus,
                  onChanged: _onSysChanged,
                  onSubmitted: (_) => _diaFocus.requestFocus(),
                  hint: 'Systolic — e.g. 120',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: (_, event) => _onBpKey(_diaFocus, event),
                child: bpNumberInput(
                  key: const ValueKey('bp/diastolic'),
                  controller: _dia,
                  focusNode: _diaFocus,
                  onChanged: _onDiaChanged,
                  onSubmitted: (_) => _pulseFocus.requestFocus(),
                  hint: 'Diastolic — e.g. 80',
                ),
              ),
            ),
          ],
        ),
        // The unit is already in the label above, and "upper number / lower
        // number" is help text for a first-time user rather than something to
        // print under the boxes forever. So this line appears only when there is
        // something wrong to say — and when there is, the form needs the room
        // more than the hint does.
        if (sysError != null || diaError != null)
          Text(
            sysError ?? diaError!,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.25,
              color: AppColors.danger,
            ),
          ),
      ],
    );
  }

  /// A field's name, its "required" mark, and the ⓘ that explains what it is.
  Widget _fieldLabel(String label, String help, {bool required = false}) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
        ],
        const SizedBox(width: 3),
        bpInfoDot(help, () => widget.onOpenGuide()),
      ],
    );
  }

  Widget _pulseBox() {
    final pulse = _pulseNumber;
    final verdict = interpretPulse(pulse);
    final error = _error(BpLimits.pulse, _pulse.text);
    final colors =
        verdict?.severity == null ? null : bpSeverityColors(verdict!.severity!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel('Pulse Rate (beats per minute)', kVitalFieldHelp['pulse']!,
            required: true),
        const SizedBox(height: 4),
        Focus(
          onKeyEvent: (_, event) => _onBpKey(_pulseFocus, event),
          child: Stack(
            children: [
              bpNumberInput(
                key: const ValueKey('bp/pulse'),
                controller: _pulse,
                focusNode: _pulseFocus,
                action: TextInputAction.next,
                onChanged: _onPulseChanged,
                hint: 'e.g. 80',
              ),
              if (verdict != null)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors!.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        verdict.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.fg,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // As with the blood pressure boxes: the unit is in the label, so the
        // line under the box is for a mistake and nothing else.
        if (error != null)
          Text(
            error,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.danger,
            ),
          ),
      ],
    );
  }

  String? _error(VitalLimit limit, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || !limit.accepts(n)) return limit.errorText;
    return null;
  }

  /// One recorded reading, and tappable.
  ///
  /// A nurse who mis-reads one of three readings should be able to fix that
  /// reading, not clear the whole form and start again — the cuff was on the
  /// visitor, and the other two readings are still good. Tapping the chip takes
  /// them back to it, marked so it is obvious which one they are amending.
  Widget _readingChip(BpReading r, int index) {
    final active = index == _reading;
    final colors = bpSeverityColors(interpretBpReading(r)!.severity);
    return Material(
      color: active ? colors.bg : AppColors.bgAlt,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey('bp/reading_$index'),
            onTap: () => _amendReading(index),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(6),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(6),
                ),
                border: Border.all(
                  color: active ? colors.fg : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Text(
                r.compact,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? colors.fg : AppColors.textMain,
                ),
              ),
            ),
          ),
          // Its own tap target, so "throw this reading away" is not something
          // a nurse has to aim at with a fingertip the size of the reading.
          InkWell(
            key: ValueKey('bp/remove_$index'),
            onTap: () => _removeReading(index),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(6),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(6),
                ),
                border: Border.all(
                  color: active ? colors.fg : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 11,
                color: active ? colors.fg : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens an earlier reading for correction, keeping the ones after it.
  ///
  /// The stored reading is loaded into the boxes first, so the nurse amends
  /// what the chip says rather than overtyping whatever the last slot held.
  void _amendReading(int index) {
    setState(() {
      _reading = index;
      final stored = _readings;
      if (index < stored.length) {
        _lastSys = '${stored[index].systolic}';
        _lastDia = '${stored[index].diastolic}';
        if (_sys.text != _lastSys) _sys.text = _lastSys;
        if (_dia.text != _lastDia) _dia.text = _lastDia;
      } else {
        _lastSys = '';
        _lastDia = '';
        if (_sys.text.isNotEmpty) _sys.clear();
        if (_dia.text.isNotEmpty) _dia.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sysFocus.requestFocus();
    });
  }

  Widget _softWarning(String text, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            danger ? Icons.error_outline : Icons.info_outline,
            size: 13,
            color: danger ? AppColors.danger : AppColors.warning,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                color: danger ? AppColors.danger : const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Repeat readings. Three is the cap: past that the average stops meaning
  /// "the reading" and starts meaning "everything the nurse did that morning".
  /// The recorded readings, the average once there are two, and the button that
  /// starts another one.
  ///
  /// The average is here, beside the readings it was computed from, rather than
  /// buried in the result card: a nurse who has taken three readings is looking
  /// for "what do I write down", and the answer is the middle one.
  Widget _repeatRow(List<BpReading> readings, bool canAdd) {
    final average = bpAverageLabel(readings);
    return Row(
      children: [
        for (var i = 0; i < readings.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _readingChip(readings[i], i),
          ),
        if (average != null) ...[
          const SizedBox(width: 2),
          Text(
            average,
            key: const ValueKey('bp/average'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSub,
            ),
          ),
        ],
        const Spacer(),
        if (canAdd)
          TextButton.icon(
            key: const ValueKey('bp/add_repeat'),
            onPressed: _addRepeatReading,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add repeat reading',
                style: TextStyle(fontSize: 11.5)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  /// Takes a reading back off the list.
  ///
  /// Three readings is the cap, not a quota, and a nurse who took three by
  /// mistake and only trusts two has to be able to say so. Removing the reading
  /// currently open closes the form and starts a fresh entry, because the boxes
  /// still hold that reading and leaving them would let it be saved twice.
  void _removeReading(int index) {
    final next = [..._readings]..removeAt(index);
    if (next.isEmpty) {
      setState(() => _reading = 0);
      _sys.clear();
      _dia.clear();
      _syncReadings(next);
      return;
    }
    // Removing a reading EARLIER than the open one leaves the caret where it is;
    // removing the open one, or a later one, leaves it on the last reading — never
    // past the end, which would silently mean "start a new reading".
    if (index < _reading) {
      setState(() => _reading -= 1);
    } else if (index == _reading) {
      setState(() => _reading = next.length - 1);
      final focus = next.last;
      _sys.text = '${focus.systolic}';
      _dia.text = '${focus.diastolic}';
    }
    _syncReadings(next);
  }

  /// Writes a shorter reading list back, without disturbing the boxes.
  ///
  /// A remove is a change to the RECORD, not to what is in the boxes: a nurse who
  /// deletes a mis-keyed reading is looking at it still on screen until they type
  /// the next one, and clearing the boxes out from under them would throw away a
  /// reading they were about to correct. The list being written is the one handed
  /// in — rebuilt from the draft it would put the deleted reading straight back.
  void _syncReadings(List<BpReading> next) {
    _persist([for (final r in next) r.toJson()]);
  }
}

// ── THE PRINTED FORM ─────────────────────────────────────────────────────────

/// The BP Taking Form: the whole reading on one sheet, laid out the way the paper
/// form prints it, with the boxes the nurse filled in and the lines the system
/// filled in for them on the same page.
///
/// Read-only, and reached only once the reading exists. It is what the nurse
/// checks before pressing Done, so a form that could still be typed into would be
/// a second place for the two numbers to disagree — and Done would be saving one
/// version while the sheet on screen showed another.
class BpFormSlide extends StatelessWidget {
  const BpFormSlide({
    super.key,
    required this.draft,
    required this.assessment,
    required this.visitorName,
    required this.visitorId,
    required this.recordedDate,
    required this.recordedTime,
    required this.recordedBy,
    this.serviceLabel = 'BP Taking',
  });

  final ServiceDraft draft;

  /// The reading and its verdict, worked out by `vitals_interpretation.dart` and
  /// passed in rather than recomputed, so the sheet and the result card the nurse
  /// just came from cannot print different verdicts.
  final BpResult? assessment;

  final String visitorName;
  final String visitorId;
  final String recordedDate;
  final String recordedTime;
  final String recordedBy;
  final String serviceLabel;

  @override
  Widget build(BuildContext context) {
    final result = assessment;
    final colors = result == null ? null : bpSeverityColors(result.severity);
    final actions = _ticked('action_taken');

    return Column(
      key: const ValueKey('bp/form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(),
        const SizedBox(height: 10),
        _section('Individual', [
          _row('Name', visitorName),
          _row('ID Number', visitorId),
        ]),
        const SizedBox(height: 8),
        _section('Blood Pressure', [
          _row('Systolic', result == null ? '—' : '${result.systolic} mmHg'),
          _row('Diastolic', result == null ? '—' : '${result.diastolic} mmHg'),
          _row('Pulse Rate', _withUnit(_text('pulse_bpm'), 'bpm')),
        ]),
        const SizedBox(height: 8),
        _section('Measurement Details', [
          _row('Position', _text('position')),
          _row('Arm Used', _text('arm_used')),
          _row('Date', recordedDate),
          _row('Time', recordedTime),
          _row('Recorded By', recordedBy),
          _row('Service', serviceLabel),
        ]),
        const SizedBox(height: 8),
        // The assessment is printed, not chosen. It is the only section with no
        // input on it anywhere in the form, and the note under it says so — a
        // sheet that let someone tick a different verdict would put a second,
        // manual assessment on a record that already has an automatic one.
        _section('Assessment', [
          if (result == null)
            _prose('No reading recorded yet.')
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: bpVerdictPill(result.label, fg: colors!.fg, bg: colors.bg),
            ),
            const SizedBox(height: 7),
            Text(result.means,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSub, height: 1.35)),
            const SizedBox(height: 4),
            Text(result.basedOn,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted, height: 1.3)),
            const SizedBox(height: 4),
            Text(result.action,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMain, height: 1.35)),
            const SizedBox(height: 6),
            const Text(
              'Worked out from the reading above. Not selected by staff. '
              'For clinic reference only — a screening aid, not a diagnosis.',
              style: TextStyle(
                  fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        _section('Action Provided', [
          if (actions.isEmpty)
            _prose('None recorded.')
          else
            for (final a in actions) _prose('•  $a'),
          if (_text('action_other').isNotEmpty)
            _prose('•  Other: ${_text('action_other')}'),
        ]),
        const SizedBox(height: 8),
        _section('Remarks / Notes', [
          _prose(_text('notes').isEmpty ? 'None.' : _text('notes')),
        ]),
      ],
    );
  }

  Widget _title() {
    return Row(
      children: [
        const Icon(Icons.description_outlined,
            size: 17, color: AppColors.textMain),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'BP Taking Form',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
        ),
        const Text(
          'Generated from this visit',
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// One titled block of the sheet. The same [bpPanel] the reading slide is built
  /// from, so the sheet and the boxes it summarises are visibly the same kind of
  /// thing.
  Widget _section(String heading, List<Widget> lines) {
    return bpPanel(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          ...lines,
        ],
      ),
    );
  }

  /// A label on the left, its value on the right, on one line — the layout of a
  /// printed form, where the two are read across rather than down.
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A line of prose rather than a labelled value — the assessment wording, a
  /// note, a list of actions.
  Widget _prose(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textMain, height: 1.35),
        ),
      );

  String _text(String key) => draft.text(key).trim();

  /// The ticked options of a check-box field, in the order the form declared them
  /// rather than the order they were tapped, so two nurses filling the same form
  /// in produce the same saved row.
  List<String> _ticked(String key) {
    final raw = draft.data[key];
    if (raw is! List) return const [];
    final picked = {for (final v in raw) '$v'};
    final spec = draft.spec;
    for (final slide in spec.slides) {
      for (final f in slide.fields) {
        if (f.key == key) {
          return [
            for (final o in f.options)
              if (picked.contains(o)) o
          ];
        }
      }
    }
    return [];
  }

  String _withUnit(String value, String unit) =>
      value.isEmpty ? '—' : '$value $unit';
}
