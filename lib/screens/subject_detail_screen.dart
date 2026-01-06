// FILE: lib/screens/subject_detail_screen.dart
//
// Subject detail screen:
// - Shows which students have assignments for this subject
// - Groups assignments by student
// - ✅ Search + Student filter chips
// - ✅ Tap an assignment to open the shared polished actions sheet
// - ✅ Live stream so completes/deletes instantly reflect here

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../widgets/assignment_actions_sheet.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;
  final List<Student> students;

  /// Kept for backwards compatibility with your existing Dashboard push.
  /// The screen uses live Firestore by default.
  final List<Assignment>? assignments;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.students,
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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _studentColor(Student s, int index) {
    final v = s.colorValue;
    if (v != 0) return Color(v);
    return _fallbackPalette[index % _fallbackPalette.length];
  }

  Map<String, Student> _studentsById() => {for (final s in widget.students) s.id: s};

  Map<String, Subject> _subjectsById() => {widget.subject.id: widget.subject};

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.name)),
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
                    // fallback to passed assignments if available (instant paint)
                    final fallback = (widget.assignments ?? const <Assignment>[])
                        .where((a) => a.subjectId == widget.subject.id)
                        .toList();
                    if (fallback.isNotEmpty) {
                      return _body(context, fallback);
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    final fallback = (widget.assignments ?? const <Assignment>[])
                        .where((a) => a.subjectId == widget.subject.id)
                        .toList();
                    if (fallback.isNotEmpty) {
                      return _body(context, fallback);
                    }
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

    // Which students have *any* assignments for this subject (unfiltered by search),
    // so chips reflect reality and still allow you to jump around.
    final studentsWithAny = <String>{};
    for (final a in subjectAssignments) {
      if (a.studentId.isNotEmpty) studentsWithAny.add(a.studentId);
    }

    // group filtered list by studentId
    final byStudent = <String, List<Assignment>>{};
    for (final a in filtered) {
      byStudent.putIfAbsent(a.studentId, () => <Assignment>[]).add(a);
    }

    final studentOrder = widget.students
        .where((s) => studentsWithAny.contains(s.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filtersActive = _query.isNotEmpty || _selectedStudentId != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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

        // Search + chips
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
              hintText: 'Search assignments (e.g. “Lesson 3” or a student name)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.text = '';
                        // listener updates _query
                      },
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
                  final count = byStudent[s.id]?.length ?? 0; // count in filtered list
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
                    ],
                  ),
                ),
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
