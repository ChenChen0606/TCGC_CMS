import 'dart:async';

import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';

/// Starts downloading what the first screens need the moment the user signs
/// in, while the dashboard is opening. By the time the user taps another
/// screen its data is already in memory, so it paints at once.
///
/// Nothing here blocks the UI and nothing here can fail the sign-in: every
/// request is independent and its errors are ignored (the screen simply
/// loads the data itself).
class AppWarmup {
  AppWarmup._();

  static void start() => unawaited(_run());

  static Future<void> _run() async {
    // Dashboard first: it is the screen the user is looking at.
    _quiet(VisitService.fetchDashboardVisits());

    // The active period decides which rosters to ask for.
    await ReferenceCatalog.loadQuietly();
    final activeId = ReferenceCatalog.activePeriod?.id;

    _quiet(IndividualRecordService.fetchAll(includeInactive: false));
    _quiet(IndividualRecordService.fetchAll(
        includeInactive: true, academicPeriodId: activeId));
    _quiet(IndividualRecordService.fetchAll(
        includeInactive: false,
        academicPeriodId: activeId,
        excludeStudents: true));
    _quiet(IndividualRecordService.fetchUserNames());
    _quiet(VisitService.fetchAllBookletRecords());
    _quiet(IndividualRecordService.fetchAllOnePerPerson());
  }

  static void _quiet(Future<Object?> f) {
    unawaited(f.then<void>((_) {}, onError: (_) {}));
  }
}
