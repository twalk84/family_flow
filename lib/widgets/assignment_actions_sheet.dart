// FILE: lib/widgets/assignment_actions_sheet.dart
//
// Shared polished Assignment Actions bottom sheet.
// UPDATED: Now uses AssignmentMutations.setCompleted() for proper
// points calculation, streak tracking, and completion date handling.


import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../services/assignment_mutations.dart';

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

    String todayYmd() {
      final d = DateTime.now();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    Future<CompletionResult?> completeAssignment({
      required int? grade,
      String? completionDate,
    }) async {
      try {
        return await AssignmentMutations.setCompleted(
          a,
          completed: true,
          gradePercent: grade,
          completionDate: completionDate,
        );
      } catch (e) {
        snack('Completion failed: $e', color: Colors.red);
        return null;
      }
    }

    Future<void> uncompleteAssignment() async {
      try {
        await AssignmentMutations.setCompleted(a, completed: false);
      } catch (e) {
        snack('Update failed: $e', color: Colors.red);
      }
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
                '${a.subjectName} - ${a.studentName}\nDue: ${a.dueDate.isEmpty ? '—' : a.dueDate}',
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

    void showCompletionFeedback(CompletionResult result, int basePoints, {int? grade}) {
      final pts = result.pointsAwarded;
      final streak = result.currentStreak;

      String msg;
      Color color;

      if (pts > 0) {
        msg = 'Completed! +$pts points';
        if (streak > 1) {
          msg += ' (🔥 $streak day streak)';
        }
        color = Colors.green;
      } else if (grade != null && grade < 90) {
        msg = 'Completed with $grade% (below 90% - no points)';
        color = Colors.orange;
      } else {
        msg = 'Completed (no points)';
        color = Colors.blue;
      }

      snack(msg, color: color);
    }

    final gradeCtrl = TextEditingController(text: a.grade?.toString() ?? '');
    final completionDateCtrl = TextEditingController(text: todayYmd());

    await showSmoothSheet<void>(
      title: 'Assignment',
      builder: (sheetContext) {
        final done = a.isCompleted;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${a.subjectName} - ${a.studentName}', style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.event, size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      a.dueDate.isEmpty ? 'No due date' : 'Due: ${a.dueDate}',
                      style: const TextStyle(color: Colors.white70),
                    ),
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

                // Show points info
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.stars, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      '${a.pointsBase} base points - ${a.gradable ? 'Graded (90% min)' : 'Pass/Fail'}',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white12),

                if (!done) ...[
                  const SizedBox(height: 10),
                  const Text('Complete', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  if (a.gradable) ...[
                    TextField(
                      controller: gradeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grade % (required for points)',
                        hintText: 'e.g. 95',
                        helperText: '90% or higher earns points',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: completionDateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Completion Date',
                      helperText: 'When was this completed?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      if (!a.gradable)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Complete'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () async {
                              final compDate = completionDateCtrl.text.trim();
                              final result = await completeAssignment(
                                grade: null,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && context.mounted) {
                                Navigator.pop(sheetContext);
                                showCompletionFeedback(result, a.pointsBase);
                              }
                            },
                          ),
                        )
                      else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('No Grade'),
                            onPressed: () async {
                              final compDate = completionDateCtrl.text.trim();
                              final result = await completeAssignment(
                                grade: null,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && context.mounted) {
                                Navigator.pop(sheetContext);
                                snack('Completed (0 points - no grade)', color: Colors.orange);
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
                                snack('Enter a grade 0-100, or leave blank.', color: Colors.orange);
                                return;
                              }

                              final compDate = completionDateCtrl.text.trim();
                              final result = await completeAssignment(
                                grade: g,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && context.mounted) {
                                Navigator.pop(sheetContext);
                                showCompletionFeedback(result, a.pointsBase, grade: g);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.grade != null)
                          Row(
                            children: [
                              const Icon(Icons.grade, color: Colors.greenAccent),
                              const SizedBox(width: 10),
                              Text(
                                'Grade: ${a.grade}%',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (a.grade! >= 90) ...[
                                const Spacer(),
                                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                const Text('Points earned', style: TextStyle(color: Colors.green, fontSize: 12)),
                              ],
                            ],
                          ),
                        if (a.completionDate.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Colors.white54, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Completed: ${a.completionDate}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                        if (a.pointsEarned > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.stars, color: Colors.amber, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '+${a.pointsEarned} points earned',
                                style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.undo),
                    label: const Text('Mark Incomplete'),
                    onPressed: () async {
                      await uncompleteAssignment();
                      if (context.mounted) Navigator.pop(sheetContext);
                      snack('Marked incomplete.', color: Colors.orange);
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
      },
    );
  }
}