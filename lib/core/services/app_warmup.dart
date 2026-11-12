import 'dart:async';

import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';

/// Starts downloading what the first screens need the moment the user signs
/// in, while the dashboard is still opening. By the time the user taps
/// Dashboard, Clinic Visit or Individual Record the data is already in
/// memory, so those screens paint at once instead of showing a spinner.
///
/// Nothing here blocks the UI and nothing here can fail the sign-in: every
/// request is independent and its errors are ignored (the screen simply
/// loads the data itself, as it did before).
class AppWarmup {
  AppWarmup._();

  static void start() {
    final activeId = ReferenceCatalog.activePeriod?.id;

    // Dashboard: today's visits.
    _quiet(VisitService.fetchDashboardVisits());

    // Clinic Visit: the active roster.
    _quiet(IndividualRecordService.fetchAll(includeInactive: false));

    // Individual Record: the two lists its default view is made of.
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