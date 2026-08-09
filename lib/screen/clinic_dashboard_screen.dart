import 'package:clinicmanagementsystem/screen/archive_screen.dart';
import 'package:clinicmanagementsystem/screen/patients_screen.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'clinic_visit_screen.dart';
import 'analytics_screen.dart';
import 'medicine_inventory_screen.dart'; 
import 'login_screen.dart'; 
import 'records_booklet_screen.dart'; 
import 'account_screen.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ClinicDashboard(),
  ));
}

class ClinicDashboard extends StatefulWidget {
  final String userRole;
  final String userEmail;
  final String userName;

  const ClinicDashboard({
    super.key,
    this.userRole  = 'Clinic Staff',
    this.userEmail = '',
    this.userName  = '',
  });

  @override
  State<ClinicDashboard> createState() => _ClinicDashboardState();
}

class _ClinicDashboardState extends State<ClinicDashboard> {
  int _selectedIndex = 0;

  List<Widget> get _pages => [
    const DashboardOverview(), // placeholder; index 0 is handled separately below
    //const ClinicVisitScreen(),
    ClinicVisitScreen(userName: widget.userName, userRole: widget.userRole),
    const PatientsScreen(),
    const MedicineInventoryScreen(),
    const RecordsBooklet(),
    const ReportsScreen(),
    AccountScreen(
      userRole:  widget.userRole,
      userEmail: widget.userEmail,
      userName:  widget.userName,
    ),
    const ArchiveScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: isDesktop ? null : AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF008080)),
        title: const Text("TCGC CLINIC", 
          style: TextStyle(color: Color(0xFF1E293B), fontSize: 21, fontWeight: FontWeight.bold)),
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _selectedIndex == 0 
                  ? DashboardOverview(onNavigate: _onItemTapped, userName: widget.userName) 
                  : _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 265,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
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
                _menuItem(2, "Patients", Icons.person),
                _menuItem(3, "Inventory", Icons.inventory_2_outlined),
                _menuItem(4, "Records Booklet", Icons.menu_book_outlined),
                _menuItem(5, "Reports", Icons.bar_chart_rounded),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                  child: Text("MANAGEMENT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1.5)),
                ),
                _menuItem(6, "User Accounts", Icons.people_alt_rounded),
                _menuItem(7, "Trash", Icons.delete_outlined), 
              ],
            ),
          ),
          const Divider(color: Color(0xFFF1F5F9), indent: 20, endIndent: 20),
          _menuItem(99, "Logout", Icons.logout_rounded, isLogout: true),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      width: double.infinity,
      color: const Color(0xFF008080),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          Row(
            children: [
              _buildMiniLogo('asset/tcgc.png',),
              const SizedBox(width: 8),
              Container(width: 1, height: 25, color: const Color(0xFF26A69A)),
              const SizedBox(width: 8),
              _buildMiniLogo('asset/cliniclogo.png'),
            ],
          ),
          const SizedBox(height: 12),
          const Text("TCGC CLINIC", 
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.userRole.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.userEmail,
            style: const TextStyle(color: Color(0xFFB2DFDB), fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLogo(String path) {
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: Container(
        height: 70, width:70,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.asset(path, errorBuilder: (c, e, s) => const Icon(Icons.business, size: 18, color: Color(0xFF008080))),
        ),
      ),
    );
  }

  Widget _menuItem(int index, String title, IconData icon, {bool isLogout = false}) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          if (isLogout) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
          } else {
            _onItemTapped(index);
            if (MediaQuery.of(context).size.width <= 900) Navigator.pop(context);
          }
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSelected ? const Color(0xFFF0FDFA) : Colors.transparent,
        leading: Icon(icon, color: isLogout ? const Color(0xFFEF4444) : (isSelected ? const Color(0xFF008080) : const Color(0xFF64748B))),
        title: Text(title, style: TextStyle(
          color: isLogout ? const Color(0xFFEF4444) : (isSelected ? const Color(0xFF008080) : const Color(0xFF334155)),
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
  const DashboardOverview({super.key, this.onNavigate, this.userName = ''});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  late String _timeString;
  late String _dateString;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timeString = DateFormat('hh:mm a').format(DateTime.now());
    _dateString = DateFormat('EEEE, MMMM d, y').format(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

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
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 20, isDesktop ? 24 : 16, isDesktop ? 40 : 20, isDesktop ? 40 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTopBar(isDesktop),
          const SizedBox(height: 30),
          _buildPatientMetricsGrid(),
          const SizedBox(height: 30),
          if (isDesktop) 
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: _consultationsCard()),
              const SizedBox(width: 25),
              Expanded(child: _symptomBreakdownCard()),
            ])
          else ...[
            _consultationsCard(),
            const SizedBox(height: 25),
            _symptomBreakdownCard(),
          ],
        ],
      ),
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
          const Text("OVERVIEW", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF008080), letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text("Welcome, $displayName!", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        ]),
        if (isDesktop) Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeString, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008080), fontSize: 17)),
              Text(_dateString, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientMetricsGrid() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("VISITATION SUMMARY", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF008080), letterSpacing: 1.2)),
          const SizedBox(height: 25),
          LayoutBuilder(builder: (context, constraints) {
            bool isSmall = constraints.maxWidth < 700;
            return isSmall 
              ? Column(children: _buildMetricItems(isMobile: true))
              : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: _buildMetricItems());
          }),
        ],
      ),
    );
  }

  List<Widget> _buildMetricItems({bool isMobile = false}) {
    // Count from real records (today = 2026-05-02)
    const today = "2026-05-02";
    final todayRecords = _allRecords.where((r) => r["date"] == today).toList();
    final total    = todayRecords.length;
    final students = todayRecords.where((r) => r["type"] == "Student").length;
    final faculty  = todayRecords.where((r) => r["type"] == "Faculty").length;
    final staff    = todayRecords.where((r) => r["type"] == "Staff").length;

    final List<Map<String, dynamic>> metrics = [
      {"label": "Total Patients",  "value": total.toString().padLeft(2, '0'),    "color": const Color(0xFF008080), "icon": Icons.analytics_outlined},
      {"label": "Students",        "value": students.toString().padLeft(2, '0'), "color": const Color(0xFF2563EB), "icon": Icons.school_outlined},
      {"label": "Faculty",         "value": faculty.toString().padLeft(2, '0'),  "color": const Color(0xFFD97706), "icon": Icons.co_present_outlined},
      {"label": "Staff / Others",  "value": staff.toString().padLeft(2, '0'),    "color": const Color(0xFF7C3AED), "icon": Icons.badge_outlined},
    ];

    return metrics.map((m) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 12.0 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
              child: Icon(m['icon'], color: m['color'], size: 22),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['value'], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                Text(m['label'], style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ],
            ),
            if (!isMobile && metrics.last != m) 
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Container(width: 1.5, height: 40, color: const Color(0xFFF1F5F9)),
              ),
          ],
        ),
      );
    }).toList();
  }

  // Shared records — same source as RecordsBooklet
  static const List<Map<String, String>> _allRecords = [
    {"date":"2026-05-02","time":"08:15 AM","name":"Cresa Delacruz S.","id":"234567","type":"Student","dept":"BSCS","year":"2nd Year","complaint":"Headache and Dizziness","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"08:40 AM","name":"John A. Doe","id":"234889","type":"Student","dept":"BSIT","year":"3rd Year","complaint":"Fever","medicine":"Biogesic","qty":"2"},
    {"date":"2026-05-02","time":"08:30 AM","name":"Jane Smith","id":"F001","type":"Faculty","dept":"ICS","year":"Dean","complaint":"Migraine","medicine":"Paracetamol","qty":"2"},
    {"date":"2026-05-02","time":"09:15 AM","name":"Ramon Garcia","id":"F002","type":"Faculty","dept":"ICS","year":"Instructor","complaint":"Headache","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"08:00 AM","name":"Mark Lee","id":"S001","type":"Staff","dept":"Registrar","year":"???","complaint":"Headache","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"11:50 AM","name":"Rosa Navarro","id":"S002","type":"Staff","dept":"Library","year":"Librarian","complaint":"Fever","medicine":"Biogesic","qty":"2"},
  ];

  Widget _consultationsCard() {
    // Show today's records, most recent first, up to 5
    const today = "2026-05-02";
    final todayRecords = _allRecords
        .where((r) => r["date"] == today)
        .toList()
      ..sort((a, b) => b["time"]!.compareTo(a["time"]!));
    final shown = todayRecords.take(5).toList();

    return _baseCard(
      title: "Recent Consultations",
      icon: Icons.history_rounded,
      child: Column(
        children: shown.map((r) {
          Color color;
          Color bgColor;
          switch (r["type"]) {
            case "Faculty":
              color = const Color(0xFFD97706); bgColor = const Color(0xFFFEF3C7);
              break;
            case "Staff":
              color = const Color(0xFF7C3AED); bgColor = const Color(0xFFEDE9FE);
              break;
            default:
              color = const Color(0xFF2563EB); bgColor = const Color(0xFFDBEAFE);
          }
          return _tile(r["name"]!, r["complaint"]!, r["time"]!, r["type"]!, color, bgColor);
        }).toList(),
      ),
    );
  }

  Widget _tile(String n, String s, String t, String type, Color color, Color bgColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFF1F5F9))),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: bgColor, child: Text(n[0], style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text("$type • $s", style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            ]),
          ),
          Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _symptomBreakdownCard() {
    return _baseCard(
      title: "Top Symptoms",
      icon: Icons.trending_up_rounded,
      child: Column(
        children: [
          _symptomRow("Fever / Flu", 12, Colors.red, 30),
          _symptomRow("Headache", 8, Colors.blue, 30),
          _symptomRow("Stomach Ache", 5, Colors.orange, 30),
          _symptomRow("Injury", 3, Colors.green, 30),
        ],
      ),
    );
  }

  Widget _symptomRow(String label, int count, Color color, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
              Text("$count cases", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: count / total,
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: const Color(0xFF008080), size: 20),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          ]),
          const SizedBox(height: 25),
          child,
        ],
      ),
    );
  }
}