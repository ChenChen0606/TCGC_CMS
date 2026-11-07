import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/patients/widgets/student_import_dialog.dart';

const String _kAddProgram = '__add_program__';
const String _kAddDepartment = '__add_department__';
const String _kAddPosition = '__add_position__';
const String _kAddInstitute = '__add_institute__';

const String _kAddTerm = '__add_term__';

bool _isOpenTerm(String year, String semester) {
  final active = ReferenceCatalog.activePeriod;
  if (active == null) return isCurrentTerm(year, semester);
  return ReferenceCatalog.periodIdFor(year, semester) == active.id;
}

class IndividualRecordScreen extends StatefulWidget {
  const IndividualRecordScreen({super.key});

  @override
  State<IndividualRecordScreen> createState() => _IndividualRecordScreenState();
}

class _IndividualRecordScreenState extends State<IndividualRecordScreen>
    with TickerProviderStateMixin {
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  static const Color kStudentColor = AppColors.student;
  static const Color kFacultyColor = AppColors.faculty;
  static const Color kStaffColor = AppColors.staff;
  static const Color kSuccess = AppColors.success;
  static const Color kBg = AppColors.bg;

  String filter = 'Student';
  final TextEditingController search = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  bool _loading = true;
  String? _loadError;

  Map<String, String> _userNames = const {};

  String? _filterAcademicPeriodId;

  bool _showInactive = false;

  bool _saving = false;

  VoidCallback? _dataListener;

  IndividualRecord? _editing;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  int _formStep = 0;
  static const int _formStepCount = 3;

  StateSetter? _dlgSet;

  bool _fetchingId = false;

  int _pickerEpoch = 0;

  Future<void> _tryLoadExistingPerson() async {
    if (_editing != null) return;
    final id = _cId.text.trim();
    if (id.isEmpty) return;
    final cat = _fCategory;
    if (cat == null) return;
    try {
      final existing = await IndividualRecordService.fetchLatest(cat, id);
      if (existing != null && mounted) {
        setState(() {
          _cFirst.text = existing.firstName;
          _cMiddle.text = existing.middleName;
          _cLast.text = existing.lastName;
          _cSuffix.text = existing.suffix;
          _fSex = existing.sex.isNotEmpty ? existing.sex : null;
          _fBirthDate = existing.birthDate;
          _cBirth.text = existing.birthDate == null
              ? ''
              : DateFormat('MMM d, yyyy').format(existing.birthDate!);
          _cContact.text = existing.contact;
          _cEmail.text = existing.email;
          _cAddress.text = existing.address;
        });
        _refreshForm();
      }
    } catch (_) {}
  }

  void _resetPickers() {
    if (!mounted) return;
    setState(() => _pickerEpoch++);
    _refreshForm();
  }

  int _idRequest = 0;

  final TextEditingController _cId = TextEditingController();
  final TextEditingController _cFirst = TextEditingController();
  final TextEditingController _cMiddle = TextEditingController();
  final TextEditingController _cLast = TextEditingController();
  final TextEditingController _cSuffix = TextEditingController();
  final TextEditingController _cBirth = TextEditingController();
  final TextEditingController _cContact = TextEditingController();
  final TextEditingController _cEmail = TextEditingController();
  final TextEditingController _cAddress = TextEditingController();
  final TextEditingController _cYearStart = TextEditingController();
  final TextEditingController _cYearEnd = TextEditingController();

  String? _fCategory;
  String? _fSex;
  String? _fSemester;
  String? _fInstitute;
  String? _fProgram;
  String? _fYearLevel;
  String? _fDepartment;
  String? _fPosition;

  String? _fPeriodId;

  DateTime? _fBirthDate;

  Map<String, List<String>> get _catalog => kProgramCatalog;

  final List<IndividualRecord> _records = [];

  bool _suppressDirectoryRefresh = false;

  Future<void> _loadRecords({
    bool silent = false,
    bool? includeInactiveOverride,
    String? academicPeriodIdOverride,
  }) async {
    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      if (!silent) {
        try {
          await ReferenceCatalog.refreshPeriods();
        } catch (_) {}
      }

      final showAllTerms = includeInactiveOverride ?? _showInactive;
      final activeId = ReferenceCatalog.activePeriod?.id;
      final studentPeriodId = showAllTerms
          ? null
          : (academicPeriodIdOverride ?? _filterAcademicPeriodId ?? activeId);

      final results = await Future.wait([
        IndividualRecordService.fetchAll(
            includeInactive: true, academicPeriodId: studentPeriodId),
        IndividualRecordService.fetchAll(
            includeInactive: false, academicPeriodId: activeId),
        IndividualRecordService.fetchUserNames(),
      ]);
      final students = (results[0] as List<IndividualRecord>)
          .where((r) => r.category == 'Student');
      final others = (results[1] as List<IndividualRecord>)
          .where((r) => r.category != 'Student');
      final list = [...students, ...others]
          .where((r) => r.status != kRecordStatusArchived)
          .toList();
      final names = results[2] as Map<String, String>;
      if (!mounted) return;
      _userNames = names;
      _suppressDirectoryRefresh = true;
      PatientDirectory.instance.hydrate(list.map(_profileFromRecord).toList());
      _suppressDirectoryRefresh = false;
      setState(() {
        _records
          ..clear()
          ..addAll(list);
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _onSearchChanged(String _) {
    setState(() {});
  }

  void _directoryListener() {
    if (!mounted || _suppressDirectoryRefresh) return;
    _loadRecords(silent: true);
  }

  void _pushToDirectory(IndividualRecord r) {
    PatientDirectory.instance.upsert(_profileFromRecord(r));
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
      updatedAt: null,
      updatedBy: null,
    );
  }

  @override
  void initState() {
    super.initState();
    PatientDirectory.instance.subscribe(_directoryListener);
    ReferenceCatalog.subscribe(_catalogListener);
    ReferenceCatalog.loadQuietly();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
    final ay = _splitAcademicYear(_defaultAcademicYear);
    _cYearStart.text = ay.$1;
    _cYearEnd.text = ay.$2;
    _loadRecords();
    _dataListener = () => _loadRecords(silent: true);
    DataTracker.listen(_dataListener!);
  }

  void _catalogListener() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    ReferenceCatalog.unsubscribe(_catalogListener);
    PatientDirectory.instance.unsubscribe(_directoryListener);
    _fadeCtrl.dispose();
    search.dispose();
    _cId.dispose();
    _cFirst.dispose();
    _cMiddle.dispose();
    _cLast.dispose();
    _cSuffix.dispose();
    _cBirth.dispose();
    _cContact.dispose();
    _cEmail.dispose();
    _cAddress.dispose();
    _cYearStart.dispose();
    _cYearEnd.dispose();
    super.dispose();
  }

  static String get _defaultAcademicYear => kCurrentAcademicYear;

  static String get _defaultSemester => kCurrentSemester;

  static (String, String) _splitAcademicYear(String ay) {
    final parts = ay.split('-');
    if (parts.length == 2 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null) {
      return (parts[0], parts[1]);
    }
    final def = _defaultAcademicYear.split('-');
    return (def[0], def[1]);
  }

  String get _composedAcademicYear =>
      '${_cYearStart.text.trim()}-${_cYearEnd.text.trim()}';

  List<({String year, String semester})> _sortedTerms() {
    int rank(String s) => kSemesters.indexOf(s);
    final list = [
      for (final t in kAcademicTerms) (year: t.year, semester: t.semester)
    ];
    list.sort((a, b) {
      final y = b.year.compareTo(a.year);
      return y != 0 ? y : rank(b.semester).compareTo(rank(a.semester));
    });
    return list;
  }

  Widget _termBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5)),
      );

  String get _idLabel => filter == 'Student'
      ? 'Student ID'
      : filter == 'Faculty'
          ? 'Faculty ID'
          : 'Staff ID';

  List<IndividualRecord> get _filtered {
    var rows = _records;
    if (filter == 'Student' && !_showInactive) {
      final pid = _filterAcademicPeriodId ?? ReferenceCatalog.activePeriod?.id;
      if (pid != null) {
        rows = rows.where((r) => r.academicPeriodId == pid).toList();
      }
    }
    return filterRoster(rows: rows, category: filter, query: search.text);
  }

  int _countFor(String category) => countInCategory(_records, category);

  String _programValue(String institute, String program) =>
      '$institute|$program';

  (String, String)? _parseProgramValue(String? value) {
    if (value == null || value.isEmpty || value == _kAddProgram) return null;
    final i = value.indexOf('|');
    if (i < 0) return null;
    return (value.substring(0, i), value.substring(i + 1));
  }

  List<String> get _programOptions {
    final inst = _fInstitute;
    if (inst == null) return const <String>[];
    return List<String>.of(_catalog[inst] ?? const <String>[]);
  }

  List<String> _departmentOptions(String? category) => category == 'Faculty'
      ? (_catalog.keys.toList()..sort())
      : List<String>.of(kStaffDepartments);

  List<String> _positionOptions(String? category) => category == 'Faculty'
      ? List<String>.of(kFacultyPositions)
      : List<String>.of(kStaffPositions);

    Future<void> _openForm({IndividualRecord? edit}) async {
    if (edit != null && edit.status == kRecordStatusInactive) {
      _showError('This record belongs to a closed term and is view-only.');
      return;
    }
    if (!ReferenceCatalog.hasCoreData) {
      await ReferenceCatalog.ensureLoaded(force: true);
      if (!mounted) return;
    }
    final category = edit?.category ?? filter;
    setState(() {
      _editing = edit;
      _formStep = 0;
      _fCategory = category;
      _fSex = edit?.sex.isNotEmpty == true ? edit!.sex : null;
      _fSemester =
          edit?.semester.isNotEmpty == true ? edit!.semester : _defaultSemester;
      _fInstitute =
          (edit?.institute.isNotEmpty ?? false) ? edit!.institute : null;
      _fProgram = (edit?.program.isNotEmpty ?? false)
          ? _programValue(edit!.institute, edit.program)
          : null;
      _fYearLevel =
          (edit?.yearLevel.isNotEmpty ?? false) ? edit!.yearLevel : null;

      final dept = category == 'Faculty'
          ? ((edit?.institute.isNotEmpty ?? false) ? edit!.institute : null)
          : ((edit?.department.isNotEmpty ?? false) ? edit!.department : null);
      _fDepartment =
          (dept != null && _departmentOptions(category).contains(dept))
              ? dept
              : null;
      final pos = (edit?.position.isNotEmpty ?? false) ? edit!.position : null;
      _fPosition = (pos != null && _positionOptions(category).contains(pos))
          ? pos
          : null;
      if (_fProgram != null &&
          !_programOptions.contains(_parseProgramValue(_fProgram)?.$2)) {
        _fProgram = null;
      }
      _fBirthDate = edit?.birthDate;

      _cId.text = edit?.id ?? '';
      _cFirst.text = edit?.firstName ?? '';
      _cMiddle.text = edit?.middleName ?? '';
      _cLast.text = edit?.lastName ?? '';
      _cSuffix.text = edit?.suffix ?? '';
      _cBirth.text = edit?.birthDate == null
          ? ''
          : DateFormat('MMM d, yyyy').format(edit!.birthDate!);
      _cContact.text = edit?.contact ?? '';
      _cEmail.text = edit?.email ?? '';
      _cAddress.text = edit?.address ?? '';

      final ay = _splitAcademicYear(edit?.academicYear.isNotEmpty == true
          ? edit!.academicYear
          : _defaultAcademicYear);
      _cYearStart.text = ay.$1;
      _cYearEnd.text = ay.$2;
      _fPeriodId = (edit?.academicPeriodId?.isNotEmpty ?? false)
          ? edit!.academicPeriodId
          : ReferenceCatalog.periodIdFor(
              _composedAcademicYear, _fSemester ?? '');
    });

    if (edit == null && category != 'Student') _fillNextId(category);
    ReferenceCatalog.ensureLoaded(force: true).then((_) {
      if (!mounted) return;
      setState(() {});
      _refreshForm();
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          _dlgSet = setDlg;
          return _buildFormDialog(ctx, setDlg);
        },
      ),
    );
    
  }

  Future<void> _fillNextId(String category) async {
    if (_editing != null) return;
    final token = ++_idRequest;
    setState(() => _fetchingId = true);
    try {
      final next = await IndividualRecordService.nextIdFor(category);
      if (!mounted || _editing != null || token != _idRequest) return;
      setState(() {
        _cId.text = next;
        _fetchingId = false;
      });
      _refreshForm();
    } catch (_) {
      if (!mounted || _editing != null || token != _idRequest) return;
      setState(() {
        if (_cId.text.trim().isEmpty) {
          _cId.text = PatientDirectory.instance.nextIdFor(category);
        }
        _fetchingId = false;
      });
      _refreshForm();
    }
  }

  void _refreshForm() => _dlgSet?.call(() {});

  void _closeFormDialog(BuildContext ctx) {
    _dlgSet = null;
    Navigator.pop(ctx);
  }

  void _formNext(StateSetter setDlg) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setDlg(() => setState(() => _formStep++));
  }

  void _saveForm(BuildContext ctx) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_saving) return;
    _saveFormAsync(ctx);
  }

  String _effectiveStatusFor(String academicYear, String semester) {
    final periodId =
        _fPeriodId ?? ReferenceCatalog.periodIdFor(academicYear, semester);
    return IndividualRecordService.statusForTerm(periodId);
  }

  Future<void> _saveFormAsync(BuildContext dialogCtx) async {
    final isEdit = _editing != null;
    final target = _editing;
    final category = _fCategory!;
    final isStudent = category == 'Student';

    if (isEdit && target!.status == kRecordStatusInactive) {
      _showError('This record belongs to a closed term and is view-only.');
      return;
    }

    if (!isEdit) {
      String? clash;
      try {
        if (isStudent) {
          final periodId = _fPeriodId ??
              ReferenceCatalog.periodIdFor(
                  _composedAcademicYear, _fSemester ?? '');
          final personId = _cId.text.trim();
          if (periodId != null &&
              periodId.isNotEmpty &&
              personId.isNotEmpty &&
              await IndividualRecordService.enrolmentExists(
                  personId, periodId)) {
            clash = '$personId already has a record in '
                '$_composedAcademicYear · ${_fSemester ?? ''}.\n\n'
                'Close this form and edit that record instead.';
          }
        } else {
          final otherId = await IndividualRecordService.identityClash(
            category,
            firstName: _cFirst.text,
            middleName: _cMiddle.text,
            lastName: _cLast.text,
            suffix: _cSuffix.text,
            birthDate: _fBirthDate,
          );
          if (otherId != null) {
            clash = '${_cFirst.text.trim()} ${_cLast.text.trim()} is already '
                'on file as $otherId.\n\n'
                'Close this form and edit that record instead of adding '
                'a new one.';
          }
        }
      } catch (_) {}

      if (clash != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Already Exists',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            content: Text(clash!,
                style: const TextStyle(fontSize: 14.5, height: 1.4)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    final parsedProgram = isStudent ? _parseProgramValue(_fProgram) : null;
    final programCode = parsedProgram?.$2 ?? '';
    final instituteId = isStudent
        ? ReferenceCatalog.instituteByCode(_fInstitute)?.id
        : (category == 'Faculty'
            ? ReferenceCatalog.instituteByCode(_fDepartment)?.id
            : null);
    final programId = isStudent
        ? ReferenceCatalog.programIdFor(instituteId, programCode)
        : null;
    final deptId = category == 'Staff'
        ? ReferenceCatalog.departmentIdByName(_fDepartment ?? '')
        : null;
    final posId =
        !isStudent ? ReferenceCatalog.positionIdByName(_fPosition ?? '') : null;

    final draft = IndividualRecord(
      uuid: target?.uuid,
      id: isEdit ? target!.id : _cId.text.trim(),
      category: category,
      academicPeriodId: _fPeriodId ??
          ReferenceCatalog.periodIdFor(_composedAcademicYear, _fSemester ?? ''),
      firstName: _cFirst.text.trim(),
      middleName: _cMiddle.text.trim(),
      lastName: _cLast.text.trim(),
      suffix: _cSuffix.text.trim(),
      sex: _fSex ?? '',
      birthDate: _fBirthDate,
      contact: _cContact.text.trim(),
      email: _cEmail.text.trim(),
      address: _cAddress.text.trim(),
      academicYear: _composedAcademicYear,
      semester: _fSemester ?? '',
      instituteId: instituteId,
      institute: isStudent
          ? (_fInstitute ?? '')
          : (category == 'Faculty' ? (_fDepartment ?? '') : ''),
      programId: programId,
      program: isStudent ? programCode : '',
      yearLevel: isStudent ? (_fYearLevel ?? '') : '',
      departmentOfficeId: deptId,
      department: category == 'Staff' ? (_fDepartment ?? '') : '',
      positionId: posId,
      position: isStudent ? '' : (_fPosition ?? ''),
      status: target?.status == kRecordStatusInactive
          ? kRecordStatusInactive
          : _effectiveStatusFor(_composedAcademicYear, _fSemester ?? ''),
    );

    setState(() => _saving = true);
    _refreshForm();

    try {
      final saved = isEdit
          ? await IndividualRecordService.update(draft,
              previousPeriodId: target?.academicPeriodId)
          : await IndividualRecordService.create(draft);

      final retired = isEdit
          ? 0
          : await IndividualRecordService.retireEarlierPeriods(
              [(category: category, recordNo: saved.id)],
              academicPeriodId: draft.academicPeriodId ?? '',
            );

      if (isEdit) {
        final i = _records.indexWhere((r) => r.uuid == saved.uuid);
        if (i >= 0) _records[i] = saved;
      } else {
        _records.add(saved);
        filter = category;
        search.clear();
      }
      _pushToDirectory(saved);

      _editing = null;
      if (mounted) setState(() => _saving = false);
      if (dialogCtx.mounted) _closeFormDialog(dialogCtx);
      _showResultDialog(
        isEdit ? 'Updated Record' : 'Saved Record',
        detail:
            retired > 0 ? '$retired earlier-term record(s) deactivated' : null,
      );
      if (mounted) await _loadRecords(silent: true);
    } catch (e) {
      if (e is IndividualRecordSaveIncomplete) {
        final saved = e.record;
        if (isEdit) {
          final i = _records.indexWhere((r) => r.uuid == saved.uuid);
          if (i >= 0) _records[i] = saved;
        } else {
          _records.add(saved);
          filter = category;
          search.clear();
        }
        _pushToDirectory(saved);
        _editing = null;
        if (mounted) setState(() => _saving = false);
        if (dialogCtx.mounted) _closeFormDialog(dialogCtx);
        _showError('${e.message}');
        return;
      }
      if (mounted) setState(() => _saving = false);
      _showError('Could not save the record: $e');
      _refreshForm();
    }
  }

  void _showResultDialog(
    String message, {
    String? detail,
    bool danger = false,
  }) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) =>
            _AutoCloseMessage(message: message, detail: detail, danger: danger),
      );
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kDanger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: Colors.white), maxLines: 3),
        ),
      ]),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: kBg,
        floatingActionButton: FloatingActionButton(
          onPressed: _openForm,
          backgroundColor: kPrimary,
          tooltip: 'Add Record',
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeaderRow(),
            const SizedBox(height: 20),
            _buildFilterBar(),
            const SizedBox(height: 16),
            _buildTabs(),
            const SizedBox(height: 14),
            if (_loadError != null && !_loading) ...[
              _loadErrorBanner(),
              const SizedBox(height: 14),
            ],
            Expanded(child: _buildTable(_filtered)),
          ]),
        ),
      ),
    );
  }

  Widget _loadErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDanger.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 18, color: kDanger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not refresh the record list — showing the last loaded data.',
            style: TextStyle(
                fontSize: 13.5, color: kDanger, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: _loadRecords,
          style: TextButton.styleFrom(
            foregroundColor: kDanger,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry'),
        ),
      ]),
    );
  }

  Widget _buildHeaderRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isNarrow = constraints.maxWidth < 700;

      final titleBlock = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kPrimary, kPrimaryDk],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.badge_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Individual Record',
                style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: kTextMain)),
            const Text('Manage Student, Faculty, & Staff Records',
                style: TextStyle(fontSize: 15, color: kTextSub)),
          ]),
        ],
      );

      final chips = _buildCategorySummary();

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), chips],
        );
      }
      return Row(children: [titleBlock, const Spacer(), chips]);
    });
  }

  Widget _buildCategorySummary() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _summaryChip('All', _records.length, kPrimary, Icons.groups_rounded),
      _summaryChip('Students', _countFor('Student'), kStudentColor,
          Icons.school_outlined),
      _summaryChip('Faculty', _countFor('Faculty'), kFacultyColor,
          Icons.co_present_outlined),
      _summaryChip(
          'Staff', _countFor('Staff'), kStaffColor, Icons.badge_outlined),
    ]);
  }

  Widget _summaryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$count',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildFilterBar() {
    final searchField = TextField(
      controller: search,
      onChanged: _onSearchChanged,
      style: const TextStyle(fontSize: 16, color: kTextMain),
      decoration: InputDecoration(
        hintText: 'Search by ID, name, program, contact...',
        hintStyle: const TextStyle(color: kTextSub, fontSize: 15),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () => setState(search.clear),
                icon:
                    const Icon(Icons.close_rounded, color: kTextSub, size: 18),
              ),
        filled: true,
        fillColor: kCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );

    final showImport = filter == 'Student';
    final importBtn = OutlinedButton.icon(
      onPressed: _openImportDialog,
      icon: const Icon(Icons.upload_file_rounded, size: 17, color: kPrimary),
      label: const Text('Import Record'),
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: const BorderSide(color: kPrimary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    );

    Widget yearFilter = const SizedBox.shrink();
    if (filter == 'Student') {
      final entries = <({String id, String year, String semester})>[];
      for (final t in _sortedTerms()) {
        final id = ReferenceCatalog.periodIdFor(t.year, t.semester);
        if (id != null && !entries.any((e) => e.id == id)) {
          entries.add((id: id, year: t.year, semester: t.semester));
        }
      }
      final activeId = ReferenceCatalog.activePeriod?.id;
      final wanted = _filterAcademicPeriodId ?? activeId;
      final value = _showInactive
          ? '__all__'
          : (entries.any((e) => e.id == wanted)
              ? wanted
              : (entries.isNotEmpty ? entries.first.id : null));

      Widget selectedRow(String text, {Widget? badge, IconData? icon}) => Row(
            children: [
              Icon(icon ?? Icons.calendar_month_outlined,
                  size: 18, color: kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        color: kTextMain,
                        fontWeight: FontWeight.w700)),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge],
            ],
          );

      Widget badgeFor(String id) => (activeId != null && id == activeId)
          ? _termBadge('CURRENT', kSuccess)
          : _termBadge('VIEW ONLY', kTextSub);

      yearFilter = Container(
        height: 48,
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
                color: kPrimary.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            menuMaxHeight: 420,
            focusColor: Colors.transparent,
            dropdownColor: kCard,
            borderRadius: BorderRadius.circular(14),
            icon:
                const Icon(Icons.keyboard_arrow_down_rounded, color: kPrimary),
            style: const TextStyle(
                fontSize: 14.5, color: kTextMain, fontWeight: FontWeight.w600),
            selectedItemBuilder: (_) => [
              for (final e in entries)
                selectedRow(academicTermLabel(e.year, e.semester),
                    badge: badgeFor(e.id)),
              selectedRow('Add year-semester...',
                  icon: Icons.add_circle_outline),
              selectedRow('Show all', icon: Icons.layers_outlined),
            ],
            items: [
              for (final e in entries)
                DropdownMenuItem<String>(
                  value: e.id,
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        academicTermLabel(e.year, e.semester),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: e.id == activeId
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    badgeFor(e.id),
                  ]),
                ),
              const DropdownMenuItem<String>(
                value: _kAddTerm,
                child: Row(children: [
                  Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
                  SizedBox(width: 8),
                  Text('Add year-semester...',
                      style: TextStyle(
                          color: kPrimary, fontWeight: FontWeight.w700)),
                ]),
              ),
              const DropdownMenuItem<String>(
                value: '__all__',
                child: Row(children: [
                  Icon(Icons.layers_outlined, size: 17, color: kTextSub),
                  SizedBox(width: 8),
                  Text('Show all (including inactive)'),
                ]),
              ),
            ],
            onChanged: (v) async {
              if (v == _kAddTerm) {
                final period = await showDialog<AcademicPeriodOption>(
                  context: context,
                  builder: (ctx) => const _AddPeriodDialog(),
                );
                if (period != null && mounted) {
                  setState(() {
                    _showInactive = false;
                    _filterAcademicPeriodId = period.id;
                  });
                  await ReferenceCatalog.refreshPeriods();
                  _loadRecords(
                      includeInactiveOverride: false,
                      academicPeriodIdOverride: period.id);
                }
                return;
              }
              if (v == '__all__') {
                setState(() {
                  _showInactive = true;
                  _filterAcademicPeriodId = null;
                });
                _loadRecords(includeInactiveOverride: true);
              } else {
                setState(() {
                  _showInactive = false;
                  _filterAcademicPeriodId = v;
                });
                _loadRecords(
                    includeInactiveOverride: false,
                    academicPeriodIdOverride: v);
              }
            },
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (ctx, con) {
      final w = con.maxWidth;
      if (w < 780) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          searchField,
          if (filter == 'Student') ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: yearFilter),
          ],
          if (showImport) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: importBtn),
          ],
        ]);
      }
      return Row(children: [
        Expanded(child: searchField),
        if (filter == 'Student') ...[
          const SizedBox(width: 12),
          SizedBox(width: 340, child: yearFilter),
        ],
        if (showImport) ...[
          const SizedBox(width: 12),
          importBtn,
        ],
      ]);
    });
  }

  Widget _buildTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: ['Student', 'Faculty', 'Staff'].map((tab) {
          final sel = filter == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (filter == tab) return;
                setState(() => filter = tab);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                              color: kPrimary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab == 'Student'
                          ? Icons.school_outlined
                          : tab == 'Faculty'
                              ? Icons.person_outlined
                              : Icons.badge_outlined,
                      size: 15,
                      color: sel ? Colors.white : kTextSub,
                    ),
                    const SizedBox(width: 6),
                    Text(tab,
                        style: TextStyle(
                          color: sel ? Colors.white : kTextSub,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 16,
                        )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static const List<String> _formStepTitles = [
    'Record Type & School Year',
    'Personal Information',
    'Academic / Employment',
  ];

  Widget _buildFormDialog(BuildContext ctx, StateSetter setDlg) {
    final isEdit = _editing != null;
    final isStudent = _fCategory == 'Student';
    final screen = MediaQuery.of(ctx).size.width;
    final w = screen < 620 ? screen * 0.92 : 560.0;

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: w,
        constraints: const BoxConstraints(maxHeight: 660),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _formDialogHeader(ctx, isEdit),
          const Divider(color: kBorder, height: 1),
          _formStepBar(),
          Flexible(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                child: _formStepBody(isStudent),
              ),
            ),
          ),
          const Divider(color: kBorder, height: 1),
          _formDialogFooter(ctx, setDlg, isEdit),
        ]),
      ),
    );
  }

  Widget _formDialogHeader(BuildContext ctx, bool isEdit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isEdit ? Icons.edit_outlined : Icons.person_add_outlined,
              color: kPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Update Record' : 'Add New Record',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            Text('${_fCategory ?? ''} record',
                style: const TextStyle(fontSize: 13.5, color: kTextSub)),
          ],
        )),
        IconButton(
          onPressed: () => _closeFormDialog(ctx),
          icon: const Icon(Icons.close_rounded, color: kTextSub),
          iconSize: 20,
          tooltip: 'Close',
        ),
      ]),
    );
  }

  Widget _formStepBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < _formStepCount; i++) ...[
            Expanded(
                child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              decoration: BoxDecoration(
                color: i <= _formStep ? kPrimary : const Color(0xFFEEF2F6),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
            if (i < _formStepCount - 1) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 10),
        Text(
          'Step ${_formStep + 1} of $_formStepCount · ${_formStepTitles[_formStep]}',
          style: const TextStyle(
              fontSize: 12.5, color: kTextSub, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  Widget _formStepBody(bool isStudent) {
    switch (_formStep) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(Icons.badge_outlined, 'Record Details'),
          _fieldGrid([_categoryField(_editing != null), _idField()],
              columns: 2),
          const SizedBox(height: 16),
          _schoolYearFields(),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(Icons.person_outline, 'Personal Information'),
          _fieldGrid([
            _firstNameField(),
            _middleNameField(),
            _lastNameField(),
            _suffixField(),
            _sexField(),
            _birthField(),
            _contactField(),
            _emailField(),
          ], columns: 2),
          const SizedBox(height: 14),
          _addressField(),
        ]);


        default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (ReferenceCatalog.lastError != null) _catalogWarning(),
          _sectionHeader(
            isStudent ? Icons.school_outlined : Icons.work_outline,
            isStudent
                ? 'Academic Information'
                : (_fCategory == 'Faculty'
                    ? 'Teaching Assignment'
                    : 'Employment Information'),
          ),
          _fieldGrid(
            isStudent
                ? [_instituteField(), _programField(), _yearLevelField()]
                : [_departmentField(), _positionField()],
            columns: 2,
          ),
        ]);
    }
  }

  Widget _formDialogFooter(BuildContext ctx, StateSetter setDlg, bool isEdit) {
    final isLast = _formStep == _formStepCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: Row(children: [
        const Spacer(),
        if (_formStep > 0) ...[
          OutlinedButton.icon(
            onPressed: () => setDlg(() => setState(() => _formStep--)),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              foregroundColor: kTextSub,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (!isLast)
          ElevatedButton.icon(
            onPressed: () => _formNext(setDlg),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: _saving
                ? null
                : () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    _saveForm(ctx);
                  },
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(isEdit ? Icons.save_outlined : Icons.add, size: 16),
            label: Text(_saving
                ? 'Saving…'
                : (isEdit ? 'Update Record' : 'Save Record')),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: kPrimary.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
      ]),
    );
  }
  Widget _catalogWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kDanger.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.cloud_off_rounded, size: 16, color: kDanger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Could not load the lists.\n${ReferenceCatalog.lastError}',
            style: const TextStyle(fontSize: 12, color: kDanger),
          ),
        ),
        TextButton(
          onPressed: () async {
            await ReferenceCatalog.ensureLoaded(force: true);
            if (mounted) setState(() {});
            _refreshForm();
          },
          child: const Text('Retry'),
        ),
      ]),
    );
  }
  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Icon(icon, size: 17, color: kPrimary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: kTextMain,
                letterSpacing: 0.3)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: kBorder, height: 1)),
      ]),
    );
  }

  Widget _fieldGrid(List<Widget> fields, {required int columns}) {
    const gap = 12.0;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: fields.map((f) => SizedBox(width: w, child: f)).toList(),
      );
    });
  }

  String? _requiredText(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Widget _categoryField(bool isEdit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Record Category'),
      DropdownButtonFormField<String>(
        initialValue: _fCategory,
        isExpanded: true,
        onChanged: isEdit
            ? null
            : (v) {
                if (v == null || v == _fCategory) return;
                _fCategory = v;
                _fInstitute = null;
                _fProgram = null;
                _fYearLevel = null;
                _fDepartment = null;
                _fPosition = null;
                if (v == 'Student') {
                  _cId.clear();
                } else {
                  _cId.clear();
                  _fillNextId(v);
                }
                _refreshForm();
              },
        decoration: _ideco('Select category',
            prefixIcon: Icons.category_outlined, readOnly: isEdit),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: const ['Student', 'Faculty', 'Staff']
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
      ),
    ]);
  }

  Widget _idField() {
    final isStudent = _fCategory == 'Student';
    final isEdit = _editing != null;
    final readOnly = !isStudent || isEdit;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel(isStudent
          ? 'Student ID'
          : (_fCategory == 'Faculty' ? 'Faculty ID' : 'Staff ID')),
      TextFormField(
        controller: _cId,
        readOnly: readOnly,
        keyboardType: isStudent ? TextInputType.number : TextInputType.text,
        inputFormatters: isStudent
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6)
              ]
            : [],
        onChanged: (v) {
          if (!isEdit && isStudent && v.trim().length == 6) {
            _tryLoadExistingPerson();
          }
        },
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: readOnly ? kTextSub : kTextMain,
        ),
        decoration: _ideco('e.g. 2025F001',
            prefixIcon: Icons.badge_outlined,
            readOnly: readOnly,
            suffix: readOnly && !isEdit
                ? (_fetchingId
                    ? const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Auto',
                            style: TextStyle(
                                fontSize: 12,
                                color: kPrimary,
                                fontWeight: FontWeight.w600)),
                      ))
                : null),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'ID is required';
          if (isStudent && v.trim().length != 6) {
            return 'Must be exactly 6 digits';
          }
          return null;
        },
      ),
    ]);
  }

  Widget _schoolYearFields() {
    final current = _composedAcademicYear;
    final openTerms =
        kAcademicTerms.where((t) => _isOpenTerm(t.year, t.semester)).toList();
    final openLabels =
        openTerms.map((t) => academicTermLabel(t.year, t.semester)).toList();
    final currentLabel = academicTermLabel(current, _fSemester ?? '');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('School Year & Semester'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-term-$_fCategory-$_fPeriodId-$_pickerEpoch'),
        initialValue: openLabels.contains(currentLabel)
            ? currentLabel
            : (openLabels.isNotEmpty ? openLabels.first : null),
        isExpanded: true,
        decoration:
            _ideco('Select term', prefixIcon: Icons.calendar_month_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          for (final t in openTerms)
            DropdownMenuItem(
              value: academicTermLabel(t.year, t.semester),
              child: Row(children: [
                Flexible(
                  child: Text(
                    academicTermLabel(t.year, t.semester),
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _termBadge('CURRENT', kSuccess),
              ]),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          final i = v.indexOf(' · ');
          if (i < 0) return;
          final year = v.substring(0, i);
          final semester = v.substring(i + 3);
          final parts = year.split('-');
          setState(() {
            _cYearStart.text = parts.isNotEmpty ? parts.first : '';
            _cYearEnd.text = parts.length > 1 ? parts.last : '';
            _fSemester = semester;
            _fPeriodId = ReferenceCatalog.periodIdFor(year, semester);
          });
          _refreshForm();
          final category = _fCategory;
          if (category != null && category != 'Student' && _editing == null) {
            _fillNextId(category);
          }
        },
      ),
      if (_composedAcademicYear.isEmpty) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: kPrimary),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Pick the term this record belongs to.',
                style: TextStyle(
                    fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _sexField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Sex'),
      DropdownButtonFormField<String>(
        initialValue: _fSex,
        isExpanded: true,
        decoration: _ideco('Select sex', prefixIcon: Icons.wc_rounded),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: kSexes
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) {
          _fSex = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _birthField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Birth Date'),
      TextFormField(
        controller: _cBirth,
        readOnly: true,
        onTap: _pickBirthDate,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('Select date', prefixIcon: Icons.cake_outlined),
      ),
    ]);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fBirthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 90),
      lastDate: now,
    );
    if (picked != null) {
      _fBirthDate = picked;
      _cBirth.text = DateFormat('MMM d, yyyy').format(picked);
      _refreshForm();
    }
  }

  Widget _suffixField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Suffix'),
      TextFormField(
        controller: _cSuffix,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration:
            _ideco('Jr., III (optional)', prefixIcon: Icons.tag_rounded),
      ),
    ]);
  }

  Widget _firstNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('First Name'),
      TextFormField(
        controller: _cFirst,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Maria', prefixIcon: Icons.person_outline),
        validator: _requiredText,
      ),
    ]);
  }

  Widget _middleNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Middle Name'),
      TextFormField(
        controller: _cMiddle,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Santos (optional)'),
      ),
    ]);
  }

  Widget _lastNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Last Name'),
      TextFormField(
        controller: _cLast,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Dela Cruz', prefixIcon: Icons.person_outline),
        validator: _requiredText,
      ),
    ]);
  }

  Widget _contactField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Contact Number'),
      TextFormField(
        controller: _cContact,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration:
            _ideco('e.g. 09171234567', prefixIcon: Icons.phone_outlined),
      ),
    ]);
  }

  Widget _emailField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Email Address'),
      TextFormField(
        controller: _cEmail,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. name@tcgc.edu.pg or name@gmail.com',
            prefixIcon: Icons.email_outlined),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
              ? null
              : 'Enter a valid email';
        },
      ),
    ]);
  }

  Widget _addressField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Address'),
      TextFormField(
        controller: _cAddress,
        maxLines: 2,
        minLines: 1,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Brgy. San Rafael, Tarlac City',
            prefixIcon: Icons.location_on_outlined),
      ),
    ]);
  }

  Widget _instituteField() {
    final institutes = _catalog.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Institute'),
      DropdownButtonFormField<String>(
        key:
            ValueKey('form-inst-${_catalog.length}-$_fInstitute-$_pickerEpoch'),
        initialValue: _fInstitute,
        isExpanded: true,
        decoration: _ideco('Select institute',
            prefixIcon: Icons.account_balance_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...institutes.map((e) => DropdownMenuItem(value: e, child: Text(e))),
          const DropdownMenuItem(
            value: _kAddProgram,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add institute / program...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddProgram) {
            _openAddProgramDialog();
            return;
          }
          _fInstitute = v;
          _fProgram = null;
          final progs =
              v == null ? const <String>[] : (_catalog[v] ?? const <String>[]);
          if (progs.length == 1) _fProgram = _programValue(v!, progs.first);
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _programField() {
    final readOnly = _fInstitute == null;
    final institute = _fInstitute;
    final programs = _programOptions;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Program'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-prog-$institute-$_fProgram-$_pickerEpoch'),
        initialValue: _fProgram,
        isExpanded: true,
        decoration: _ideco(
          readOnly
              ? 'Select an institute first'
              : (programs.length == 1
                  ? 'Only one program offered'
                  : 'Select program'),
          prefixIcon: Icons.menu_book_outlined,
          readOnly: readOnly,
        ),
        style: TextStyle(fontSize: 15, color: readOnly ? kTextSub : kTextMain),
        items: [
          ...programs.map((p) => DropdownMenuItem(
                value: _programValue(institute!, p),
                child: Text(p,
                    style: const TextStyle(
                        fontSize: 15, overflow: TextOverflow.ellipsis)),
              )),
          const DropdownMenuItem(
            value: _kAddProgram,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add program...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddProgram) {
            _openAddProgramDialog(requireProgram: true);
          } else if (v != null) {
            _fProgram = v;
            _refreshForm();
          }
        },
        validator: (v) => _fInstitute == null ? null : _requiredText(v),
      ),
    ]);
  }

  Future<void> _openAddProgramDialog({
    bool requireProgram = false,
    bool intoFacultyInstitute = false,
  }) async {
    final result = await showDialog<
        ({String instituteCode, String programCode, bool created})?>(
      context: context,
      builder: (ctx) => _AddProgramDialog(
        institutes: (_catalog.keys.toList()..sort()),
        initialInstitute: intoFacultyInstitute ? _fDepartment : _fInstitute,
        requireProgram: requireProgram,
      ),
    );
    if (result == null || !mounted) {
      _resetPickers();
      return;
    }
    setState(() {
      if (intoFacultyInstitute) {
        _fDepartment = result.instituteCode;
      } else {
        _fInstitute = result.instituteCode;
        _fProgram = result.programCode.isEmpty
            ? null
            : _programValue(result.instituteCode, result.programCode);
      }
    });
    _refreshForm();
    if (result.created) _showResultDialog('Saved Record');
  }

  Widget _yearLevelField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Year Level'),
      DropdownButtonFormField<String>(
        initialValue: _fYearLevel,
        isExpanded: true,
        decoration: _ideco('Select year level',
            prefixIcon: Icons.calendar_today_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: kYearLevels
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) {
          _fYearLevel = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _departmentField() {
    final isFaculty = _fCategory == 'Faculty';
    final options = _departmentOptions(_fCategory);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel(isFaculty ? 'Institute' : 'Department / Office'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-dept-$_fCategory-$_fDepartment-$_pickerEpoch'),
        initialValue: _fDepartment,
        isExpanded: true,
        decoration: _ideco(
          isFaculty ? 'Select institute' : 'Select department / office',
          prefixIcon: Icons.business_outlined,
        ),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...options.map((e) => DropdownMenuItem(
              value: e, child: Text(e, style: const TextStyle(fontSize: 15)))),
          if (isFaculty)
            const DropdownMenuItem(
              value: _kAddInstitute,
              child: Row(children: [
                Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
                SizedBox(width: 8),
                Text('Add institute...',
                    style: TextStyle(
                        fontSize: 15,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
              ]),
            )
          else
            const DropdownMenuItem(
              value: _kAddDepartment,
              child: Row(children: [
                Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
                SizedBox(width: 8),
                Text('Add department / office...',
                    style: TextStyle(
                        fontSize: 15,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        onChanged: (v) {
          if (v == _kAddInstitute) {
            _openAddProgramDialog(intoFacultyInstitute: true);
            return;
          }
          if (v == _kAddDepartment) {
            _openAddDepartmentDialog();
            return;
          }
          _fDepartment = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _positionField() {
    final isFaculty = _fCategory == 'Faculty';
    final options = _positionOptions(_fCategory);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Position'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-pos-$_fCategory-$_fPosition-$_pickerEpoch'),
        initialValue: _fPosition,
        isExpanded: true,
        decoration: _ideco(
          isFaculty ? 'Select faculty position' : 'Select staff position',
          prefixIcon: Icons.work_outline,
        ),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...options.map((e) => DropdownMenuItem(
              value: e, child: Text(e, style: const TextStyle(fontSize: 15)))),
          const DropdownMenuItem(
            value: _kAddPosition,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add position...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddPosition) {
            _openAddPositionDialog();
            return;
          }
          _fPosition = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Future<void> _openAddDepartmentDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddNamedDialog(
        title: 'Add Department / Office',
        subtitle: 'Added to the list',
        label: 'Department / Office',
        hint: 'e.g. Office of the Registrar',
        icon: Icons.business_outlined,
        onSave: (value) async =>
            (await ReferenceDataService.addDepartment(value)).name,
      ),
    );
    if (name == null || !mounted) {
      _resetPickers();
      return;
    }
    setState(() => _fDepartment = name);
    _refreshForm();
    _showResultDialog('Saved Record');
  }

  Future<void> _openAddPositionDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddNamedDialog(
        title: 'Add Position',
        subtitle: 'Added to the list',
        label: 'Position',
        hint: 'e.g. Instructor',
        icon: Icons.work_outline,
        onSave: (value) async =>
            (await ReferenceDataService.addPosition(value)).name,
      ),
    );
    if (name == null || !mounted) {
      _resetPickers();
      return;
    }
    setState(() => _fPosition = name);
    _refreshForm();
    _showResultDialog('Saved Record');
  }

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint,
      {IconData? prefixIcon, bool readOnly = false, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger, width: 1.5)),
    );
  }

  void _showDetail(IndividualRecord r) {
    final color = _categoryColor(r.category);
    final viewOnly = r.status == kRecordStatusInactive;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                      r.isStudent
                          ? Icons.person_outline_rounded
                          : Icons.work_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.fullName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kTextMain)),
                      const SizedBox(height: 5),
                      Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(r.category,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: color)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(r.id,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: kTextSub)),
                            ),
                            if (r.academicYear.isNotEmpty)
                              Text('AY ${r.academicYear} · ${r.semester}',
                                  style: const TextStyle(
                                      fontSize: 12.5, color: kTextSub)),
                          ]),
                    ],
                  )),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: kTextSub),
                      iconSize: 20),
                ]),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoSection(
                              'Personal Information', Icons.person_outline, [
                            _infoRow('First Name', r.firstName),
                            _infoRow('Middle Name', r.middleName),
                            _infoRow('Last Name', r.lastName),
                            _infoRow('Suffix', r.suffix),
                            _infoRow('Sex', r.sex),
                            _infoRow(
                                'Birth Date',
                                r.birthDate == null
                                    ? ''
                                    : DateFormat('MMMM d, yyyy')
                                        .format(r.birthDate!)),
                            _infoRow('Contact', r.contact),
                            _infoRow('Email', r.email),
                            _infoRow('Address', r.address),
                          ]),
                          _infoSection(
                            r.isStudent
                                ? 'Academic Information'
                                : (r.category == 'Faculty'
                                    ? 'Teaching Assignment'
                                    : 'Employment Information'),
                            r.isStudent
                                ? Icons.school_outlined
                                : Icons.work_outline,
                            [
                              _infoRow('School Year', r.academicYear),
                              _infoRow('Semester', r.semester),
                              if (r.isStudent) ...[
                                _infoRow('Institute', r.institute),
                                _infoRow('Program', r.program),
                                _infoRow('Year Level', r.yearLevel),
                              ] else if (r.category == 'Faculty') ...[
                                _infoRow('Institute', r.institute),
                                _infoRow('Position', r.position),
                              ] else ...[
                                _infoRow('Department / Office', r.department),
                                _infoRow('Position', r.position),
                              ],
                            ],
                          ),
                          _infoSection(
                              'Record Information', Icons.history_rounded, [
                            _infoRow('Status', r.status),
                            _infoRow(
                                'Created',
                                r.createdAt == null
                                    ? '—'
                                    : DateFormat('MMM d, yyyy, h:mm a')
                                        .format(r.createdAt!)),
                            _infoRow('Created By', _auditWho(r.createdBy)),
                          ]),
                        ]),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: viewOnly
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _openForm(edit: r);
                          },
                    icon: Icon(
                        viewOnly ? Icons.lock_outline : Icons.edit_outlined,
                        size: 16,
                        color: viewOnly ? kTextSub : kPrimary),
                    label: Text(
                        viewOnly ? 'View only (past term)' : 'Edit Record',
                        style:
                            TextStyle(color: viewOnly ? kTextSub : kPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoSection(String title, IconData icon, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: kPrimary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kTextMain,
                  letterSpacing: 0.3)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: kBorder, height: 1)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final twoCol = c.maxWidth > 460;
          final pairs = <Widget>[];
          for (var i = 0; i < rows.length; i += (twoCol ? 2 : 1)) {
            final end = (i + (twoCol ? 2 : 1)).clamp(0, rows.length);
            pairs.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: rows[i]),
                if (twoCol && end - i == 2) ...[
                  const SizedBox(width: 16),
                  Expanded(child: rows[i + 1]),
                ],
              ]),
            ));
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: pairs);
        }),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11.5, color: kTextSub, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value.isEmpty ? '—' : value,
          style: const TextStyle(
              fontSize: 14.5, color: kTextMain, fontWeight: FontWeight.w600)),
    ]);
  }

  String _auditWho(String? id) {
    if (id == null || id.isEmpty) return '—';
    final name = _userNames[id];
    if (name != null && name.isNotEmpty) return name;
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  Widget _buildTable(List<IndividualRecord> list) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: _loading
          ? _loadingState()
          : list.isEmpty
              ? _emptyState()
              : Column(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SingleChildScrollView(
                        child: LayoutBuilder(builder: (ctx, con) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minWidth: con.maxWidth),
                              child: DataTable(
                                headingRowHeight: 52,
                                dataRowMinHeight: 58,
                                dataRowMaxHeight: 68,
                                showCheckboxColumn: false,
                                headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFF8FAFC)),
                                headingTextStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: kTextSub,
                                    fontSize: 14,
                                    letterSpacing: 0.5),
                                dataTextStyle: const TextStyle(
                                    color: kTextMain, fontSize: 15),
                                columnSpacing: 24,
                                horizontalMargin: 20,
                                dividerThickness: 1,
                                border: const TableBorder(
                                  horizontalInside:
                                      BorderSide(color: kBorder, width: 0.8),
                                ),
                                columns: [
                                  DataColumn(
                                      label: Text(_idLabel.toUpperCase())),
                                  const DataColumn(label: Text('NAME')),
                                  const DataColumn(label: Text('SEX')),
                                  DataColumn(
                                      label: Text(switch (filter) {
                                    'Student' => 'PROGRAM',
                                    'Faculty' => 'INSTITUTE',
                                    _ => 'DEPT/OFFICE',
                                  })),
                                  const DataColumn(label: Text('CONTACT')),
                                  const DataColumn(label: Text('ACTIONS')),
                                ],
                                rows: list.asMap().entries.map((entry) {
                                  final r = entry.value;
                                  final even = entry.key % 2 == 0;
                                  return DataRow(
                                    color: WidgetStateProperty.all(
                                        even ? kCard : const Color(0xFFFAFCFD)),
                                    onSelectChanged: (_) => _showDetail(r),
                                    cells: [
                                      DataCell(Text(
                                        r.id,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: _categoryColor(r.category)),
                                      )),
                                      DataCell(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(r.fullName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15)),
                                          if (r.academicYear.isNotEmpty ||
                                              r.semester.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                                academicTermLabel(
                                                    r.academicYear, r.semester),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: kTextSub)),
                                          ],
                                        ],
                                      )),
                                      DataCell(Text(r.sex.isEmpty ? '—' : r.sex,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              color: kTextSub))),
                                      DataCell(Text(
                                        r.affiliationLabel,
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: kPrimary),
                                      )),
                                      DataCell(Text(
                                          r.contact.isEmpty ? '—' : r.contact,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              color: kTextSub))),
                                      DataCell(r.status == kRecordStatusInactive
                                          ? const Tooltip(
                                              message: 'Past term — view only',
                                              child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.lock_outline,
                                                        size: 16,
                                                        color: kTextSub),
                                                    SizedBox(width: 6),
                                                    Text('View only',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: kTextSub)),
                                                  ]),
                                            )
                                          : _actionBtn(
                                              icon: Icons.edit_outlined,
                                              color: kPrimary,
                                              tooltip: 'Edit',
                                              onTap: () => _openForm(edit: r),
                                            )),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _actionBtn(
      {required IconData icon,
      required Color color,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _loadingState() {
    return SizedBox(
      height: 260,
      child: Center(
        child: _loadError == null
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 34, color: kTextSub),
                    const SizedBox(height: 12),
                    const Text('Could not load the record list',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kTextMain)),
                    const SizedBox(height: 6),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: kTextSub, height: 1.4)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loadRecords,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _emptyState() {
    final q = search.text.trim();
    final msg = q.isEmpty
        ? (_countFor(filter) == 0
            ? 'No $filter records added yet.'
            : 'No $filter records match "$q".')
        : 'No $filter records match "$q".';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.borderStrong),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSub, fontSize: 16),
          ),
        ]),
      ),
    );
  }

  Color _categoryColor(String cat) => cat == 'Student'
      ? kStudentColor
      : cat == 'Faculty'
          ? kFacultyColor
          : kStaffColor;

  void _openImportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StudentImportDialog(),
    );
  }
}

class _AddProgramDialog extends StatefulWidget {
  final List<String> institutes;
  final String? initialInstitute;

  final bool requireProgram;

  const _AddProgramDialog({
    required this.institutes,
    this.initialInstitute,
    this.requireProgram = false,
  });

  @override
  State<_AddProgramDialog> createState() => _AddProgramDialogState();
}

class _AddProgramDialogState extends State<_AddProgramDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  String? _institute;
  final TextEditingController _instCodeCtrl = TextEditingController();
  final TextEditingController _instNameCtrl = TextEditingController();
  final TextEditingController _progCodeCtrl = TextEditingController();
  final TextEditingController _progNameCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.requireProgram) {
      _institute = widget.initialInstitute ??
          (widget.institutes.isNotEmpty ? widget.institutes.first : null);
    }
  }

  @override
  void dispose() {
    _instCodeCtrl.dispose();
    _instNameCtrl.dispose();
    _progCodeCtrl.dispose();
    _progNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String ic;
    final String iname;
    final String pc;
    final String pn;

    if (widget.requireProgram) {
      ic = _institute ?? '';
      if (ic.isEmpty) {
        setState(() => _error = 'Select an institute.');
        return;
      }
      iname = '';
      pc = _progCodeCtrl.text.trim().toUpperCase();
      pn = _progNameCtrl.text.trim();
      if (pc.isEmpty || pn.isEmpty) {
        setState(() => _error = 'Enter the program code and name.');
        return;
      }
    } else {
      ic = _instCodeCtrl.text.trim().toUpperCase();
      iname = _instNameCtrl.text.trim();
      if (ic.isEmpty) {
        setState(() => _error = 'Enter the institute code.');
        return;
      }
      if (iname.isEmpty) {
        setState(() => _error = 'Enter the institute name.');
        return;
      }
      pc = _progCodeCtrl.text.trim().toUpperCase();
      pn = _progNameCtrl.text.trim();
      if (pc.isNotEmpty != pn.isNotEmpty) {
        setState(() => _error = pc.isEmpty
            ? 'Enter the program code too.'
            : 'Enter the program name too.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ReferenceDataService.saveInstituteAndProgram(
        instituteCode: ic,
        instituteName: iname,
        programCode: pc,
        programName: pn,
      );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add_business_outlined,
                          color: kPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            widget.requireProgram
                                ? 'Add Program'
                                : 'Add Institute',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                        Text(
                            widget.requireProgram
                                ? 'A new program for an institute on file'
                                : 'An institute, with an optional first program',
                            style: const TextStyle(
                                fontSize: 13.5, color: kTextSub)),
                      ],
                    )),
                    IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: kTextSub),
                        iconSize: 20),
                  ]),
                  const SizedBox(height: 18),
                  const Divider(color: kBorder, height: 1),
                  const SizedBox(height: 16),
                  if (widget.requireProgram) ...[
                    _labeled('Institute'),
                    DropdownButtonFormField<String>(
                      initialValue: _institute,
                      isExpanded: true,
                      decoration: _ideco('Select institute',
                          prefixIcon: Icons.account_balance_outlined),
                      style: const TextStyle(fontSize: 15, color: kTextMain),
                      items: widget.institutes
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _institute = v;
                        _error = null;
                      }),
                    ),
                  ] else ...[
                    _labeled('Institute Code'),
                    TextField(
                      controller: _instCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 15, color: kTextMain),
                      decoration: _ideco('e.g. INTS',
                          prefixIcon: Icons.qr_code_2_outlined),
                    ),
                    const SizedBox(height: 14),
                    _labeled('Institute Name'),
                    TextField(
                      controller: _instNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15, color: kTextMain),
                      decoration: _ideco('e.g. Institute of Nursing',
                          prefixIcon: Icons.account_balance_outlined),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    const Text('Program',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextSub)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: (widget.requireProgram ? kDanger : kPrimary)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          widget.requireProgram ? 'Required' : 'Optional',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  widget.requireProgram ? kDanger : kPrimary)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _progCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('Code',
                            prefixIcon: Icons.qr_code_2_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _progNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('Program name',
                            prefixIcon: Icons.menu_book_outlined),
                      ),
                    ),
                  ]),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.error_outline, size: 15, color: kDanger),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  fontSize: 13, color: kDanger))),
                    ]),
                  ],
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 17),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _labeled(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    );
  }
}

class _AddPeriodDialog extends StatefulWidget {
  const _AddPeriodDialog();

  @override
  State<_AddPeriodDialog> createState() => _AddPeriodDialogState();
}

class _AddPeriodDialogState extends State<_AddPeriodDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String _semester = kSemesters.first;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final currentStart = int.tryParse(kCurrentAcademicYear.split('-').first) ??
        DateTime.now().year;
    _startCtrl = TextEditingController(text: '${currentStart + 1}');
    _endCtrl = TextEditingController(text: '${currentStart + 2}');
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final start = int.tryParse(_startCtrl.text.trim());
    if (start == null || start < 2000 || start > 2200) {
      setState(() => _error = 'Enter a four-digit start year, e.g. 2026.');
      return;
    }
    final end = int.tryParse(_endCtrl.text.trim());
    if (end == null || end != start + 1) {
      setState(() => _error =
          'The end year must be the start year plus one (e.g. 2026 / 2027).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ReferenceDataService.addAcademicPeriod(
        yearStart: start,
        yearEnd: end,
        semester: _semester,
        makeCurrent: true,
      );
      if (!mounted) return;
      Navigator.pop(context, result.period);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.calendar_month_outlined,
                          color: kPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add School Year & Semester',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                        const Text('Starts a new term',
                            style: TextStyle(fontSize: 13.5, color: kTextSub)),
                      ],
                    )),
                    IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: kTextSub),
                        iconSize: 20),
                  ]),
                  const SizedBox(height: 18),
                  const Divider(color: kBorder, height: 1),
                  const SizedBox(height: 16),
                  _labeled('School Year'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _startCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('Start', prefixIcon: Icons.event),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('–',
                          style: TextStyle(fontSize: 18, color: kTextSub)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _endCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('End', prefixIcon: Icons.event),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _labeled('Semester'),
                  DropdownButtonFormField<String>(
                    initialValue: _semester,
                    isExpanded: true,
                    decoration: _ideco('Select semester',
                        prefixIcon: Icons.school_outlined),
                    style: const TextStyle(fontSize: 15, color: kTextMain),
                    items: [
                      for (final s in kSemesters)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) =>
                        setState(() => _semester = v ?? _semester),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: kPrimary.withValues(alpha: 0.18)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 15, color: kPrimary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text(
                        'This becomes the current term. The previous term\'s '
                        'records are kept for viewing but become read-only, '
                        'and no longer load in Clinic Visit.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: kPrimary,
                            fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.error_outline, size: 15, color: kDanger),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  fontSize: 13, color: kDanger))),
                    ]),
                  ],
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 17),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _labeled(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger, width: 1.5)),
    );
  }
}

class _AddNamedDialog extends StatefulWidget {
  const _AddNamedDialog({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final String label;
  final String hint;
  final IconData icon;
  final Future<String> Function(String name) onSave;

  @override
  State<_AddNamedDialog> createState() => _AddNamedDialogState();
}

class _AddNamedDialogState extends State<_AddNamedDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  final TextEditingController _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the ${widget.label.toLowerCase()}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(name);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(widget.icon, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kTextMain)),
                      Text(widget.subtitle,
                          style:
                              const TextStyle(fontSize: 13.5, color: kTextSub)),
                    ],
                  )),
                  IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: kTextSub),
                      iconSize: 20),
                ]),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                _labeled(widget.label),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 15, color: kTextMain),
                  decoration: _ideco(widget.hint),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.error_outline, size: 15, color: kDanger),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_error!,
                            style:
                                const TextStyle(fontSize: 13, color: kDanger))),
                  ]),
                ],
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 17),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _labeled(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    );
  }
}

class _AutoCloseMessage extends StatefulWidget {
  const _AutoCloseMessage({
    required this.message,
    this.detail,
    this.danger = false,
  });

  final String message;
  final String? detail;
  final bool danger;

  @override
  State<_AutoCloseMessage> createState() => _AutoCloseMessageState();
}

class _AutoCloseMessageState extends State<_AutoCloseMessage> {
  static const Duration _visibleFor = Duration(seconds: 5);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_visibleFor, _close);
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.danger : AppColors.success;
    final detail = widget.detail;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.danger
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
