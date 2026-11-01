import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_details_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/features/visits/screens/clinic_visit_step_three.dart';
import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';

class VisitEditScreen extends StatefulWidget {
  const VisitEditScreen({
    super.key,
    required this.userName,
    required this.visitId,
    required this.person,
    this.serviceIds = const [],
    this.serviceData = const {},
    this.vitals,
    this.medicines,
    this.initialReason = '',
    this.visitStamp,
  });

  final String userName;

  final String visitId;

  final IndividualRecord person;

  final List<String> serviceIds;
  final Map<String, Map<String, dynamic>> serviceData;
  final VisitVitals? vitals;
  final List<MedicineDose>? medicines;

  final String initialReason;

  final DateTime? visitStamp;

  @override
  State<VisitEditScreen> createState() => _VisitEditScreenState();
}

class _VisitEditScreenState extends State<VisitEditScreen> {
  late final TextEditingController _reasonCtrl;
  late final VisitDetailsController _details;
  late final ClinicProfile _visitor;
  late final DateTime _stamp;

  late final List<String> _originalServiceIds;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController(text: widget.initialReason);
    _stamp = widget.visitStamp ?? DateTime.now();
    _originalServiceIds = List<String>.of(widget.serviceIds);
    _visitor = _profileFromRecord(widget.person);

    _details = VisitDetailsController(
      serviceIds: widget.serviceIds,
      staffName: widget.userName,
    );
    _details.hydrate(
      serviceData: widget.serviceData,
      visitVitals: widget.vitals,
      restoredMedicines: [
        for (final m in widget.medicines ?? const <MedicineDose>[]) m.copy(),
      ],
    );
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _details.dispose();
    super.dispose();
  }

  ClinicProfile _profileFromRecord(IndividualRecord r) {
    final existing = PatientDirectory.instance.byId(r.id);
    return ClinicProfile(
      uuid: r.uuid,
      id: r.id,
      category: r.category,
      firstName: r.firstName,
      middleName: r.middleName,
      lastName: r.lastName,
      suffix: r.suffix,
      sex: r.sex,
      birthDate: r.birthDate == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(r.birthDate!),
      contact: r.contact,
      email: r.email,
      address: r.address,
      academicYear: r.academicYear,
      semester: r.semester,
      institute: r.institute,
      program: r.program,
      yearLevel: r.yearLevel,
      department: r.department,
      position: r.position,
      emergencyName: existing?.emergencyName ?? '',
      emergencyContact: existing?.emergencyContact ?? '',
      status: r.status,
      createdAt: r.createdAt,
      createdBy: r.createdBy,
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update this record?'),
        content: const Text(
          'Update reason and service details. Visit date and time are not '
          'changed.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm_visit_update'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final reason = _reasonCtrl.text.trim();
      if (reason != widget.initialReason.trim()) {
        await VisitService.update(widget.visitId, complaint: reason);
      }

      final removed = [
        for (final id in _originalServiceIds)
          if (_details.draftFor(id) == null) id,
      ];
      if (removed.isNotEmpty) {
        await VisitDetailsService.removeServices(
          visitId: widget.visitId,
          serviceIds: removed,
        );
      }

      await VisitDetailsService.saveAll(
        visitId: widget.visitId,
        controller: _details,
        userName: widget.userName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save the changes: $e'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Visit updated by ${widget.userName}.'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgAlt,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _reasonCard(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: ClinicVisitStepThree(
                  controller: _details,
                  visitor: _visitor,
                  userName: widget.userName,
                  visitStamp: _stamp,
                ),
              ),
            ),
            _saveBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
            color: AppColors.textMain,
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Edit Record',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textMain,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  DateFormat('MMM d, yyyy  ·  h:mm a').format(_stamp),
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reasonCard() {
    final empty = _reasonCtrl.text.trim().isEmpty;
    OutlineInputBorder box(Color color) =>
        OutlineInputBorder(borderSide: BorderSide(color: color));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason for Visit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _reasonCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter reason of visit',
                hintStyle:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted),
                filled: true,
                fillColor:
                    empty ? AppColors.dangerContainer : AppColors.fieldFill,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: box(empty ? AppColors.danger : AppColors.border),
                enabledBorder: box(empty ? AppColors.danger : AppColors.border),
                focusedBorder: box(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SizedBox(
        height: 36,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.bgAlt,
            disabledForegroundColor: AppColors.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Save changes',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
