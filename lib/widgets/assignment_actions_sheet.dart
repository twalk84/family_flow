// FILE: lib/widgets/assignment_actions_sheet.dart
//
// Shared polished Assignment Actions bottom sheet.
// Use anywhere: dashboard, subject detail, student profile, etc.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';

class AssignmentActionsSheet {
  static Future<void> show(BuildContext context, Assignment a) async {
    void snack(String msg, {Color? color}) {
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

    Future<void> toggleComplete(String assignmentId, {required bool completed, int? grade}) async {
      await FirestorePaths.assignmentsCol().doc(assignmentId).set(
        {
          'completed': completed,
          'grade': completed ? grade : null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    Future<void> deleteAssignment(String assignmentId) async {
      await FirestorePaths.assignmentsCol().doc(assignmentId).delete();
    }

    Future<T?> showSmoothSheet<T>({
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

    Future<void> showDeleteConfirm(Assignment a) async {
      await showSmoothSheet<void>(
        title: 'Delete?',
        builder: (sheetContext) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete "${a.name}"?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${a.subjectName} • ${a.studentName}\nDue: ${a.dueDate.isEmpty ? '—' : a.dueDate}',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        try {
                          await deleteAssignment(a.id);
                          if (context.mounted) Navigator.pop(sheetContext);
                          snack('Deleted.', color: Colors.redAccent);
                        } catch (e) {
                          snack('Delete failed: $e', color: Colors.red);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }

    final gradeCtrl = TextEditingController(text: a.grade?.toString() ?? '');

    await showSmoothSheet<void>(
      title: 'Assignment',
      builder: (sheetContext) {
        final done = a.isCompleted;

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
                Text(a.dueDate.isEmpty ? 'No due date' : a.dueDate, style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: done ? Colors.green.withOpacity(0.18) : Colors.white10,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: done ? Colors.green.withOpacity(0.35) : Colors.white12,
                    ),
                  ),
                  child: Text(
                    done ? 'Completed' : 'Not completed',
                    style: TextStyle(
                      color: done ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),

            if (!done) ...[
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
                          await toggleComplete(a.id, completed: true, grade: null);
                          if (context.mounted) Navigator.pop(sheetContext);
                          snack('Marked complete.', color: Colors.green);
                        } catch (e) {
                          snack('Update failed: $e', color: Colors.red);
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
                          snack('Enter a grade 0–100, or leave blank.', color: Colors.orange);
                          return;
                        }

                        try {
                          await toggleComplete(a.id, completed: true, grade: g);
                          if (context.mounted) Navigator.pop(sheetContext);
                          snack(g == null ? 'Completed.' : 'Completed • $g%', color: Colors.green);
                        } catch (e) {
                          snack('Update failed: $e', color: Colors.red);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (a.grade != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.grade, color: Colors.greenAccent),
                      const SizedBox(width: 10),
                      Text('Grade: ${a.grade}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Mark Incomplete'),
                onPressed: () async {
                  try {
                    await toggleComplete(a.id, completed: false);
                    if (context.mounted) Navigator.pop(sheetContext);
                    snack('Marked incomplete.', color: Colors.orange);
                  } catch (e) {
                    snack('Update failed: $e', color: Colors.red);
                  }
                },
              ),
            ],

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
                await showDeleteConfirm(a);
              },
            ),
          ],
        );
      },
    );
  }
}
