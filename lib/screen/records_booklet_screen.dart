// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class RecordsBooklet extends StatefulWidget {
  const RecordsBooklet({super.key});

  @override
  State<RecordsBooklet> createState() => RecordsBookletState();
}

class RecordsBookletState extends State<RecordsBooklet> {

  static const Color kPrimary   = Color(0xFF008080);
  static const Color kPrimaryDk = Color(0xFF0F766E);
  static const Color kTextMain  = Color(0xFF0F172A);
  static const Color kTextSub   = Color(0xFF64748B);
  static const Color kDanger    = Color(0xFFEF4444);
  static const Color kBorder    = Color(0xFFE2E8F0);

  String selectedFilter = "Today";
  DateTime selectedDate = DateTime(2026, 5, 2);
  String searchQuery = "";

  static const String _simulatedToday = "2026-05-02";

  final List<Map<String, String>> _allRecords = [
    {"date":"2026-06-02","time":"02:15 PM","name":"Cresa Delacruz S.","id":"234567","type":"Student","dept":"BSCS","year":"2nd Year","complaint":"Sore Throat","medicine":"Amoxicillin","qty":"1"},
    {"date":"2026-05-02","time":"08:15 AM","name":"Cresa Delacruz S.","id":"234567","type":"Student","dept":"BSCS","year":"2nd Year","complaint":"Headache and Dizziness","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"08:40 AM","name":"John A. Doe","id":"234889","type":"Student","dept":"BSIT","year":"3rd Year","complaint":"Fever","medicine":"Biogesic","qty":"2"},
    {"date":"2024-05-02","time":"09:05 AM","name":"John A. Doe","id":"234889","type":"Student","dept":"BSIT","year":"3rd Year","complaint":"Fever","medicine":"Biogesic","qty":"3"},
    {"date":"2023-05-02","time":"10:05 AM","name":"John A. Doe","id":"234889","type":"Student","dept":"BSIT","year":"3rd Year","complaint":"Fever","medicine":"Biogesic","qty":"5"},
    {"date":"2026-05-02","time":"08:15 AM","name":"Cresa Delacruz S.","id":"234567","type":"Student","dept":"BSCS","year":"2nd Year","complaint":"Headache and Dizziness","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"08:30 AM","name":"Jane Smith","id":"F001","type":"Faculty","dept":"ICS","year":"Dean","complaint":"Migraine","medicine":"Paracetamol","qty":"2"},
    {"date":"2026-05-02","time":"09:15 AM","name":"Prof. Ramon Garcia","id":"F002","type":"Faculty","dept":"ICS","year":"Instructor","complaint":"Headache","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-06-02","time":"10:10 AM","name":"Jane Smith","id":"F001","type":"Faculty","dept":"ICS","year":"Dean","complaint":"Fever","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"08:00 AM","name":"Mark Lee","id":"S001","type":"Staff","dept":"Registrar","year":"???","complaint":"Headache","medicine":"Paracetamol","qty":"1"},
    {"date":"2026-05-02","time":"11:50 AM","name":"Rosa Navarro","id":"S002","type":"Staff","dept":"Library","year":"Librarian","complaint":"Fever","medicine":"Biogesic","qty":"2"},
  ];

  // ── FILTER ────────────────────────────────────────────────────────────

  List<Map<String, String>> _getFilteredRecords({String? typeFilter}) {
    var filtered = List<Map<String, String>>.from(_allRecords);

    if (typeFilter != null) {
      filtered = filtered.where((e) => e["type"] == typeFilter).toList();
    }
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((e) => e.values.join(" ").toLowerCase().contains(searchQuery)).toList();
    }
    if (selectedFilter == "Today") {
      filtered = filtered.where((e) => e["date"] == _simulatedToday).toList();
    } else if (selectedFilter == "Custom") {
      final String picked = DateFormat("yyyy-MM-dd").format(selectedDate);
      filtered = filtered.where((e) => e["date"] == picked).toList();
    }
    return filtered;
  }

  Map<String, int> _getVisitSummary() {
    final all = _getFilteredRecords();
    return {
      "all": all.length,
      "student": all.where((e) => e["type"] == "Student").length,
      "faculty": all.where((e) => e["type"] == "Faculty").length,
      "staff": all.where((e) => e["type"] == "Staff").length,
    };
  }

  // ── DATE PICKER ───────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2027),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kPrimary,
            onPrimary: Colors.white,
            onSurface: kTextMain,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedFilter = "Custom";
      });
    }
  }

  // ── EDIT DIALOG ───────────────────────────────────────────────────────

  void _showEditDialog(Map<String, String> record) {
    final controllers = {
      "complaint": TextEditingController(text: record["complaint"]),
      "medicine":  TextEditingController(text: record["medicine"]),
      "qty":       TextEditingController(text: record["qty"]),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_outlined, color: kPrimary, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Edit Record",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain)),
            Text("Update visit details",
                style: TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.normal)),
          ]),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _readOnlyField("Full Name",       record["name"]!,  Icons.person_outline),
              _readOnlyField("ID",              record["id"]!,    Icons.badge_outlined),
              _readOnlyField("Dept / Institute",record["dept"]!,  Icons.business_outlined),
              _readOnlyField("Year / Position", record["year"]!,  Icons.school_outlined),
              const Divider(height: 20, color: kBorder),
              _editField(controllers["complaint"]!, "Complaint", Icons.sick_outlined),
              _editField(controllers["medicine"]!,  "Medicine",  Icons.medication_outlined),
              _editField(controllers["qty"]!,        "Qty",       Icons.numbers_outlined),
            ]),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              foregroundColor: kTextSub,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            icon: const Icon(Icons.save_outlined, size: 15),
            label: const Text("Update", style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () {
              Navigator.pop(ctx);
              _showUpdateConfirmDialog(record, controllers);
            },
          ),
        ],
      ),
    );
  }

  // ── UPDATE CONFIRMATION ───────────────────────────────────────────────

void _showUpdateConfirmDialog(
  Map<String, String> record,
  Map<String, TextEditingController> controllers,
) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.save_outlined, color: kPrimary, size: 22),
            ),
            const SizedBox(height: 12),
            const Text("Update Record",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kTextMain)),
            const SizedBox(height: 6),
            const Text("Are you sure you want to save changes to this record?",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showEditDialogWithControllers(record, controllers);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBorder),
                  foregroundColor: kTextSub,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text("Cancel", style: TextStyle(fontSize: 12)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    record["complaint"] = controllers["complaint"]!.text;
                    record["medicine"]  = controllers["medicine"]!.text;
                    record["qty"]       = controllers["qty"]!.text;
                  });
                  Navigator.pop(context);
                  _showSuccess("Record updated successfully.");
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text("Update",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              )),
            ]),
          ]),
        ),
      ),
    ),
  );
}

  void _showEditDialogWithControllers(
    Map<String, String> record,
    Map<String, TextEditingController> controllers,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_outlined, color: kPrimary, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Edit Record",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain)),
            Text("Update visit details",
                style: TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.normal)),
          ]),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _readOnlyField("Full Name",       record["name"]!,  Icons.person_outline),
              _readOnlyField("ID",              record["id"]!,    Icons.badge_outlined),
              _readOnlyField("Dept / Institute",record["dept"]!,  Icons.business_outlined),
              _readOnlyField("Year / Position", record["year"]!,  Icons.school_outlined),
              const Divider(height: 20, color: kBorder),
              _editField(controllers["complaint"]!, "Complaint", Icons.sick_outlined),
              _editField(controllers["medicine"]!,  "Medicine",  Icons.medication_outlined),
              _editField(controllers["qty"]!,        "Qty",       Icons.numbers_outlined),
            ]),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              foregroundColor: kTextSub,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            icon: const Icon(Icons.save_outlined, size: 15),
            label: const Text("Update", style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () {
              Navigator.pop(ctx);
              _showUpdateConfirmDialog(record, controllers);
            },
          ),
        ],
      ),
    );
  }

  // ── READ-ONLY FIELD ───────────────────────────────────────────────────

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSub),
          prefixIcon: Icon(icon, size: 17, color: kTextSub),
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 13, color: kTextSub),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 13, color: kTextMain),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSub),
          prefixIcon: Icon(icon, size: 17, color: kPrimary),
          filled: true,
          fillColor: const Color(0xFFFAFCFE),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
      ),
    );
  }

  // ── SUCCESS SNACKBAR ──────────────────────────────────────────────────

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(msg, style: const TextStyle(color: Colors.white)),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── DELETE CONFIRMATION ───────────────────────────────────────────────

void _showDeleteConfirmDialog(Map<String, String> e) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: kDanger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: kDanger, size: 22),
            ),
            const SizedBox(height: 12),
            const Text("Delete Record",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kTextMain)),
            const SizedBox(height: 6),
            const Text("Are you sure you want to delete this record?",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBorder),
                  foregroundColor: kTextSub,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text("Cancel", style: TextStyle(fontSize: 12)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () {
                  setState(() => _allRecords.remove(e));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: kDanger,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    content: const Row(children: [
                      Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Text("Record deleted.", style: TextStyle(color: Colors.white)),
                    ]),
                    duration: const Duration(seconds: 2),
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDanger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text("Delete",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              )),
            ]),
          ]),
        ),
      ),
    ),
  );
}

  // ── PRINT ─────────────────────────────────────────────────────────────

  Future<void> _printRecords() async {
    final doc = pw.Document();
    final records = _getFilteredRecords();
    final summary = _getVisitSummary();
    final headers = ["ID", "Name", "Type", "Dept", "Year/Pos", "Complaint", "Medicine", "Qty", "Date", "Time"];
    final tableData = records.map((e) => [e["id"]!,e["name"]!,e["type"]!,e["dept"]!,e["year"]!,e["complaint"]!,e["medicine"]!,e["qty"]!,e["date"]!,e["time"]!]).toList();

    String filterLabel = selectedFilter == "Today"
        ? "Today (${DateFormat('MMMM d, yyyy').format(DateTime(2026,5,2))})"
        : selectedFilter == "Custom"
            ? DateFormat("MMMM d, yyyy").format(selectedDate)
            : "All Records";

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("Medical Records Report", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text("Filter: $filterLabel", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text("Total: ${summary['all']}  |  Students: ${summary['student']}  |  Faculty: ${summary['faculty']}  |  Staff: ${summary['staff']}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ]),
            ]),
            pw.SizedBox(height: 14),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {0:const pw.FlexColumnWidth(1.2),1:const pw.FlexColumnWidth(2.0),2:const pw.FlexColumnWidth(1.0),3:const pw.FlexColumnWidth(1.0),4:const pw.FlexColumnWidth(1.2),5:const pw.FlexColumnWidth(2.0),6:const pw.FlexColumnWidth(1.5),7:const pw.FlexColumnWidth(0.5),8:const pw.FlexColumnWidth(1.2),9:const pw.FlexColumnWidth(1.1)},
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal),
                  children: headers.map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                    child: pw.Text(h, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center),
                  )).toList(),
                ),
                ...tableData.asMap().entries.map((entry) {
                  final isEven = entry.key % 2 == 0;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.teal50),
                    children: entry.value.map((cell) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                      child: pw.Text(cell, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
                    )).toList(),
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text("Generated on: ${DateFormat('MMMM d, yyyy – hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final summary = _getVisitSummary();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      
      floatingActionButton: FloatingActionButton(
        
        onPressed: _printRecords,
        backgroundColor: kPrimary,
        child: const Icon(Icons.print_outlined, color: Colors.white),
      ),
      appBar: AppBar(
        
     //   backgroundColor: Colors.white,
        elevation: 0.5,
        
        title: Padding(
          
          padding: const EdgeInsets.only(top: 25, bottom: 15),
          
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              
              Container(
                width: 44, height: 44,
                
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [kPrimary, kPrimaryDk],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 15),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Medical Records",
                      style: TextStyle(
                          color: kTextMain,
                          fontWeight: FontWeight.w800,
                          fontSize: 20)),
                  Text("TCGC Clinic Management",
                      style: TextStyle(color: kTextSub, fontSize: 12)),
                ],
              ),
              const Spacer(),
              _buildAppBarSummary(summary),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: _buildTabBar(),
        ),
      ),
      body: Column(
        
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: DefaultTabController(
              length: 4,
              child: Builder(builder: (context) {
                return TabBarView(
                  children: [
                    _buildTable(null),
                    _buildTable("Student"),
                    _buildTable("Faculty"),
                    _buildTable("Staff"),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── CUSTOM TAB BAR ────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return DefaultTabController(
      length: 4,
      child: Container(
       color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            indicator: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: kTextSub,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: "ALL"),
              Tab(text: "STUDENTS"),
              Tab(text: "FACULTY"),
              Tab(text: "STAFF"),
            ],
          ),
        ),
      ),
    );
  }

  // ── APPBAR SUMMARY CHIPS ──────────────────────────────────────────────

  Widget _buildAppBarSummary(Map<String, int> summary) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _miniChip(summary["all"]!,     kPrimary,                 Icons.people_alt_rounded,  "All"),
      const SizedBox(width: 6),
      _miniChip(summary["student"]!, const Color(0xFF0EA5E9), Icons.school_rounded,       "Students"),
      const SizedBox(width: 6),
      _miniChip(summary["faculty"]!, const Color(0xFF8B5CF6), Icons.person_4_rounded,     "Faculty"),
      const SizedBox(width: 6),
      _miniChip(summary["staff"]!,   const Color(0xFFF59E0B), Icons.badge_rounded,        "Staff"),
    ]);
  }

  Widget _miniChip(int count, Color color, IconData icon, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text("$count",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  // ── SEARCH + FILTERS ──────────────────────────────────────────────────

  Widget _buildSearchAndFilters() {
    return LayoutBuilder(builder: (context, constraints) {
      bool isMobile = constraints.maxWidth < 700;
      return Container(
        color: const Color(0xFFF8FAFC),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: isMobile
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _searchField(),
                const SizedBox(height: 10),
                _filterRow(),
              ])
            : Row(children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 14),
                _filterRow(),
              ]),
      );
    });
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
      style: const TextStyle(fontSize: 13, color: kTextMain),
      decoration: InputDecoration(
        hintText: "Search anything...",
        hintStyle: const TextStyle(color: kTextSub, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }

  Widget _filterRow() {
    final dateLabel = selectedFilter == "Custom"
        ? DateFormat("MMM d, yyyy").format(selectedDate)
        : "Pick Date";

    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selectedFilter == "Custom"
                ? kPrimary.withOpacity(0.08)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
                color: selectedFilter == "Custom"
                    ? kPrimary.withOpacity(0.4)
                    : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined,
                size: 14,
                color: selectedFilter == "Custom" ? kPrimary : kTextSub),
            const SizedBox(width: 6),
            Text(dateLabel,
                style: TextStyle(
                    fontSize: 12,
                    color: selectedFilter == "Custom" ? kPrimary : kTextSub,
                    fontWeight: selectedFilter == "Custom" ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      _filterChip("Today"),
      const SizedBox(width: 8),
      _filterChip("All"),
    ]);
  }

  Widget _filterChip(String label) {
    final sel = selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: sel ? kPrimary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(25),
          boxShadow: sel
              ? [BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: sel ? Colors.white : kTextSub,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  // ── TABLE ─────────────────────────────────────────────────────────────

  Widget _buildTable(String? type) {
    final filtered = _getFilteredRecords(typeFilter: type);

    if (filtered.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        const Text("No records found",
            style: TextStyle(color: kTextSub, fontSize: 14)),
      ]));
    }

    final bool isAllTab = type == null;

    final List<String> headers = isAllTab
        ? ["ID", "Full Name", "Type", "Dept", "Year / Position", "Complaint", "Medicine", "Qty", "Date", "Time", "Actions"]
        : type == "Student"
            ? ["Student ID", "Full Name", "Course", "Year", "Complaint", "Medicine", "Qty", "Date", "Time", "Actions"]
            : ["Employee ID", "Full Name", "Institute", "Position", "Complaint", "Medicine", "Qty", "Date", "Time", "Actions"];

    return LayoutBuilder(builder: (context, constraints) {
      int columnCount = headers.length;
      bool isMobile = constraints.maxWidth < 900;
      double columnWidth = isMobile ? 150 : constraints.maxWidth / columnCount;

      Widget cell(String text) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Text(text,
            softWrap: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextMain)),
      );

      Widget typeCell(String t) {
        final color = t == "Student"
            ? const Color(0xFF3B82F6)
            : t == "Faculty"
                ? const Color(0xFF8B5CF6)
                : const Color(0xFF10B981);
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          child: Text(t,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color)),
         /* child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),*/
        );
      }

      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 8, bottom: 20, top: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: constraints.maxHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: isMobile ? columnCount * columnWidth : constraints.maxWidth,
                  child: Column(children: [
                    // HEADER
                    Table(
                      columnWidths: {for (int i = 0; i < columnCount; i++) i: FixedColumnWidth(columnWidth)},
                      children: [TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                        children: headers.map((h) => Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
                          child: Text(h,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: kTextSub,
                                  fontSize: 12)),
                        )).toList(),
                      )],
                    ),
                    // BODY
                    Expanded(child: SingleChildScrollView(child: Table(
                      columnWidths: {for (int i = 0; i < columnCount; i++) i: FixedColumnWidth(columnWidth)},
                      border: TableBorder(
                        horizontalInside: BorderSide(color: Colors.grey.shade100),
                        verticalInside: BorderSide(color: Colors.grey.shade100),
                      ),
                      children: filtered.asMap().entries.map((entry) {
                        final e = entry.value;
                        final even = entry.key % 2 == 0;
                        final row = isAllTab
                            ? [cell(e["id"]!), cell(e["name"]!), typeCell(e["type"]!), cell(e["dept"]!), cell(e["year"]!), cell(e["complaint"]!), cell(e["medicine"]!), cell(e["qty"]!), cell(e["date"]!), cell(e["time"]!), _actionButtons(e)]
                            : [cell(e["id"]!), cell(e["name"]!), cell(e["dept"]!), cell(e["year"]!), cell(e["complaint"]!), cell(e["medicine"]!), cell(e["qty"]!), cell(e["date"]!), cell(e["time"]!), _actionButtons(e)];
                        return TableRow(
                          decoration: BoxDecoration(
                              color: even ? Colors.white : const Color(0xFFFAFCFD)),
                          children: row,
                        );
                      }).toList(),
                    ))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ── ACTION BUTTONS ────────────────────────────────────────────────────

  Widget _actionButtons(Map<String, String> e) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Tooltip(
          message: "Edit",
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showEditDialog(e),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.edit_outlined, size: 16, color: kPrimary),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: "Delete",
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showDeleteConfirmDialog(e),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: kDanger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete_outline_rounded, size: 16, color: kDanger),
            ),
          ),
        ),
      ]),
    );
  }
}