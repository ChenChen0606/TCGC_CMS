import 'dart:typed_data';

import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/patients/services/student_import_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';

class StudentImportDialog extends StatefulWidget {
  const StudentImportDialog({super.key});

  @override
  State<StudentImportDialog> createState() => _StudentImportDialogState();
}

class _StudentImportDialogState extends State<StudentImportDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;
  static const Color kSuccess = AppColors.success;

  int _stage = 0;
  String _working = '';

  String? _fileName;
  Uint8List? _bytes;
  int _fileSize = 0;
  String? _error;

  StudentImportPlan? _plan;
  StudentImportReport? _report;

  Future<void> _chooseFile() async {
    setState(() => _error = null);
    try {
      const typeGroup = XTypeGroup(
        label: 'Spreadsheet',
        extensions: ['xlsx', 'xls', 'csv'],
        uniformTypeIdentifiers: [
          'org.openxmlformats.spreadsheetml.sheet',
          'public.comma-separated-values-text',
        ],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() {
          _fileName = file.name;
          _bytes = null;
          _fileSize = 0;
          _error = 'That file is empty.';
        });
        return;
      }
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        _fileSize = bytes.length;
        _plan = null;
        _stage = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the file: $e');
    }
  }

  Future<void> _analyze() async {
    final bytes = _bytes;
    final name = _fileName;
    if (bytes == null || name == null) return;
    setState(() {
      _stage = 1;
      _working = 'Analyzing file…';
      _error = null;
    });
    try {
      final plan =
          await StudentImportService.analyze(fileName: name, bytes: bytes);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _stage = 2;
      });
    } on ImportFileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not analyze the file: $e';
        _stage = 0;
      });
    }
  }

  Future<void> _confirmAndSave() async {
    final plan = _plan;
    if (plan == null || plan.saveCount == 0) return;

    final skipped = plan.exists + plan.invalid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Save these students?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: SizedBox(
          width: 360,
          child: Text(
            'This will save ${plan.saveCount} student record(s) into '
            '${plan.termLabel}:\n\n'
            '• ${plan.added} new student(s)\n'
            '• ${plan.updated} with updated personal info\n'
            '• ${plan.unchanged} with no personal changes (term record only)'
            '${skipped > 0 ? '\n\n$skipped row(s) will be skipped.' : ''}',
            style: const TextStyle(fontSize: 14.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kTextSub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _stage = 1;
      _working = 'Saving to the database…';
      _error = null;
    });
    try {
      final report = await StudentImportService.save(plan);
      if (!mounted) return;
      setState(() {
        _report = report;
        _stage = 3;
      });
    } on ImportFileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save the import: $e';
        _stage = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size.width;
    final w = screen < 620 ? screen * 0.94 : 720.0;
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: w,
        constraints: const BoxConstraints(maxHeight: 780),
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _header(),
          const SizedBox(height: 16),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 16),
          Flexible(child: _body()),
        ]),
      ),
    );
  }

  Widget _header() {
    final String title;
    final String sub;
    final IconData icon;
    final Color color;
    switch (_stage) {
      case 2:
        title = 'Import Analysis';
        sub = '$_fileName · ${_plan?.total ?? 0} row(s) read';
        icon = Icons.analytics_outlined;
        color = AppColors.info;
      case 3:
        title = 'Import Complete';
        sub = _report?.termLabel ?? '';
        icon = Icons.check_circle_outline;
        color = kSuccess;
      default:
        title = 'Import Records';
        sub = 'Add a whole batch of student records in one go';
        icon = Icons.upload_file_rounded;
        color = AppColors.info;
    }
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: kTextSub)),
          ],
        ),
      ),
      IconButton(
        onPressed: _stage == 1 ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded, color: kTextSub),
        iconSize: 20,
      ),
    ]);
  }

  Widget _body() {
    if (_stage == 1) return _workingView();
    if (_stage == 3 && _report != null) return _savedView(_report!);
    if (_stage == 2 && _plan != null) return _analysisView(_plan!);
    return _configureView();
  }

  Widget _configureView() {
    final period = ReferenceCatalog.activePeriod;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepLabel('1', 'School Year & Semester'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dlabel('Term'),
              _readOnlyField(
                Icons.calendar_month_outlined,
                period?.label ?? 'No current term',
                badge: period == null ? null : _currentBadge(),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dlabel('Category'),
              _readOnlyField(Icons.school_outlined, 'Student'),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        _infoBox(
          'Every row is filed under the current term. A student who already '
          'has a record in this term is skipped. On import, the same '
          'students\' earlier-term records are kept for viewing but become '
          'read-only.',
          kPrimary,
        ),
        const SizedBox(height: 20),
        _stepLabel('2', 'Upload File'),
        _dropZone(),
        const SizedBox(height: 10),
        const Text(
          'Required columns: Student ID, First Name, Last Name, Sex, Program, '
          'Year Level.\nOptional: Institute, Middle Name, Suffix, Birth Date, '
          'Contact, Email, Address. If Institute is missing it is taken from '
          'the program.',
          style: TextStyle(fontSize: 12, color: kTextSub, height: 1.45),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorRow(_error!),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kBorder),
                foregroundColor: kTextSub,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (_bytes == null || period == null) ? null : _analyze,
              icon: const Icon(Icons.analytics_outlined, size: 17),
              label: const Text('Analyze File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _dropZone() {
    final hasFile = _fileName != null && _bytes != null;
    return GestureDetector(
      onTap: _chooseFile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: hasFile
              ? kPrimary.withValues(alpha: 0.05)
              : const Color(0xFFFAFCFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasFile
                ? kPrimary.withValues(alpha: 0.4)
                : AppColors.borderStrong,
            width: 1.4,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            hasFile ? Icons.table_chart_rounded : Icons.cloud_upload_outlined,
            size: 34,
            color: hasFile ? kPrimary : kTextSub,
          ),
          const SizedBox(height: 10),
          if (hasFile) ...[
            Text(_fileName!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 4),
            Text('${_formatBytes(_fileSize)} · tap to choose a different file',
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ] else ...[
            const Text('Tap to choose a file',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 4),
            const Text('Excel (.xlsx / .xls) or CSV — one row per student',
                style: TextStyle(fontSize: 12.5, color: kTextSub)),
          ],
        ]),
      ),
    );
  }

  Widget _workingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 54,
          height: 54,
          child: CircularProgressIndicator(strokeWidth: 4, color: kPrimary),
        ),
        const SizedBox(height: 20),
        Text(_working,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain)),
        const SizedBox(height: 6),
        const Text('Please keep this window open.',
            style: TextStyle(fontSize: 13.5, color: kTextSub)),
      ]),
    );
  }

  Widget _analysisView(StudentImportPlan p) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth < 560 ? 2 : 3;
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _statTile(Icons.receipt_long_rounded, 'Total Records', p.total,
                    kPrimary, w),
                _statTile(Icons.new_releases_rounded, 'New', p.added,
                    AppColors.success, w),
                _statTile(Icons.edit_note_rounded, 'Updated', p.updated,
                    AppColors.warning, w),
                _statTile(Icons.remove_circle_outline_rounded, 'Unchanged',
                    p.unchanged, kTextSub, w),
                _statTile(Icons.block_rounded, 'Already Exists', p.exists,
                    AppColors.info, w),
                if (p.invalid > 0)
                  _statTile(Icons.error_outline_rounded, 'Invalid', p.invalid,
                      kDanger, w),
              ]);
            }),
            const SizedBox(height: 10),
            _infoBox(
              'Students are matched by Student ID. New: not on file yet. '
              'Updated: already on file and their personal info changed. '
              'Unchanged: personal info is the same. New, Updated and '
              'Unchanged students all get a record in ${p.termLabel}. '
              'Already exists: they already have a record in ${p.termLabel}, '
              'so they are NOT saved again.',
              kTextSub,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorRow(_error!),
            ],
            const SizedBox(height: 16),
            Row(children: [
              const Text('Students in the file',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kTextMain)),
              const Spacer(),
              Text('${p.total} row(s)',
                  style: const TextStyle(fontSize: 12.5, color: kTextSub)),
            ]),
            const SizedBox(height: 10),
            _analysisTable(p),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _plan = null;
              _stage = 0;
              _error = null;
            }),
            icon:
                const Icon(Icons.arrow_back_rounded, size: 16, color: kPrimary),
            label: const Text('Back', style: TextStyle(color: kPrimary)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: p.saveCount == 0 ? null : _confirmAndSave,
            icon: const Icon(Icons.download_done_rounded, size: 17),
            label: Text(p.saveCount == 0
                ? 'Nothing to import'
                : 'Import ${p.saveCount} student(s)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ]),
    ]);
  }

  Color _statusColor(String s) {
    switch (s) {
      case kImportNew:
        return AppColors.success;
      case kImportUpdated:
        return AppColors.warning;
      case kImportExists:
        return AppColors.info;
      case kImportInvalid:
        return kDanger;
      default:
        return kTextSub;
    }
  }

  Widget _analysisTable(StudentImportPlan p) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                showCheckboxColumn: false,
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextSub,
                    fontSize: 12,
                    letterSpacing: 0.4),
                dataTextStyle: const TextStyle(color: kTextMain, fontSize: 13),
                columnSpacing: 18,
                horizontalMargin: 14,
                dividerThickness: 1,
                border: const TableBorder(
                    horizontalInside: BorderSide(color: kBorder, width: 0.8)),
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('PROGRAM')),
                  DataColumn(label: Text('YEAR')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('NOTE')),
                ],
                rows: [
                  for (final r in p.rows)
                    DataRow(cells: [
                      DataCell(Text(r.record.id.isEmpty ? '—' : r.record.id,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700))),
                      DataCell(Text(r.record.fullName,
                          style: const TextStyle(fontSize: 13))),
                      DataCell(Text(
                          r.record.program.isEmpty ? '—' : r.record.program,
                          style: const TextStyle(
                              fontSize: 12.5, color: kTextSub))),
                      DataCell(Text(
                          r.record.yearLevel.isEmpty ? '—' : r.record.yearLevel,
                          style: const TextStyle(
                              fontSize: 12.5, color: kTextSub))),
                      DataCell(_statusBadge(r.status, _statusColor(r.status))),
                      DataCell(Tooltip(
                        message: r.note,
                        child: SizedBox(
                          width: 260,
                          child: Text(r.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: kTextSub)),
                        ),
                      )),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _savedView(StudentImportReport r) {
    final nothing = r.saved.isEmpty;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 4),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: (nothing ? kDanger : kSuccess).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                nothing ? Icons.error_outline : Icons.check_circle_outline,
                color: nothing ? kDanger : kSuccess,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(nothing ? 'Nothing was saved' : 'Saved',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kTextMain)),
            const SizedBox(height: 6),
            Text(
              nothing
                  ? 'No student record was added to ${r.termLabel}.'
                  : '${r.saved.length} student record(s) were saved to '
                      '${r.termLabel}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: kTextSub),
            ),
            if (!nothing) ...[
              const SizedBox(height: 4),
              Text(
                '${r.added} new · ${r.updated} updated · '
                '${r.unchanged} unchanged'
                '${r.retired > 0 ? ' · ${r.retired} earlier-term record(s) set to view-only' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: kTextSub),
              ),
            ],
            if (r.alreadyExisting.isNotEmpty)
              _listSection(
                'Not saved — already have a record in this term '
                '(${r.alreadyExisting.length})',
                AppColors.info,
                [
                  for (final x in r.alreadyExisting)
                    (id: x.record.id, name: x.record.fullName, note: ''),
                ],
              ),
            if (r.failed.isNotEmpty)
              _listSection(
                'Could not be saved (${r.failed.length})',
                kDanger,
                [
                  for (final f in r.failed)
                    (
                      id: f.row.record.id,
                      name: f.row.record.fullName,
                      note: f.reason
                    ),
                ],
              ),
            if (r.invalid.isNotEmpty)
              _listSection(
                'Skipped — missing or incorrect data (${r.invalid.length})',
                AppColors.warning,
                [
                  for (final x in r.invalid)
                    (
                      id: x.record.id.isEmpty
                          ? 'row ${x.rowNumber}'
                          : x.record.id,
                      name: x.record.fullName,
                      note: x.note
                    ),
                ],
              ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          child: const Text('Done'),
        ),
      ),
    ]);
  }

  Widget _listSection(
    String title,
    Color color,
    List<({String id, String name, String note})> items,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 170),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i.id} · ${i.name}',
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: kTextMain)),
                            if (i.note.isNotEmpty)
                              Text(i.note,
                                  style: const TextStyle(
                                      fontSize: 12, color: kTextSub)),
                          ]),
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _currentBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: kSuccess.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text('CURRENT',
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: kSuccess,
                letterSpacing: 0.5)),
      );

  Widget _readOnlyField(IconData icon, String text, {Widget? badge}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: kTextSub),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, color: kTextMain, fontWeight: FontWeight.w600)),
        ),
        if (badge != null) ...[const SizedBox(width: 8), badge],
      ]),
    );
  }

  Widget _infoBox(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                  height: 1.4)),
        ),
      ]),
    );
  }

  Widget _errorRow(String msg) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 15, color: kDanger),
          const SizedBox(width: 6),
          Expanded(
            child:
                Text(msg, style: const TextStyle(fontSize: 13, color: kDanger)),
          ),
        ],
      );

  Widget _stepLabel(String n, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: kPrimary, borderRadius: BorderRadius.circular(7)),
          child: Text(n,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: kTextMain)),
      ]),
    );
  }

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  Widget _statTile(
      IconData icon, String label, int value, Color color, double w) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('$value',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
