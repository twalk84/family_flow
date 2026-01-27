// FILE: lib/screens/subjects_screen.dart
//
// Subjects screen:
// - Lists all subjects
// - Search by subject name
// - Edit (rename) subject
// - Tap subject -> SubjectDetailScreen (shows which students have assignments)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';
import 'subject_detail_screen.dart';

class SubjectsScreen extends StatefulWidget {
  final List<Student> students;

  /// Optional: lets the list paint instantly while streams connect.
  final List<Assignment>? initialAssignments;

  const SubjectsScreen({
    super.key,
    required this.students,
    this.initialAssignments,
  });

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  final List<Color> _fallbackStudentPalette = const [
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
    return _fallbackStudentPalette[index % _fallbackStudentPalette.length];
  }

  String _getSubjectIcon(Subject s) {
    final id = (s.courseConfigId.isNotEmpty ? s.courseConfigId : s.name).toLowerCase();
    if (id.contains('math') || id.contains('saxon')) return '📐';
    if (id.contains('chem')) return '🧪';
    if (id.contains('bio')) return '🧬';
    if (id.contains('latin')) return '🏛️';
    if (id.contains('lit')) return '📚';
    if (id.contains('typing')) return '⌨️';
    if (id.contains('spanish')) return '🇪🇸';
    if (id.contains('german') || id.contains('deutsche')) return '🇩🇪';
    if (id.contains('russian')) return '🇷🇺';
    return '📖';
  }

  Future<void> _renameSubject(Subject subject) async {
    final ctrl = TextEditingController(text: subject.name);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Edit Subject'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Subject name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final name = ctrl.text.trim();
    if (name.isEmpty) {
      _snack('Name cannot be empty.', color: Colors.orange);
      return;
    }

    try {
      await FirestorePaths.subjectsCol().doc(subject.id).set(
        {
          'name': name,
          'nameLower': name.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _snack('Subject updated.', color: Colors.green);
    } catch (e) {
      _snack('Update failed: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Subjects')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final targetW = maxW > 900 ? 900.0 : maxW;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: targetW,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirestorePaths.subjectsCol().orderBy('nameLower').snapshots(),
                  builder: (context, subjSnap) {
                    if (!subjSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final subjects = subjSnap.data!.docs.map(Subject.fromDoc).toList();

                    // assignments stream so we can show counts + student dots per subject
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirestorePaths.assignmentsCol().snapshots(),
                      builder: (context, aSnap) {
                        final hasAssignments = aSnap.hasData;
                        final studentsById = {for (final s in widget.students) s.id: s};
                        final subjectsById = {for (final s in subjects) s.id: s};

                        List<Assignment> assignments = const <Assignment>[];
                        if (hasAssignments) {
                          assignments = aSnap.data!.docs
                              .map((d) => Assignment.fromDoc(d, studentsById: studentsById, subjectsById: subjectsById))
                              .toList();
                        } else if (widget.initialAssignments != null) {
                          assignments = widget.initialAssignments!;
                        }

                        // subjectId -> counts + studentIds
                        final Map<String, int> countBySubject = {};
                        final Map<String, Set<String>> studentIdsBySubject = {};

                        for (final a in assignments) {
                          if (a.subjectId.isEmpty) continue;
                          countBySubject[a.subjectId] = (countBySubject[a.subjectId] ?? 0) + 1;
                          (studentIdsBySubject[a.subjectId] ??= <String>{}).add(a.studentId);
                        }

                        final filtered = subjects.where((s) {
                          if (q.isEmpty) return true;
                          return s.name.toLowerCase().contains(q);
                        }).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search subjects (e.g. “Latin”, “Math”)',
                                prefixIcon: const Icon(Icons.search, color: Colors.white60),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear',
                                        icon: const Icon(Icons.close),
                                        onPressed: () => _searchCtrl.text = '',
                                      ),
                                filled: true,
                                fillColor: const Color(0xFF1F2937),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                Text(
                                  'Subjects (${filtered.length})',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                if (!hasAssignments)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            Expanded(
                              child: filtered.isEmpty
                                  ? const Center(
                                      child: Text('No subjects found.', style: TextStyle(color: Colors.white60)),
                                    )
                                  : ListView.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final s = filtered[index];
                                        final count = countBySubject[s.id] ?? 0;
                                        final studentIds = (studentIdsBySubject[s.id] ?? <String>{}).toList();

                                        // turn studentIds into color dots
                                        final dots = <Color>[];
                                        for (int i = 0; i < widget.students.length; i++) {
                                          final st = widget.students[i];
                                          if (studentIds.contains(st.id)) {
                                            dots.add(_studentColor(st, i));
                                          }
                                        }

                                        final icon = _getSubjectIcon(s);

                                        return Card(
                                          color: const Color(0xFF1F2937),
                                          margin: const EdgeInsets.only(bottom: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: const BorderSide(color: Colors.white10),
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(16),
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => SubjectDetailScreen(
                                                    subject: s,
                                                    students: widget.students,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black26,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(icon, style: const TextStyle(fontSize: 24)),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          s.name,
                                                          style: const TextStyle(
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            Text(
                                                              '$count assignment${count == 1 ? '' : 's'}',
                                                              style: const TextStyle(
                                                                color: Colors.white60,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 10),
                                                            if (dots.isNotEmpty) ...[
                                                              for (final c in dots.take(6))
                                                                Container(
                                                                  width: 7,
                                                                  height: 7,
                                                                  margin: const EdgeInsets.only(right: 4),
                                                                  decoration: BoxDecoration(
                                                                    color: c,
                                                                    shape: BoxShape.circle,
                                                                  ),
                                                                ),
                                                              if (dots.length > 6)
                                                                Text(
                                                                  '+${dots.length - 6}',
                                                                  style: const TextStyle(
                                                                    color: Colors.white60,
                                                                    fontSize: 11,
                                                                  ),
                                                                ),
                                                            ] else ...[
                                                              const Text(
                                                                '• no students yet',
                                                                style: TextStyle(
                                                                  color: Colors.white38,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(Icons.more_vert, color: Colors.white60),
                                                    onSelected: (val) {
                                                      if (val == 'edit') {
                                                        _renameSubject(s);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      const PopupMenuItem(
                                                        value: 'edit',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.edit, size: 18),
                                                            SizedBox(width: 8),
                                                            Text('Edit Subject'),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const Icon(Icons.chevron_right, color: Colors.white24),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
