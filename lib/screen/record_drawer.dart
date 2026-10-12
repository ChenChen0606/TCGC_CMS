import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/certificate_engine.dart';
import '../core/patient_directory.dart';
import '../core/visit_details.dart';
import '../core/vitals.dart';
import 'app_colors.dart';

/// The visitor's whole record, in a panel that slides in from the right over
/// the step 3 form.
///
/// WHAT THIS IS FOR
/// A nurse mid-visit asks the same four questions: what did this person come in
/// with last time, what was done, what are they on, and have we ever issued
/// them a certificate. Every one of those is a round trip to another screen in
/// this app, and every round trip costs the half-finished form behind it. So
/// the answers are all here, in one panel, read-only, beside the work.
///
/// WHY READ-ONLY
/// Nothing here edits the person. A name or a birth date belongs on the
/// Individual Record page, where the clinic manages it and where the change is
/// audited; a form that quietly corrected a visitor's details mid-visit would
/// make two sources of truth for the same person. The one thing the drawer does
/// offer is a jump into a service form — that changes the visit, not the person.
///
/// WHY IT IS A PANEL AND NOT A TAB
/// A tab would hide the form to show the record, and a back gesture would
/// discard whatever was typed. This covers the form, so closing it returns to
/// exactly the slide and the caret position the nurse left.
class RecordDrawer extends StatefulWidget {
  const RecordDrawer({
    super.key,
    required this.profile,
    required this.controller,
    required this.history,
    required this.historyFor,
    required this.onOpenService,
  });

  final ClinicProfile profile;

  /// The visit's own drafts, so the Services tab can say which service is
  /// being recorded and which is still to do, and jump straight to one.
  final VisitDetailsController controller;

  /// History already fetched elsewhere. Reused rather than read a second time,
  /// so opening the drawer does not repeat the query.
  final List<HistoryRow> history;

  final Future<List<HistoryRow>> Function() historyFor;

  /// Jump into a service form. [slide] is the slide that needs the attention.
  final void Function(String serviceId, int? slide) onOpenService;

  @override
  State<RecordDrawer> createState() => RecordDrawerState();
}

class RecordDrawerState extends State<RecordDrawer> {
  /// The five the clinic asked for. `Profile` is always present as the first
  /// thing; the rest are what a nurse reaches for.
  static const _tabs = <({String label, IconData icon})>[
    (label: 'Profile', icon: Icons.badge_outlined),
    (label: 'History', icon: Icons.history_outlined),
    (label: 'Medicines', icon: Icons.medication_outlined),
    (label: 'Vitals', icon: Icons.monitor_heart_outlined),
  ];

  int _tab = 0;

  /// Fetched per tab, on first visit, and kept afterwards. Nullable because
  /// "not fetched yet" and "fetched, and there was nothing" are different
  /// states and only one of them should look empty.
  List<HistoryRow>? _history;

  /// The prescription the current visit has recorded, plus the drawer's own
  /// copy of the last one, which is what the nurse is actually checking
  /// against: what is this person on *right now*.
  List<MedicineDose> get _currentMeds =>
      widget.controller.draftFor('medication')?.medicines ?? const [];

  @override
  void initState() {
    super.initState();
    _history = widget.history;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        child: SizedBox(
          // Fixed rather than a fraction: the record is a column of values that
          // have to stay on one line, and a narrow panel turns every name into
          // an ellipsis. On a phone the drawer takes the whole width, which is
          // the same trade the app makes everywhere else.
          width: width < 560 ? width : 480,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                _tabBar(),
                const Divider(height: 1, color: AppColors.border),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final v = widget.profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Visitor Record',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  v.fullName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${v.id}  ·  ${v.category}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('close_record_drawer'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 19),
            color: AppColors.textSub,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (final (i, t) in _tabs.indexed)
            Expanded(
              child: InkWell(
                key: ValueKey('drawer_tab_${t.label.toLowerCase()}'),
                onTap: () {
                  setState(() => _tab = i);
                  // Fetched on the tab that needs it, not up front: four
                  // queries on open is four queries every nurse pays for,
                  // including for the one tab they actually wanted.
                  if (t.label == 'History') _loadHistory();
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            _tab == i ? AppColors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(t.icon,
                          size: 16,
                          color: _tab == i
                              ? AppColors.primary
                              : AppColors.textMuted),
                      const SizedBox(height: 2),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _tab == i
                              ? AppColors.primaryDark
                              : AppColors.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadHistory() async {
    if (_history != null && _history!.isNotEmpty) return;
    final rows = await widget.historyFor();
    if (!mounted) return;
    setState(() => _history = rows);
  }

  Widget _body() {
    return switch (_tab) {
      1 => _historyTab(),
      2 => _medicinesTab(),
      3 => _vitalsTab(),
      _ => _profileTab(),
    };
  }

  // ── PROFILE ────────────────────────────────────────────────────────────

  Widget _profileTab() {
    final v = widget.profile;
    return _scroll([
      _note(
        'Read-only here. Names, addresses and affiliations are maintained on the '
        'Individual Record page, where a change is recorded against whoever made it.',
      ),
      _group('Personal', [
        _row('Full name', v.fullName),
        _row('ID number', v.id),
        _row('Category', v.category),
        _row('Sex', v.sex),
        _row('Birthday', v.birthDate.isEmpty ? '—' : _date(v.birthDate)),
        _row('Age', _ageOf(v)),
        _row('Civil status', '—'),
        _row('Contact', v.contact),
        _row('Address', v.address),
      ]),
      if (v.isStudent)
        _group('Academic', [
          _row('Institute', v.institute),
          _row('Program', v.program),
          _row('Year level', v.yearLevel),
          _row('Academic year', v.academicYear),
          _row('Semester', v.semester),
        ])
      else
        _group('Employment', [
          _row('Institute', v.institute),
          _row('Department', v.department),
          _row('Position', v.position),
        ]),
      _group('Next of kin', [
        _row('Name', v.emergencyName),
        _row('Contact', v.emergencyContact),
      ]),
    ]);
  }

  // ── HISTORY ────────────────────────────────────────────────────────────

  Widget _historyTab() {
    final rows = _history;
    return _scroll([
      _note(
        'Previous visits, newest first. This is the same list the Individual '
        'Clients Record prints, read from the same place.',
      ),
      if (rows == null || rows.isEmpty)
        const _EmptyNote('No previous visits recorded for this person.')
      else
        for (final h in rows) _historyRow(h),
    ]);
  }

  Widget _historyRow(HistoryRow h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                h.date,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded,
                  size: 12, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 3),
          _labelled('Came in with', h.chiefComplaint),
          const SizedBox(height: 2),
          _labelled('Treatment', h.treatment),
        ],
      ),
    );
  }

  // ── MEDICINES ──────────────────────────────────────────────────────────

  Widget _medicinesTab() {
    final meds = _currentMeds;
    return _scroll([
      _group('Prescribed on this visit', [
        for (final m in meds) _row(m.name, _doseOf(m)),
        if (meds.isEmpty) _row('Nothing recorded', '—'),
      ]),
      const SizedBox(height: 4),
      _note(
        'A prescription recorded on step 3 is not deducted from the inventory '
        'here — stock moves when the visit is completed.',
      ),
    ]);
  }

  String _doseOf(MedicineDose m) {
    final parts = <String>[
      if (m.dose.trim().isNotEmpty) m.dose.trim(),
      if ((m.quantity ?? 0) > 0) '× ${m.quantity}',
      if (m.frequency.trim().isNotEmpty) m.frequency.trim(),
      if (m.action.trim().isNotEmpty && m.action != 'Given') m.action.trim(),
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  // ── VITALS ─────────────────────────────────────────────────────────────

  Widget _vitalsTab() {
    final v = widget.controller.vitals;
    final now = v.readings;
    return _scroll([
      _group('Taken on this visit', [
        for (final r in now) _readingRow(r),
        if (now.isEmpty) _row('Nothing taken yet', '—'),
      ]),
      const SizedBox(height: 4),
      _note(
        'Blood pressure, pulse, temperature and weight taken during this visit. '
        'Earlier visits are read from the person\u2019s history, not this tab.',
      ),
    ]);
  }

  Widget _readingRow(VitalReading r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(r.band.icon, size: 14, color: r.band.color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              r.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            r.display,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: r.isAbnormal ? r.band.color : AppColors.textMain,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(
              r.category ?? r.band.label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: r.isAbnormal ? r.band.color : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SERVICES ON THIS VISIT ─────────────────────────────────────────────

  Widget _servicesSection() {
    final drafts = widget.controller.drafts;
    return _group('On this visit', [
      for (final d in drafts)
        InkWell(
          key: ValueKey('drawer_service_${d.serviceId}'),
          onTap: () => widget.onOpenService(d.serviceId, null),
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _statusColor(d.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    d.label,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMain),
                  ),
                ),
                Text(
                  d.status.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(d.status),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (drafts.isEmpty) _row('No services recorded', '—'),
    ]);
  }

  /// The same three colours the service list uses for the same three states, so
  /// a dot in the drawer and a pill in the list cannot disagree about how far
  /// along a service is.
  static Color _statusColor(ServiceDraftStatus s) => switch (s) {
        ServiceDraftStatus.notStarted => AppColors.textMuted,
        ServiceDraftStatus.inProgress => AppColors.warning,
        ServiceDraftStatus.completed => AppColors.success,
      };

  // ── SMALL PIECES ───────────────────────────────────────────────────────

  Widget _scroll(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [_servicesSection(), const SizedBox(height: 6), ...children],
    );
  }

  Widget _group(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
              value.trim().isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelled(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSub,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '—' : value,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textMain, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11.5, color: AppColors.textSub, height: 1.4),
      ),
    );
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('MMMM d, yyyy').format(d);
  }

  static String _ageOf(ClinicProfile v) {
    if (v.birthDate.isEmpty) return '—';
    final b = DateTime.tryParse(v.birthDate);
    if (b == null) return '—';
    final now = DateTime.now();
    var years = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day))
      years--;
    return years < 0 ? '—' : '$years';
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Text(
        message,
        style: const TextStyle(
            fontSize: 12, color: AppColors.textMuted, height: 1.4),
      ),
    );
  }
}
