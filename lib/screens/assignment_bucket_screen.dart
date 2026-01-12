// FILE: lib/screens/assignment_bucket_screen.dart
//
// Dedicated list screens for:
// - Due Today (incomplete only)
// - Overdue (incomplete only)
//
// Live list: when you complete an item it disappears because it no longer matches.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../core/models/models.dart'; // <-- IMPORTANT: correct path
import '../widgets/app_scaffolds.dart';

enum AssignmentBucket { dueToday, overdue }

class AssignmentBucketScreen extends StatelessWidget {
  final AssignmentBucket bucket;

  const AssignmentBucketScreen({super.key, required this.bucket});

  String _todayYmd() => normalizeDueDate(DateTime.now());

  String get _title {
    switch (bucket) {
      case AssignmentBucket.dueToday:
        return 'Due Today';
      case AssignmentBucket.overdue:
        return 'Overdue';
    }
  }

  String get _subtitle {
    switch (bucket) {
      case AssignmentBucket.dueToday:
        return 'Incomplete assignments due today.';
      case AssignmentBucket.overdue:
        return 'Incomplete assignments past their due date.';
    }
  }

  bool _matchesBucket(Assignment a) {
    final today = _todayYmd();
    if (a.isCompleted) return false;

    final due = normalizeDueDate(a.dueDate);
    if (due.isEmpty) return false;

    switch (bucket) {
      case AssignmentBucket.dueToday:
        return due == today;
      case AssignmentBucket.overdue:
        return due.compareTo(today) < 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.studentsCol().snapshots(),
      builder: (context, studentsSnap) {
        if (!studentsSnap.hasData) return const LoadingScaffold();

        final students = studentsSnap.data!.docs.map(Student.fromDoc).toList();
        final studentsById = {for (final s in students) s.id: s};

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestorePaths.subjectsCol().snapshots(),
          builder: (context, subjectsSnap) {
            if (!subjectsSnap.hasData) return const LoadingScaffold();

            final subjects = subjectsSnap.data!.docs.map(Subject.fromDoc).toList();
            final subjectsById = {for (final s in subjects) s.id: s};

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // NOTE: removed orderBy('dueDate') to avoid crashes if old docs have
              // missing/mixed-type dueDate values. We sort in-memory instead.
              stream: FirestorePaths.assignmentsCol().snapshots(),
              builder: (context, assignmentsSnap) {
                if (!assignmentsSnap.hasData) return const LoadingScaffold();

                final all = assignmentsSnap.data!.docs
                    .map((d) => Assignment.fromDoc(
                          d,
                          studentsById: studentsById,
                          subjectsById: subjectsById,
                        ))
                    .toList();

                final list = all.where(_matchesBucket).toList()
                  ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

                return _BucketScaffold(
                  title: _title,
                  subtitle: _subtitle,
                  bucket: bucket,
                  assignments: list,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BucketScaffold extends StatefulWidget {
  final String title;
  final String subtitle;
  final AssignmentBucket bucket;
  final List<Assignment> assignments;

  const _BucketScaffold({
    required this.title,
    required this.subtitle,
    required this.bucket,
    required this.assignments,
  });

  @override
  State<_BucketScaffold> createState() => _BucketScaffoldState();
}

class _BucketScaffoldState extends State<_BucketScaffold> {
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

  Future<void> _toggleAssignmentComplete(
    String assignmentId, {
    required bool completed,
    int? grade,
  }) async {
    await FirestorePaths.assignmentsCol().doc(assignmentId).set(
      {
        'completed': completed,
        'grade': completed ? grade : null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _deleteAssignment(String assignmentId) async {
    await FirestorePaths.assignmentsCol().doc(assignmentId).delete();
  }

  Future<T?> _showSmoothSheet<T>({
    required String title,
    required Widget Function(BuildContext sheetContext) builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
        final size = MediaQuery.of(sheetContext).size;
        final targetW = size.width > 720 ? 640.0 : size.width;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: viewInsets),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: targetW,
                  maxHeight: size.height * 0.88,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: SingleChildScrollView(child: builder(sheetContext))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAssignmentActionsSheet(Assignment a) async {
    final gradeCtrl = TextEditingController(text: a.grade?.toString() ?? '');

    await _showSmoothSheet<void>(
      title: 'Assignment',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${a.subjectName} • ${a.studentName}', style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.event, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Text(a.dueDate, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text('Complete', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: gradeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Grade % (optional)',
                hintText: 'e.g. 95',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('No Grade'),
                    onPressed: () async {
                      try {
                        await _toggleAssignmentComplete(a.id, completed: true, grade: null);
                        if (mounted) Navigator.pop(sheetContext);
                        _snack('Marked complete.', color: Colors.green);
                      } catch (e) {
                        _snack('Update failed: $e', color: Colors.red);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('With Grade'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      final raw = gradeCtrl.text.trim();
                      final g = raw.isEmpty ? null : int.tryParse(raw);

                      if (raw.isNotEmpty && (g == null || g < 0 || g > 100)) {
                        _snack('Enter a grade 0–100, or leave blank.', color: Colors.orange);
                        return;
                      }

                      try {
                        await _toggleAssignmentComplete(a.id, completed: true, grade: g);
                        if (mounted) Navigator.pop(sheetContext);
                        _snack(g == null ? 'Completed.' : 'Completed • $g%', color: Colors.green);
                      } catch (e) {
                        _snack('Update failed: $e', color: Colors.red);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete assignment', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('This cannot be undone.', style: TextStyle(color: Colors.white60)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _deleteAssignment(a.id);
                _snack('Deleted.', color: Colors.redAccent);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.assignments;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final targetW = constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: targetW,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.bucket == AssignmentBucket.overdue ? Icons.warning_amber : Icons.event_available,
                              color: widget.bucket == AssignmentBucket.overdue ? Colors.orange : Colors.purpleAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(widget.subtitle, style: const TextStyle(color: Colors.white70))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text('${list.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: list.isEmpty
                            ? Center(child: Text('Nothing here 🎉', style: TextStyle(color: Colors.grey[500])))
                            : ListView.builder(
                                itemCount: list.length,
                                itemBuilder: (context, i) {
                                  final a = list[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _showAssignmentActionsSheet(a),
                                        child: Ink(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1F2937),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                widget.bucket == AssignmentBucket.overdue
                                                    ? Icons.warning_amber
                                                    : Icons.calendar_today,
                                                color: widget.bucket == AssignmentBucket.overdue
                                                    ? Colors.orange
                                                    : Colors.white70,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      a.name,
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${a.subjectName} • ${a.studentName}',
                                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(a.dueDate, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                              const SizedBox(width: 6),
                                              const Icon(Icons.chevron_right, color: Colors.white30),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
