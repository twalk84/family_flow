// FILE: lib/screens/subject_detail_screen.dart
//
// Subject detail screen:
// - Shows which students have assignments for this subject
// - Groups assignments by student
// - ✅ Search + Student filter chips
// - ✅ Tap an assignment to open the shared polished actions sheet
// - ✅ Live stream so completes/deletes instantly reflect here
// - ✅ Progress header with completion bar, badges, streaks
// - ✅ Delete Subject + Cleanup button in AppBar (calls SubjectDeleteService)
// - ✅ Shows "Completed: <timestamp>" on completed assignments when completionDate is present

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/firestore/firestore_paths.dart';
import '../core/models/models.dart';

import '../services/subject_delete_service.dart';

import '../widgets/assignment_actions_sheet.dart';
import '../widgets/progress_header.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;
  final List<Student> students;

  /// Optional: current student for progress header (if viewing for a specific student)
  final Student? currentStudent;

  /// Kept for backwards compatibility with your existing Dashboard push.
  /// The screen uses live Firestore by default.
  final List<Assignment>? assignments;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.students,
    this.currentStudent,
    this.assignments,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _selectedStudentId;

  final List<Color> _fallbackPalette = const [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.orange,
    Colors.teal,
    Colors.red,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });

    // If a current student is specified, default filter to them
    if (widget.currentStudent != null) {
      _selectedStudentId = widget.currentStudent!.id;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _studentColor(Student s, int index) {
    final v = s.colorValue;
    if (v != 0) return Color(v);
    return _fallbackPalette[index % _fallbackPalette.length];
  }

  Map<String, Student> _studentsById() => {for (final s in widget.students) s.id: s};
  Map<String, Subject> _subjectsById() => {widget.subject.id: widget.subject};

  Student? _findStudentById(String id) {
    for (final s in widget.students) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Assignment> _mapDocs(QuerySnapshot<Map<String, dynamic>> snap) {
    final studentsById = _studentsById();
    final subjectsById = _subjectsById();

    final out = snap.docs
        .map((d) => Assignment.fromDoc(d, studentsById: studentsById, subjectsById: subjectsById))
        .toList();

    out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return out;
  }

  List<Assignment> _applyFilters(List<Assignment> all) {
    final q = _query.toLowerCase();

    return all.where((a) {
      if (_selectedStudentId != null && a.studentId != _selectedStudentId) return false;

      if (q.isNotEmpty) {
        final hay = '${a.name} ${a.studentName}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _selectedStudentId = null;
      _query = '';
      _searchCtrl.text = '';
    });
  }

  Future<void> _onDeleteSubjectPressed() async {
    int assignmentCount = 0;
    int badgeCount = 0;

    try {
      final aSnap = await FirestorePaths.assignmentsCol()
          .where('subjectId', isEqualTo: widget.subject.id)
          .get();
      assignmentCount = aSnap.docs.length;
    } catch (_) {}

    try {
      final bSnap = await FirebaseFirestore.instance
          .collectionGroup('badgesEarned')
          .where('subjectId', isEqualTo: widget.subject.id)
          .get();
      badgeCount = bSnap.docs.length;
    } catch (_) {}

    final studentIds = widget.students.map((s) => s.id).toList();

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Delete Subject + Cleanup?'),
              content: Text(
                'This will permanently delete:\n'
                '• Subject: "${widget.subject.name}"\n'
                '• Assignments: $assignmentCount\n'
                '• Progress docs (subjectProgress): up to ${studentIds.length}\n'
                '• Badges for this subject: $badgeCount\n\n'
                '✅ Wallet points WILL be reversed for completed assignments.\n\n'
                'Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 90,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Deleting subject and cleaning up...'),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await SubjectDeleteService.instance.deleteSubjectCascade(
        subjectId: widget.subject.id,
        courseConfigId: widget.subject.courseConfigId,
        studentIds: studentIds,
        reversePoints: true,
      );

      if (!mounted) return;
      Navigator.pop(context); // close progress dialog

      _snack(
        'Deleted subject. '
        '${result.assignmentsDeleted} assignments, '
        '${result.progressDocsDeleted} progress docs, '
        '${result.badgesDeleted} badges cleaned, '
        '${result.pointsReversed} points reversed.',
        color: Colors.green,
      );

      // Leave detail screen (subject no longer exists)
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      _snack('Delete failed: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          IconButton(
            tooltip: 'Delete subject + cleanup',
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _onDeleteSubjectPressed,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final targetW = maxW > 900 ? 900.0 : maxW;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: targetW,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestorePaths.assignmentsCol()
                    .where('subjectId', isEqualTo: widget.subject.id)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    final fallback = (widget.assignments ?? const <Assignment>[])
                        .where((a) => a.subjectId == widget.subject.id)
                        .toList();
                    if (fallback.isNotEmpty) return _body(context, fallback);
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    final fallback = (widget.assignments ?? const <Assignment>[])
                        .where((a) => a.subjectId == widget.subject.id)
                        .toList();
                    if (fallback.isNotEmpty) return _body(context, fallback);
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  final docs = snap.data;
                  if (docs == null) return const Center(child: Text('No data.'));

                  final liveAssignments = _mapDocs(docs);
                  return _body(context, liveAssignments);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<Assignment> subjectAssignments) {
    final filtered = _applyFilters(subjectAssignments);

    final studentsWithAny = <String>{};
    for (final a in subjectAssignments) {
      if (a.studentId.isNotEmpty) studentsWithAny.add(a.studentId);
    }

    final byStudent = <String, List<Assignment>>{};
    for (final a in filtered) {
      byStudent.putIfAbsent(a.studentId, () => <Assignment>[]).add(a);
    }

    final studentOrder = widget.students
        .where((s) => studentsWithAny.contains(s.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filtersActive = _query.isNotEmpty || _selectedStudentId != null;

    Student? progressStudent = widget.currentStudent;
    if (progressStudent == null && _selectedStudentId != null) {
      progressStudent = _findStudentById(_selectedStudentId!);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (progressStudent != null) ...[
          ProgressHeader(
            student: progressStudent,
            subject: widget.subject,
          ),
          const SizedBox(height: 8),
        ],

        Text(
          'Assignments by Student',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white60),
            ),
            const Spacer(),
            if (filtersActive)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 12),

        _filterBar(studentOrder, byStudent),

        const SizedBox(height: 14),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No matches. Try clearing filters or searching a different term.',
              style: TextStyle(color: Colors.white70),
            ),
          ),

        if (filtered.isNotEmpty)
          for (int i = 0; i < studentOrder.length; i++)
            if (byStudent.containsKey(studentOrder[i].id))
              _studentSection(
                context,
                studentOrder[i],
                _studentColor(studentOrder[i], i),
                (byStudent[studentOrder[i].id] ?? const <Assignment>[])
                  ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
              ),
      ],
    );
  }

  Widget _filterBar(List<Student> studentOrder, Map<String, List<Assignment>> byStudent) {
    final selectedId = _selectedStudentId;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search assignments (e.g. "Lesson 3" or a student name)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => _searchCtrl.text = '',
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Filter by student', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: 'All',
                  selected: selectedId == null,
                  onTap: () => setState(() => _selectedStudentId = null),
                ),
                ...studentOrder.map((s) {
                  final count = byStudent[s.id]?.length ?? 0;
                  final isSelected = selectedId == s.id;

                  return _chip(
                    label: count > 0 ? '${s.name} ($count)' : s.name,
                    selected: isSelected,
                    onTap: () => setState(() => _selectedStudentId = s.id),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.purple : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _studentSection(
    BuildContext context,
    Student student,
    Color color,
    List<Assignment> items,
  ) {
    final total = items.length;
    final done = items.where((a) => a.isCompleted).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  student.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('$done/$total', style: const TextStyle(color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 12),
          for (final a in items) _assignmentRow(context, a),
        ],
      ),
    );
  }

  Widget _assignmentRow(BuildContext context, Assignment a) {
    final isDone = a.isCompleted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => AssignmentActionsSheet.show(context, a),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDone ? Colors.green.withOpacity(0.10) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDone ? Colors.green.withOpacity(0.28) : Colors.white12),
            ),
            child: Row(
              children: [
                Icon(
                  isDone ? Icons.check_circle : Icons.circle_outlined,
                  color: isDone ? Colors.green : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        a.dueDate.isEmpty ? 'No due date' : a.dueDate,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      if (isDone && a.completionDate.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Completed: ${a.completionDate}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
                if (isDone && a.rewardPointsApplied > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+${a.rewardPointsApplied}',
                      style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
                if (a.grade != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.green.withOpacity(0.25)),
                    ),
                    child: Text(
                      '${a.grade}%',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
