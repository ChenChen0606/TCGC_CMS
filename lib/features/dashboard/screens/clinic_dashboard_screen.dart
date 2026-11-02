
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:clinicmanagementsystem/features/visits/screens/clinic_visit_screen.dart';
import 'package:clinicmanagementsystem/features/dashboard/screens/analytics_screen.dart';
import 'package:clinicmanagementsystem/features/inventory/screens/medicine_inventory_screen.dart';
import 'package:clinicmanagementsystem/features/patients/screens/individual_record_screen.dart';
import 'package:clinicmanagementsystem/features/vitals/screens/bmi_records_screen.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/platform/browser_tabs.dart';
import 'package:clinicmanagementsystem/features/auth/screens/login_screen.dart';
import 'package:clinicmanagementsystem/features/records/screens/records_booklet_screen.dart';
import 'package:clinicmanagementsystem/features/account/screens/account_screen.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

class ClinicDashboard extends StatefulWidget {
  final String userRole;
  final String userEmail;
  final String userName;
  final String userUsername;

  const ClinicDashboard({
    super.key,
    this.userRole = 'Clinic Staff',
    this.userEmail = '',
    this.userName = '',
    this.userUsername = '',
  });

  @override
  State<ClinicDashboard> createState() => _ClinicDashboardState();
}

class _ClinicDashboardState extends State<ClinicDashboard> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    if (browserHistoryEnabled) {
      initTabHistory((index) {
        if (index < 0 || index > _lastTabIndex) return;
        if (mounted) setState(() => _selectedIndex = index);
      });
    }
  }

  @override
  void dispose() {
    disposeTabHistory();
    super.dispose();
  }

  bool get _isHead => widget.userRole == 'Clinic Head';

  int get _lastTabIndex => 7;

  List<Widget> get _pages => [
        DashboardOverview(
          isActive: _selectedIndex == 0,
          onNavigate: _onItemTapped,
          userName: widget.userName,
        ),
        ClinicVisitScreen(
          isActive: _selectedIndex == 1,
          userName: widget.userName,
          userRole: widget.userRole,
        ),
        const IndividualRecordScreen(),
        const BmiRecordsScreen(),
        const MedicineInventoryScreen(),
        RecordsBooklet(isActive: _selectedIndex == 5),
        const ReportsScreen(),
        AccountScreen(
          userRole: widget.userRole,
          userEmail: widget.userEmail,
          userName: widget.userName,
          userUsername: widget.userUsername,
        ),
        
      ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (browserHistoryEnabled) pushTabHistory(index);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return PopScope(
      canPop: !browserHistoryEnabled,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: isDesktop
            ? null
            : AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                iconTheme: const IconThemeData(color: AppColors.primary),
                title: const Text("TCGC CLINIC MANAGEMENT SYSTEM",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(color: const Color(0xFFF1F5F9), height: 1),
                ),
              ),
        drawer: isDesktop ? null : _buildSidebar(),
        body: Row(
          children: [
            if (isDesktop) _buildSidebar(),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 265,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        boxShadow: [
          BoxShadow(
              color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        children: [
          _buildSidebarHeader(),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _menuItem(0, "Dashboard", Icons.grid_view_rounded),
                _menuItem(1, "Clinic Visits", Icons.medical_services_outlined),
                _menuItem(2, "Individual Records", Icons.badge_outlined),
                _menuItem(3, "BMI Records", Icons.monitor_weight_outlined),
                _menuItem(4, "Inventory", Icons.inventory_2_outlined),
                _menuItem(5, "Records Booklet", Icons.menu_book_outlined),
                _menuItem(6, "Reports", Icons.bar_chart_rounded),
                if (_isHead) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                    child: Text("MANAGEMENT",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 1.5)),
                  ),
                  _menuItem(7, "User Accounts", Icons.people_alt_rounded),
                ] else
                  _menuItem(7, "User Account", Icons.manage_accounts_outlined),
               
              ],
            ),
          ),
          const Divider(color: Color(0xFFF1F5F9), indent: 20, endIndent: 20),
          _buildUserFooter(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            AppColors.primaryDeep
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniLogo('asset/tcgc.png'),
              Container(
                  width: 1,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0x59FFFFFF)),
              _buildMiniLogo('asset/cliniclogo.png'),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "TCGC CLINIC",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.6,
                height: 1.1,
                shadows: [
                  Shadow(
                      color: Color(0x40000000),
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ]),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x4DFFFFFF)),
            ),
            child: const Text(
              "MANAGEMENT SYSTEM",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  height: 1.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLogo(String path) {
    return Container(
      height: 50,
      width: 50,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(path,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.business, size: 18, color: AppColors.primary)),
      ),
    );
  }

  Widget _buildUserAvatar() {
    final String firstName = widget.userName.trim().isNotEmpty
        ? widget.userName.trim().split(RegExp(r'\s+')).first
        : 'U';
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            firstName.substring(0, 1).toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildUserFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF99F6E4)),
        ),
        child: Row(
          children: [
            _buildUserAvatar(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.userName.isEmpty ? 'User' : widget.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 2),
                  Text(widget.userRole,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _logout,
              tooltip: 'Logout',
              iconSize: 20,
              icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.logout_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: 8),
                      const Text('Log out',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B))),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                        'Are you sure you want to log out of your account?',
                        style: TextStyle(
                            fontSize: 14.5,
                            color: AppColors.textSub,
                            height: 1.5)),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontSize: 14.5, color: AppColors.textSub)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Log out',
                            style: TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    resetTabHistory();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  Widget _menuItem(int index, String title, IconData icon) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          _onItemTapped(index);
          if (MediaQuery.of(context).size.width <= 900) Navigator.pop(context);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSelected ? const Color(0xFFCCFBF1) : Colors.transparent,
        hoverColor: const Color(0xFFF0FDFA),
        selected: isSelected,
        leading: Icon(icon,
            color: isSelected ? AppColors.primary : AppColors.textSub),
        title: Text(title,
            style: TextStyle(
              color:
                  isSelected ? AppColors.primaryDark : const Color(0xFF334155),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 16,
            )),
      ),
    );
  }
}

class DashboardOverview extends StatefulWidget {
  final Function(int)? onNavigate;
  final String userName;
  final bool isActive;
  const DashboardOverview(
      {super.key, this.isActive = false, this.onNavigate, this.userName = ''});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  late String _timeString;
  late String _dateString;
  late Timer _timer;

  List<DashboardVisit> _visits = [];
  String? _error;

  int _outOfStockCount = 0;
  int _lowStockCount = 0;

  VoidCallback? _dataListener;

  @override
  void initState() {
    super.initState();
    _timeString = DateFormat('hh:mm a').format(DateTime.now());
    _dateString = DateFormat('EEEE, MMMM d, y').format(DateTime.now());
    _timer =
        Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
    _loadData();
    _dataListener = () => _loadData();
    DataTracker.listen(_dataListener!);
  }

  @override
  void didUpdateWidget(DashboardOverview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !oldWidget.isActive) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _error = null);
    try {
      final visits = await VisitService.fetchDashboardVisits();
      if (mounted) setState(() => _visits = visits);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load dashboard data: $e');
    }

    try {
      final meds = await MedicineService.fetchAll();
      if (!mounted) return;
      setState(() {
        _outOfStockCount = meds.where((m) => m.isOutOfStock).length;
        _lowStockCount =
            meds.where((m) => m.isLowStock && !m.isOutOfStock).length;
      });
    } catch (_) {}
  }

  DateTime get _todayOnly {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isToday(DashboardVisit v) {
    final d = v.visitDate;
    if (d == null) return false;
    final t = _todayOnly;
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    final DateTime now = DateTime.now();
    if (mounted) {
      setState(() {
        _timeString = DateFormat('hh:mm a').format(now);
        _dateString = DateFormat('EEEE, MMMM d, y').format(now);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Padding(
      padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 20, isDesktop ? 24 : 16,
          isDesktop ? 40 : 20, isDesktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(isDesktop),
          const SizedBox(height: 18),
          if (_error != null) _dashboardErrorBanner(_error!),
          if (_outOfStockCount > 0 || _lowStockCount > 0)
            _inventoryAlertBanner(),
          _buildPatientMetricsGrid(),
          const SizedBox(height: 16),
          Expanded(
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: _consultationsCard()),
                      const SizedBox(width: 18),
                      Expanded(child: _topServicesCard()),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _consultationsCard()),
                      const SizedBox(height: 14),
                      Expanded(child: _topServicesCard()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDesktop) {
    final displayName = widget.userName.isNotEmpty ? widget.userName : 'User';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("OVERVIEW",
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text("Welcome, $displayName!",
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A))),
        ]),
        if (isDesktop)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 20,
                    offset: Offset(0, 6))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_timeString,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 17)),
                Text(_dateString,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dashboardErrorBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
        TextButton(onPressed: _loadData, child: const Text("Retry")),
      ]),
    );
  }

  Widget _inventoryAlertBanner() {
    final bool anyOut = _outOfStockCount > 0;
    final Color accent = anyOut ? AppColors.danger : AppColors.warning;
    final Color bg = anyOut ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7ED);
    final Color border =
        anyOut ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A);

    final String message;
    if (anyOut && _lowStockCount > 0) {
      message = '$_outOfStockCount medicine${_outOfStockCount > 1 ? 's' : ''} '
          'out of stock and $_lowStockCount running low — please review inventory.';
    } else if (anyOut) {
      message = '$_outOfStockCount medicine${_outOfStockCount > 1 ? 's' : ''} '
          'out of stock — please review inventory.';
    } else {
      message = '$_lowStockCount medicine${_lowStockCount > 1 ? 's' : ''} '
          'running low on stock — please review inventory.';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, size: 19, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  color: anyOut ? AppColors.danger : const Color(0xFFB45309),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
        ),
        TextButton(
          onPressed: () => widget.onNavigate?.call(4),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text("Review inventory",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _buildPatientMetricsGrid() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F0F172A), blurRadius: 28, offset: Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("VISITATION SUMMARY",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 1.2)),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            bool isSmall = constraints.maxWidth < 700;
            return isSmall
                ? Column(children: _buildMetricItems(isMobile: true))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _buildMetricItems());
          }),
        ],
      ),
    );
  }

  List<Widget> _buildMetricItems({bool isMobile = false}) {
    final todayRecords = _visits.where(_isToday).toList();
    final total = todayRecords.length;

    final students =
        todayRecords.where((v) => v.personType == "Student").length;
    final faculty = todayRecords.where((v) => v.personType == "Faculty").length;
    final staff = todayRecords.where((v) => v.personType == "Staff").length;

    final List<Map<String, dynamic>> metrics = [
      {
        "label": "Total Visits",
        "value": total.toString().padLeft(2, '0'),
        "color": AppColors.primary,
        "icon": Icons.analytics_outlined
      },
      {
        "label": "Students",
        "value": students.toString().padLeft(2, '0'),
        "color": const Color(0xFF2563EB),
        "icon": Icons.school_outlined
      },
      {
        "label": "Faculty",
        "value": faculty.toString().padLeft(2, '0'),
        "color": const Color(0xFFD97706),
        "icon": Icons.co_present_outlined
      },
      {
        "label": "Staff",
        "value": staff.toString().padLeft(2, '0'),
        "color": const Color(0xFF7C3AED),
        "icon": Icons.badge_outlined
      },
    ];

    return metrics.map((m) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 12.0 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(m['icon'], color: m['color'], size: 22),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['value'],
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A))),
                Text(m['label'],
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600)),
              ],
            ),
            if (!isMobile && metrics.last != m)
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Container(
                    width: 1.5, height: 40, color: const Color(0xFFF1F5F9)),
              ),
          ],
        ),
      );
    }).toList();
  }

  Widget _consultationsCard() {
    final todayRecords = _visits.where(_isToday).toList();
    final shown = todayRecords.take(5).toList();

    return _baseCard(
      title: "Recent Consultations",
      icon: Icons.history_rounded,
      trailing: TextButton(
        onPressed: () => widget.onNavigate?.call(5),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text("View all >>",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      child: shown.isEmpty
          ? const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text("No consultations recorded today yet.",
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final r = shown[i];
                Color color;
                Color bgColor;
                switch (r.personType) {
                  case "Faculty":
                    color = const Color(0xFFD97706);
                    bgColor = const Color(0xFFFEF3C7);
                    break;
                  case "Staff":
                    color = const Color(0xFF7C3AED);
                    bgColor = const Color(0xFFEDE9FE);
                    break;
                  default:
                    color = const Color(0xFF2563EB);
                    bgColor = const Color(0xFFDBEAFE);
                }
                return _tile(r, color, bgColor);
              },
            ),
    );
  }

  String _initialOf(DashboardVisit r) {
    final label = r.displayName.trim();
    return label.isEmpty ? '?' : label[0].toUpperCase();
  }

  Widget _tile(DashboardVisit r, Color color, Color bgColor) {
    final date =
        r.visitDate == null ? '—' : DateFormat('MMM d, y').format(r.visitDate!);
    final time = r.visitTime.isEmpty ? '—' : r.visitTime;
    final services =
        r.services.isEmpty ? 'No services recorded' : r.services.join(', ');
    final aff = r.affiliation;
    final id = r.personId.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: bgColor,
              child: Text(_initialOf(r),
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                  ),
                  const SizedBox(width: 8),
                  Text('$date • $time',
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFF94A3B8))),
                ],
              ),
              const SizedBox(height: 3),
              Text(services,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF475569))),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (id.isNotEmpty)
                  _pill('ID: $id', const Color(0xFF475569),
                      const Color(0xFFF1F5F9)),
                if (aff.isNotEmpty)
                  _pill(aff, AppColors.primary, const Color(0xFFCCFBF1)),
                _pill(
                  r.personType.isEmpty ? 'Unassigned' : r.personType,
                  color,
                  bgColor,
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _topServicesCard() {
    final counts = <String, int>{};
    for (final v in _visits.where(_isToday)) {
      for (final s in v.services) {
        final n = s.trim();
        if (n.isEmpty) continue;
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = ranked.take(5).toList();
    final max = shown.isEmpty ? 0 : shown.first.value;

    const colors = [
      AppColors.danger,
      AppColors.info,
      AppColors.warning,
      AppColors.success,
      Color(0xFF7C3AED),
    ];

    return _baseCard(
      title: "Top Services",
      icon: Icons.trending_up_rounded,
      child: shown.isEmpty
          ? const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text("No service recorded today yet.",
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final e = shown[i];
                return _symptomRow(e.key, e.value, colors[i % colors.length],
                    max == 0 ? 1 : max);
              },
            ),
    );
  }

  Widget _symptomRow(String label, int count, Color color, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155))),
              Text('$count',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 5,
            width: double.infinity,
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: count / total,
              child: Container(
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseCard(
      {required String title,
      required IconData icon,
      required Widget child,
      String? subtitle,
      Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F0F172A), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A))),
            ),
            if (trailing != null) trailing,
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ],
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
