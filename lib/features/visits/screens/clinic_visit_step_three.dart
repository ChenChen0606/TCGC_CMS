import 'package:clinicmanagementsystem/shared/widgets/simple_print_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/features/visits/models/clinic_purposes.dart';
import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_summary.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
import 'package:clinicmanagementsystem/features/certificates/services/signatory_store.dart';
import 'package:clinicmanagementsystem/core/services/time_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

import 'package:clinicmanagementsystem/shared/printing/print_service.dart';

class StepThreeNav {
  const StepThreeNav({
    required this.onBack,
    required this.onContinue,
    required this.continueLabel,
    this.continueEnabled = true,
    this.saving = false,
  });

  final VoidCallback onBack;

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
    this.visitStamp,
    this.nav,
    this.onServiceAdded,
    this.onServiceRemoved,
  });

  final VisitDetailsController controller;

  final ClinicProfile visitor;
  final String userName;

  final DateTime? visitStamp;

  final StepThreeNav? nav;

  final void Function(String serviceId)? onServiceAdded;

  final void Function(String serviceId)? onServiceRemoved;

  @override
  State<ClinicVisitStepThree> createState() => _ClinicVisitStepThreeState();
}

class _ClinicVisitStepThreeState extends State<ClinicVisitStepThree> {
  final Map<String, TextEditingController> _texts = {};

  String? _naggedField;

  bool _showAllErrors = false;
  String? _showAllErrorsFor;

  List<Medicine>? _medicines;
  bool _loadingMedicines = false;

  bool _medicinesLoadQueued = false;

  List<String>? _staffNames;

  bool _staffLoadQueued = false;

  List<Visit> _visitOptions = const [];
  bool _loadingVisitOptions = false;
  String _visitOptionsFor = '';

  bool _signatorySeeded = false;

  List<AppProfile> _clinicHeads = const [];
  bool _loadingClinicHeads = false;

  bool _clinicHeadsAttempted = false;

  static const ServiceField _certIssuedField = ServiceField(
    key: 'cert_issued_on',
    label: 'Issuance Date',
    kind: ServiceFieldKind.date,
    hint: 'Today',
    datePast: true,
  );

  static const ServiceField _certReasonField = ServiceField(
    key: 'reason',
    label: 'Reason for visit',
    kind: ServiceFieldKind.multiline,
    hint: 'Refilled from the visit you pick',
    maxChars: 300,
  );

  static const ServiceField _certExcusedField = ServiceField(
    key: 'excused_for',
    label: 'Excuse / Purpose Details',
    kind: ServiceFieldKind.multiline,
    hint: 'Enter the details to appear in the certification..',
    maxChars: 500,
    note: 'Everything you type here is printed on the certificate, in the '
        'words you wrote.',
  );

  static const ServiceField _certSignatoryField = ServiceField(
    key: 'cert_signatory_name',
    label: 'Name',
    kind: ServiceFieldKind.text,
    hint: 'Name of the clinic head',
  );

  static const ServiceField _certAutoField = ServiceField(
    key: 'cert_auto',
    label: '',
    kind: ServiceFieldKind.readOnly,
  );

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

  TextEditingController _textFor(ServiceDraft d, ServiceField f) {
    final key = '${d.serviceId}/${f.key}';
    final value = d.text(f.key);
    final existing = _texts[key];
    if (existing == null) {
      final created = TextEditingController(text: value);
      _texts[key] = created;
      return created;
    }
    if (existing.text != value) {
      // Don't wipe "27." or "27.0" while the user is still typing.
      final numeric = RegExp(r'^\d*\.?\d*$');
      final typed = double.tryParse(existing.text);
      final stored = double.tryParse(value);
      final sameNumber = numeric.hasMatch(existing.text) &&
          typed != null &&
          stored != null &&
          typed == stored;
      if (!sameNumber) existing.text = value;
    }
    return existing;
  }

  void _onText(ServiceDraft d, ServiceField f, String value) {
    if (f.vital != null) {
      _c.setVital(f.vital!, value, fromServiceId: d.serviceId);
    } else {
      _c.setField(d.serviceId, f.key, value);
    }
    _naggedField = '${d.serviceId}/${f.key}';
    _autoCompleteIfValid(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: const <ShortcutActivator, VoidCallback>{},
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
           _c.vitals.setSubject(
            sex: _v.sex,
            birthDate: DateTime.tryParse(_v.birthDate),
            asOf: widget.visitStamp ?? DateTime.now(),
          );
          final draft = _c.active;

          if (_showAllErrorsFor != draft?.serviceId) {
            _showAllErrorsFor = draft?.serviceId;
            _showAllErrors = false;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }

  Widget _visitorBlock() {
    final v = _v;
    final now = widget.visitStamp ?? DateTime.now();
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

  Widget _serviceList() {
    final drafts = _c.drafts;
    return _panel(
      key: const ValueKey('step3/services_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                const SizedBox(width: 2),
                _removeServiceButton(d),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _formCard(ServiceDraft d) {
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
        ],
      ),
    );
  }

  bool _keepsSlides(ServiceDraft d) => false;

  Widget _formBody(ServiceDraft d) {
    final sections = [
      for (final s in d.spec.slides)
        if (s.custom?.id != 'form_review' && s.custom?.id != 'bp_form') s,
    ];
    final banners = _referralBanner(d);
    return SingleChildScrollView(
      key: const ValueKey('step3/form_body'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...banners,
          if (banners.isNotEmpty) const SizedBox(height: 14),
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _section(d, i, sections[i]),
          ],
        ],
      ),
    );
  }

  List<Widget> _referralBanner(ServiceDraft d) {
    final reasons =
        d.spec.referralReasons?.call(d.data, _c.vitals) ?? const <String>[];
    final warnings =
        d.spec.warnings?.call(d.data, _c.vitals) ?? const <String>[];
    if (reasons.isEmpty && warnings.isEmpty) return const [];
    return [
      if (reasons.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_hospital_outlined,
                  size: 18, color: AppColors.danger),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.spec.referralTitle ?? 'Refer to doctor / hospital.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reasons.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      for (var i = 0; i < warnings.length; i++) ...[
        if (i > 0 || reasons.isNotEmpty) const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  warnings[i],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

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
            inProgress: isBp
                ? (const Color(0xFF1D4ED8), const Color(0xFFDBEAFE))
                : null,
          ),
        ],
      ),
    );
  }

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

  List<Widget> _fieldGrid(
      ServiceDraft d, List<ServiceField> fields, List<FieldGroup> groups) {
    final startsHere = <int, FieldGroup>{};
    for (final g in groups) {
      for (var i = 0; i < fields.length; i++) {
        if (g.holds(fields[i].key)) {
          startsHere[i] = g;
          break;
        }
      }
    }

    final drawnInACard = <String>{};

    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(w);
    }

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

  Widget _groupCard(ServiceDraft d, List<ServiceField> group) {
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

  Widget _field(ServiceDraft d, ServiceField f) {
    final key = '${d.serviceId}/${f.key}';
    final tint = _requiredTint(d, f);
    Widget input = _fieldInput(d, f, key);
    if (tint != null && _isGroupField(f.kind)) {
      input = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tint, width: 1.2),
        ),
        child: input,
      );
    }
    final otherBox = _otherBox(d, f);
    final children = <Widget>[
      _fieldLabel(d, f, key),
      const SizedBox(height: 5),
      input,
      if (otherBox != null) ...[
        const SizedBox(height: 7),
        otherBox,
      ],
    ];
    final error = _fieldError(d, f, key);
    if (error != null) {
      children.add(const SizedBox(height: 4));
      children.add(Text(
        error,
        key: ValueKey('field/$key/error'),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.danger,
            height: 1.3),
      ));
    }
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
      key: ValueKey('field/$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  bool _otherPicked(ServiceDraft d, ServiceField f) {
    if (!d.spec.offersOther(f) || f.allowCustomEntries) return false;
    final v = d.data[f.key];
    return v is List
        ? v.any((e) => '$e' == kOtherLabel)
        : '${v ?? ''}' == kOtherLabel;
  }

  /// Opens when "Other" is picked. Red until something is typed. What is
  /// typed is saved in the same record as the other answers.
  Widget? _otherBox(ServiceDraft d, ServiceField f) {
    if (!_otherPicked(d, f)) return null;
    final box = ServiceField(
      key: f.otherFieldKey,
      label: 'Other',
      kind: ServiceFieldKind.text,
      maxChars: 100,
    );
    final controller = _textFor(d, box);
    final empty = controller.text.trim().isEmpty;
    final line = empty ? AppColors.danger : AppColors.border;
    return Column(
      key: ValueKey('field/${d.serviceId}/${f.otherFieldKey}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          autofocus: empty,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          onChanged: (value) => _onText(d, box, value),
          style: const TextStyle(fontSize: 13, color: AppColors.textMain),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: empty
                ? AppColors.danger.withValues(alpha: 0.06)
                : AppColors.surface,
            hintText: 'Type the other answer',
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.textMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: _inputBorder(line, width: 1.5),
            enabledBorder: _inputBorder(line, width: 1.5),
            focusedBorder:
                _inputBorder(empty ? AppColors.danger : AppColors.primary,
                    width: 1.5),
          ),
        ),
        if (empty)
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text(
              'Please type what \u201COther\u201D is.',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger),
            ),
          ),
      ],
    );
  }

  String? _fieldError(ServiceDraft d, ServiceField f, String key) {
    final own = d.spec.validateInContext(f.key, d.data);
    if (own != null) return own;
    if (!f.isRequiredIn(d.data) || _isAnswered(d, f.key)) return null;
    if (_showAllErrors || _naggedField == key) return '${f.label} needs a valid answer.';
    return null;
  }

  Color? _requiredTint(ServiceDraft d, ServiceField f) {
    // Red only when a typed answer is not allowed.
    if (f.isRequiredIn(d.data) && !_isAnswered(d, f.key)) {
      return AppColors.danger;
    }
    // Green hint for a suggested box that is still empty. Never blocks.
    if (!f.isSuggestedIn(d.data)) return null;
    if (_isAnswered(d, f.key)) return null;
    return AppColors.primary;
  }

  static bool _isGroupField(ServiceFieldKind kind) =>
      kind == ServiceFieldKind.chips ||
      kind == ServiceFieldKind.multiselect ||
      kind == ServiceFieldKind.checkboxes ||
      kind == ServiceFieldKind.inventoryPick;

  Widget _fieldLabel(ServiceDraft d, ServiceField f, String key) {
    final wrong = f.isRequiredIn(d.data) && !_isAnswered(d, f.key);
    final owed = wrong || (f.isSuggestedIn(d.data) && !_isAnswered(d, f.key));
    final missing = wrong;
    return Row(
      children: [
        Flexible(
          child: Text(
            f.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: missing ? AppColors.danger : AppColors.textSub,
            ),
          ),
        ),
        if (d.isAutoFilled(f.key))
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: _AutoTag(),
          ),
        if (owed)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              '*',
              style: TextStyle(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        if (owed)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              missing ? 'please check' : 'suggested',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: missing ? AppColors.danger : AppColors.primary,
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
        ServiceFieldKind.vitalsCard => _vitalsCard(d),
        ServiceFieldKind.medicationCard => _medicationCard(d),
        ServiceFieldKind.staffName => _staffNameBox(d, f, key),
        ServiceFieldKind.inventoryPick => _inventoryPickBox(d, f, key),
        ServiceFieldKind.linkServiceCard => _linkServiceCard(d, f),
        ServiceFieldKind.notice => _noticeBox(d, f),
      };

  Widget _noticeBox(ServiceDraft d, ServiceField f) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 15, color: AppColors.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only the Clinic Head and Clinic Staff can see Restricted '
              'records.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          decoration: _decoration(f, filled: true, tint: _requiredTint(d, f)),
        ),
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
            decoration: _decoration(f, filled: true, tint: _requiredTint(d, f)),
          ),
        ),
        const SizedBox(width: 6),
        _staffMenu(f, others),
      ],
    );
  }

  Widget _staffMenu(ServiceField f, List<String> names) {
    return PopupMenuButton<String>(
      key: ValueKey('field/${f.key}/menu'),
      tooltip: 'Someone else did this',
      onSelected: (name) {
        final d = _c.active;
        if (d == null) return;
        _c.setField(d.serviceId, f.key, name);
        _naggedField = f.key;
        _autoCompleteIfValid(d);
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
        } catch (_) {}
      });
    }
    return const [];
  }

  Widget _inventoryPickBox(ServiceDraft d, ServiceField f, String key) {
    _ensureMedicinesLoaded();
    final chosen = d.chosen(f.key);
    final loading = _medicines == null;
    final list = _medicines ?? const <Medicine>[];
    final pickable = list.where(VisitDetailsController.canPick).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
                  onTap: () {
                    _toggleInventoryPick(d, f, name);
                    _autoCompleteIfValid(d);
                  },
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
                  onTap: () {
                    _toggleInventoryPick(d, f, m.name);
                    _autoCompleteIfValid(d);
                  },
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

  Widget _inventoryEscapeHatch(ServiceDraft d, ServiceField f) {
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
    _autoCompleteIfValid(d);
    setState(() {});
  }

  void _toggleInventoryPick(ServiceDraft d, ServiceField f, String name) {
    final current = d.chosen(f.key).toList();
    if (!current.remove(name)) current.add(name);
    _c.setField(d.serviceId, f.key, current);
    _naggedField = f.key;
    _autoCompleteIfValid(d);
    setState(() {});
  }

  void _ensureMedicinesLoaded() {
    if (_medicines != null || _loadingMedicines || _medicinesLoadQueued) return;
    _medicinesLoadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _medicinesLoadQueued = false;
      if (!mounted) return;
      _loadMedicines();
    });
  }

  Widget _numberBox(ServiceDraft d, ServiceField f, String key) {
    final controller = _textFor(d, f);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
      ],
      onChanged: (value) => _onText(d, f, value),
      style: const TextStyle(fontSize: 13, color: AppColors.textMain),
      decoration:
          _decoration(f, filled: true, unit: f.unit, tint: _requiredTint(d, f)),
    );
  }

  Widget _bandPill(VitalReading r, {bool showValue = false}) {
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
              showValue
                  ? '${r.label}  ${r.display}'
                  : (r.category ?? r.band.label),
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownBox(ServiceDraft d, ServiceField f, String key) {
    final options = d.spec.optionsFor(f, d.data);
    final current = d.text(f.key);

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
            child: Text(optionLabel(o),
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textMain)),
          ),
      ],
      onChanged: (value) {
        _c.setField(d.serviceId, f.key, value);
        _naggedField = key;
        _autoCompleteIfValid(d);
        setState(() {});
      },
      decoration: _decoration(f, tint: _requiredTint(d, f)),
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      style: const TextStyle(fontSize: 13, color: AppColors.textMain),
    );
  }

  Widget _chipBox(ServiceDraft d, ServiceField f, String key) {
    final chosen = d.chosen(f.key);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final o in d.spec.optionsFor(f, d.data))
          _optionChip(
            label: optionLabel(o),
            selected: chosen.contains(o),
            onTap: () {
              _c.toggleChoice(d.serviceId, f.key, o);
              _naggedField = key;
              _autoCompleteIfValid(d);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _singleChipBox(ServiceDraft d, ServiceField f, String key) {
    final chosen = d.chosen(f.key);

    final lockedRestricted = f.key == 'privacy_level' &&
        chosen.contains('Restricted') &&
        counsellingAutoRestricted(d.data);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final o in d.spec.optionsFor(f, d.data))
          _optionChip(
            label: optionLabel(o),
            selected: chosen.contains(o),
            onTap: (lockedRestricted && o == 'Normal')
                ? () {}
                : () {
                    if (chosen.contains(o)) {
                      _c.setField(d.serviceId, f.key, <String>[]);
                    } else {
                      _c.toggleChoice(d.serviceId, f.key, o, max: 1);
                    }
                    _naggedField = key;
                    _autoCompleteIfValid(d);
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

    final shown = d.spec.optionsFor(f, d.data);
    final custom = [
      for (final c in chosen)
        if (!shown.contains(c)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 340 ? 2 : 1;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: 2,
              children: [
                for (final o in shown)
                  SizedBox(
                    width: itemWidth,
                    child: _checkRow(
                      label: optionLabel(o),
                      checked: chosen.contains(o),
                      onTap: () {
                        if (f.key == kVitalsSelectedKey) {
                          _toggleVitalChoice(d, f, o, key);
                          return;
                        }
                        _c.toggleChoice(d.serviceId, f.key, o);
                        _naggedField = key;
                        _autoCompleteIfValid(d);
                        setState(() {});
                      },
                    ),
                  ),
                for (final c in custom)
                  SizedBox(
                    width: itemWidth,
                    child: _checkRow(
                      label: c,
                      checked: true,
                      onTap: () {
                        _c.toggleChoice(d.serviceId, f.key, c);
                        _autoCompleteIfValid(d);
                        setState(() {});
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        if (f.allowCustomEntries && chosen.contains('Other')) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _customTextFor(d, f),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.fieldFill,
                      hintText: 'Type anything else',
                      hintStyle: const TextStyle(
                          fontSize: 12.5, color: AppColors.textMuted),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: _inputBorder(AppColors.border),
                      enabledBorder: _inputBorder(AppColors.border),
                      focusedBorder:
                          _inputBorder(AppColors.primary, width: 1.5),
                    ),
                    onSubmitted: (_) => _addCustomEntry(d, f),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _addCustomEntry(d, f),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('Add',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  TextEditingController _customTextFor(ServiceDraft d, ServiceField f) {
    final key = '${d.serviceId}/${f.key}#custom';
    return _texts.putIfAbsent(key, () => TextEditingController());
  }

    void _toggleVitalChoice(
      ServiceDraft d, ServiceField f, String option, String key) {
    final current = d.chosen(f.key).toSet();
    final all = kVitalChoiceKeys.keys.toSet();
    Set<String> next;
    if (option == kSelectAllLabel) {
      next = all.every(current.contains) ? <String>{} : all;
    } else {
      next = {...current}..remove(kSelectAllLabel);
      if (!next.remove(option)) next.add(option);
    }
    _c.setVitalSelection(d.serviceId, next);
    _naggedField = key;
    _autoCompleteIfValid(d);
    setState(() {});
  }
  
  void _addCustomEntry(ServiceDraft d, ServiceField f) {
    final box = _customTextFor(d, f);
    final typed = box.text.trim();
    if (typed.isEmpty) {
      _toast('Type what you want to add first.');
      return;
    }
    final current = d.chosen(f.key).toList();
    if (!current.any((n) => n.toLowerCase() == typed.toLowerCase())) {
      _c.toggleChoice(d.serviceId, f.key, typed);
    }
    box.clear();
    _autoCompleteIfValid(d);
    setState(() {});
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
        _autoCompleteIfValid(d);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(9),
      child: InputDecorator(
        decoration: _decoration(f, filled: true, tint: _requiredTint(d, f)),
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

  Widget _readOnlyBox(ServiceDraft d, ServiceField f, String key) {
    final reading = _autoReading(f);
    return InputDecorator(
      decoration: _decoration(f, filled: true).copyWith(
        fillColor: AppColors.fieldFillDisabled,
        suffixIcon: const Padding(
          padding: EdgeInsets.only(right: 10),
          child: _AutoTag(),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      child: reading != null
          ? Align(
              alignment: Alignment.centerLeft,
              child: _bandPill(reading, showValue: f.key == 'bmi'),
            )
          : Text(
              _autoValue(d, f),
              style: const TextStyle(fontSize: 13, color: AppColors.textMain),
            ),
    );
  }

  VitalReading? _autoReading(ServiceField f) => switch (f.key) {
        'bmi' || 'bmi_class' => _c.vitals.bmiReading,
        'temp_assessment' => _c.vitals.tempReading,
        'bp_assessment' => _c.vitals.bloodPressure,
        'pulse_assessment' => _c.vitals.heartRateReading,
        'resp_assessment' => _c.vitals.respRateReading,
        'spo2_assessment' => _c.vitals.o2Reading,
        _ => null,
      };

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

  String _autoValue(ServiceDraft d, ServiceField f) {
    switch (f.key) {
      case 'bmi':
        final bmi = _c.vitals.bmi;
        return bmi == null ? '—' : bmi.toStringAsFixed(1);
      case 'bmi_class':
                return _c.vitals.bmiReading?.category ??
            _c.vitals.bmiBlockReason ??
            '—';
      case 'temp_assessment':
        return _c.vitals.tempReading?.category ?? '—';
      case 'bp_assessment':
        return _c.vitals.bloodPressure?.category ?? '—';
      case 'pulse_assessment':
        return _c.vitals.heartRateReading?.category ?? '—';
      case 'resp_assessment':
        return _c.vitals.respRateReading?.category ?? '—';
      case 'spo2_assessment':
        return _c.vitals.o2Reading?.category ?? '—';
      case 'aog':
        final lmp = _parseIso(d.text('lmp'));
        if (lmp == null) return '—';
        final days = DateTime.now().difference(lmp).inDays;
        if (days < 0) return '—';
        return '${days ~/ 7}w ${days % 7}d';
      case 'edd':
        return _dueDate(d) ?? '—';
      case 'session_date':
        final raw = d.text('session_date').trim();
        final when = _parseIso(raw);
        if (when == null) return raw.isEmpty ? '—' : raw;
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final h = when.hour % 12 == 0 ? 12 : when.hour % 12;
        final minute = when.minute.toString().padLeft(2, '0');
        final meridiem = when.hour < 12 ? 'AM' : 'PM';
        return '${when.day} ${months[when.month - 1]} ${when.year}, '
            '$h:$minute $meridiem';
      default:
        return d.text(f.key).isEmpty ? '—' : d.text(f.key);
    }
  }

  Widget _formFooter(ServiceDraft d,
      {bool navOnly = false, bool slides = false}) {
    final nav = widget.nav;

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
            if (d.spec.slides.length > 1) _slideDots(d, d.spec.slides.length),
            Text(
              'Slide ${d.slidePosition}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSub),
            ),
            const SizedBox(width: 10),
            if (canGoBack) ...[
              _footerButton(
                label: '‹ Prev',
                onPressed: () => setState(() => _c.previousSlideOrService()),
              ),
              const SizedBox(width: 6),
            ],
            _footerButton(
              label: d.isLastSlide ? 'Next ›' : 'Next ›',
              filled: true,
              onPressed: d.isLastSlide
                  ? () => _goToNextSlide(d)
                  : () => _goToNextSlide(d),
            ),
          ] else if (!navOnly)
            ...[],
          const Spacer(),
          if (nav != null) ...[
            _footerButton(label: 'Back', onPressed: nav.onBack),
            const SizedBox(width: 8),
            if (nav.saving)
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
                onPressed: nav.continueEnabled
                    ? (() {
                        if (_c.active?.serviceId == 'prenatal' &&
                            _c.vitals.bloodPressure == null) {
                          _toast(
                              'Record the blood pressure in Vital Signs before continuing.');
                          return;
                        }
                        if (!_readyToLeave(_c.active)) return;
                        nav.onContinue?.call();
                      })
                    : null,
              ),
          ],
        ],
      ),
    );
  }

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

  void _goToNextSlide(ServiceDraft d) {
    final missing = d.missingOnCurrentSlide();
    if (missing.isNotEmpty) {
      setState(() => _naggedField = '${d.serviceId}/${missing.first}');
      _toast('Please correct the red box to continue.');
      return;
    }
    setState(() => _c.nextSlide());
  }

  bool _readyToLeave(ServiceDraft? d) {
    if (d == null) return true;
        if (d.serviceId == 'bpi') {
      final why = _c.vitals.bmiBlockReason;
      if (why != null) {
        _toast(why);
        return false;
      }
    }
    if (_firstAidVitalsMissing()) {
      _toast('Tip: vital signs are not taken yet. You can still continue.');
    }
    final missing =
        d.spec.requiredKeysIn(d.data).where((k) => !_isAnswered(d, k)).toList();
    if (missing.isEmpty) {
      if (_showAllErrors) setState(() => _showAllErrors = false);
      return true;
    }

    setState(() {
      _showAllErrors = true;
      _naggedField = '${d.serviceId}/${missing.first}';
    });
    _toast('Please correct the red box to continue.');
    return false;
  }

  bool _firstAidVitalsMissing() {
    final d = _c.active;
    if (d == null || d.serviceId != 'first_aid_treatment') return false;
    final incident = '${d.data['incident'] ?? ''}'.trim();
    if (!const ['Fainting', 'Dizziness', 'Head Injury'].contains(incident)) {
      return false;
    }
    return _c.vitals.systolic == null ||
        _c.vitals.diastolic == null ||
        _c.vitals.heartRate == null;
  }

  bool _isAnswered(ServiceDraft d, String key) {
    if (key == 'medicine_name') return d.medicines.isNotEmpty;
    final v = d.data[key];
    final empty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty);
    if (empty || d.spec.validate(key, v) != null) return false;
    for (final g in d.spec.fields) {
      if (g.shownWhenKey != key) continue;
      if (g.isSuggestedIn(d.data) && !_isAnswered(d, g.key)) return false;
    }
    return true;
  }

  void _autoCompleteIfValid(ServiceDraft d) {
    final missing =
        d.spec.requiredKeysIn(d.data).where((k) => !_isAnswered(d, k)).toList();
    if (missing.isEmpty && d.status != ServiceDraftStatus.completed) {
      d.refreshStatus();
      d.dirty = false;
    }
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
      {bool filled = false, String? unit, Color? tint}) {
    final line = tint ?? AppColors.border;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: filled ? AppColors.fieldFill : AppColors.surface,
      hintText: _hintOf(f),
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      suffixText: unit == null || unit.isEmpty ? null : unit,
      suffixStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      border: _inputBorder(line, width: tint == null ? 1 : 1.5),
      enabledBorder: _inputBorder(line, width: tint == null ? 1 : 1.5),
      focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  String _hintOf(ServiceField f) {
    final own = f.hint?.trim();
    if (own != null && own.isNotEmpty) return own;
    switch (f.kind) {
      case ServiceFieldKind.dropdown:
      case ServiceFieldKind.chips:
        return f.options.isEmpty
            ? 'Choose one'
            : 'e.g. ${optionLabel(f.options.first)}';
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
      case ServiceFieldKind.vitalsCard:
      case ServiceFieldKind.medicationCard:
      case ServiceFieldKind.readOnly:
      case ServiceFieldKind.staffName:
      case ServiceFieldKind.inventoryPick:
      case ServiceFieldKind.linkServiceCard:
      case ServiceFieldKind.notice:
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

  String? _dueDate(ServiceDraft d) {
    final lmp = _parseIso(d.text('lmp'));
    if (lmp == null) return null;
    return _prettyDate(
      _isoOf(lmp.add(const Duration(days: VisitServiceForms.pregnancyDays))),
    );
  }

  void _showAddServiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddServiceSheet(
        taken: _c.drafts.map((d) => d.serviceId).toSet(),
        onPick: (id) {
          Navigator.of(context).pop();

          setState(() => _c.addService(id));

          widget.onServiceAdded?.call(id);
        },
        onUnpick: (id) {
          Navigator.of(context).pop();
          setState(() => _c.removeService(id));

          widget.onServiceRemoved?.call(id);
          _toast('${_labelOf(id)} removed from this visit.');
        },
      ),
    );
  }

  Widget _customSlide(ServiceDraft d, String id) {
    if (id.startsWith('medicine_')) _ensureMedicinesLoaded();
    if (id.startsWith('certificate_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureVisitOptions(d);
        _ensureSignatory(d);
      });
    }
    return switch (id) {
      'medicine_picker' => _medicinePicker(d),
      'medicine_dosage' => _medicineDosage(d),
      'certificate_sheet' => _certificateSheet(d),
      'form_review' => _formReview(d),
      _ => _unbuiltSlide(id),
    };
  }

  Widget _formReview(ServiceDraft d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        key: const ValueKey('form_review'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reviewTitle(d),
          const SizedBox(height: 10),
          for (final section in serviceSummary(d, _c.vitals,
              canSeeRestricted:
                  AccountService.canSeeRestrictedCounselling)) ...[
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

  DocumentDraft? get _docDraft {
    final med = _c.draftFor('medicine_certificate');
    final visit = _selectedVisit(med);
    final savedSignatory = (med?.text('cert_signatory_name') ?? '').trim();
    return buildCertificateDraft(
      template: DocTemplate.medicalCertificate,
      controller: _c,
      profile: _v,
      clinicVisitDate: visit?.visitDate,
      issuedOn: _issuedOn(med),
      visitReason: _visitReasonOf(visit),
      issuedBy: widget.userName,
      signatoryName:
          savedSignatory.isEmpty ? SignatoryStore.defaultName : savedSignatory,
      signatoryRole: SignatoryStore.defaultRole,
    );
  }

  DateTime _issuedOn(ServiceDraft? med) =>
      _parseIso((med?.text('cert_issued_on') ?? '').trim()) ?? DateTime.now();

  String _visitReasonOf(Visit? v) {
    if (v == null) return '';
    return v.reasonForVisit.isNotEmpty ? v.reasonForVisit : v.complaint;
  }

  Visit? _selectedVisit(ServiceDraft? d) {
    final vid = d?.text('cert_visit_id').trim() ?? '';
    if (vid.isEmpty) return null;
    for (final v in _visitOptions) {
      if (v.id == vid) return v;
    }
    return null;
  }

  Future<void> _ensureVisitOptions(ServiceDraft d) async {
    final personId = _v.id;
    if (_loadingVisitOptions || _visitOptionsFor == personId) return;
    setState(() {
      _loadingVisitOptions = true;
      _visitOptionsFor = personId;
      _visitOptions = const [];
    });
    List<Visit> options = const [];
    try {
      final fetched = await VisitService.fetchByPatient(personId);
      final serverNow = await TimeService.serverNow();
      options = fetched
          .where((v) => v.visitDate?.year == serverNow.year)
          .toList(growable: false);
    } catch (_) {
      options = const [];
    }
    if (!mounted) return;
    setState(() {
      _visitOptions = options;
      _loadingVisitOptions = false;
    });
    final chosen = _defaultVisit(options);
    if (chosen != null) {
      _pickCertificateVisit(d, chosen);
    } else {
      _c.setField(d.serviceId, 'cert_visit_id', '');
      d.refreshStatus();
      setState(() {});
    }
  }

  Visit? _defaultVisit(List<Visit> options) =>
      options.isEmpty ? null : options.first;

  void _ensureSignatory(ServiceDraft d) {
    if (_signatorySeeded) return;
    _signatorySeeded = true;
    var changed = false;
    if ((d.text('cert_issued_on')).trim().isEmpty) {
      _c.setField(d.serviceId, 'cert_issued_on', _isoOf(DateTime.now()));
      changed = true;
    }
    if (changed) {
      d.refreshStatus();
      setState(() {});
    }
    _ensureClinicHeads(d);
  }

  Future<void> _ensureClinicHeads(ServiceDraft d) async {
    if (_clinicHeadsAttempted || _loadingClinicHeads) return;
    _clinicHeadsAttempted = true;
    setState(() => _loadingClinicHeads = true);
    List<AppProfile> heads = const [];
    try {
      heads = await AccountService.fetchActiveClinicHeads();
    } catch (_) {
      heads = const [];
    }
    if (!mounted) return;
    setState(() {
      _clinicHeads = heads;
      _loadingClinicHeads = false;
    });
    _seedSignatoryName(d, heads);
  }

  void _seedSignatoryName(ServiceDraft d, List<AppProfile> heads) {
    final key = _certSignatoryField.key;
    final current = d.text(key).trim();
    final isPlaceholder =
        current.isEmpty || current == SignatoryStore.defaultName;
    if (!isPlaceholder) return;

    String? name;
    if (heads.isNotEmpty) {
      final uid = AccountService.currentUserId;
      final own = heads.where((h) => h.id == uid);
      name = (own.isEmpty ? heads.first : own.first).displayName;
    }
    if (name == null || name.trim().isEmpty) {
      name = SignatoryStore.read().name;
    }
    name = name.trim();
    if (name.isEmpty || name == current) return;

    _c.setField(d.serviceId, key, name);
    d.refreshStatus();
    setState(() {});
  }

  void _pickCertificateVisit(ServiceDraft d, Visit visit) {
    final changed = _selectedVisit(d)?.id != visit.id;
    if (changed) {
      _c.setField(d.serviceId, 'reason', _visitReasonOf(visit));
    }
    _c.setField(d.serviceId, 'cert_visit_id', visit.id ?? '');
    d.refreshStatus();
    setState(() {});
  }

  String _visitTimeLabel(Visit v) {
    final t = v.visitTime.trim();
    if (t.isEmpty) return '';
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  Widget _certificateSheet(ServiceDraft d) {
    final picked = _selectedVisit(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _visitPicker(d),
        if (picked != null) ...[
          const SizedBox(height: 14),
          _visitorInfoCard(d, picked),
          const SizedBox(height: 12),
          _signatureCard(d),
        ],
        const SizedBox(height: 16),
        _printButton(d),
      ],
    );
  }

  Widget _visitPicker(ServiceDraft d) {
    final loading = _loadingVisitOptions;
    final options = _visitOptions;
    final selected = d.text('cert_visit_id').trim();

    final safe = options.any((v) => v.id == selected) ? selected : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Clinic visit date',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSub),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: safe,
          isExpanded: true,
          hint: Text(
            loading ? 'Loading visits…' : 'No recorded clinic visits on file',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          items: [
            for (final v in options.where((e) => (e.id ?? '').isNotEmpty))
              DropdownMenuItem(
                value: v.id,
                child: Text(
                  _visitLabel(v),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textMain),
                ),
              ),
          ],
          onChanged: loading
              ? null
              : (value) {
                  if (value == null) return;
                  for (final v in options) {
                    if (v.id == value) {
                      _pickCertificateVisit(d, v);
                      return;
                    }
                  }
                },
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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

  String _visitLabel(Visit v) {
    final date = v.visitDate;
    final label =
        date == null ? 'Date not recorded' : _prettyDate(_isoOf(date));
    final time = _visitTimeLabel(v);
    final today = DateTime.now();
    final isToday = date != null &&
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    return [
      time.isEmpty ? label : '$label · $time',
      if (isToday) 'Today',
    ].join('  ·  ');
  }

  Widget _printButton(ServiceDraft d) {
    final rendered = _docDraft?.resolve();
    return ElevatedButton.icon(
      onPressed: rendered == null
          ? null
          : () => _showCertificatePrintPreview(rendered),
      icon: const Icon(Icons.print_outlined, size: 17),
      label: const Text('Print / Export PDF',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        elevation: 0,
      ),
    );
  }

  Widget _certCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _certAuto(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSub),
        ),
        const SizedBox(height: 5),
        InputDecorator(
          decoration: _decoration(_certAutoField, filled: true).copyWith(
            fillColor: AppColors.fieldFillDisabled,
            suffixIcon: const Padding(
              padding: EdgeInsets.only(right: 10),
              child: _AutoTag(),
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          child: Text(
            value.trim().isEmpty ? '—' : value.trim(),
            style: const TextStyle(fontSize: 13, color: AppColors.textMain),
          ),
        ),
      ],
    );
  }

  Widget _visitorInfoCard(ServiceDraft d, Visit visit) {
    final v = _v;
    final visitDate = visit.visitDate;
    return _certCard(
      title: 'Visitor Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _certAuto('Name', v.fullName),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _certAuto('Age', _ageOn(v, visitDate))),
              const SizedBox(width: 10),
              Expanded(child: _certAuto('Sex', v.sex)),
            ],
          ),
          const SizedBox(height: 10),
          _certAuto('Address', v.address),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _certAuto(
                  'Clinic Visit date',
                  visitDate == null
                      ? ''
                      : DateFormat('MMMM d, yyyy').format(visitDate),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _field(d, _certIssuedField)),
            ],
          ),
          const SizedBox(height: 10),
          _field(d, _certReasonField),
          const SizedBox(height: 10),
          _field(d, _certExcusedField),
        ],
      ),
    );
  }

  Widget _signatureCard(ServiceDraft d) {
    final heads = _clinicHeads;
    return _certCard(
      title: 'Authorized Signature',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _signatureField(d, heads),
          if (heads.isEmpty && _loadingClinicHeads)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Loading clinic heads…',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          if (heads.isEmpty && !_loadingClinicHeads)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'No active clinic head accounts found — type the name.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 9),
          Text(
            SignatoryStore.defaultRole,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain),
          ),
        ],
      ),
    );
  }

  Widget _signatureField(ServiceDraft d, List<AppProfile> heads) {
    final suggestions = <String>{
      for (final h in heads)
        if (h.displayName.isNotEmpty) h.displayName,
    }.toList();

    return Autocomplete<String>(
      displayStringForOption: (option) => option,
      optionsBuilder: (TextEditingValue value) {
        if (suggestions.isEmpty) return const <String>[];
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return suggestions;
        return suggestions.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (String value) {
        _onText(d, _certSignatoryField, value);
      },
      fieldViewBuilder: (BuildContext context, TextEditingController controller,
          FocusNode focusNode, VoidCallback onFieldSubmitted) {
        final draftValue = d.text(_certSignatoryField.key);
        if (controller.text != draftValue) controller.text = draftValue;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (value) => _onText(d, _certSignatoryField, value),
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(fontSize: 13, color: AppColors.textMain),
          decoration: _decoration(_certSignatoryField, filled: true),
        );
      },
    );
  }

  String _ageOn(ClinicProfile p, DateTime? asOf) {
    final birth = _parseIso(p.birthDate);
    if (birth == null) return '';
    final ref = asOf ?? DateTime.now();
    var years = ref.year - birth.year;
    final hadBirthday = ref.month > birth.month ||
        (ref.month == birth.month && ref.day >= birth.day);
    if (!hadBirthday) years -= 1;
    return years < 0 ? '' : '$years';
  }

  Future<void> _showCertificatePrintPreview(RenderedDocument rendered) async {
    await SimplePrintPreview.show(
      context,
      document: rendered,
      fileName: 'Medical Certificate - ${_v.fullName}',
      title: 'Print Preview — Medical Certificate',
      requirements: medicalCertificateRequirements,
    );
  }

  Widget _medicinePicker(ServiceDraft d) {
    final loading = _medicines == null;
    final list = _medicines ?? const <Medicine>[];
    final pickable = list.where(VisitDetailsController.canPick).toList();

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
            key: const ValueKey('medicine_shelf'),
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final m in pickable)
                _optionChip(
                  label: _medicineChipLabel(m, timesPicked[m.name] ?? 0),
                  selected: (timesPicked[m.name] ?? 0) > 0,
                  onTap: () {
                    _c.addMedicine(d, m);
                    _autoCompleteIfValid(d);
                    setState(() {});
                  },
                ),
            ],
          ),
      ],
    );
  }

  String _medicineChipLabel(Medicine m, int times) {
    final base = m.stock > 0 ? '${m.name}  ·  ${m.stock}' : m.name;
    return times > 1 ? '$base  ×$times' : base;
  }

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
                  _c.removeMedicine(d, index);
                  _autoCompleteIfValid(d);
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
                    _autoCompleteIfValid(d);
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
                    _autoCompleteIfValid(d);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _actionPicker(d, m),
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
                _autoCompleteIfValid(d);
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
                    _autoCompleteIfValid(d);
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
                    _autoCompleteIfValid(d);
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

  Widget _actionPicker(ServiceDraft d, MedicineDose m) {
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
            _autoCompleteIfValid(d);
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

  Widget _unbuiltSlide(String id) {
    return _notice(
      AppColors.warning,
      Icons.construction_rounded,
      'This slide ("$id") is not on screen yet. Everything else on this form '
      'works; the rest of the visit can be recorded around it.',
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
        duration: const Duration(seconds: 1),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 52),
      ));
  }

  Widget _vitalsCard(ServiceDraft d) {
    final isPrenatal = d.serviceId == 'prenatal';
    final isFirstAid = d.serviceId == 'first_aid_treatment';
    final bp = _c.vitals.bloodPressure;

    final needsReferral = isPrenatal && prenatalNeedsReferral(_c.vitals);

    final vitalsRequired = isFirstAid && _firstAidVitalsMissing();
    final hasVitals = _c.vitals.readings.isNotEmpty;

    final stripPills = <Widget>[
      for (final r in [
        _c.vitals.bloodPressure,
        _c.vitals.heartRateReading,
        _c.vitals.tempReading,
      ])
        if (r != null) _bandPill(r, showValue: true),
    ];

    if (_c.vitals.weightKg != null || _c.vitals.bmi != null) {
      final w = _c.vitals.bmiReading;
      if (w != null) stripPills.add(_bandPill(w, showValue: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (needsReferral)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.local_hospital_outlined,
                    size: 18, color: AppColors.danger),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    bp == null
                        ? 'Blood pressure is missing. Please record it.'
                        : 'High blood pressure. Refer to a doctor.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (vitalsRequired)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.monitor_heart_outlined,
                    size: 18, color: AppColors.danger),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Take vital signs first.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: vitalsRequired ? AppColors.danger : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                      hasVitals
                          ? Icons.lock_outline_rounded
                          : Icons.monitor_heart_outlined,
                      size: 14,
                      color: AppColors.textMuted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      hasVitals
                          ? 'Taken in Vital Signs. Read only here.'
                          : (isPrenatal
                              ? 'Blood pressure is needed.'
                              : (vitalsRequired
                                  ? 'Vital signs are needed.'
                                  : (isFirstAid
                                      ? 'Optional. A reading is suggested.'
                                      : 'No vitals yet.'))),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              if (hasVitals && stripPills.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(spacing: 8, runSpacing: 8, children: stripPills),
              ],
              const SizedBox(height: 12),
              _serviceCardButton(
                serviceId: 'vital_signs',
                recorded: hasVitals,
                recordLabel: 'Record Vital Signs',
                editLabel: 'Edit Vital Signs',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _medicationCard(ServiceDraft d) {
    final isFirstAid = d.serviceId == 'first_aid_treatment';
    final med = _c.draftFor('medication');
    final rows = med?.medicines ?? const <MedicineDose>[];
    final hasMeds = rows.isNotEmpty;

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
              Icon(
                  hasMeds
                      ? Icons.lock_outline_rounded
                      : Icons.medication_outlined,
                  size: 14,
                  color: AppColors.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  hasMeds
                      ? (isFirstAid
                          ? 'Added. Stock is deducted in Medication.'
                          : 'Recorded in Medication. Read only here.')
                      : 'No medicine yet.',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (hasMeds) ...[
            const SizedBox(height: 9),
            for (final m in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5.5),
                      child: Icon(Icons.circle,
                          size: 5, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        m.summary,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textMain),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          _serviceCardButton(
            serviceId: 'medication',
            recorded: hasMeds,
            recordLabel: isFirstAid ? 'Add Medication' : 'Record Medications',
            editLabel: isFirstAid ? 'Edit Medication' : 'Edit Medications',
          ),
        ],
      ),
    );
  }

  Widget _linkServiceCard(ServiceDraft d, ServiceField f) {
    String? serviceId = f.opensService;
    final fromKey = f.linkFromKey;
    if (serviceId == null && fromKey != null) {
      final picked = '${d.data[fromKey] ?? ''}'.trim();
      serviceId = appServiceIdForRecommended(picked);
    }
    if (serviceId == null) return const SizedBox.shrink();
    final added = _c.draftFor(serviceId) != null;
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
              const Icon(Icons.assignment_add,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  added
                      ? 'Already added. Tap to open.'
                      : 'Suggested. Optional.',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (f.note != null) ...[
            const SizedBox(height: 6),
            Text(
              f.note!,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSub, height: 1.3),
            ),
          ],
          const SizedBox(height: 10),
          _serviceCardButton(
            serviceId: serviceId,
            recorded: added,
            recordLabel: f.buttonLabel ?? 'Open',
            editLabel: f.buttonLabel ?? 'Open',
          ),
        ],
      ),
    );
  }

  Widget _serviceCardButton({
    required String serviceId,
    required bool recorded,
    required String recordLabel,
    required String editLabel,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _c.addService(serviceId);
            _c.open(serviceId);
          });
          widget.onServiceAdded?.call(serviceId);
        },
        icon: Icon(recorded ? Icons.edit_outlined : Icons.add_circle_outline,
            size: 16),
        label: Text(recorded ? editLabel : recordLabel,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textMain,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

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
                for (final p in ClinicPurposes.all)
                  if (p.id != 'other') _row(context, p),
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