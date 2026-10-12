import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../core/certificate_engine.dart';
import '../core/clinic_purposes.dart';
import '../core/patient_directory.dart';
import '../core/visit_details.dart';
import '../core/visit_service_forms.dart';
import '../core/visit_service_summary.dart';
import '../core/vitals.dart';
import '../core/vitals_interpretation.dart';
import '../services/account_service.dart';
import '../services/medicine_service.dart';
import '../services/visit_details_service.dart';
import 'app_colors.dart';
import 'bp_guide_overlay.dart';
import 'bp_taking_slides.dart';
import 'document_template.dart';

/// Step 3 of the visit wizard — "Service Details".
///
/// This file is the whole of the step's body: the strip of who is being seen,
/// the narrow list of the services ticked on step 2 with where each one has got
/// to, and the active service's form on the right, one slide at a time.
///
/// The rules are not here. What a form asks, which slide a field sits on, which
/// keys make a service Complete, and how a reading is banded all live in
/// `VisitServiceForms` and `VitalsInterpreter`, so that the description of a
/// form can be read in one place and tested without a widget. All this file
/// does is draw [VisitDetailsController]'s state and push what the nurse typed
/// back into it.

/// The wizard's own way on and off this step, handed to the form's footer so
/// both pairs of controls can share one bar.
///
/// The two used to be two bars: the slide arrows in a strip pinned to the bottom
/// of the form card, and the wizard's Back and Continue in a row underneath the
/// cards. Two bars for one step, each holding controls that move between slides
/// and controls that move between steps, with a card edge between them. The form
/// card's footer now carries all four, so there is one bar and one place the
/// eye has to find.
class StepThreeNav {
  const StepThreeNav({
    required this.onBack,
    required this.onContinue,
    required this.continueLabel,
    this.continueEnabled = true,
    this.saving = false,
  });

  /// Back to step 2. Always live: step 2 is where the services came from and it
  /// is never more than one step behind.
  final VoidCallback onBack;

  /// Save this service and move to the next one, or to the review. Null while
  /// the visit has no services to save, which is the same rule the wizard's own
  /// button used.
  final VoidCallback? onContinue;

  final String continueLabel;

  final bool continueEnabled;
  final bool saving;
}

class ClinicVisitStepThree extends StatefulWidget {
  const ClinicVisitStepThree({
    super.key,
    required this.controller,
    required this.visitor,
    required this.userName,
    this.nav,
    this.onServiceAdded,
    this.onServiceRemoved,
  });

  /// The step's state. Owned by the wizard screen so it survives the user
  /// walking back to step 1 and forward again, and so the wizard's Save &
  /// Continue button has the same controller to drive.
  final VisitDetailsController controller;

  final ClinicProfile visitor;
  final String userName;

  /// The wizard's Back and Continue, drawn by this step's own footer.
  ///
  /// Null when the step is used on its own, and then the footer carries the slide
  /// arrows alone.
  final StepThreeNav? nav;

  /// Told about a service added from this step's own Add New Service sheet.
  ///
  /// The service has to be added to the visit as well as to the drafts, because
  /// step 2's selection is the visit's list of services: the review step reads
  /// it, and the controller is rebuilt from it.
  final void Function(String serviceId)? onServiceAdded;

  /// Told about a service taken off the visit from this step.
  ///
  /// The mirror of [onServiceAdded], and for the same reason: step 2's selection
  /// *is* the visit's list of services, so dropping a draft here without
  /// dropping it there would leave a service the review step still counts and
  /// the controller would be rebuilt with.
  final void Function(String serviceId)? onServiceRemoved;

  @override
  State<ClinicVisitStepThree> createState() => _ClinicVisitStepThreeState();
}

class _ClinicVisitStepThreeState extends State<ClinicVisitStepThree> {
  /// One text controller per (service, field) that has been shown, keyed
  /// `"serviceId/fieldKey"`. Held rather than rebuilt on every frame because a
  /// controller created inside `build` throws away the caret position and the
  /// selection on each keystroke, and because rebuilding one while it has focus
  /// is what makes a field drop characters.
  final Map<String, TextEditingController> _texts = {};

  /// The key of the field whose "this is required" note is being shown, so the
  /// hint appears once rather than under every empty box.
  String? _naggedField;

  /// The inventory, loaded the first time the medicine picker is opened. Null
  /// means "not fetched yet", which the picker shows as a spinner; an empty
  /// list means "fetched, and there is nothing in stock".
  List<Medicine>? _medicines;
  bool _loadingMedicines = false;

  /// True between "the picker slide is being built" and "the load has actually
  /// started". The load is deferred to after the frame, so without this a slide
  /// that rebuilds in the meantime would queue a second one.
  bool _medicinesLoadQueued = false;

  /// The clinic's other accounts, for the "who did this" box on a service that
  /// records the person rather than the finding. Null means not fetched yet; an
  /// empty list means fetched and nothing to offer, which is not an error — RLS
  /// lets a staff member read their own profile row and no others.
  List<String>? _staffNames;

  /// As [_medicinesLoadQueued]: the read is deferred past the frame, and a slide
  /// that rebuilds in between must not queue a second one.
  bool _staffLoadQueued = false;

  /// True while the first certificate history load is in flight, so opening
  /// the exam slide and moving back onto it does not start a second read.
  bool _loadingCertificate = false;

  /// This visitor's past visits, for the Individual Clients Record. Read once
  /// alongside the first certificate form that is opened, because that
  /// page is generated from this history.
  List<HistoryRow> _history = const [];

  /// Whether the BP guide is up. Held here rather than inside the slide so the
  /// guide survives moving between the BP slides, and so Escape can reach it
  /// without every slide having to own a key handler.
  bool _guideOpen = false;

  String _paperKey = 'Letter';
  bool _landscape = false;

  VisitDetailsController get _c => widget.controller;

  ClinicProfile get _v => widget.visitor;

  @override
  void dispose() {
    for (final t in _texts.values) {
      t.dispose();
    }
    _texts.clear();
    super.dispose();
  }

  // ── TEXT FIELDS ────────────────────────────────────────────────────────

  /// The controller for a text-ish field, created on first use and kept in step
  /// with the draft afterwards.
  ///
  /// The sync in the getter is what makes a resumed visit show what is on the
  /// server: `hydrate` writes into the draft behind this widget's back, and a
  /// controller that is not told would keep showing the empty string it was
  /// born with. It only assigns when the two actually differ, because assigning
  /// moves the caret to the end.
  TextEditingController _textFor(ServiceDraft d, ServiceField f) {
    final key = '${d.serviceId}/${f.key}';
    final value = d.text(f.key);
    final existing = _texts[key];
    if (existing == null) {
      final created = TextEditingController(text: value);
      _texts[key] = created;
      return created;
    }
    if (existing.text != value) existing.text = value;
    return existing;
  }

  /// Text the nurse is typing, routed to the visit's vitals when the field owns
  /// a reading and to the service's own answers otherwise. That single
  /// indirection is what makes "entered once, read-only everywhere else" true
  /// rather than a habit.
  void _onText(ServiceDraft d, ServiceField f, String value) {
    if (f.vital != null) {
      // The box is on this form, so this form is the one typing — its status,
      // and only its status, may become "in progress" when the mirror of the
      // reading lands in the other forms that declare it.
      _c.setVital(f.vital!, value, fromServiceId: d.serviceId);
    } else {
      _c.setField(d.serviceId, f.key, value);
    }
    _naggedField = '${d.serviceId}/${f.key}';
    setState(() {});
  }

  // ── LAYOUT ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Escape closes the guide. A panel that opened over the form has to be
      // dismissible by the key a nurse reaches for when they have read enough,
      // and reaching for the mouse to find a small ✕ is how guides get left
      // open over the form underneath.
      //
      // Registered only while it is open so Escape keeps meaning "step back"
      // everywhere else on this screen.
      bindings: <ShortcutActivator, VoidCallback>{
        if (_guideOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _closeBpGuide,
      },
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final draft = _c.active;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A stretched Row rather than an IntrinsicHeight pair: the
              // service list is as tall as the form beside it whatever the
              // form's content height turns out to be, and no layout pass is
              // spent measuring text that has already been laid out once.
              //
              // No strip across the top. There was one, and it took sixty-odd
              // pixels off the height of every form on this step — the one thing
              // on the step that does not fit a clinic laptop — to repeat four
              // facts. They are the width of the column beside it now, above
              // the services, and the form has that height back.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 2:8, not 3:7. The list is a reminder of what else is on
                    // the visit; the form is where the nurse spends the whole
                    // step. At 3:7 on a 1366-wide laptop the blood pressure
                    // and pulse boxes were left as two cramped strips.
                    Expanded(flex: 2, child: _serviceList()),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 8,
                      child:
                          draft == null ? _nothingToFill() : _formCard(draft),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsets? padding, Key? key}) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      // 12, not 16. Every pixel of padding here is a pixel taken from the form
      // the nurse is typing into, and on a 1366x768 laptop the form is the
      // tightest thing on the screen.
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }

  // ── WHO IS BEING SEEN ──────────────────────────────────────────────────

  /// Who is being seen, at the top of the column the services are in.
  ///
  /// It used to be a strip across the top of the whole step. It was there to say
  /// four things — who, what number, what they do or study, and when this visit
  /// is — and it cost the form beside it sixty-odd pixels of height on every
  /// service to say them, which is the one thing on this step that does not fit
  /// a clinic laptop.
  ///
  /// So the same four facts are the width of the column instead: the list below
  /// them already scrolls, so height spent here is height the service list can
  /// give up, and the form gets the difference. Read-only, as it always was: the
  /// visitor was chosen on step 1 and a nurse halfway through a form should not
  /// be able to change them by accident.
  ///
  /// A rule down the left edge and a filled number rather than a sentence: the
  /// school ID is an identifier, and one that is set in the middle of a line of
  /// words reads as part of the affiliation instead of the thing the record will
  /// be found by.
  Widget _visitorBlock() {
    final v = _v;
    final now = DateTime.now();
    return Container(
      key: const ValueKey('step3/visitor_block'),
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        border: Border(
          left: BorderSide(
            width: 3,
            color: AppColors.primary.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _initialsAvatar(v, 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.1,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 1.5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _orDash(v.id),
                        style: const TextStyle(
                          fontSize: 9.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _affiliation(v),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1.5),
                Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 9.5, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        DateFormat('MMM d, yyyy  ·  h:mm a').format(now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          height: 1.1,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _affiliation(ClinicProfile v) {
    if (v.isStudent) {
      final year = v.yearLevel.trim();
      return [v.program.trim(), year].where((s) => s.isNotEmpty).join(' · ');
    }
    return [v.department.trim(), v.position.trim()]
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  // ── THE SERVICE LIST ───────────────────────────────────────────────────

  Widget _serviceList() {
    final drafts = _c.drafts;
    return _panel(
      key: const ValueKey('step3/services_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who is being seen, above the services rather than across the top of
          // the step: the same facts, in the width of the column, so the form
          // beside it keeps the height.
          _visitorBlock(),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'VISIT SERVICES',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                Text(
                  '${drafts.where((d) => d.isComplete).length}/${drafts.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSub),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          // The list scrolls on its own because twelve services do not fit a
          // narrow column; the page itself must not, so this is the one place
          // on the step where a scrollbar is allowed.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              children: [
                for (final d in drafts) _serviceRow(d),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: _addServiceButton(),
          ),
        ],
      ),
    );
  }

  Widget _serviceRow(ServiceDraft d) {
    final active = _c.activeId == d.serviceId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? AppColors.primaryContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _c.open(d.serviceId)),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(d.serviceId),
                  size: 16,
                  color: active ? AppColors.primaryDark : AppColors.textSub,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    d.shortLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color:
                          active ? AppColors.primaryDeep : AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _statusPill(d.status),
                // Taking a service off the visit, from the list the nurse is
                // already looking at. It used to be step 2 only, which meant a
                // service ticked there by mistake could not be undone until she
                // walked the whole wizard backwards — and step 3 can add
                // services, so it has to be able to remove them too.
                const SizedBox(width: 2),
                _removeServiceButton(d),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The small ✕ on a service row. Confirmed, because a single tap next to the
  /// row's own "open this form" tap is the kind of thing that is one mis-aimed
  /// finger away from throwing away a filled-in form.
  Widget _removeServiceButton(ServiceDraft d) {
    return Tooltip(
      message: 'Remove ${d.label} from this visit',
      child: IconButton(
        key: ValueKey('remove_service_${d.serviceId}'),
        onPressed: () => _confirmRemoveService(d),
        icon: const Icon(Icons.close_rounded, size: 15),
        color: AppColors.textMuted,
        hoverColor: AppColors.dangerContainer,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      ),
    );
  }

  Future<void> _confirmRemoveService(ServiceDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${d.label}?'),
        content: Text(
          d.isComplete || d.dirty
              ? 'Everything entered on this service will be discarded and it '
                  'will be taken off the visit.'
              : 'This service will be taken off the visit.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const ValueKey('confirm_remove_service'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _c.removeService(d.serviceId);
    });
    widget.onServiceRemoved?.call(d.serviceId);
    _toast('${d.label} removed from this visit.');
  }

  IconData _iconFor(String serviceId) {
    return ClinicPurposes.byId(serviceId)?.icon ?? Icons.edit_note_rounded;
  }

  /// The `+ Add New Service` row. The catalogue of what can be added comes from
  /// the same list step 2 draws, so a service that cannot be ticked on step 2
  /// cannot be added here either.
  Widget _addServiceButton() {
    return OutlinedButton.icon(
      onPressed: _showAddServiceSheet,
      icon: const Icon(Icons.add_rounded, size: 17),
      label: const Text('Add New Service',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  // ── THE ACTIVE FORM ────────────────────────────────────────────────────

  Widget _formCard(ServiceDraft d) {
    // The clinic is still finalising these two, so the panel is left empty for
    // now. Everything the form itself owns is gone — title, boxes, slide
    // arrows, Done. The wizard's Back and Continue are kept, because they are
    // the only way off this step and a panel that took them too would leave the
    // nurse on a screen with no controls at all.
    if (kBlankFormServiceIds.contains(d.serviceId)) {
      return _panel(
        key: const ValueKey('step3/form_card'),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: SizedBox.shrink()),
            _formFooter(d, navOnly: true),
          ],
        ),
      );
    }
    // The Medication Service keeps its slide-by-slide flow, with its dots,
    // arrows and Done-on-the-sheet, because it is an inventory picker first
    // and the dosage table after. Every other form — BP Taking included — is
    // one page that scrolls internally: a section per spec slide, and Done
    // always waiting in the footer, because a form that carries its own
    // questions and its own answers has nothing left to walk through and slide
    // counters would be a lie about the shape of what is on screen.
    final slides = _keepsSlides(d);
    return _panel(
      key: const ValueKey('step3/form_card'),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _formHeader(d),
              const Divider(color: AppColors.border, height: 1),
              Expanded(
                child: slides ? _slideBody(d) : _formBody(d),
              ),
              _formFooter(d, slides: slides),
            ],
          ),
          // The guide covers the form area only. A sibling of the card's content
          // rather than a dialog over the screen, so the visitor strip and the
          // service list stay usable and the reading underneath is still there
          // to be compared against the table.
          if (_guideOpen)
            Positioned.fill(
              child: BpGuideOverlay(
                current: _bpCurrent?.severity,
                onClose: _closeBpGuide,
              ),
            ),
        ],
      ),
    );
  }

  /// Whether this form is walked one sheet at a time rather than as one page.
  ///
  /// The Medication Service is an inventory picker followed by the dosage
  /// table — it wants the step-by-step walk and keeps its dots and arrows.
  /// Everything else in `visit_service_forms.dart` collapses into the single
  /// scrolling page instead: a form that carries its own questions and its own
  /// answers has nothing left to walk through. BP Taking was walked once, as a
  /// session that ended in a printed sheet; now the whole reading sits on one
  /// page and the nurse scrolls it, the same as every other box.
  bool _keepsSlides(ServiceDraft d) => d.serviceId == 'medication';

  /// The whole form drawn as one scrolling page.
  ///
  /// A section per spec slide, in the order the slides were declared, with the
  /// shared vitals strip once at the top. The read-only review sheets — the
  /// `form_review` slide every form used to end on, and BP Taking's `bp_form`
  /// printed sheet — are left out: the page IS the review now, questions
  /// above, Done below, and a second sheet that says it all again would scroll
  /// past the very answers it existed to confirm.
  Widget _formBody(ServiceDraft d) {
    final sections = [
      for (final s in d.spec.slides)
        if (s.custom?.id != 'form_review' && s.custom?.id != 'bp_form') s,
    ];
    return SingleChildScrollView(
      key: const ValueKey('step3/form_body'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _section(d, i, sections[i]),
          ],
        ],
      ),
    );
  }

  /// One section of the scrolling form: a heading, then the slide's contents —
  /// a hand-built slide if the description named one, otherwise the declared
  /// fields laid out in a two-column grid.
  ///
  /// Only the fields the answers so far put on screen are laid out. A box behind
  /// a condition that has not fired is left out entirely rather than shown greyed
  /// out, so the grid closes up around it and the section never carries an empty
  /// row for a question that is not being asked. A section whose boxes are all
  /// conditional and none have fired draws nothing at all.
  Widget _section(ServiceDraft d, int index, ServiceSlide slide) {
    final custom = slide.custom;
    if (custom != null) {
      return _customSlide(d, custom.id);
    }
    final shown = d.spec.visibleFields(slide, d.data);
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(index, slide),
        const SizedBox(height: 12),
        ..._fieldGrid(d, shown, slide.groups),
      ],
    );
  }

  Widget _sectionHeader(int index, ServiceSlide slide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${index + 1}.',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slide.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
        ),
      ],
    );
  }

  Widget _formHeader(ServiceDraft d) {
    final isBp = d.serviceId == 'bp_tracking';
    return Padding(
      key: const ValueKey('step3/form_header'),
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 10),
      child: Row(
        children: [
          if (isBp) ...[
            const Icon(
              Icons.monitor_heart_outlined,
              size: 19,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isBp ? 'BP Taking' : d.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                // The BP form is a single screen with the section named inside
                // it, so a second line here saying which "slide" of one is on
                // screen is a line spent on nothing. It also cost the form
                // twenty pixels it needs at 1366x768.
                if (!isBp)
                  Text(
                    d.currentSlide.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSub,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusPill(
            _headerStatus(d),
            // The BP form's own spec: gray Not Started, blue In Progress, green
            // Completed.
            inProgress: isBp
                ? (const Color(0xFF1D4ED8), const Color(0xFFDBEAFE))
                : null,
          ),
        ],
      ),
    );
  }

  /// What the header pill is allowed to claim.
  ///
  /// [ServiceDraft.refreshStatus] calls a service "Completed" as soon as its
  /// required fields are answered. That is the right test for the list and for
  /// the progress count, and the wrong one for a pill a nurse is looking at
  /// beside the boxes they are still typing into: a form that is answered but
  /// has been changed again since the last Save & Continue has not been saved.
  ///
  /// So the header asks for both halves — answered AND not edited since the last
  /// save. Every other pill on the screen keeps using the plain status, because
  /// this is the only place the claim is made about work in front of the user.
  ServiceDraftStatus _headerStatus(ServiceDraft d) {
    if (d.isComplete && d.dirty) return ServiceDraftStatus.inProgress;
    return d.status;
  }

  Widget _slideBody(ServiceDraft d) {
    final slide = d.currentSlide;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _slideChildren(d, slide),
    );

    // Every slide scrolls inside the card, including BP's reading slide, which
    // used to be sized to fit at 1366x768 instead and overflowed the moment a
    // reading was typed into it: the result card, the urgent banner and the
    // repeat row all appear at once, and the bottom of the form was pushed off
    // the bottom of the form.
    //
    // The reason it was exempt does not hold. It was excluded so that "a form
    // that silently scrolls hides its own Next button's worth of content", but
    // the footer is a sibling of this column, not a child of it: Next is pinned
    // to the card whatever the slide does, so scrolling can never hide the
    // button that saves the reading.
    //
    // A short window now scrolls this slide and a tall one does not scroll at
    // all, which is the outcome that was wanted either way. A sheet that
    // quietly clipped its last section would have been the thing to avoid: the
    // remarks the nurse came to read would simply not be there.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: body,
          ),
        ),
      ],
    );
  }

  /// The slide's contents: the shared vitals box first if the slide has any, a
  /// hand-built slide if the description named one, and otherwise the declared
  /// fields laid out in a two-column grid.
  ///
  /// Only the fields the answers so far put on screen are laid out. A box behind
  /// a condition that has not fired is left out entirely rather than shown greyed
  /// out, so the grid closes up around it and the slide never carries an empty
  /// row for a question that is not being asked.
  List<Widget> _slideChildren(ServiceDraft d, ServiceSlide slide) {
    final out = <Widget>[];
    final custom = slide.custom;
    if (custom != null) {
      out.add(_customSlide(d, custom.id));
      return out;
    }
    final shown = d.spec.visibleFields(slide, d.data);
    if (shown.isEmpty) {
      out.add(_nothingOnThisSlide());
      return out;
    }
    out.addAll(_fieldGrid(d, shown, slide.groups));
    return out;
  }

  /// Lays the declared fields out two to a row where a field is [FieldWidth.half]
  /// and a whole row where it is not. Grouped here rather than in a GridView
  /// because a half field is not half the *width* of a row: it is half of a row
  /// that has already had a 14px gap taken out of it, and a GridView cannot
  /// express that without measuring first.
  ///
  /// Fields named in a [FieldGroup] are drawn as one card in the position the
  /// first of them holds on the slide, and take no part in the two-to-a-row
  /// packing — the card decides its own inside. Walking the visible fields in
  /// order rather than drawing the groups first is what keeps a group beside the
  /// conditional box that belongs to it: "Other Cleaning Used" appears directly
  /// under the card it belongs to, not after the card two rows further down.
  List<Widget> _fieldGrid(
      ServiceDraft d, List<ServiceField> fields, List<FieldGroup> groups) {
    // Where each group starts, so the walk below can emit it at that point.
    final startsHere = <int, FieldGroup>{};
    for (final g in groups) {
      for (var i = 0; i < fields.length; i++) {
        if (g.holds(fields[i].key)) {
          startsHere[i] = g;
          break;
        }
      }
    }
    // A field that belongs to a card is drawn by the card, wherever on the slide
    // it is declared. Tracked rather than assumed: the fields inside a group are
    // not declared side by side, so a conditional box belonging to the first of
    // them ("Other Cleaning Used") sits between them on the slide, and a walk
    // that only skipped a contiguous run would draw the second one a second time.
    final drawnInACard = <String>{};

    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(w);
    }

    // A half field waiting for a partner, held until the next loose field.
    ServiceField? pending;
    void flushPending() {
      final p = pending;
      pending = null;
      if (p != null) add(_field(d, p));
    }

    var i = 0;
    while (i < fields.length) {
      final g = startsHere[i];
      if (g != null) {
        flushPending();
        final inCard = [
          for (final f in fields)
            if (g.holds(f.key)) f,
        ];
        drawnInACard.addAll(g.keys);
        add(_groupCard(d, inCard));
        i += 1;
        continue;
      }
      final f = fields[i];
      if (drawnInACard.contains(f.key)) {
        i += 1;
        continue;
      }
      if (f.width == FieldWidth.half && pending == null) {
        pending = f;
      } else if (f.width == FieldWidth.half) {
        final left = pending!;
        pending = null;
        add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(d, left)),
            const SizedBox(width: 14),
            Expanded(child: _field(d, f)),
          ],
        ));
      } else {
        flushPending();
        add(_field(d, f));
      }
      i += 1;
    }
    flushPending();
    return out;
  }

  /// One bordered card around a set of fields that only mean something together.
  Widget _groupCard(ServiceDraft d, List<ServiceField> group) {
    // The same two-to-a-row packing as the slide, so a half-width field is half
    // of the card: putting a reading and its method on one row inside the card
    // is the whole reason for the card.
    final rows = <Widget>[];
    var i = 0;
    while (i < group.length) {
      final f = group[i];
      if (f.width == FieldWidth.half && i + 1 < group.length) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(d, f)),
            const SizedBox(width: 12),
            Expanded(child: _field(d, group[i + 1])),
          ],
        ));
        i += 2;
      } else {
        rows.add(_field(d, f));
        i += 1;
      }
    }
    final inside = <Widget>[];
    for (var r = 0; r < rows.length; r++) {
      if (r > 0) inside.add(const SizedBox(height: 12));
      inside.add(rows[r]);
    }
    return Container(
      // Named after the first field of the group, which is the field whose
      // position the card is drawn in. A card is the only thing on a slide that
      // can be asked for twice, and asking for it twice is how a slip that
      // renders a group a second time gets caught.
      key: ValueKey('group/${d.serviceId}/${group.first.key}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: inside,
      ),
    );
  }

  // ── FIELDS ─────────────────────────────────────────────────────────────

  Widget _field(ServiceDraft d, ServiceField f) {
    final key = '${d.serviceId}/${f.key}';
    final children = <Widget>[
      _fieldLabel(d, f, key),
      const SizedBox(height: 5),
      _fieldInput(d, f, key),
    ];
    final note = f.note;
    if (note != null) {
      children.add(const SizedBox(height: 4));
      children.add(Text(
        note,
        style: const TextStyle(
            fontSize: 11, color: AppColors.textMuted, height: 1.3),
      ));
    }
    return Column(
      // Named so a test can find one named field without depending on the order
      // the form happens to lay them out in, which is a layout decision and not
      // part of what a form means. The label is a separate `Text`, so matching
      // on the label text would also match a note that quotes it.
      key: ValueKey('field/$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _fieldLabel(ServiceDraft d, ServiceField f, String key) {
    // The whole form's requirement set rather than the current slide's: on the
    // one-page form every box is on "slide one", and a red "needed to continue"
    // that only looked at the first section would go dark on a field Done just
    // flagged two sections down.
    final needed =
        d.spec.requiredKeysIn(d.data).where((k) => !_isAnswered(d, k)).toList();
    final missing = needed.contains(f.key) && _naggedField == key;
    return Row(
      children: [
        Flexible(
          child: Text(
            f.required ? '${f.label} *' : f.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: missing ? AppColors.danger : AppColors.textSub,
            ),
          ),
        ),
        if (f.required)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              missing ? 'needed to continue' : 'required',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: missing ? AppColors.danger : AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _fieldInput(ServiceDraft d, ServiceField f, String key) =>
      switch (f.kind) {
        ServiceFieldKind.text => _textBox(d, f, key, lines: 1),
        ServiceFieldKind.multiline => _textBox(d, f, key, lines: 3),
        ServiceFieldKind.number => _numberBox(d, f, key),
        ServiceFieldKind.dropdown => _dropdownBox(d, f, key),
        ServiceFieldKind.chips => _singleChipBox(d, f, key),
        ServiceFieldKind.multiselect => _chipBox(d, f, key),
        ServiceFieldKind.checkboxes => _checkBoxList(d, f, key),
        ServiceFieldKind.date => _dateBox(d, f, key),
        ServiceFieldKind.readOnly => _readOnlyBox(d, f, key),
        ServiceFieldKind.sharedVitals => _sharedVitalsBox(d, f),
        ServiceFieldKind.staffName => _staffNameBox(d, f, key),
        ServiceFieldKind.inventoryPick => _inventoryPickBox(d, f, key),
      };

  // ── Text / multiline ───────────────────────────────────────────────────

  Widget _textBox(ServiceDraft d, ServiceField f, String key, {int lines = 1}) {
    final controller = _textFor(d, f);
    final isNotes = f.key == 'notes';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          maxLines: lines,
          minLines: lines,
          onChanged: (value) => _onText(d, f, value),
          style: const TextStyle(fontSize: 13, color: AppColors.textMain),
          decoration: _decoration(f, filled: true),
        ),
        // Only the notes box carries a counter. Every other box having one
        // would put five running "0 / 500" labels on a slide, which is noise
        // rather than information.
        if (isNotes)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Align(
              alignment: Alignment.centerRight,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Text(
                  '${controller.text.length} / ${f.maxChars}',
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── The person who did the work ─────────────────────────────────────────

  /// The signed-in staff member, with a way to say it was somebody else.
  ///
  /// A text field with the signed-in name already in it, and a menu of the other
  /// clinic accounts beside it. Both halves are needed: the field is what makes
  /// this box free rather than a chore, and the menu is what makes it correct
  /// when a colleague covered the session. Tapping the menu does not replace
  /// what was typed unless a name is actually chosen, so a half-typed name is
  /// never thrown away by a stray tap.
  Widget _staffNameBox(ServiceDraft d, ServiceField f, String key) {
    final controller = _textFor(d, f);
    final others = _otherStaffNames;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (value) => _onText(d, f, value),
            style: const TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: _decoration(f, filled: true),
          ),
        ),
        const SizedBox(width: 6),
        _staffMenu(f, others),
      ],
    );
  }

  /// The account list, behind one button so it costs no width on the slide and
  /// no network call until it is asked for.
  Widget _staffMenu(ServiceField f, List<String> names) {
    return PopupMenuButton<String>(
      key: ValueKey('field/${f.key}/menu'),
      tooltip: 'Someone else did this',
      onSelected: (name) {
        final d = _c.active;
        if (d == null) return;
        _c.setField(d.serviceId, f.key, name);
        _naggedField = f.key;
        setState(() {});
      },
      itemBuilder: (context) => [
        for (final n in names)
          PopupMenuItem(
              value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
      ],
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.switch_account_outlined,
                size: 15, color: AppColors.textSub),
            SizedBox(width: 5),
            Text('Swap',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }

  /// The other clinic accounts, fetched once and only when a form that wants
  /// them is actually on screen.
  ///
  /// A failure here must not take the slide with it. A staff member may only be
  /// able to read their own profile row, and a nurse who cannot see the list
  /// still has to be able to type the name — so the box stays a text field
  /// either way and the menu is simply empty.
  List<String> get _otherStaffNames {
    final loaded = _staffNames;
    if (loaded != null) return loaded;
    if (!_staffLoadQueued) {
      _staffLoadQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _staffLoadQueued = false;
        if (!mounted) return;
        try {
          final profiles = await AccountService.fetchAll();
          if (!mounted) return;
          setState(() {
            _staffNames = [
              for (final p in profiles)
                if (p.isActive) p.fullName.isEmpty ? p.username : p.fullName,
            ]..removeWhere((n) => n.trim().isEmpty || n == widget.userName);
          });
        } catch (_) {
          // RLS, or the network. The box is typed either way.
        }
      });
    }
    return const [];
  }

  // ── What came off the shelf ─────────────────────────────────────────────

  /// Items taken from the clinic's own inventory and used on the patient, without
  /// a prescription and without spending stock.
  ///
  /// The chosen ones go to the top, filled in, with the count beside the label,
  /// because the commonest mistake here is to believe a previous choice is still
  /// there: with everything in one undifferentiated wrap of grey chips, the only
  /// way to tell what is already on the wound is to remember it, and a nurse who
  /// forgets ends up listing the same bottle twice.
  ///
  /// Archived items and things at zero are not offered, and a shelf that cannot
  /// be read is not allowed to block the visit: below the chips there is always
  /// a way to type a name that is not on the list. Without it, a dressing visit
  /// on a clinic day with no network could not be recorded at all, and the
  /// alternative - a box the nurse can leave blank - is worse, because the wound
  /// then has no record of what went on it at all.
  Widget _inventoryPickBox(ServiceDraft d, ServiceField f, String key) {
    _ensureMedicinesLoaded();
    final chosen = d.chosen(f.key);
    final loading = _medicines == null;
    final list = _medicines ?? const <Medicine>[];
    final pickable = list.where(VisitDetailsController.canPick).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // A name already on the wound that is no longer pickable - archived, or out
    // of stock since the visit was resumed - is deliberately left out of the
    // shelf list but stays in the chosen row above, where it can still be
    // removed. Dropping it would quietly rewrite history: the bottle really was
    // used on this patient.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chosen.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'On the wound',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppColors.textSub),
                ),
              ),
              Text('${chosen.length} chosen',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final name in chosen)
                _optionChip(
                  label: name,
                  selected: true,
                  onTap: () => _toggleInventoryPick(d, f, name),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (pickable.isEmpty)
          _notice(
            AppColors.warning,
            Icons.inventory_2_outlined,
            'The shelf could not be read, or nothing on it can be used here. '
            'Name what was used below. This form does not spend stock - a '
            'prescription is still made on the Medication service.',
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final m in pickable)
                _optionChip(
                  label: m.stock > 0 ? '${m.name}  ·  ${m.stock}' : m.name,
                  selected: chosen.contains(m.name),
                  onTap: () => _toggleInventoryPick(d, f, m.name),
                ),
            ],
          ),
        if (!loading) ...[
          const SizedBox(height: 8),
          _inventoryEscapeHatch(d, f),
        ],
      ],
    );
  }

  /// The way out when the right bottle is not on the list.
  ///
  /// One line, always collapsed to nothing but a link, so it costs no height on
  /// a slide that is already full — and it is here rather than a "skip this box"
  /// because a wound with nothing recorded about what was put on it is a worse
  /// record than a wound with a name that a stock-take can correct later.
  Widget _inventoryEscapeHatch(ServiceDraft d, ServiceField f) {
    // The same controller cache the text fields use, under a key nothing else
    // writes to, so the box keeps what was half-typed across a rebuild.
    final key = '${d.serviceId}/${f.key}/other';
    final box = _texts.putIfAbsent(key, () => TextEditingController());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('field/${f.key}/other'),
            controller: box,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMain),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.fieldFill,
              hintText: 'Not on the shelf? Name it here',
              hintStyle:
                  const TextStyle(fontSize: 12, color: AppColors.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 42,
          child: OutlinedButton(
            key: ValueKey('field/${f.key}/other_add'),
            onPressed: () => _addTypedInventoryItem(d, f, box),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            child: const Text('Add',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  void _addTypedInventoryItem(
      ServiceDraft d, ServiceField f, TextEditingController box) {
    final typed = box.text.trim();
    if (typed.isEmpty) {
      _toast('Type what was used first.');
      return;
    }
    final current = d.chosen(f.key).toList();
    if (!current.any((n) => n.toLowerCase() == typed.toLowerCase())) {
      current.add(typed);
      _c.setField(d.serviceId, f.key, current);
    }
    box.clear();
    _naggedField = f.key;
    setState(() {});
  }

  void _toggleInventoryPick(ServiceDraft d, ServiceField f, String name) {
    final current = d.chosen(f.key).toList();
    if (!current.remove(name)) current.add(name);
    _c.setField(d.serviceId, f.key, current);
    _naggedField = f.key;
    setState(() {});
  }

  /// The stock read, started at most once and never during a build.
  ///
  /// Both the picker and this field need it, so it is one deferred load rather
  /// than two paths that can each decide to fire.
  void _ensureMedicinesLoaded() {
    if (_medicines != null || _loadingMedicines || _medicinesLoadQueued) return;
    _medicinesLoadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _medicinesLoadQueued = false;
      if (!mounted) return;
      _loadMedicines();
    });
  }

  // ── Number ──────────────────────────────────────────────────────────────

  Widget _numberBox(ServiceDraft d, ServiceField f, String key) {
    final controller = _textFor(d, f);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (value) => _onText(d, f, value),
      style: const TextStyle(fontSize: 13, color: AppColors.textMain),
      decoration: _decoration(f, filled: true, unit: f.unit),
    );
  }

  /// A reading's band as a coloured pill: green for normal, and amber, orange
  /// and red for the three degrees of "not normal", matching the four states
  /// [VitalBand] carries.
  Widget _bandPill(VitalReading r) {
    final color = switch (r.band) {
      VitalBand.low => const Color(0xFF2563EB),
      VitalBand.normal => AppColors.success,
      VitalBand.watch => AppColors.warning,
      VitalBand.high => const Color(0xFFEA580C),
      VitalBand.critical => AppColors.danger,
    };
    return Tooltip(
      message: 'For clinic reference only — screening aid, not a diagnosis.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (r.band) {
                VitalBand.low => Icons.arrow_downward_rounded,
                VitalBand.normal => Icons.check_circle_rounded,
                VitalBand.watch => Icons.info_rounded,
                VitalBand.high => Icons.warning_rounded,
                VitalBand.critical => Icons.error_rounded,
              },
              size: 13,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              r.category ?? r.band.label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dropdown ───────────────────────────────────────────────────────────

  Widget _dropdownBox(ServiceDraft d, ServiceField f, String key) {
    final options = f.options;
    final current = d.text(f.key);
    // A value that is in the list but not in the options is a service whose
    // catalogue changed under a resumed visit. Keeping it selected would crash
    // the assert inside DropdownButtonFormField, so it is added instead.
    final safe = current.isNotEmpty && !options.contains(current)
        ? [current, ...options]
        : options;
    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? null : current,
      isExpanded: true,
      hint: Text(
        _hintOf(f),
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
      items: [
        for (final o in safe)
          DropdownMenuItem(
            value: o,
            child: Text(o,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textMain)),
          ),
      ],
      onChanged: (value) {
        _c.setField(d.serviceId, f.key, value);
        _naggedField = key;
        setState(() {});
      },
      decoration: _decoration(f),
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      style: const TextStyle(fontSize: 13, color: AppColors.textMain),
    );
  }

  // ── Chips / tick boxes ─────────────────────────────────────────────────

  Widget _chipBox(ServiceDraft d, ServiceField f, String key) {
    final chosen = d.chosen(f.key);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final o in f.options)
          _optionChip(
            label: o,
            selected: chosen.contains(o),
            onTap: () {
              _c.toggleChoice(d.serviceId, f.key, o);
              _naggedField = key;
              setState(() {});
            },
          ),
      ],
    );
  }

  /// The same chip, but one answer at a time. Tapping the chosen chip clears it,
  /// because a nurse who picked the wrong arm needs to undo it without finding
  /// whatever button clears the whole form.
  Widget _singleChipBox(ServiceDraft d, ServiceField f, String key) {
    final chosen = d.chosen(f.key);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final o in f.options)
          _optionChip(
            label: o,
            selected: chosen.contains(o),
            onTap: () {
              // max: 1 turns the group into a radio group, and the explicit
              // clear is what lets a wrong answer be undone — the radio group
              // on its own cannot untick.
              if (chosen.contains(o)) {
                _c.setField(d.serviceId, f.key, <String>[]);
              } else {
                _c.toggleChoice(d.serviceId, f.key, o, max: 1);
              }
              _naggedField = key;
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _optionChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primaryDeep : AppColors.textMain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkBoxList(ServiceDraft d, ServiceField f, String key) {
    final chosen = d.chosen(f.key);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Lay the ticks out in columns instead of one tall stack. A list of a
        // dozen reasons down the slide is the tallest thing on the form, and the
        // height is what pushed the footer off the laptop screen. Two columns as
        // soon as there is room, one on a narrow phone.
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 2,
          children: [
            for (final o in f.options)
              SizedBox(
                width: itemWidth,
                child: _checkRow(
                  label: o,
                  checked: chosen.contains(o),
                  onTap: () {
                    _c.toggleChoice(d.serviceId, f.key, o);
                    _naggedField = key;
                    setState(() {});
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _checkRow({
    required String label,
    required bool checked,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            _tick(checked),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.textMain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tick(bool checked) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.borderStrong,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }

  // ── Date ───────────────────────────────────────────────────────────────

  Widget _dateBox(ServiceDraft d, ServiceField f, String key) {
    final current = d.text(f.key);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _parseIso(current) ?? DateTime.now(),
          firstDate: DateTime(1990),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (picked == null) return;
        _c.setField(d.serviceId, f.key, _isoOf(picked));
        _naggedField = key;
        setState(() {});
      },
      borderRadius: BorderRadius.circular(9),
      child: InputDecorator(
        decoration: _decoration(f, filled: true),
        child: Text(
          current.isEmpty ? _hintOf(f) : _prettyDate(current),
          style: TextStyle(
            fontSize: 13,
            color: current.isEmpty ? AppColors.textMuted : AppColors.textMain,
          ),
        ),
      ),
    );
  }

  // ── Worked-out and shared values ───────────────────────────────────────

  /// A value the form computes rather than the nurse. Greyed, tagged "auto", and
  /// not editable: a box the nurse can type into is a box whose number the
  /// record can disagree with.
  Widget _readOnlyBox(ServiceDraft d, ServiceField f, String key) {
    return InputDecorator(
      decoration: _decoration(f, filled: true).copyWith(
        fillColor: AppColors.fieldFillDisabled,
        suffixIcon: const Padding(
          padding: EdgeInsets.only(right: 10),
          child: _AutoTag(),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      child: Text(
        _autoValue(d, f),
        style: const TextStyle(fontSize: 13, color: AppColors.textMain),
      ),
    );
  }

  /// The visit's own readings, shown because this form needs them but does not
  /// own them, with a link to the service that does. A nurse looking at Blood
  /// Pressure in a Prenatal visit should not have to hunt for the BP service to
  /// check a number, nor be able to change it here by accident.
  Widget _sharedVitalsBox(ServiceDraft d, ServiceField f) {
    final readings = _c.vitals.readings;
    final owner = _ownerOfVitals();
    if (readings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.monitor_heart_outlined,
                size: 17, color: AppColors.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                owner == null
                    ? 'No readings recorded for this visit yet.'
                    : 'Not taken yet. ${_labelOf(owner)} records them.',
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.textSub),
              ),
            ),
            if (owner != null) _editVitalsLink(owner),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Recorded once for this visit — read-only here',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted),
                ),
              ),
              if (owner != null) _editVitalsLink(owner),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final r in readings) _bandPill(r)],
          ),
        ],
      ),
    );
  }

  Widget _editVitalsLink(String ownerId) {
    return TextButton.icon(
      onPressed: () => setState(() => _c.open(ownerId)),
      icon: const Icon(Icons.edit_outlined, size: 13),
      label: Text('Edit in ${_labelOf(ownerId)}',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  /// The first service in the visit's order that owns a vital reading, which is
  /// the one to send the nurse to. BP Taking is normally first, so this is
  /// almost always it.
  String? _ownerOfVitals() {
    for (final d in _c.drafts) {
      for (final s in d.spec.slides) {
        if (s.fields.any((f) => f.vital != null)) return d.serviceId;
      }
    }
    return null;
  }

  String _labelOf(String serviceId) =>
      _c.draftFor(serviceId)?.shortLabel ?? serviceId;

  /// The value a [ServiceFieldKind.readOnly] field shows. Switched on the key
  /// the description gave it, so adding a computed field to a form is a line in
  /// the description and a case here — not a new widget.
  ///
  /// The keys the forms actually declare are `bmi`, `bmi_class` (the adult band
  /// the BMI falls in), `bp_assessment` (the same for the visit's blood
  /// pressure), `aog` (age of gestation), `edd` (expected due date) and
  /// `service_name`. Anything else falls through to whatever is in the draft, so
  /// an unrecognised read-only field shows a dash rather than an error.
  String _autoValue(ServiceDraft d, ServiceField f) {
    switch (f.key) {
      case 'bmi':
        final bmi = _c.vitals.bmi;
        return bmi == null ? '—' : bmi.toStringAsFixed(1);
      case 'bmi_class':
        return _c.vitals.bmiReading?.category ?? '—';
      case 'temp_assessment':
        return _c.vitals.tempReading?.category ?? '—';
      case 'bp_assessment':
        return _c.vitals.bloodPressure?.category ?? '—';
      case 'aog':
        // "12w 3d" rather than a decimal of weeks: a nurse reads a gestation
        // in whole weeks and days, and 17.43 weeks is not a thing anyone says
        // out loud in a clinic.
        final lmp = _parseIso(d.text('lmp'));
        if (lmp == null) return '—';
        final days = DateTime.now().difference(lmp).inDays;
        if (days < 0) return '—';
        return '${days ~/ 7}w ${days % 7}d';
      case 'edd':
        return _dueDate(d) ?? '—';
      default:
        return d.text(f.key).isEmpty ? '—' : d.text(f.key);
    }
  }

  // ── THE FORM FOOTER — Done, and the wizard's way off the step ───────────

  /// One row, reading left to right in the order the eye moves: how the service
  /// is finished, then the wizard's own way off the step.
  ///
  /// Three shapes:
  ///
  /// * [slides] keeps the sheet-walk form — the Medication Service, which is an
  ///   inventory picker followed by the dosage table — dots, Prev/Next, and
  ///   Done on the last slide, which is the printed sheet the nurse checks the
  ///   finished entry against.
  /// * The default is the one-page form: a single Done, always live, that
  ///   validates the WHOLE service — a form with its questions and its answers
  ///   on one page has no last slide for Done to live on, and there is no slide
  ///   behind a box anymore that "fill in the required fields" could be hiding.
  /// * [navOnly] drops the form's own half of the bar and keeps only the
  ///   wizard's Back and Continue, for the deliberately blank services: there is
  ///   nothing to fill in, so a Done that saved nothing would be a control that
  ///   lies about what the nurse can do.
  Widget _formFooter(ServiceDraft d,
      {bool navOnly = false, bool slides = false}) {
    final nav = widget.nav;

    // The sheet-walk forms print their own finishing page. Done is live there
    // and nowhere else on that path: a form's last slide is where "I have
    // finished with this" belongs, and pressing it marks the service saved
    // without moving off the sheet, so the nurse is left looking at the
    // finished form rather than the next service.
    final customId = d.currentSlide.custom?.id;
    final isFormSheet = customId == 'bp_form' || customId == 'form_review';

    // Prev is absent on the first slide rather than disabled. A greyed-out
    // "‹ Prev" on slide 1 of every form is a control that cannot do anything,
    // and removing it is what makes the remaining pair sit together.
    final canGoBack = slides && d.slide > 0;
    return Container(
      key: const ValueKey('step3/form_footer'),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!navOnly && slides) ...[
            // Dots for the slides, so the nurse can see how much of the form is
            // left without counting. A form of one slide gets a plain counter
            // rather than a single lonely dot.
            if (d.spec.slides.length > 1) _slideDots(d, d.spec.slides.length),
            Text(
              'Slide ${d.slidePosition}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSub),
            ),
            // The slide arrows, right under the number they move.
            const SizedBox(width: 10),
            if (canGoBack) ...[
              _footerButton(
                label: '‹ Prev',
                onPressed: () => setState(() => _c.previousSlideOrService()),
              ),
              const SizedBox(width: 6),
            ],
            _footerButton(
              label: d.isLastSlide ? 'Done' : 'Next ›',
              filled: true,
              onPressed: d.isLastSlide
                  ? (isFormSheet ? () => _finishService(d) : null)
                  : () => _goToNextSlide(d),
            ),
          ] else if (!navOnly) ...[
            // The one-page form's own finish. Always live: Done refuses on a
            // half-filled form with the name of the box, which it can because
            // every box is on the same page as the button.
            _footerButton(
              label: 'Done',
              filled: true,
              onPressed: () => _finishService(d),
            ),
          ],
          const Spacer(),
          // The wizard's Back and Continue, in the form's own footer. The bar
          // under the cards is not drawn on this step, so this is the only place
          // they are.
          if (nav != null) ...[
            _footerButton(label: 'Back', onPressed: nav.onBack),
            const SizedBox(width: 8),
            if (nav.saving)
              // The save is in flight, and the only thing a nurse needs to know
              // is that the button they just pressed is working. The label and
              // the width stay put so the row does not jump under their hand.
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              )
            else
              _footerButton(
                label: nav.continueLabel,
                filled: true,
                onPressed: nav.continueEnabled ? nav.onContinue : null,
              ),
          ],
        ],
      ),
    );
  }

  /// One of the four controls in the footer bar, in one place so they cannot
  /// drift apart in height.
  ///
  /// 28px with a shrunk tap target, on purpose: Material pads every button out
  /// to 48px for a fingertip, and this bar is pinned to the bottom of the form
  /// the nurse is typing into. On the clinic's laptop that padding is the
  /// difference between the note box being on screen and being below the fold.
  Widget _footerButton({
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.bgAlt,
            disabledForegroundColor: AppColors.textMuted,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AppColors.textMain,
            side: const BorderSide(color: AppColors.border),
            disabledForegroundColor: AppColors.textMuted,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          );
    final button = filled
        ? FilledButton(
            onPressed: onPressed,
            style: style,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          );
    return button;
  }

  /// Next, on any slide but the last.
  ///
  /// One method for two footers: the reading slide's slim bar and the full one
  /// have to agree about what "next" means, and a rule that lives in the button
  /// that presses it is a rule that can be written twice and mean two things.
  void _goToNextSlide(ServiceDraft d) {
    final missing = d.missingOnCurrentSlide();
    if (missing.isNotEmpty) {
      // Nags the first box that is wanted, by name, rather than refusing
      // silently.
      setState(() => _naggedField = '${d.serviceId}/${missing.first}');
      _toast('Fill in the required box to continue.');
      return;
    }
    setState(() => _c.nextSlide());
  }

  /// Done.
  ///
  /// It saves and stays. Moving on to the next unfinished service is what the
  /// wizard's own Save & Continue is for, and doing it here too would take the
  /// nurse off the sheet in the same breath they were checking it — which is the
  /// one thing a "have I got this right" screen should not do.
  ///
  /// It refuses on a half-filled form, and it says WHICH box, because a required
  /// box behind a condition that has not fired is no longer required and "fill
  /// in the required fields" would send the nurse hunting for a box that is not
  /// there. The nag also paints the named field red, which works on the one-page
  /// form precisely because the box and the button share a page.
  void _finishService(ServiceDraft d) {
    final missing =
        d.spec.requiredKeysIn(d.data).where((k) => !_isAnswered(d, k)).toList();
    if (missing.isNotEmpty) {
      setState(() => _naggedField = '${d.serviceId}/${missing.first}');
      _toast('Still needed: ${_labelOfKey(d, missing.first)}.');
      return;
    }
    setState(() {
      d.refreshStatus();
      d.dirty = false;
    });
    _toast('${d.label} saved.');
    // If only one service and it became completed, auto-show form_review
    if (_c.drafts.length == 1 && d.status == ServiceDraftStatus.completed) {
      final spec = d.spec;
      final reviewIndex =
          spec.slides.indexWhere((s) => s.custom?.id == 'form_review');
      if (reviewIndex >= 0 && d.slide != reviewIndex) {
        setState(() => _c.goToSlide(reviewIndex));
      }
    }
  }

  /// Whether one required key holds an answer the form would accept. A filled-in
  /// box is not the same as an answered one: a systolic of 9999 is filled in, and
  /// it is still not a measurement, so it must not let Done through.
  bool _isAnswered(ServiceDraft d, String key) {
    final v = d.data[key];
    final empty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty);
    return !empty && d.spec.validate(key, v) == null;
  }

  /// The box's own name, so a refusal can say "Position" rather than
  /// "position_required_key".
  String _labelOfKey(ServiceDraft d, String key) {
    for (final f in d.spec.fields) {
      if (f.key == key) return f.label;
    }
    return key;
  }

  Widget _slideDots(ServiceDraft d, int slides) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < slides; i++)
            Container(
              width: i == d.slide ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i == d.slide
                    ? AppColors.primary
                    : (i < d.slide
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : AppColors.border),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  // ── PLACES A SLIDE CAN BE EMPTY ────────────────────────────────────────

  /// Step 2 let the visit through with nothing ticked. The form card cannot
  /// render "choose a service" — that is step 2's job and the user has already
  /// been past it — so this says what to do instead of showing a blank panel.
  Widget _nothingToFill() {
    return _panel(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_add_check_rounded,
                size: 34, color: AppColors.textMuted),
            const SizedBox(height: 10),
            const Text('No services on this visit',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain)),
            const SizedBox(height: 6),
            const SizedBox(
              child: Text(
                'Go back to Select Services and tick what this visitor is here for.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nothingOnThisSlide() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text('Nothing to fill in on this slide.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      ),
    );
  }

  // ── SMALL PIECES ───────────────────────────────────────────────────────

  /// A service's state, as a small pill.
  ///
  /// [inProgress] can be overridden because "In Progress" means two different
  /// things on this screen and they are not the same colour. In the Visit
  /// Services list it is a work queue, so amber — something to come back to. In
  /// the header of the card the nurse is looking at, it is the honest current
  /// state of the form in front of them, and the spec for that form asks for
  /// blue. The same word in two colours would be worse than either, which is why
  /// the override is an argument at the one call site that needs it rather than a
  /// second pill widget to drift out of step with the first.
  Widget _statusPill(ServiceDraftStatus s, {(Color, Color)? inProgress}) {
    final (color, bg) = switch (s) {
      ServiceDraftStatus.notStarted => (AppColors.textMuted, AppColors.bgAlt),
      ServiceDraftStatus.inProgress =>
        inProgress ?? (AppColors.warning, const Color(0xFFFEF3C7)),
      ServiceDraftStatus.completed => (
          AppColors.success,
          AppColors.successContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s == ServiceDraftStatus.completed) ...[
            Icon(Icons.check_circle_rounded, size: 11, color: color),
            const SizedBox(width: 4),
          ] else if (s == ServiceDraftStatus.inProgress) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            s.label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(ServiceField f,
      {bool filled = false, String? unit}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: filled ? AppColors.fieldFill : AppColors.surface,
      hintText: _hintOf(f),
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      suffixText: unit == null || unit.isEmpty ? null : unit,
      suffixStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// What an empty box says about itself.
  ///
  /// It used to say "Select…" for every field that had no hint of its own, which
  /// is an instruction to open a menu and no help at all about what goes in it.
  /// The prompt now shows a real example drawn from the field's own options, so
  /// a nurse can tell a list of methods from a list of sites by the shape of the
  /// answer before tapping anything.
  ///
  /// Never a required value, and never a clinical suggestion: an example is
  /// there to be replaced, and a placeholder that reads like a recommendation is
  /// how a default ends up recorded as a finding.
  String _hintOf(ServiceField f) {
    final own = f.hint?.trim();
    if (own != null && own.isNotEmpty) return own;
    switch (f.kind) {
      case ServiceFieldKind.dropdown:
      case ServiceFieldKind.chips:
        return f.options.isEmpty ? 'Choose one' : 'e.g. ${f.options.first}';
      case ServiceFieldKind.date:
        return 'Pick a date';
      case ServiceFieldKind.number:
        final unit = f.unit?.trim() ?? '';
        return unit.isEmpty ? 'Type a number' : 'Type a number in $unit';
      case ServiceFieldKind.text:
      case ServiceFieldKind.multiline:
        return 'Type your answer';
      case ServiceFieldKind.checkboxes:
      case ServiceFieldKind.multiselect:
      case ServiceFieldKind.sharedVitals:
      case ServiceFieldKind.readOnly:
      case ServiceFieldKind.staffName:
      case ServiceFieldKind.inventoryPick:
        // These draw their own lists or their own strip rather than a box, so
        // they never show a hint. Listed rather than left out so adding a kind
        // is a compile error here instead of a silently blank box.
        return '';
    }
  }

  Widget _initialsAvatar(ClinicProfile p, double radius) {
    final parts = [p.firstName, p.lastName]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.map((s) => s[0].toUpperCase()).take(2).join();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: _roleColor(p.category).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w700,
          color: _roleColor(p.category),
        ),
      ),
    );
  }

  Color _roleColor(String category) => switch (category) {
        'Student' => AppColors.student,
        'Faculty' => AppColors.faculty,
        'Staff' => AppColors.staff,
        _ => AppColors.textSub,
      };

  // ── PRENATAL ARITHMETIC ────────────────────────────────────────────────

  /// The due date: the last menstrual period plus 280 days, which is the only
  /// arithmetic a due date is allowed to be. Null when there is no LMP on file,
  /// because a due date worked out from a missing date is a guess.
  String? _dueDate(ServiceDraft d) {
    final lmp = _parseIso(d.text('lmp'));
    if (lmp == null) return null;
    return _prettyDate(
      _isoOf(lmp.add(const Duration(days: VisitServiceForms.pregnancyDays))),
    );
  }

  // ── DIALOGS ────────────────────────────────────────────────────────────

  /// The catalogue sheet. It is a toggle now, not just an "add" list: a service
  /// already on the visit can be taken off from here too, so the sheet is one
  /// place that answers both "what can I still add" and "what did I add by
  /// mistake" — the two questions a nurse opens it with.
  void _showAddServiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddServiceSheet(
        taken: _c.drafts.map((d) => d.serviceId).toSet(),
        onPick: (id) {
          Navigator.of(context).pop();
          // `addService` rather than `open`: the service is not on the visit
          // yet, so there is no draft to open. It also switches to it, which is
          // what a nurse who has just added something wants to happen next.
          setState(() => _c.addService(id));
          // Step 2 owns the service list — it is what decides whether a service
          // is on the visit at all, and what the review step reads. Adding only
          // to this controller would leave a service on screen that the visit
          // did not ask for, and one that disappears the moment the nurse walks
          // back to step 2.
          widget.onServiceAdded?.call(id);
        },
        onUnpick: (id) {
          Navigator.of(context).pop();
          setState(() => _c.removeService(id));
          // Same reason as onPick, in reverse: step 2's selection is the visit's
          // list, so a service dropped here has to be dropped there or it comes
          // straight back when the controller is rebuilt.
          widget.onServiceRemoved?.call(id);
          _toast('${_labelOf(id)} removed from this visit.');
        },
      ),
    );
  }

  // ── CUSTOM SLIDES ──────────────────────────────────────────────────────

  /// A slide the description named rather than declared — the ones that are a
  /// table or a document rather than a grid of boxes.
  ///
  /// Switched on the id the description gives it, so adding a hand-built slide
  /// to a form is a line in `visit_service_forms.dart` and a case here, and the
  /// description still owns the slide's position and its validation either way.
  Widget _customSlide(ServiceDraft d, String id) {
    // Deferred to after this frame, for the same reason as the certificate load
    // below: the fetch opens with a setState, and calling it straight out of
    // build marks this widget dirty while the framework is still building it —
    // which throws in debug and leaves the picker spinning in release.
    if (id.startsWith('medicine_')) _ensureMedicinesLoaded();
    // The date a certificate carries is required, so a draft that has never been
    // given one is a draft the form can never advance past. It is seeded off this
    // slide rather than off the template load, so it still happens for the second
    // certificate of a visit - the load only ever runs once.
    if (id.startsWith('certificate_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _seedIssueDate(d);
      });
    }
    // Deferred to after this frame, because the certificate history load opens
    // with a setState and calling it from build would rebuild a widget
    // mid-build.
    if (id.startsWith('certificate_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureCertificate();
      });
    }
    return switch (id) {
      'medicine_picker' => _medicinePicker(d),
      'medicine_dosage' => _medicineDosage(d),
      'certificate_type' => _certificateType(d),
      'certificate_details' => _certificateDetails(d),
      'certificate_exam' => _certificateExam(d),
      'certificate_preview' => _certificatePreview(d),
      'bp_reading' => _bpReading(d),
      'bp_form' => _bpForm(d),
      'form_review' => _formReview(d),
      _ => _unbuiltSlide(id),
    };
  }

  // ── BLOOD PRESSURE ─────────────────────────────────────────────────────

  /// The reading this visit will be judged on, or null when there is not one.
  ///
  /// Asked of `vitals_interpretation.dart` rather than read off the boxes, so
  /// the two places the reading is shown cannot disagree about it. With repeat
  /// readings saved this is the average, which is what the nurse is looking at
  /// on the result card.
  BpResult? get _bpCurrent {
    final d = _c.active;
    if (d == null || d.serviceId != 'bp_tracking') return null;
    final raw = d.data['bp_readings'];
    final readings = raw is List
        ? [
            for (final r in raw)
              if (BpReading.fromJson(r) case final b?) b
          ]
        : const <BpReading>[];
    final avg = bpAverage(readings);
    if (avg != null) return interpretBP(avg.systolic, avg.diastolic);
    return interpretBP(d.text('systolic'), d.text('diastolic'));
  }

  Widget _bpReading(ServiceDraft d) {
    return BpReadingSlide(
      controller: _c,
      draft: d,
      onOpenGuide: _openBpGuide,
    );
  }

  /// The BP Taking Form, as the nurse reads it back before pressing Done.
  ///
  /// The date, the time, the visitor and the staff member are printed on the
  /// sheet rather than left to the strip above it, because a sheet that is meant
  /// to stand on its own once printed has to carry who it is about and who took
  /// it. The clock is read at the moment the sheet is built, so "Time Taken" is
  /// when the form was checked, not a value the nurse could get wrong.
  Widget _bpForm(ServiceDraft d) {
    final now = DateTime.now();
    return BpFormSlide(
      draft: d,
      assessment: _bpCurrent,
      visitorName: _v.fullName,
      visitorId: _orDash(_v.id),
      recordedDate: DateFormat('MMMM d, yyyy').format(now),
      recordedTime: DateFormat('h:mm a').format(now),
      recordedBy: widget.userName,
      serviceLabel: d.label,
    );
  }

  /// Opens the guide over the form area.
  ///
  /// Not a dialog: a dialog dims the screen and covers the reading it is
  /// explaining, so the nurse cannot check the two against each other — which is
  /// the only reason to open it.
  void _openBpGuide() {
    if (_guideOpen) return;
    setState(() => _guideOpen = true);
  }

  void _closeBpGuide() {
    if (!_guideOpen) return;
    setState(() => _guideOpen = false);
  }

  // ── THE READ-ONLY REVIEW SHEET ─────────────────────────────────────────

  /// The whole service printed back for the nurse to check before Done — the
  /// `form_review` slide that every service ends on, mirroring what BP Taking's
  /// own printed sheet does.
  ///
  /// Built from the spec rather than one hand-written sheet per service: the
  /// boxes the nurse answered decide what is on it, so it cannot drift from the
  /// form that produced it. A section per slide, a value per answered field,
  /// and the prescription as the rows were entered.
  ///
  /// The rows themselves come from [serviceSummary], which step 4 reads as well:
  /// one description of the record, drawn twice, rather than two descriptions
  /// that can quietly disagree.
  Widget _formReview(ServiceDraft d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        key: const ValueKey('form_review'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reviewTitle(d),
          const SizedBox(height: 10),
          for (final section in serviceSummary(d, _c.vitals)) ...[
            _reviewPanel(section.title, [
              for (final r in section.rows)
                r.label.isEmpty
                    ? _prose('•  ${r.value}')
                    : _labelledRow(r.label, r.value),
            ]),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _reviewTitle(ServiceDraft d) {
    return Row(
      children: [
        const Icon(Icons.receipt_long_outlined,
            size: 17, color: AppColors.textMain),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Review',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
        ),
        const Text(
          'Check before Done',
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _reviewPanel(String heading, List<Widget> lines) {
    return _panel(
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

  Widget _labelledRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  Widget _prose(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textMain, height: 1.35),
        ),
      );

  // ── CERTIFICATES ───────────────────────────────────────────────────────

  /// The document as it will be issued, or null while the templates load.
  ///
  /// Rebuilt from the controller each time it is asked for rather than cached,
  /// because the readings and the typed findings underneath it change as the
  /// nurse works, and a certificate preview that is a frame behind the form it
  /// is previewing is worse than none.
  DocumentDraft? get _docDraft {
    final med = _c.draftFor('medicine_certificate');
    final draft = buildCertificateDraft(
      template: _templateFor(_certificateTypeOf(med)),
      controller: _c,
      profile: _v,
      visitDate: _issueDate(med),
      issuedBy: widget.userName,
      history: _history,
    );
    // The examination findings and the staff's own lines are typed on these
    // slides, so they are read back out of the draft the nurse is editing. The
    // draft itself is rebuilt on every build, which is what keeps the preview
    // live as a vital is corrected on another service's form.
    if (med != null) {
      for (final key in [
        'recommendations',
        'excused_for',
        'clearance_status',
        'reason'
      ]) {
        final v = med.text(key).trim();
        if (v.isNotEmpty) draft.setOperator(key, v);
      }
      med.data.forEach((key, value) {
        if (key.startsWith('exam_') && '${value ?? ''}'.trim().isNotEmpty) {
          draft.setExam(key.substring(5), '$value');
        }
      });
    }
    return draft;
  }

  /// The date the certificate says it was issued: what was picked, or today.
  ///
  /// A document whose date is a consequence of when the screen was opened would
  /// be a document nobody can reproduce next term, so the picked date wins and
  /// the fallback is only ever today.
  DateTime _issueDate(ServiceDraft? d) {
    final picked = DateTime.tryParse(d?.text('issue_date').trim() ?? '');
    return picked ?? DateTime.now();
  }

  /// Puts today's date in the issue-date box the first time a certificate form
  /// is opened, so a nurse is not made to open a date picker to confirm the day
  /// the document is already dated.
  ///
  /// Seeded rather than merely defaulted: the field is required, and a document
  /// whose date is a consequence of when the screen happened to be opened is a
  /// document nobody can reproduce next term. The nurse changes it only when the
  /// certificate is for another day.
  void _seedIssueDate(ServiceDraft d) {
    if (d.text('issue_date').trim().isEmpty) {
      _c.setField(d.serviceId, 'issue_date', _isoOf(DateTime.now()));
      d.refreshStatus();
    }
  }

  /// Loads the visitor's own visit history once, because the Individual
  /// Clients Record — the certificate's annex — is generated from it. The
  /// document itself renders from the built-in templates; there is no template
  /// table in the database any more.
  Future<void> _ensureCertificate() async {
    if (_history.isNotEmpty || _loadingCertificate) return;
    setState(() => _loadingCertificate = true);
    var history = const <HistoryRow>[];
    try {
      history = await VisitDetailsService.historyFor(_v.id);
    } catch (_) {
      // An empty record is used instead; a certificate that cannot be rendered
      // because history is unreachable would be a worse outcome.
    }
    if (!mounted) return;
    setState(() {
      _history = history;
      _loadingCertificate = false;
    });
  }

  /// The template a document type prints on, falling back to the medical
  /// certificate — the one every clinic issues and the safest default when a
  /// type has no template.
  DocTemplate _templateFor(String type) =>
      DocTemplate.builtIns[type] ?? DocTemplate.medicalCertificate;

  String _certificateTypeOf(ServiceDraft? d) {
    final t = d?.text('doc_type').trim() ?? '';
    return t.isEmpty ? 'certificate' : t;
  }

  /// Which document to issue. The four the clinic prints, in the order they are
  /// used, so the common one is first and pre-selected.
  Widget _certificateType(ServiceDraft d) {
    final loading = _loadingCertificate;
    final options =
        <({String type, String label, IconData icon, String blurb})>[
      (
        type: 'certificate',
        label: 'Medical Certificate',
        icon: Icons.medical_information_outlined,
        blurb: 'Cleared or not cleared to participate.'
      ),
      (
        type: 'certification',
        label: 'Certification',
        icon: Icons.description_outlined,
        blurb: 'Excused from an activity for a period.'
      ),
      (
        type: 'clearance',
        label: 'Medical Clearance',
        icon: Icons.verified_user_outlined,
        blurb: 'Fit to participate, with restrictions.'
      ),
      (
        type: 'client_record',
        label: 'Individual Clients Record',
        icon: Icons.history_edu_outlined,
        blurb: 'The visitor’s whole clinic history.'
      ),
    ];
    final current = _certificateTypeOf(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Which document is being issued?',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'It fixes the wording, the signatories and the reference prefix. The preview is the last slide.',
          style: TextStyle(
              fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _optionRow(
                key: ValueKey('doc_type_${o.type}'),
                icon: o.icon,
                label: o.label,
                blurb: o.blurb,
                selected: current == o.type,
                onTap: () {
                  _c.setField(d.serviceId, 'doc_type', o.type);
                  setState(() {});
                },
              ),
            ),
      ],
    );
  }

  /// Who the document is for and why. The date is a picker rather than a
  /// free-text box, because a certificate dated with a typo is a certificate the
  /// clinic has to reissue.
  Widget _certificateDetails(ServiceDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _visitorCard(d),
        const SizedBox(height: 12),
        // The clearance status and the activity are the two words the certificate
        // is actually built around — every wording on the form turns on them —
        // so they are chosen from a list rather than typed, and neither can be
        // left blank. A certificate that says "found to be — to participate" is
        // not a certificate.
        _clearanceChoice(d),
        const SizedBox(height: 12),
        _field(
            d,
            const ServiceField(
              key: 'purpose',
              label: 'Activity / Event',
              kind: ServiceFieldKind.dropdown,
              required: true,
              hint: 'What they are being cleared for',
              options: [
                'Sports participation',
                'Intramurals',
                'Academic requirement',
                'Medical requirement',
                'Work immersion',
                'Other',
              ],
            )),
        const SizedBox(height: 12),
        _field(
            d,
            const ServiceField(
              key: 'reason',
              label: 'Reason / Purpose',
              kind: ServiceFieldKind.multiline,
              required: true,
              hint: 'What the document is for — e.g. Intramurals participation',
            )),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                  d,
                  const ServiceField(
                    key: 'issue_date',
                    label: 'Date Issued',
                    kind: ServiceFieldKind.date,
                    required: true,
                    hint: 'Today',
                  )),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _field(
                  d,
                  const ServiceField(
                    key: 'excused_for',
                    label: 'Excused For / Period',
                    kind: ServiceFieldKind.text,
                    hint: 'e.g. Intramurals, 2 days',
                    note: 'Only used by a Certification.',
                  )),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
            d,
            const ServiceField(
              key: 'recommendations',
              label: 'Recommendations',
              kind: ServiceFieldKind.multiline,
              hint: 'Optional — advice printed on the document',
            )),
      ],
    );
  }

  /// Cleared or not cleared, as the one decision a certificate exists to record.
  ///
  /// Two states rather than a list of six: "not cleared" needs a reason, which
  /// goes in the recommendation box, and splitting the negative into "fit for
  /// light duty" and "not fit for contact" on a paper certificate is a claim the
  /// form was never designed to make.
  Widget _clearanceChoice(ServiceDraft d) {
    const options = [
      ('Fit for participation', Icons.check_circle_outline_rounded),
      ('Not fit for participation', Icons.cancel_outlined),
    ];
    final current = d.text('clearance_status');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Is the visitor fit to participate?',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain),
            ),
            const Spacer(),
            Text(
              'Required',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: _naggedField == '${d.serviceId}/clearance_status'
                    ? AppColors.danger
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (i, o) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _optionRow(
                  key: ValueKey('clearance_$i'),
                  icon: o.$2,
                  label: o.$1,
                  blurb: o.$1.startsWith('Fit')
                      ? 'Cleared to take part, with any advice below.'
                      : 'Not cleared. Say why in the recommendations.',
                  selected: current == o.$1,
                  onTap: () {
                    _c.setField(d.serviceId, 'clearance_status', o.$1);
                    d.refreshStatus();
                    setState(
                        () => _naggedField = '${d.serviceId}/clearance_status');
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The visitor as the document will print them, read-only. A certificate that
  /// disagrees with the roster is worse than one that is slow, so nothing here
  /// can be edited — it comes from the person the step-1 search found.
  Widget _visitorCard(ServiceDraft d) {
    final v = _v;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _initialsAvatar(v, 18),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v.fullName,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain)),
                const SizedBox(height: 2),
                Text(
                  '${_orDash(v.id)}  ·  ${_orDash(v.sex)}  ·  ${_orDash(v.birthDate.isEmpty ? null : _prettyDate(v.birthDate))}',
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.textSub),
                ),
                const SizedBox(height: 2),
                Text(
                  _affiliation(v),
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          const Tooltip(
            message:
                'Taken from the visitor’s record. Edit it on Individual Record, not here.',
            child: Icon(Icons.lock_outline_rounded,
                size: 15, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// The thirteen physical-examination rows, in the order the paper form prints
  /// them. One free line each rather than a dropdown of findings, because a
  /// clinic writes "WNAR, well-nourished" in the box and no list of options
  /// contains what a clinician actually types.
  Widget _certificateExam(ServiceDraft d) {
    final draft = _docDraft;
    if (draft == null) return _loadingNotice();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'PHYSICAL EXAMINATION',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMain,
                ),
              ),
            ),
            Text('${kPhysicalExamRows.length} findings',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 3),
        const Text(
          'Printed in this order on the certificate. Blank is left blank — a row is a decision, not a default.',
          style:
              TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 10),
        for (final row in kPhysicalExamRows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _examRow(d, draft, row.key, row.label),
          ),
      ],
    );
  }

  Widget _examRow(
      ServiceDraft d, DocumentDraft draft, String key, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 172,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSub),
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            key: ValueKey('exam_$key'),
            initialValue: draft.examValue(key),
            onChanged: (v) {
              draft.setExam(key, v);
              // Written into the draft as well, so a nurse who goes back to
              // step 2 and returns has not lost the findings.
              _c.setField(d.serviceId, 'exam_$key', v);
            },
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMain),
            decoration: InputDecoration(
              isDense: true,
              hintText: '—',
              hintStyle:
                  const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: _inputBorder(AppColors.border),
              enabledBorder: _inputBorder(AppColors.border),
              focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  /// The last slide: the document as it will print, and the two buttons that
  /// turn it into something the visitor can be handed.
  Widget _certificatePreview(ServiceDraft d) {
    final draft = _docDraft;
    if (draft == null) return _loadingNotice();
    final rendered = draft.resolve();
    final blank = rendered.unfilled.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rendered.template.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain),
              ),
            ),
            Text('v${rendered.template.version}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 3),
        const Text(
          'Every filled line can still be corrected on the slide before this one.',
          style: TextStyle(
              fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 10),
        // The document itself, in a paper-coloured frame so it reads as a
        // separate artefact rather than as more of the form.
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PaperFormatPicker(
                paperKey: _paperKey,
                landscape: _landscape,
                onPaper: (key) => setState(() => _paperKey = key),
                onOrientation: (value) => setState(() => _landscape = value),
              ),
              SizedBox(
                height: 400,
                child: PdfPreview(
                  key: ValueKey('${_paperKey}_$_landscape'),
                  build: (_) => renderDocumentPdf(
                    rendered,
                    pageFormat: PaperFormat.formatFor(_paperKey, _landscape),
                  ),
                  initialPageFormat:
                      PaperFormat.formatFor(_paperKey, _landscape),
                  useActions: false,
                  canDebug: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (blank > 0)
          _notice(
            AppColors.warning,
            Icons.info_outline_rounded,
            '$blank placeholder${blank == 1 ? '' : 's'} on this template '
            '${blank == 1 ? 'has' : 'have'} nothing in them and will print as '
            '“—”. That is allowed; a blank line on a certificate is a decision.',
          )
        else
          _notice(
            AppColors.success,
            Icons.check_circle_outline_rounded,
            'Every line on this template is filled.',
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _printDocument(rendered),
                icon: const Icon(Icons.print_outlined, size: 17),
                label: const Text('Print',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMain,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _loadingNotice() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Future<void> _printDocument(RenderedDocument rendered) async {
    final bytes = await renderDocumentPdf(
      rendered,
      pageFormat: PaperFormat.formatFor(_paperKey, _landscape),
    );
    if (!mounted) return;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${rendered.template.name} - ${_v.fullName}',
    );
  }

  // ── MEDICINE PICKER ────────────────────────────────────────────────────

  /// Picking what was prescribed. The inventory is loaded the first time this
  /// slide is opened rather than with the rest of the step, because a visit
  /// that prescribes nothing should not pay for the request.
  Widget _medicinePicker(ServiceDraft d) {
    final loading = _medicines == null;
    final list = _medicines ?? const <Medicine>[];
    final pickable = list.where(VisitDetailsController.canPick).toList();
    // How many times each bottle has been added on this visit. A nurse reaching
    // for the same medicine twice is usually fixing a mistake, but sometimes is
    // genuinely prescribing two courses of it - and the only way to tell the two
    // apart is to see the count, so it is shown on the chip rather than only in
    // the total at the top.
    final timesPicked = <String, int>{};
    for (final m in d.medicines) {
      timesPicked[m.name] = (timesPicked[m.name] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Choose a medicine from the inventory',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
              ),
            ),
            if (d.medicines.isNotEmpty)
              Text('${d.medicines.length} added',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Nothing is deducted from stock here. That happens when the visit is completed.',
          style: TextStyle(
              fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 6),
        // The dosage boxes for what is already chosen, right here under the
        // shelf rather than one slide on. Picking a medicine and then having to
        // go and find it again to say how much of it is the reason nurses leave
        // the quantity blank, and a prescription with no quantity is not one the
        // pharmacy can fill.
        if (d.medicines.isNotEmpty) ...[
          for (int i = 0; i < d.medicines.length; i++) ...[
            _medicineRow(d, d.medicines[i], i),
            if (i < d.medicines.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (pickable.isEmpty)
          _notice(
            AppColors.warning,
            Icons.inventory_2_outlined,
            'No medicine in stock can be prescribed right now. Archived items and '
            'anything at zero are not offered.',
          )
        else
          Wrap(
            // Named so a test can press a chip on the shelf rather than a
            // prescription line that happens to carry the same drug's name.
            key: const ValueKey('medicine_shelf'),
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final m in pickable)
                _optionChip(
                  label: _medicineChipLabel(m, timesPicked[m.name] ?? 0),
                  // Filled, not outlined: the whole point of the request was
                  // that a chosen medicine should look chosen. An outline around
                  // a chip in a field of outlines is not a state anybody can
                  // read at a glance.
                  selected: (timesPicked[m.name] ?? 0) > 0,
                  onTap: () {
                    _c.addMedicine(m);
                    setState(() {});
                  },
                ),
            ],
          ),
      ],
    );
  }

  /// `Name · 12 in stock`, with the times-picked badge on the end.
  String _medicineChipLabel(Medicine m, int times) {
    final base = m.stock > 0 ? '${m.name}  ·  ${m.stock}' : m.name;
    return times > 1 ? '$base  ×$times' : base;
  }

  // ── MEDICINE DOSAGE ────────────────────────────────────────────────────

  /// How much, how often, and what to tell the patient — one row each, with the
  /// stock the row was picked against shown beside the quantity.
  ///
  /// The quantity box is the only place a nurse can be told their prescription
  /// cannot be filled, and it is told at the point of typing it rather than at
  /// the end of the visit, when it is too late to change it.
  Widget _medicineDosage(ServiceDraft d) {
    if (d.medicines.isEmpty) {
      return _notice(
        AppColors.textMuted,
        Icons.medication_outlined,
        'No medicine picked yet. Go back a slide and choose what is prescribed.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < d.medicines.length; i++) ...[
          _medicineRow(d, d.medicines[i], i),
          if (i < d.medicines.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _medicineRow(ServiceDraft d, MedicineDose m, int index) {
    final over = m.overdraw();
    return Container(
      // Named by its position on the visit, so a test can address one line of a
      // two-line prescription without depending on the drug's name - which is
      // exactly the thing a test about doses must not vary.
      key: ValueKey('medicine_row/$index'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: over > 0 ? AppColors.danger : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain),
                ),
              ),
              Text(
                '${m.stockAtPick} in stock',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () {
                  _c.removeMedicine(index);
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _inline(
                  'Quantity',
                  initial: '${m.quantity ?? ''}',
                  number: true,
                  onChanged: (v) {
                    m.quantity = VitalsInterpreter.parse(v)?.toInt();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _inline(
                  'Unit',
                  initial: m.unit,
                  hint: 'tablet',
                  onChanged: (v) {
                    m.unit = v;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _inline(
                  'Dose',
                  initial: m.dose,
                  hint: '1 tab',
                  onChanged: (v) {
                    m.dose = v;
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _inline(
                  'Frequency',
                  initial: m.frequency,
                  hint: 'twice a day',
                  onChanged: (v) {
                    m.frequency = v;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _actionPicker(m),
              ),
            ],
          ),
          if (m.action != 'Given' && m.action != 'Partially Given') ...[
            const SizedBox(height: 9),
            _inline(
              'Reason not given',
              initial: m.reasonNotGiven,
              hint: 'Why the medicine was not administered',
              onChanged: (v) {
                m.reasonNotGiven = v;
                setState(() {});
              },
            ),
          ],
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _inline(
                  'Response',
                  initial: m.response,
                  hint: 'How the patient responded',
                  onChanged: (v) {
                    m.response = v;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _inline(
                  'Notes',
                  initial: m.notes,
                  hint: 'Anything else about this medicine',
                  onChanged: (v) {
                    m.notes = v;
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          if (over > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$over more than the inventory holds. This cannot be filled today.',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A small labelled box inside a table row. These are not
  /// [ServiceField]s — a medicine row is data in a list, not part of the
  /// service's `data` map — so it cannot go through the declared-field path.
  ///
  /// The controller is created here and thrown away with the widget, which is
  /// safe for a row because a row is rebuilt whenever the list changes and a
  /// nurse typing into it is not typing for long enough to lose a frame's
  /// worth of characters. The declared fields, which are typed into for a
  /// whole slide, keep their controllers in [_texts] instead.
  Widget _inline(
    String label, {
    required String initial,
    required ValueChanged<String> onChanged,
    bool number = false,
    String hint = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: initial,
          onChanged: onChanged,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: false)
              : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.digitsOnly]
              : [LengthLimitingTextInputFormatter(200)],
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMain),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint.isEmpty ? null : hint,
            hintStyle:
                const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: _inputBorder(AppColors.border),
            enabledBorder: _inputBorder(AppColors.border),
            focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
          ),
        ),
      ],
    );
  }

  /// The label-and-box shape [_inline] draws, but as a choice list: what was
  /// done with this medicine. Only adminstered lines deduct stock at save time.
  Widget _actionPicker(MedicineDose m) {
    const options = [
      'Given',
      'Partially Given',
      'Not Given',
      'Held',
      'Refused'
    ];
    final safe = options.contains(m.action) ? options : [m.action, ...options];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Action',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: m.action.isEmpty ? null : m.action,
          isExpanded: true,
          hint: const Text('Given',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          items: [
            for (final o in safe)
              DropdownMenuItem(
                value: o,
                child: Text(o,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMain)),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            m.action = value;
            setState(() {});
          },
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: _inputBorder(AppColors.border),
            enabledBorder: _inputBorder(AppColors.border),
            focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
          ),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMain),
        ),
      ],
    );
  }

  /// A slide the description names but this file does not draw. Rendered rather
  /// than thrown, so a form can still be walked to the end and a nurse can see
  /// exactly which part of it is missing.
  Widget _unbuiltSlide(String id) {
    return _notice(
      AppColors.warning,
      Icons.construction_rounded,
      'This slide ("$id") is not on screen yet. Everything else on this form '
      'works; the rest of the visit can be recorded around it.',
    );
  }

  /// A wider row than the chips: an icon, a title, a line explaining what the
  /// option is for, and a tick. Used by the certificate type slide, where the
  /// options differ in what they *mean* and a bare label is not enough to
  /// choose between them.
  Widget _optionRow({
    required Key key,
    required IconData icon,
    required String label,
    required String blurb,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          key: key,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? AppColors.primaryDark : AppColors.textSub),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.primaryDeep
                            : AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      blurb,
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSub,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 17, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(Color color, IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSub, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Loads the inventory once, on the first visit to the picker.
  Future<void> _loadMedicines() async {
    if (_medicines != null || _loadingMedicines) return;
    setState(() => _loadingMedicines = true);
    try {
      final list = await MedicineService.fetchAll();
      if (!mounted) return;
      setState(() => _medicines = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _medicines = const <Medicine>[]);
    } finally {
      if (mounted) setState(() => _loadingMedicines = false);
    }
  }

  // ── SMALL UTILITIES ────────────────────────────────────────────────────

  String _orDash(String? value) =>
      (value == null || value.trim().isEmpty) ? '—' : value.trim();

  DateTime? _parseIso(String iso) {
    if (iso.trim().isEmpty) return null;
    return DateTime.tryParse(iso.trim());
  }

  String _isoOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _prettyDate(String iso) {
    final d = _parseIso(iso);
    return d == null ? iso : DateFormat('MMM d, yyyy').format(d);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        // Clears the footer's button bar, which is pinned to the bottom of the
        // form card. A nag about a box that has to be filled in arrives exactly
        // when the nurse is reaching for Next, and a message lying across Next
        // means she can only wait for it to go away.
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 52),
      ));
  }
}

/// The "auto" tag on a box the nurse does not type into.
class _AutoTag extends StatelessWidget {
  const _AutoTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'auto',
        style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSub),
      ),
    );
  }
}

/// The sheet behind `+ Add New Service`.
///
/// The catalogue comes from [ClinicPurposes] — the same list step 2 draws — so
/// a service that cannot be ticked on step 2 cannot be quietly added here
/// either, and one already on the visit is shown as taken rather than hidden,
/// because a list that silently drops things is worse than a greyed row.
///
/// Every row is tappable in both directions. It used to disable the ones already
/// taken and say so in the subtitle, and pointed the nurse at step 2 to undo a
/// mistake — while this very sheet is how a mistake gets made, on a step the
/// nurse is told she can add services from. A control that can add but not
/// remove is half a control.
class _AddServiceSheet extends StatelessWidget {
  const _AddServiceSheet({
    required this.taken,
    required this.onPick,
    required this.onUnpick,
  });

  final Set<String> taken;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onUnpick;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Services on this visit',
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain),
          ),
          const SizedBox(height: 3),
          const Text(
            'Tap a service to add it, or to take it back off this visit.',
            style: TextStyle(fontSize: 12, color: AppColors.textSub),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // Reordered so Vital Signs first, BP Taking next, then rest
                for (final id in const [
                  'vital_signs',
                  'bp_tracking',
                  'temperature_checking',
                  'bpi',
                  'wound_dressing',
                  'first_aid_treatment',
                  'health_counselling',
                  'prenatal',
                  'medication',
                  'medicine_consultation',
                  'medicine_certificate',
                  'medical_clearance',
                ])
                  _row(context, ClinicPurposes.byId(id)!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ClinicPurpose p) {
    final already = taken.contains(p.id);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(p.icon,
          size: 18, color: already ? AppColors.success : AppColors.primary),
      title: Text(
        p.label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: already ? AppColors.textMain : AppColors.textMain,
        ),
      ),
      subtitle: Text(
        already ? 'On this visit — tap to remove' : 'Tap to add',
        style: TextStyle(
          fontSize: 11.5,
          color: already ? AppColors.success : AppColors.textMuted,
        ),
      ),
      trailing: Icon(
        already ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
        size: 18,
        color: already ? AppColors.success : AppColors.textMuted,
      ),
      onTap: () => already ? onUnpick(p.id) : onPick(p.id),
    );
  }
}
