import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_times.dart';
import 'package:clinicmanagementsystem/core/services/time_service.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_details_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/features/visits/models/clinic_purposes.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:clinicmanagementsystem/features/visits/screens/clinic_visit_step_three.dart';
import 'package:clinicmanagementsystem/features/visits/widgets/visit_review_card.dart';

class ClinicVisitScreen extends StatefulWidget {
  final String userName;
  final String userRole;

  final bool isActive;

  final DateTime Function() clock;

  final String? editVisitId;

  final IndividualRecord? editVisitor;

  final List<String> editServiceIds;
  final Map<String, Map<String, dynamic>> editServiceData;
  final VisitVitals? editVitals;
  final List<MedicineDose>? editMedicines;
  final DateTime? editCheckedInAt;
  final String? editReasonForVisit;

  const ClinicVisitScreen({
    super.key,
    this.userName = '',
    this.userRole = 'Clinic Staff',
    this.isActive = false,
    this.clock = DateTime.now,
    this.editVisitId,
    this.editVisitor,
    this.editServiceIds = const [],
    this.editServiceData = const {},
    this.editVitals,
    this.editMedicines,
    this.editCheckedInAt,
    this.editReasonForVisit,
  });

  @override
  State<ClinicVisitScreen> createState() => _ClinicVisitScreenState();
}

class _ClinicVisitScreenState extends State<ClinicVisitScreen> {
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kPrimaryDeep = AppColors.primaryDeep;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kBorderStrong = AppColors.borderStrong;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kTextMuted = AppColors.textMuted;
  static const Color kDanger = AppColors.danger;
  static const Color kDangerContainer = AppColors.dangerContainer;
  static const Color kWarning = AppColors.warning;
  static const Color kFieldFill = AppColors.fieldFill;

  static const TextStyle kSectionTitleStyle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain);
  static const TextStyle kSectionSubtitleStyle =
      TextStyle(fontSize: 12.5, color: kTextSub);
  static const TextStyle kFieldLabelStyle =
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextSub);
  static const TextStyle kCaptionStyle =
      TextStyle(fontSize: 12, color: kTextSub);

  static const TextStyle kEyebrowStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.7,
      color: kTextMain);

  static const List<String> _visitorFilters = [
    'All',
    'Student',
    'Faculty',
    'Staff'
  ];
  String _visitorFilter = 'All';

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _reasonForVisitCtrl = TextEditingController();

  ClinicProfile? _visitor;
  String? _academicPeriodId;

  String? _patientUuid;

  DateTime? _checkedInAt;

    DateTime? _timeOutAt; // null = not edited -> server time when saved
  bool _timeInEdited = false;
  Duration _serverOffset = Duration.zero;

  DateTime _serverNow() => widget.clock().add(_serverOffset);

  Future<void> _syncServerClock() async {
    try {
      final server = await TimeService.serverNow();
      _serverOffset = server.difference(widget.clock());
    } catch (_) {}
  }

  String get _timeInText =>
      _checkedInAt == null ? '' : VisitTimes.clock(_checkedInAt!);

  final List<String> _selectedServiceIds = [];

  static const List<String> _stepTitles = [
    'Search Visitor',
    'Select Services',
    'Service Details',
    'Review & Complete',
  ];
  int _step = 0;

  VoidCallback? _dataListener;
  VoidCallback? _directoryListener;

  Future<void>? _directoryLoad;

  bool _hydrating = false;
  bool _saving = false;

  VisitDetailsController? _details;

  String _detailsSignature = '';

  String get _currentUserName =>
      widget.userName.isNotEmpty ? widget.userName : 'Unknown User';

  bool get _isEditing => widget.editVisitId != null;

  @override
  void initState() {
    super.initState();
    _syncServerClock();     //???
    _loadDirectory();

    _academicPeriodId = ReferenceCatalog.currentPeriod?.id;
    ReferenceCatalog.loadQuietly();
    
    if (_isEditing) {
      _seedEditMode();
      VisitService.periodIdOf(widget.editVisitId!).then((id) {
        if (mounted && id != null) setState(() => _academicPeriodId = id);
      });
    }

    _directoryListener = () {
      if (!mounted || _hydrating) return;

      setState(_syncVisitorWithDirectory);
    };
    PatientDirectory.instance.subscribe(_directoryListener!);

    ReferenceCatalog.subscribe(_catalogListener);

    _dataListener = _loadDirectory;
    DataTracker.listen(_dataListener!);
  }

    void _catalogListener() {
    if (!mounted) return;
    setState(() {
      _academicPeriodId ??= ReferenceCatalog.currentPeriod?.id;
    });
  }

  @override
  void didUpdateWidget(ClinicVisitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadDirectory();
    }
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    if (_directoryListener != null) {
      PatientDirectory.instance.unsubscribe(_directoryListener!);
    }

    ReferenceCatalog.unsubscribe(_catalogListener);
    _searchCtrl.dispose();
    _reasonForVisitCtrl.dispose();
    _details?.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    final pending = _directoryLoad;
    if (pending != null) await pending;
    final mine = _loadDirectoryInner();
    _directoryLoad = mine;
    try {
      await mine;
    } finally {
      if (identical(_directoryLoad, mine)) _directoryLoad = null;
    }
  }

  Future<void> _loadDirectoryInner() async {
    try {
      final records = await IndividualRecordService.fetchAll(
        includeInactive: false,
      );
      if (!mounted) return;
      _hydrating = true;
      try {
        PatientDirectory.instance
            .hydrate(records.map(_profileFromRecord).toList());
      } finally {
        _hydrating = false;
      }
      setState(_syncVisitorWithDirectory);
    } catch (e) {
      debugPrint('clinic visit: could not load roster: $e');
    }
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

  void _syncVisitorWithDirectory() {
    final current = _visitor;
    if (current == null) return;
    final fresh = PatientDirectory.instance.byId(current.id);
    if (fresh == null || identical(fresh, current)) return;
    _visitor = fresh;
  }

  void _seedEditMode() {
    final r = widget.editVisitor;
    if (r == null) return;
    _visitor = _profileFromRecord(r);
    _patientUuid = r.id;
    _checkedInAt = widget.editCheckedInAt ?? widget.clock();
    _reasonForVisitCtrl.text = widget.editReasonForVisit ?? '';
    _selectedServiceIds
      ..clear()
      ..addAll(widget.editServiceIds);
    _step = 1;
    final details = _detailsFor();
    details.hydrate(
      serviceData: widget.editServiceData,
      visitVitals: widget.editVitals,
      restoredMedicines: widget.editMedicines,
    );
  }

  List<ClinicProfile> get _results => PatientDirectory.instance.search(
        _searchCtrl.text,
        category: _visitorFilter == 'All' ? null : _visitorFilter,
      );

  List<ClinicPurpose> get _selectedPurposes {
    final out = <ClinicPurpose>[];
    for (final id in _selectedServiceIds) {
      final p = ClinicPurposes.byId(id);
      if (p != null) out.add(p);
    }
    return out;
  }

  String get _complaintText => ClinicPurposes.joinLabels(_selectedPurposes);

  bool get _hasVisitor => _visitor != null;

  bool get _hasServices {
    if (_selectedServiceIds.isEmpty) return false;
    return true;
  }

  bool get _hasReason => _reasonForVisitCtrl.text.trim().isNotEmpty;

  bool get _canSave =>
      _hasVisitor && _hasReason && _hasServices && _patientUuid != null;

  bool get _allServicesDone => _details?.isEverythingComplete ?? false;

  int get _maxReachable {
    if (_allServicesDone && _hasReason) return _stepTitles.length - 1;
    if (_hasServices && _hasReason) return 2;
    if (_hasVisitor) return 1;
    return 0;
  }

  bool _stepDone(int i) {
    switch (i) {
      case 0:
        return _hasVisitor;
      case 1:
        return _hasServices && _hasReason;
      case 2:
        return _details == null ? _hasServices : _allServicesDone;
      default:
        return false;
    }
  }

  void _goToStep(int i) {
    final target = i.clamp(0, _stepTitles.length - 1);
    if (target == _step) return;
    if (target > _maxReachable) {
      _toast(_blockReasonFor(target), kWarning);
      return;
    }
    setState(() => _step = target);
  }

  String _blockReasonFor(int target) {
    if (target >= 1 && !_hasVisitor) {
      return 'Search for a visitor and pick them from the list first.';
    }
    if (target >= 2 && !_hasReason) {
      return 'Enter the reason for the visit before continuing.';
    }
    if (target >= 2 && !_hasServices) {
      return 'Tick at least one service before continuing.';
    }
    return 'Complete the previous step first.';
  }
  Future<void> _selectVisitor(ClinicProfile p) async {
    final changed = _visitor?.id != p.id;
    if (changed) await _syncServerClock();
    if (!mounted) return;
    setState(() {
      _visitor = p;
      _patientUuid = p.id;

      if (changed) {
        _clearServices();
        _checkedInAt = _serverNow();
        _timeInEdited = false;
        _timeOutAt = null;
      }
    });
  }

  static const List<String> _freeTextProcedureKeywords = [
    'wound',
    'cut',
    'burn',
    'sprain',
    'fracture',
    'bleeding',
    'injury',
    'faint',
    'unconscious',
    'nosebleed',
    'dislocat',
    'seizure',
    'blood pressure',
    'asthma',
    'breath',
    'chest pain',
  ];

  @pragma('vm:prefer-inline')
  bool _keywordTriggersProcedure(String text) =>
      _freeTextProcedureKeywords.any((k) => text.contains(k));

  bool get _requiresProcedure {
    final t = _reasonForVisitCtrl.text.trim().toLowerCase();
    return _selectedPurposes.any((p) => p.procedures.isNotEmpty) ||
        (t.isNotEmpty && _keywordTriggersProcedure(t));
  }

    Future<void> _completeConsultation() async {
    final v = _visitor;
    if (v == null || !_hasServices) {
      _toast('Pick a visitor and tick at least one service first.', kWarning);
      _goToStep(v == null ? 0 : 1);
      return;
    }

    if (!_hasReason) {
      _toast('Enter the reason for the visit first.', kWarning);
      _goToStep(1);
      return;
    }
    if (_patientUuid == null) {
      _toast(
        "Still preparing this visitor's record — try again in a moment.",
        kWarning,
      );
      return;
    }

    final name = v.middleInitial.isEmpty
        ? '${v.lastName}, ${v.firstName}'
        : '${v.lastName}, ${v.firstName} ${v.middleInitial}';

    // Preview for the dialog (server clock; Time Out re-read when saving).
    final previewNow = await TimeService.serverNow();
    if (!mounted) return;
    final previewIn = _checkedInAt ?? previewNow;
    final previewOut = _timeOutAt ?? previewNow;
    if (!_isEditing && VisitTimes.outBeforeIn(previewIn, previewOut)) {
      _toast(VisitTimes.outBeforeInMessage, kDanger);
      _goToStep(1);
      return;
    }

    final complaint = _complaintText;
    final needsProcedure = _requiresProcedure;

    final confirmed = await _confirmVisitDialog(
      name: name,
      id: v.id,
      category: v.category,
      affiliation: v.affiliationLabel,
      complaint: complaint,
      timeIn: VisitTimes.stamp(previewIn),
      timeOut: VisitTimes.stamp(previewOut),
      stay: VisitTimes.stayBetween(previewIn, previewOut),
      needsProcedure: needsProcedure,
      editing: _isEditing,
    );
    if (confirmed != true || !mounted) return;

    if (_isEditing) {
      final updateReason = _reasonForVisitCtrl.text.trim();
      setState(() => _saving = true);
      try {
        await VisitService.update(
          widget.editVisitId!,
          complaint: updateReason,
          academicPeriodId: _academicPeriodId,
        );
        await _saveStepThreeToServer(widget.editVisitId!);
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        _toast('Could not update visit: $e', kDanger);
        return;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Visit updated by $_currentUserName.', kPrimary);
      Navigator.of(context).pop(true);
      return;
    }

    // Unedited values come from the Supabase server clock at the moment of saving.
    final saveNow = await TimeService.serverNow();
    if (!mounted) return;
    final timeInAt = _checkedInAt ?? saveNow;
    final timeOutAt = _timeOutAt ?? saveNow;
    if (VisitTimes.outBeforeIn(timeInAt, timeOutAt)) {
      _toast(VisitTimes.outBeforeInMessage, kDanger);
      _goToStep(1);
      return;
    }

    setState(() => _saving = true);
    final String? patientUuid = _patientUuid;
    Visit? savedVisit;
    try {
      savedVisit = await VisitService.create(
        patientId: patientUuid!,
        patientNo: v.id,
        patientName: name,
        category: v.category,
        department: v.isStudent ? v.program : v.department,
        yearPosition: v.isStudent ? v.yearLevel : v.position,
        complaint: complaint,
        reasonForVisit: _reasonForVisitCtrl.text.trim(),
        visitDate: timeInAt,
        visitTime: VisitTimes.clock(timeInAt),
        timeOut: timeOutAt,
        academicPeriodId: _academicPeriodId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save visit: $e', kDanger);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (savedVisit.id != null) {
      await _saveStepThreeToServer(savedVisit.id!);
      if (!mounted) return;
    }

    if (!mounted) return;
    _toast('Saved Record', kPrimary);

    _resetVisit();
  }

  Future<bool?> _confirmVisitDialog({
    required String name,
    required String id,
    required String category,
    required String affiliation,
    required String complaint,
   // required String visitDate,  //??
    required String timeIn,
    required String timeOut,
    String? stay,
    required bool needsProcedure,
    bool editing = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(editing ? Icons.edit_outlined : Icons.check_circle_outline,
              color: kPrimary, size: 22),
          const SizedBox(width: 8),
          Text(editing ? "Update Record" : "Confirm Record"),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VisitReviewRow("Visitor", name),
              VisitReviewRow("School ID", id),
              VisitReviewRow("Role", category),
              VisitReviewRow("Affiliation", affiliation),
              VisitReviewRow("Service", complaint),
          //    VisitReviewRow("Date", visitDate),
              VisitReviewRow("Time in", timeIn),
              if (!editing) ...[
                VisitReviewRow("Time out", timeOut),
                if (stay != null) VisitReviewRow("Stay length", stay),
              ],
              const SizedBox(height: 4),
              VisitReviewRow(
                  editing ? "Updated by" : "Recorded by", _currentUserName),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(editing ? "Confirm & Update" : "Confirm & Save"),
          ),
        ],
      ),
    );
  }

  void _resetVisit() {
    setState(() {
      _academicPeriodId = ReferenceCatalog.currentPeriod?.id;
      _step = 0;
      _visitor = null;
      _patientUuid = null;

      _checkedInAt = null;
      _timeOutAt = null;
      _timeInEdited = false;
      _clearServices();
      _searchCtrl.clear();
      _reasonForVisitCtrl.clear();
      _visitorFilter = 'All';
    });
  }

  void _clearServices() {
    _selectedServiceIds.clear();
    _disposeDetails();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgAlt,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pageHeader(),
                const SizedBox(height: 14),
                _stepTracker(),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _stepBody(),
            ),
          ),
          if (_step > 0 && _step != 1 && _step != 2) _wizardFooter(),
        ]),
      ),
    );
  }

  Widget _cardBody({required Widget child}) {
    return Expanded(
      child: ClipRect(child: SingleChildScrollView(child: child)),
    );
  }

  Widget _pageHeader() {
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kPrimary, kPrimaryDk],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.medical_services_outlined,
            color: Colors.white, size: 19),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isEditing ? 'Edit Visit' : 'Clinic Consultation',
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: kTextMain)),
        const SizedBox(height: 2),
        Text(
            _isEditing
                ? 'Correct the services and the answers recorded on this visit'
                : 'Search the visitor, record the service, complete the visit',
            style: const TextStyle(fontSize: 12.5, color: kTextSub)),
      ]),
    ]);
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _searchVisitorLayout();
      case 1:
        return _selectServicesStep();
      case 2:
        return _serviceDetailsStep();
      default:
        return _reviewStep();
    }
  }

  Widget _serviceDetailsStep() {
    final v = _visitor;
    if (v == null) return _noVisitorSelected();
    final isLast = _step == _stepTitles.length - 1;
    return ClinicVisitStepThree(
      controller: _detailsFor(),
      visitor: v,
      userName: _currentUserName,
      nav: StepThreeNav(
        onBack: () => _goToStep(1),
        onContinue: isLast ? _completeConsultation : _saveStepThree,
        continueLabel: isLast ? 'Complete Consultation' : 'Continue',
        continueEnabled: isLast ? _canSave : _hasServices,
        saving: _saving,
      ),
      onServiceAdded: (id) {
        if (_selectedServiceIds.contains(id)) return;
        setState(() => _selectedServiceIds.add(id));
      },
      onServiceRemoved: (id) {
        if (!_selectedServiceIds.remove(id)) return;

        setState(() {});
      },
    );
  }

  VisitDetailsController _detailsFor() {
    final signature = _detailsSignatureFor;
    final existing = _details;

    if (existing != null && _detailsSignature == signature) {
      return existing;
    }

    final visitorId = _visitor?.id ?? '';
    if (existing != null &&
        _detailsVisitorId == visitorId &&
        existing.drafts
            .every((d) => _selectedServiceIds.contains(d.serviceId))) {
      for (final id in _selectedServiceIds) {
        if (existing.draftFor(id) == null) {
          existing.addService(id,
              otherName: '', activate: false, notify: false);
        }
      }
      _detailsSignature = signature;
      return existing;
    }

    existing?.dispose();
    _details = VisitDetailsController(
      serviceIds: _selectedServiceIds,
      otherNames: const {},
      staffName: _currentUserName,
    );
    _detailsSignature = signature;
    _detailsVisitorId = visitorId;
    return _details!;
  }

  String get _detailsSignatureFor =>
      '${_visitor?.id ?? ''}|${_selectedServiceIds.join(',')}';

  String _detailsVisitorId = '';

  void _disposeDetails() {
    _details?.dispose();
    _details = null;
    _detailsSignature = '';
    _detailsVisitorId = '';
  }

  Widget _stepTracker() {
    return _panel(
      key: const ValueKey('step-tracker'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: MediaQuery.of(context).size.width < 620
          ? _trackerColumn()
          : _trackerRow(),
    );
  }

  Widget _trackerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _rule(done: _step > 0),
          for (int i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0) _rule(done: i <= _step),
            _trackerNode(i),
          ],
          _rule(done: _step >= _stepTitles.length - 1),
        ],
      ),
    );
  }

  Widget _trackerColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _stepTitles.length; i++) ...[
          if (i > 0) _verticalConnector(i),
          _trackerNode(i),
        ],
      ],
    );
  }

  Widget _rule({required bool done}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: done ? kPrimary : kBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _verticalConnector(int i) {
    final done = i <= _step;
    return Container(
      width: 2,
      height: 12,
      margin: const EdgeInsets.only(left: 11.5, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: done ? kPrimary : kBorder,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _trackerNode(int i) {
    final active = i == _step;
    final done = !active && _stepDone(i) && i < _step;
    final reachable = i <= _maxReachable;
    final circleColor = done || active ? kPrimary : kFieldFill;
    final borderColor =
        done || active ? kPrimary : (reachable ? kBorderStrong : kBorder);
    final labelColor =
        done || active ? kPrimary : (reachable ? kTextSub : kTextMuted);

    final circle = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: done || active ? Colors.white : kTextSub,
              ),
            ),
    );

    final label = Text(
      _stepTitles[i],
      key: active ? const ValueKey('tracker-active') : null,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.1,
        fontWeight: active
            ? FontWeight.w800
            : (done ? FontWeight.w700 : FontWeight.w500),
        color: labelColor,
      ),
    );

    final node = Semantics(
      selected: active,
      label: 'Step ${i + 1} of ${_stepTitles.length}, ${_stepTitles[i]}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(width: 8),
          label,
        ],
      ),
    );

    if (!done) return node;
    return Tooltip(
      message: 'Back to ${_stepTitles[i]}',
      child: InkWell(
        onTap: () => _goToStep(i),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: node,
        ),
      ),
    );
  }

  Widget _searchVisitorLayout() {
    return LayoutBuilder(builder: (context, constraints) {
      final stack = constraints.maxWidth < 980 && constraints.maxHeight >= 700;
      if (stack) {
        return Column(children: [
          Expanded(flex: 5, child: _searchVisitorCard()),
          const SizedBox(height: 14),
          Expanded(flex: 4, child: _visitorInfoCard()),
        ]);
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _searchVisitorCard()),
          const SizedBox(width: 20),
          Expanded(flex: 6, child: _visitorInfoCard()),
        ],
      );
    });
  }

  Widget _searchVisitorCard() {
    final results = _results;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.search_rounded, size: 20, color: kPrimary),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Search Visitor', style: kSectionTitleStyle),
                  SizedBox(height: 2),
                  Text('Enter School ID or Name', style: kSectionSubtitleStyle),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _filterPills(),
          const SizedBox(height: 10),
          _searchField(),
          const SizedBox(height: 10),
          _cardBody(
            child: results.isEmpty
                ? _noVisitorFound()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < results.length; i++) ...[
                        _visitorRow(results[i]),
                        if (i < results.length - 1) const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterPills() {
    return LayoutBuilder(builder: (context, c) {
      final filters = _visitorFilters;

      int countFor(String f) {
        final all = PatientDirectory.instance.all;
        if (f == 'All') return all.length;
        return all.where((p) => p.category == f).length;
      }

      Widget pill(String f) {
        final selected = _visitorFilter == f;
        final n = countFor(f);
        return InkWell(
          key: ValueKey('visitor_filter_$f'),
          onTap: () => setState(() => _visitorFilter = f),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? kPrimary : AppColors.bgAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? kPrimary : kBorder),
            ),
            child: Text(
              '$f  $n',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : kTextSub,
              ),
            ),
          ),
        );
      }

      const minPerChip = 78.0;
      if (c.maxWidth >= filters.length * minPerChip) {
        return Row(
          children: [
            for (var i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: pill(filters[i])),
            ],
          ],
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final f in filters) pill(f)],
      );
    });
  }

  Widget _searchField() {
    return TextField(
      key: const ValueKey('visitor_search_field'),
      controller: _searchCtrl,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14, color: kTextMain),
      decoration: InputDecoration(
        hintText: "Search by ID number or name...",
        hintStyle: const TextStyle(fontSize: 12.5, color: kTextSub),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: kPrimary),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon:
                    const Icon(Icons.close_rounded, size: 18, color: kTextSub),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: kFieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }

  Widget _visitorRow(ClinicProfile p) {
    final selected = _visitor?.id == p.id;
    return Semantics(
      button: true,
      selected: selected,
      label: '${p.fullName}, ${p.category}, ID ${p.id}',
      child: InkWell(
        onTap: () => _selectVisitor(p),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: selected
                ? kPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                color: selected ? kPrimary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _initialsAvatar(p, 14),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          p.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: selected ? kPrimaryDeep : kTextMain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _roleBadge(p.category, fontSize: 10.5),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      _idChip(p),
                      const SizedBox(width: 7),
                      Container(width: 1, height: 12, color: kBorder),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _affiliationLine(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kCaptionStyle,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: selected ? kPrimary : kTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idChip(ClinicProfile p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Text(
        p.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: kTextSub,
        ),
      ),
    );
  }

  String _affiliationLine(ClinicProfile p) => p.isStudent
      ? _joined([p.program, p.yearLevel])
      : _joined([p.department, p.position]);

  static String _joined(List<String> parts) =>
      parts.map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');

  Widget _noVisitorFound() {
    final term = _searchCtrl.text.trim();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_search_outlined, size: 44, color: kTextMuted),
          const SizedBox(height: 12),
          const Text('No visitor found',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: kTextMain)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              term.isEmpty
                  ? 'The roster is empty in this category.'
                  : "Nobody matches \"$term\"${_visitorFilter == 'All' ? '' : ' in $_visitorFilter'}.",
              textAlign: TextAlign.center,
              style: kCaptionStyle,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _showAddVisitorDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('+ Add New Visitor'),
          ),
        ],
      ),
    );
  }

  Widget _visitorInfoCard() {
    final v = _visitor;
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.badge_outlined, size: 20, color: kPrimary),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Visitor Information', style: kSectionTitleStyle)),
          ]),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          if (v == null)
            _cardBody(child: _noVisitorSelected())
          else ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _visitorIdentity(v),
                  const SizedBox(height: 12),
                  _academicBox(v),
                  const SizedBox(height: 12),
                  Expanded(child: _detailGrid(v)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _hasVisitor ? _proceedFromStepOne : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.borderStrong,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Proceed',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _proceedFromStepOne() {
    if (!_hasVisitor) {
      _toast('Pick a visitor from the list first.', kWarning);
      return;
    }
    _goToStep(1);
  }

  Widget _noVisitorSelected() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: [
        const Icon(Icons.person_outline, size: 44, color: kTextMuted),
        const SizedBox(height: 12),
        const Text('No visitor selected',
            style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700, color: kTextMain)),
        const SizedBox(height: 4),
        const Text(
          'Search by School ID or name on the left, then pick the person '
          'this visit is for.',
          textAlign: TextAlign.center,
          style: kCaptionStyle,
        ),
      ]),
    );
  }

  Widget _visitorIdentity(ClinicProfile v) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _initialsAvatar(v, 24),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(
                  v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kTextMain),
                ),
              ),
              const SizedBox(width: 8),
              _roleBadge(v.category, fontSize: 11.5),
            ]),
            const SizedBox(height: 2),
            Text('School ID: ${v.id}',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ],
        ),
      ),
    ]);
  }

  Widget _academicBox(ClinicProfile v) {
    String headline;
    String subline;

    if (v.isStudent) {
      headline = [v.institute, v.program, v.yearLevel]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');

      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else if (v.isFaculty) {
      headline = [v.institute, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');

      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else if (v.isStaff) {
      headline = [v.department, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');

      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else {
      headline = v.department;
      subline = '${_orDash(v.position)}, ${_orDash(v.id)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.school_outlined, size: 20, color: kPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current Academic Information',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDk,
                      letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text(_orDash(headline),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kTextMain)),
              Text(subline, style: kCaptionStyle),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _detailGrid(ClinicProfile v) {
    final cells = <Widget>[
      _detailCell(Icons.wc_outlined, 'Sex', _orDash(v.sex)),
      _detailCell(Icons.alternate_email, 'Email', _orDash(v.email)),
      _detailCell(
          Icons.cake_outlined, 'Date of Birth', _formatDate(v.birthDate)),
      _detailCell(Icons.home_outlined, 'Address', _orDash(v.address)),
      _detailCell(Icons.phone_outlined, 'Contact Number', _orDash(v.contact)),
      _detailCell(Icons.contact_emergency_outlined, 'Emergency Contact',
          _emergencyText(v)),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 620 ? 3 : 2;
      const gap = 10.0;
      final rows = <Widget>[];
      for (var i = 0; i < cells.length; i += columns) {
        final slice = cells.skip(i).take(columns).toList();
        rows.add(Padding(
          padding:
              EdgeInsets.only(bottom: i + columns < cells.length ? gap : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c2 = 0; c2 < columns; c2++) ...[
                if (c2 > 0) const SizedBox(width: gap),
                Expanded(
                  child:
                      c2 < slice.length ? slice[c2] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ));
      }
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      );
    });
  }

  String _emergencyText(ClinicProfile v) {
    final name = v.emergencyName.trim();
    final number = v.emergencyContact.trim();
    if (name.isEmpty && number.isEmpty) return '—';
    if (name.isEmpty) return number;
    if (number.isEmpty) return name;
    return '$name · $number';
  }

  Widget _detailCell(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: kPrimary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: kTextMuted, height: 1.1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _orDash(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      color: kTextSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _serviceColumn1 = [
    'vital_signs',
    'bpi',
    'wound_dressing',
    'first_aid_treatment',
    'health_counselling',
  ];
  static const List<String> _serviceColumn2 = [
    'prenatal',
    'medication',
    'medicine_consultation',
    'medicine_certificate',
  ];

  List<({String id, String label, IconData icon})> _serviceRowsFor(int column) {
    final ids = column == 0 ? _serviceColumn1 : _serviceColumn2;
    final rows = <({String id, String label, IconData icon})>[];
    for (final id in ids) {
      final p = ClinicPurposes.byId(id);
      if (p == null) continue;
      rows.add((id: p.id, label: p.label, icon: p.icon));
    }

    return rows;
  }

  String _serviceLabel(String id) {
    return ClinicPurposes.byId(id)?.label ?? id;
  }

  IconData _iconForService(String id) =>
      ClinicPurposes.byId(id)?.icon ?? Icons.medical_services_outlined;

  void _toggleService(String id) {
    setState(() {
      if (_selectedServiceIds.contains(id)) {
        _selectedServiceIds.remove(id);
      } else {
        _selectedServiceIds.add(id);
      }
    });
  }

  void _continueFromStepTwo() {
    if (!_hasReason) {
      _toast('Reason for Visit is required. Please fill it in.', kWarning);
      return;
    }
    if (_selectedServiceIds.isEmpty) {
      _toast('Tick at least one service before continuing.', kWarning);
      return;
    }
    if (!_hasServices) {
      _toast('Name the service under "Other", or untick it.', kWarning);
      return;
    }
    _goToStep(2);
  }

  Widget _selectServicesStep() {
    return LayoutBuilder(builder: (context, constraints) {
      final stack = constraints.maxWidth < 980 && constraints.maxHeight >= 700;
      if (stack) {
        return Column(children: [
          Expanded(flex: 5, child: _newVisitCard()),
          const SizedBox(height: 14),
          Expanded(flex: 4, child: _visitInformationCard()),
        ]);
      }

      final infoWidth =
          (constraints.maxWidth * 5 / 12).clamp(260.0, 380.0).toDouble();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _newVisitCard()),
          const SizedBox(width: 20),
          SizedBox(width: infoWidth, child: _visitInformationCard()),
        ],
      );
    });
  }

  Widget _newVisitCard() {
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(Icons.medical_services_outlined,
              'Reason for Visit / Services Needed'),
          const SizedBox(height: 12),
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text.rich(
                  TextSpan(
                    text: 'Reason for Visit',
                    style: kFieldLabelStyle,
                    children: [
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                            color: kDanger, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _reasonOfVisitField(),
                const SizedBox(height: 8),
                _assistBanner(),
                const SizedBox(height: 10),
                const Text('Available Services', style: kFieldLabelStyle),
                const SizedBox(height: 6),
                _serviceChecklist(),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _stepTwoVisitorSummary(ClinicProfile v) {
    String affiliation;
    if (v.isStudent) {
      affiliation = [v.institute, v.program, v.yearLevel]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else if (v.isFaculty) {
      affiliation = [v.institute, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else if (v.isStaff) {
      affiliation = [v.department, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else {
      affiliation = [
        v.department,
        v.position,
        v.institute,
        v.program,
        v.yearLevel
      ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');
    }

    return Container(
      key: const ValueKey('step2/visitor_block'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _initialsAvatar(v, 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: kTextMain,
                  ),
                ),
              ),
              const SizedBox(width: 6),
             
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kBorder),
                ),
                child: Text(
                  v.id,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: kTextSub,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              '${v.id} | ${_orDash(affiliation)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.15,
                color: kTextSub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  

 // String _labelOf(String serviceId) =>
    //  ClinicPurposes.byId(serviceId)?.label ?? serviceId;

  Widget _assistBanner() {
    return _tealBanner(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'How can we assist you today?',
      message: 'Select one or more services. You can choose multiple '
          'services for the same visit.',
    );
  }

  Widget _serviceChecklist() {
    Widget rowsOf(int index) {
      final rows = _serviceRowsFor(index);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _serviceRow(rows[i]),
            if (i < rows.length - 1) const SizedBox(height: 6),
          ],
        ],
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final twoUp = c.maxWidth >= 480;
      if (!twoUp) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [rowsOf(0), const SizedBox(height: 6), rowsOf(1)],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: rowsOf(0)),
          const SizedBox(width: 12),
          Expanded(child: rowsOf(1)),
        ],
      );
    });
  }

  Widget _serviceRow(({String id, String label, IconData icon}) row) {
    final checked = _selectedServiceIds.contains(row.id);

    return Semantics(
      button: true,
      checked: checked,
      label: row.label,
      child: InkWell(
        onTap: () => _toggleService(row.id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: checked ? kPrimary.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: checked ? kPrimary : kBorder,
              width: checked ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            _checkBox(checked),
            const SizedBox(width: 10),
            Icon(row.icon, size: 17, color: checked ? kPrimary : kTextSub),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
                  color: checked ? kPrimaryDeep : kTextMain,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _checkBox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? kPrimary : kBorderStrong,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }

  Widget _visitInformationCard() {
    final v = _visitor;
   // final now = DateTime.now();
    final count = _selectedServiceIds.length;

    return _panel(
      key: const ValueKey('step2/visit_info_card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(Icons.calendar_month_outlined, 'Visit Information'),
          const SizedBox(height: 12),
          if (v != null) ...[
            _stepTwoVisitorSummary(v),
            const SizedBox(height: 12),
          ],
          _timeRow(),
          const SizedBox(height: 12),
           _periodPicker(),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          _eyebrow(Icons.checklist_rounded, 'Selected Services ($count)'),
          const SizedBox(height: 10),
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count == 0)
                  _noServicesSelected()
                else
                  for (final id in _selectedServiceIds) _selectedServiceRow(id),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: () => _goToStep(0),
              style: OutlinedButton.styleFrom(
                foregroundColor: kTextMain,
                side: const BorderSide(color: kBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed:
                  (_hasServices && _hasReason) ? _continueFromStepTwo : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.borderStrong,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Continue',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }
    Widget _periodPicker() {
    final periods = ReferenceCatalog.periodsNewestFirst;
    final currentId = ReferenceCatalog.currentPeriod?.id;
    final safe = periods.any((p) => p.id == _academicPeriodId)
        ? _academicPeriodId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('School Year · Semester', style: kFieldLabelStyle),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('period_$safe'),
          initialValue: safe,
          isExpanded: true,
          hint: Text(
            periods.isEmpty ? 'No school year on file' : 'Choose school year',
            style: const TextStyle(fontSize: 12.5, color: kTextMuted),
          ),
          items: [
            for (final p in periods)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                  p.id == currentId ? '${p.label}  (Current)' : p.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: kTextMain),
                ),
              ),
          ],
          onChanged: periods.isEmpty
              ? null
              : (v) => setState(() => _academicPeriodId = v),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: kFieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }
  Widget _timeRow() {
    final inAt = _checkedInAt ?? _serverNow();
    final outAt = _timeOutAt ?? _serverNow();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: _timeTile(
          key: const ValueKey('time_in_tile'),
          icon: Icons.login_rounded,
          label: 'Time In',
          value: inAt,
          auto: !_timeInEdited,
          locked: _isEditing,
          onTap: () => _pickTime(isIn: true),
          onReset: () => setState(() {
            _checkedInAt = _serverNow();
            _timeInEdited = false;
          }),
        ),
      ),
      if (!_isEditing) ...[
        const SizedBox(width: 12),
        Expanded(
          child: _timeTile(
            key: const ValueKey('time_out_tile'),
            icon: Icons.logout_rounded,
            label: 'Time Out',
            value: outAt,
            auto: _timeOutAt == null,
            locked: false,
            onTap: () => _pickTime(isIn: false),
            onReset: () => setState(() => _timeOutAt = null),
          ),
        ),
      ],
    ]);
  }

  Widget _timeTile({
    Key? key,
    required IconData icon,
    required String label,
    required DateTime value,
    required bool auto,
    required bool locked,
    required VoidCallback onTap,
    required VoidCallback onReset,
  }) {
    return InkWell(
      key: key,
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: kPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 11.5, color: kTextSub)),
              ),
              if (locked)
                const Icon(Icons.lock_outline, size: 13, color: kTextMuted)
              else if (!auto)
                InkWell(
                  onTap: onReset,
                  child: const Tooltip(
                    message: 'Use the current time again',
                    child: Icon(Icons.restart_alt_rounded,
                        size: 15, color: kTextMuted),
                  ),
                )
              else
                const Icon(Icons.edit_calendar_outlined,
                    size: 14, color: kTextMuted),
            ]),
            const SizedBox(height: 4),
            Text(VisitTimes.date(value),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kTextSub)),
            Text(VisitTimes.clock(value),
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            if (auto && !locked)
              const Text('Auto · tap to edit',
                  style: TextStyle(fontSize: 10.5, color: kTextMuted)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isIn}) async {
    final current =
        isIn ? (_checkedInAt ?? _serverNow()) : (_timeOutAt ?? _serverNow());
    final today = _serverNow();

    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (day == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final picked = VisitTimes.combine(day, time.hour, time.minute);

    if (isIn) {
      if (VisitTimes.outBeforeIn(picked, _timeOutAt)) {
        _toast(VisitTimes.outBeforeInMessage, kDanger);
        return;
      }
      setState(() {
        _checkedInAt = picked;
        _timeInEdited = true;
      });
    } else {
      if (VisitTimes.outBeforeIn(_checkedInAt, picked)) {
        _toast(VisitTimes.outBeforeInMessage, kDanger);
        return;
      }
      setState(() => _timeOutAt = picked);
    }
  }
 

  Widget _selectedServiceRow(String id) {
    final label = _serviceLabel(id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(_iconForService(id), size: 18, color: kPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: kTextMain),
          ),
        ),
        IconButton(
          onPressed: () => _toggleService(id),
          icon: const Icon(Icons.close_rounded, size: 18),
          color: kPrimary,
          tooltip: 'Remove $label',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        ),
      ]),
    );
  }

  Widget _noServicesSelected() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: const Column(children: [
        Icon(Icons.playlist_add_check_rounded, size: 36, color: kTextMuted),
        SizedBox(height: 10),
        Text('No services selected yet',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain)),
        SizedBox(height: 4),
        Text(
          'Tick a service on the left to add it here.',
          textAlign: TextAlign.center,
          style: kCaptionStyle,
        ),
      ]),
    );
  }

  Widget _eyebrow(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 20, color: kPrimary),
      const SizedBox(width: 10),
      Expanded(child: Text(label.toUpperCase(), style: kEyebrowStyle)),
    ]);
  }

  Widget _tealBanner({
    required IconData icon,
    required String message,
    String? title,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextMain)),
                  const SizedBox(height: 2),
                ],
                Text(message,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: title != null ? kTextSub : kTextMain,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final v = _visitor;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.fact_check_outlined, size: 20, color: kPrimary),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review & Complete', style: kSectionTitleStyle),
                  SizedBox(height: 2),
                  Text('Check the visit before it is written to the record',
                      style: kSectionSubtitleStyle),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v == null)
                  _noteBanner(kWarning, Icons.person_search_outlined,
                      'Pick a visitor on step 1 before completing a visit.')
                else if (!_hasReason)
                  _noteBanner(kWarning, Icons.edit_note_outlined,
                      'Enter the reason for the visit on step 2.')
                else if (!_hasServices)
                  _noteBanner(kWarning, Icons.healing_outlined,
                      'Tick at least one service for this visit on step 2.')
                else ...[
                  VisitReviewCard(title: 'Visitor', lines: [
                    VisitReviewLine.pair('Name', v.fullName),
                    VisitReviewLine.pair('School ID', v.id),
                    VisitReviewLine.pair('Role', v.category),
                    VisitReviewLine.pair('Affiliation', v.affiliationLabel),
                    VisitReviewLine.pair('Contact', _orDash(v.contact)),
                  ]),
                  const SizedBox(height: 14),
                  VisitReviewCard(title: 'Service', lines: [
                    VisitReviewLine.pair(
                        'Services ticked', '${_selectedServiceIds.length}'),
                    for (final id in _selectedServiceIds)
                      VisitReviewLine.plain(_serviceLabel(id)),
                    VisitReviewLine.pair('Procedure required',
                        _requiresProcedure ? 'Yes' : 'No'),
                  ]),
                  const SizedBox(height: 14),
                  _serviceDetailGroups(),
                  const SizedBox(height: 14),
                   VisitReviewCard(title: 'Record', lines: [
                    VisitReviewLine.pair(
                        'Time in',
                        _checkedInAt == null
                            ? '—'
                            : VisitTimes.stamp(_checkedInAt!)),
                    if (!_isEditing)
                      VisitReviewLine.pair(
                          'Time out',
                          _timeOutAt == null
                              ? 'Server time on completion'
                              : VisitTimes.stamp(_timeOutAt!)),
                    VisitReviewLine.pair('Recorded by', _currentUserName),
                  ]),
                  if (_patientUuid == null) ...[
                    const SizedBox(height: 14),
                    _noteBanner(
                      kDanger,
                      Icons.error_outline,
                      "This visitor's clinic record is not ready yet, so the "
                      'visit cannot be saved. Go back to step 1 and pick '
                      'them again.',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceDetailGroups() {
    final controller = _details;
    if (controller == null || controller.drafts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final draft in controller.drafts) ...[
          VisitReviewCard(
              title: draft.label,
              lines: visitReviewLines(draft, _details!.vitals,
                  canSeeRestricted:
                      AccountService.canSeeRestrictedCounselling)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _wizardFooter() {
    final isLast = _step == _stepTitles.length - 1;

    final isDetails = _step == 2;
    final canAdvance = isLast
        ? _canSave
        : isDetails
            ? _hasServices
            : _step + 1 <= _maxReachable;
    final label = isLast
        ? 'Complete Consultation'
        : isDetails
            ? 'Continue'
            : 'Proceed';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: SafeArea(
        top: false,
        child: Row(children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: () => _goToStep(_step - 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: kTextMain,
                side: const BorderSide(color: kBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
          ],
          const Spacer(),
          ElevatedButton.icon(
            onPressed: (_saving || !canAdvance)
                ? null
                : (isLast
                    ? _completeConsultation
                    : isDetails
                        ? _saveStepThree
                        : () => _goToStep(_step + 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.borderStrong,
              disabledForegroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 16,
                  ),
            label: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _saveStepThreeToServer(String visitId) async {
    final controller = _details;
    if (controller == null || controller.drafts.isEmpty) return;
    try {
      await VisitDetailsService.saveAll(
        visitId: visitId,
        controller: controller,
        userName: _currentUserName,
      );
    } catch (e) {
      debugPrint('clinic visit: step 3 save failed: $e');
      if (!mounted) return;
      _toast('Visit saved, but the service details did not. Re-check step 3.',
          kWarning);
    }
  }

  void _saveStepThree() {
    final controller = _detailsFor();
    final label = controller.active?.label ?? 'Service';
    if (controller.active == null) {
      _toast('Pick a service to record first.', kWarning);
      return;
    }

    final allDone = controller.saveAndContinue();

    final outstanding = controller.outstanding;
    setState(() {});
    if (!allDone) {
      _toast(
          outstanding.isEmpty
              ? '$label not finished yet — fill in the required boxes.'
              : '$label saved. Before you continue: ${outstanding.first}',
          kWarning);
      return;
    }

    _goToStep(_stepTitles.length - 1);
    if (outstanding.isNotEmpty) {
      _toast(
          'All services recorded. Note before completing: ${outstanding.first}',
          kWarning);
    }
  }

  Future<void> _showAddVisitorDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String role = 'Student';
    String? program;
    String? yearLevel;
    String? institute;
    String? department;
    String? position;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isStudent = role == 'Student';
          final isFaculty = role == 'Faculty';
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.person_add_alt_1_rounded, color: kPrimary, size: 22),
              SizedBox(width: 8),
              Text('Add New Visitor'),
            ]),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogLabel('First Name'),
                      _dialogField(firstCtrl,
                          placeholder: 'e.g. Maria',
                          prefixIcon: Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogLabel('Last Name'),
                      _dialogField(lastCtrl,
                          placeholder: 'e.g. Santos',
                          prefixIcon: Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogLabel('School ID'),
                      _dialogField(
                        idCtrl,
                        placeholder: isStudent
                            ? '6-digit student number'
                            : 'leave blank to auto-generate',
                        prefixIcon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: isStudent
                            ? [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ]
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _dialogLabel('Role Type'),
                      _dialogDropdown(
                        value: role,
                        items: const ['Student', 'Faculty', 'Staff'],
                        onChanged: (v) => setLocal(() {
                          role = v ?? 'Student';
                          program = null;
                          yearLevel = null;
                          institute = null;
                          department = null;
                          position = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabel(isStudent
                          ? 'Program'
                          : isFaculty
                              ? 'Institute'
                              : 'Department'),
                      if (isStudent)
                        _programDropdown(
                            value: program,
                            onChanged: (v) => setLocal(() => program = v))
                      else if (isFaculty)
                        _dialogDropdown(
                          value: institute ?? '',
                          items: kInstitutes,
                          allowEmpty: true,
                          emptyLabel: 'Select an institute',
                          onChanged: (v) => setLocal(() => institute = v),
                        )
                      else
                        _dialogDropdown(
                          value: department ?? '',
                          items: departmentOptionsFor(role),
                          allowEmpty: true,
                          emptyLabel: 'Select a department',
                          onChanged: (v) => setLocal(() => department = v),
                        ),
                      const SizedBox(height: 12),
                      _dialogLabel(isStudent ? 'Year Level' : 'Position'),
                      _dialogDropdown(
                        value: isStudent ? yearLevel ?? '' : position ?? '',
                        items:
                            isStudent ? kYearLevels : positionOptionsFor(role),
                        allowEmpty: true,
                        emptyLabel: isStudent
                            ? 'Select a year level'
                            : 'Select a position',
                        onChanged: (v) => setLocal(() {
                          if (isStudent) {
                            yearLevel = v;
                          } else {
                            position = v;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabel('Contact Number'),
                      _dialogField(
                        contactCtrl,
                        placeholder: '09XXXXXXXXX',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        required: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final ok = await _createVisitor(
                    ctx: ctx,
                    role: role,
                    first: firstCtrl.text.trim(),
                    last: lastCtrl.text.trim(),
                    requestedId: idCtrl.text.trim(),
                    contact: contactCtrl.text.trim(),
                    program: program ?? '',
                    yearLevel: yearLevel ?? '',
                    institute: institute ?? '',
                    department: department ?? '',
                    position: position ?? '',
                  );
                  if (ctx.mounted) Navigator.pop(ctx, ok);
                },
                child: const Text('Add Visitor'),
              ),
            ],
          );
        },
      ),
    );

    if (created == true) {
      _toast('Visitor added. They are now in the search list.', kPrimary);
    }
  }

  Future<bool> _createVisitor({
    required BuildContext ctx,
    required String role,
    required String first,
    required String last,
    required String requestedId,
    required String contact,
    required String program,
    required String yearLevel,
    required String institute,
    required String department,
    required String position,
  }) async {
    final isStudent = role == 'Student';

    final id = isStudent
        ? requestedId
        : (requestedId.isNotEmpty
            ? requestedId
            : await IndividualRecordService.nextIdFor(role));

    if (id.isEmpty) {
      _toast('Enter the School ID for a new student.', kWarning);
      return false;
    }

    final periodId = kCurrentAcademicPeriodId;
    if (periodId == null || periodId.isEmpty) {
      _toast(
          'There is no current term to enrol them in. Set one on the Individual '
          'Record page first.',
          kWarning);
      return false;
    }

    final programId =
        isStudent ? ReferenceCatalog.programIdFor(null, program) : null;
    final instituteId = isStudent
        ? ReferenceCatalog.instituteIdOfProgram(programId)
        : ReferenceCatalog.instituteByCode(institute)?.id;
    final departmentId =
        isStudent ? null : ReferenceCatalog.departmentIdByName(department);
    final positionId =
        isStudent ? null : ReferenceCatalog.positionIdByName(position);

    final existing = await IndividualRecordService.fetchLatest(role, id);

    if (existing != null) {
      if (existing.isArchived) {
        _toast(
            '$role $id is archived. Restore them from the Archive page '
            'before checking them in.',
            kWarning);
        return false;
      }

      if (existing.academicPeriodId == periodId &&
          existing.status == kRecordStatusActive) {
        _toast(
            '$role $id is already on the roster for '
            '${academicTermLabel(kCurrentAcademicYear, kCurrentSemester)}.',
            kWarning);
        return false;
      }

      final reEnrolled = await _enrolExisting(
        existing: existing,
        role: role,
        contact: contact,
        academicPeriodId: periodId,
        instituteId: instituteId,
        programId: programId,
        yearLevel: isStudent ? yearLevel : '',
        departmentOfficeId: departmentId,
        positionId: positionId,
      );
      if (reEnrolled == null) return false;
      if (!mounted) return false;
      PatientDirectory.instance.upsert(_profileFromRecord(reEnrolled));
      await _selectVisitor(_profileFromRecord(reEnrolled));
      return true;
    }

    final record = IndividualRecord(
      id: id,
      category: role,
      firstName: first,
      lastName: last,
      sex: '',
      contact: contact,
      academicPeriodId: periodId,
      academicYear: kCurrentAcademicYear,
      semester: kCurrentSemester,
      instituteId: instituteId,
      institute: isStudent ? (instituteOfProgram(program) ?? '') : institute,
      programId: programId,
      program: isStudent ? program : '',
      yearLevel: isStudent ? yearLevel : '',
      departmentOfficeId: departmentId,
      department: isStudent ? '' : department,
      positionId: positionId,
      position: isStudent ? '' : position,
    );

    IndividualRecord saved;
    try {
      saved = await IndividualRecordService.create(record);
    } on IndividualRecordSaveIncomplete catch (e) {
      saved = e.record;
      _toast(e.message, kWarning);
    } catch (e) {
      _toast(
        IndividualRecordService.describeWriteFailure(
          e,
          category: role,
          recordNo: record.id,
        ),
        kDanger,
      );
      return false;
    }
    if (!mounted) return false;

    final profile = _profileFromRecord(saved);
    PatientDirectory.instance.upsert(profile);
    await _selectVisitor(profile);
    return true;
  }

  Future<IndividualRecord?> _enrolExisting({
    required IndividualRecord existing,
    required String role,
    required String contact,
    required String academicPeriodId,
    required String? instituteId,
    required String? programId,
    required String yearLevel,
    required String? departmentOfficeId,
    required String? positionId,
  }) async {
    final uuid = existing.uuid;
    if (uuid == null) return null;

    final draft = IndividualRecord(
      uuid: uuid,
      id: existing.id,
      category: role,
      firstName: existing.firstName,
      middleName: existing.middleName,
      lastName: existing.lastName,
      suffix: existing.suffix,
      sex: existing.sex,
      birthDate: existing.birthDate,
      contact: contact.isEmpty ? existing.contact : contact,
      email: existing.email,
      address: existing.address,
      academicPeriodId: academicPeriodId,
      academicYear: kCurrentAcademicYear,
      semester: kCurrentSemester,
      instituteId: instituteId ?? existing.instituteId,
      programId: programId,
      yearLevel: yearLevel,
      departmentOfficeId: departmentOfficeId,
      positionId: positionId,
      status: kRecordStatusActive,
    );

    try {
      return await IndividualRecordService.update(draft);
    } on IndividualRecordSaveIncomplete catch (e) {
      _toast(e.message, kWarning);
      return e.record;
    } catch (e) {
      _toast(
        IndividualRecordService.describeWriteFailure(
          e,
          category: role,
          recordNo: draft.id,
        ),
        kDanger,
      );
      return null;
    }
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(20),
    Key? key,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }

  Widget _noteBanner(Color color, IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style:
                const TextStyle(fontSize: 12.5, color: kTextMain, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _initialsAvatar(ClinicProfile p, double radius) {
    final letters = [p.firstName, p.lastName]
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim()[0].toUpperCase())
        .take(2)
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: kPrimary.withValues(alpha: 0.10),
      child: Text(
        letters.isEmpty ? '?' : letters,
        style: TextStyle(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w800,
          color: kPrimary,
        ),
      ),
    );
  }

  Widget _roleBadge(String category, {double fontSize = 11.5}) {
    late final Color bg;
    late final Color fg;
    switch (category) {
      case 'Faculty':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
      case 'Staff':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
      default:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _dialogLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextSub),
        ),
      );

  InputDecoration _dialogDecoration(
    String hint, {
    IconData? prefixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: kTextSub),
      errorText: errorText,
      filled: true,
      fillColor: kFieldFill,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 18, color: kTextSub),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: _dialogBorder(kBorder),
      enabledBorder: _dialogBorder(kBorder),
      focusedBorder: _dialogBorder(kPrimary, width: 1.5),
      errorBorder: _dialogBorder(kDanger),
      focusedErrorBorder: _dialogBorder(kDanger, width: 1.5),
    );
  }

  OutlineInputBorder _dialogBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _dialogField(
    TextEditingController controller, {
    required String placeholder,
    IconData? prefixIcon,
    bool required = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: kTextMain),
      validator: (v) =>
          required && (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: _dialogDecoration(placeholder, prefixIcon: prefixIcon),
    );
  }

  Widget _dialogDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool allowEmpty = false,
    String emptyLabel = 'Select',
  }) {
    final options = <String>[
      if (allowEmpty) '',
      ...items.where((e) => e.isNotEmpty),
    ];
    if (value.isNotEmpty && !options.contains(value)) options.add(value);

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      onChanged: onChanged,
      items: options
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e.isEmpty ? emptyLabel : e,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: e.isEmpty ? kTextSub : kTextMain,
                  ),
                ),
              ))
          .toList(),
      decoration: _dialogDecoration(emptyLabel),
    );
  }

  Widget _reasonOfVisitField() {
    final empty = _reasonForVisitCtrl.text.trim().isEmpty;
    OutlineInputBorder box(Color color) =>
        OutlineInputBorder(borderSide: BorderSide(color: color));
    return TextFormField(
      controller: _reasonForVisitCtrl,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Enter reason of visit (required)',
        filled: true,
        fillColor: empty ? kDangerContainer : kFieldFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: box(empty ? kDanger : kBorder),
        enabledBorder: box(empty ? kDanger : kBorder),
        focusedBorder: box(kPrimary),
      ),
    );
  }

  Widget _programDropdown({
    required String? value,
    required void Function(String?) onChanged,
  }) {
    final list = value == null || value.isEmpty ? kInstitutes : <String>[value];
    return _dialogDropdown(
      value: value ?? '',
      items: list,
      allowEmpty: true,
      emptyLabel: 'Select a program',
      onChanged: onChanged,
    );
  }

  String _orDash(String? value) {
    final t = (value ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  String _formatDate(String? iso) {
    final raw = (iso ?? '').trim();
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, yyyy').format(parsed);
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 52),
      ),
    );
  }
}
