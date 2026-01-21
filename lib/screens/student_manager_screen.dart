// FILE: lib/screens/student_manager_screen.dart
//
// Parent-only screen for managing students:
// - View all students with stats
// - Edit student details (name, age, grade, PIN, color, notes)
// - Adjust wallet points
// - Reset streaks
// - Delete students
//
// Access: Parent PIN required (enforced by caller)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/firestore/firestore_paths.dart';
import '../core/models/models.dart';
import '../widgets/point_adjustment_dialog.dart';

class StudentManagerScreen extends StatefulWidget {
  const StudentManagerScreen({super.key});

  @override
  State<StudentManagerScreen> createState() => _StudentManagerScreenState();
}

class _StudentManagerScreenState extends State<StudentManagerScreen> {
  static const List<Color> _colorPalette = [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.orange,
    Colors.teal,
    Colors.red,
    Colors.amber,
    Colors.indigo,
    Colors.cyan,
  ];

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

  Color _colorForStudent(Student student, int index) {
    if (student.colorValue != 0) return Color(student.colorValue);
    return _colorPalette[index % _colorPalette.length];
  }

  // ============================================================
  // Smooth Bottom Sheet
  // ============================================================

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
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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
                      Expanded(
                        child: SingleChildScrollView(
                          child: builder(sheetContext),
                        ),
                      ),
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

  // ============================================================
  // Add Student
  // ============================================================

  Future<void> _showAddStudentSheet() async {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    int selectedColorValue = _colorPalette.first.value;

    await _showSmoothSheet<void>(
      title: 'Add Student',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student Info', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Age',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: gradeCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Grade Level',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Student PIN (optional)',
                    helperText: 'For student login to view rewards.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Goals, accommodations, etc.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _colorPalette.map((c) {
                    final selected = c.value == selectedColorValue;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setSheetState(() => selectedColorValue = c.value),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white24,
                            width: selected ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
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
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add'),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack('Name is required.', color: Colors.orange);
                            return;
                          }

                          final age = int.tryParse(ageCtrl.text.trim()) ?? 0;
                          final grade = gradeCtrl.text.trim();
                          final pin = pinCtrl.text.trim();
                          final notes = notesCtrl.text.trim();

                          final payload = <String, dynamic>{
                            'name': name,
                            'nameLower': name.toLowerCase(),
                            'age': age,
                            'gradeLevel': grade,
                            'color': selectedColorValue,
                            'walletBalance': 0,
                            'currentStreak': 0,
                            'longestStreak': 0,
                            'lastCompletionDate': '',
                            'notes': notes,
                            'updatedAt': FieldValue.serverTimestamp(),
                            'createdAt': FieldValue.serverTimestamp(),
                          };

                          if (pin.isNotEmpty) payload['pin'] = pin;

                          await FirestorePaths.studentsCol().add(payload);

                          if (mounted) Navigator.pop(sheetContext);
                          _snack('Student added.', color: Colors.green);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // Edit Student
  // ============================================================

  Future<void> _showEditStudentSheet(Student student) async {
    final nameCtrl = TextEditingController(text: student.name);
    final ageCtrl = TextEditingController(text: student.age.toString());
    final gradeCtrl = TextEditingController(text: student.gradeLevel);
    final pinCtrl = TextEditingController(text: student.pin);
    final notesCtrl = TextEditingController(text: student.notes);

    int selectedColorValue = student.colorValue != 0
        ? student.colorValue
        : _colorPalette.first.value;

    await _showSmoothSheet<void>(
      title: 'Edit Student',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student Info', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Age',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: gradeCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Grade Level',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Student PIN (optional)',
                    helperText: 'For student login to view rewards.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Goals, accommodations, etc.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _colorPalette.map((c) {
                    final selected = c.value == selectedColorValue;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setSheetState(() => selectedColorValue = c.value),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white24,
                            width: selected ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
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
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack('Name is required.', color: Colors.orange);
                            return;
                          }

                          final age = int.tryParse(ageCtrl.text.trim()) ?? 0;
                          final grade = gradeCtrl.text.trim();
                          final pin = pinCtrl.text.trim();
                          final notes = notesCtrl.text.trim();

                          await FirestorePaths.studentsCol().doc(student.id).update({
                            'name': name,
                            'nameLower': name.toLowerCase(),
                            'age': age,
                            'gradeLevel': grade,
                            'color': selectedColorValue,
                            'pin': pin,
                            'notes': notes,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                          if (mounted) Navigator.pop(sheetContext);
                          _snack('Student updated.', color: Colors.green);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // Adjust Points (UPDATED to match your Dialog)
  // ============================================================

  Future<void> _showAdjustPointsDialog(Student student) async {
    // Calls your existing PointAdjustmentDialog.show()
    // It handles the logic (API calls) and validation internally.
    final changed = await PointAdjustmentDialog.show(context, student);

    if (changed && mounted) {
      _snack('Points adjusted successfully.', color: Colors.green);
    }
  }

  // ============================================================
  // Reset Streak
  // ============================================================

  Future<void> _confirmResetStreak(Student student) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Reset ${student.name}\'s streak?'),
        content: Text(
          'Current streak: ${student.currentStreak} days\n'
          'Longest streak: ${student.longestStreak} days\n\n'
          'This will reset their current streak to 0. Longest streak will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await FirestorePaths.studentsCol().doc(student.id).update({
          'currentStreak': 0,
          'lastCompletionDate': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _snack('Streak reset for ${student.name}.', color: Colors.orange);
      } catch (e) {
        _snack('Reset failed: $e', color: Colors.red);
      }
    }
  }

  // ============================================================
  // Delete Student
  // ============================================================

  Future<void> _confirmDeleteStudent(Student student) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Delete ${student.name}?'),
        content: const Text(
          'This will permanently delete this student and ALL their assignments, '
          'wallet transactions, progress data, and badges.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        // Delete assignments
        final assignmentsSnap = await FirestorePaths.assignmentsCol()
            .where('studentId', isEqualTo: student.id)
            .get();
        
        for (final doc in assignmentsSnap.docs) {
          await doc.reference.delete();
        }

        // Delete wallet transactions
        final txnSnap = await FirestorePaths.walletTransactionsCol(student.id).get();
        for (final doc in txnSnap.docs) {
          await doc.reference.delete();
        }

        // Delete badges
        final badgesSnap = await FirestorePaths.badgesEarnedCol(student.id).get();
        for (final doc in badgesSnap.docs) {
          await doc.reference.delete();
        }

        // Delete subject progress
        final progressSnap = await FirestorePaths.subjectProgressCol(student.id).get();
        for (final doc in progressSnap.docs) {
          await doc.reference.delete();
        }

        // Delete daily activity
        final activitySnap = await FirestorePaths.dailyActivityCol(student.id).get();
        for (final doc in activitySnap.docs) {
          await doc.reference.delete();
        }

        // Delete reward claims
        final claimsSnap = await FirestorePaths.rewardClaimsCol(student.id).get();
        for (final doc in claimsSnap.docs) {
          await doc.reference.delete();
        }

        // Finally, delete the student
        await FirestorePaths.studentsCol().doc(student.id).delete();

        _snack('${student.name} deleted.', color: Colors.red);
      } catch (e) {
        _snack('Delete failed: $e', color: Colors.red);
      }
    }
  }

  // ============================================================
  // Student Actions Sheet
  // ============================================================

  Future<void> _showStudentActionsSheet(Student student, int index) async {
    final color = _colorForStudent(student, index);

    await _showSmoothSheet<void>(
      title: 'Manage Student',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Center(
                    child: Text(
                      student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Age ${student.age} • Grade ${student.gradeLevel}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _statChip('💰 ${student.walletBalance}', 'Points'),
                const SizedBox(width: 10),
                _statChip('🔥 ${student.currentStreak}', 'Streak'),
                const SizedBox(width: 10),
                _statChip('🏆 ${student.longestStreak}', 'Best'),
              ],
            ),

            if (student.pin.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pin, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('PIN: ${student.pin}', style: const TextStyle(color: Colors.blue)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),

            // Actions
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Edit Student'),
              subtitle: const Text('Name, age, grade, PIN, color, notes'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditStudentSheet(student);
              },
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet, color: Colors.purple),
              title: const Text('Adjust Points'),
              subtitle: const Text('Add or remove wallet points'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAdjustPointsDialog(student);
              },
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restart_alt, color: Colors.orange),
              title: const Text('Reset Streak'),
              subtitle: Text('Current: ${student.currentStreak} days'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmResetStreak(student);
              },
            ),

            const Divider(color: Colors.white12),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete Student', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Permanently remove student and all data'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteStudent(student);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _statChip(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Manager'),
        actions: [
          IconButton(
            tooltip: 'Add Student',
            icon: const Icon(Icons.person_add),
            onPressed: _showAddStudentSheet,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestorePaths.studentsCol().orderBy('name').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    'No students yet',
                    style: TextStyle(fontSize: 18, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add Student'),
                    onPressed: _showAddStudentSheet,
                  ),
                ],
              ),
            );
          }

          final students = snap.data!.docs.map(Student.fromDoc).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final color = _colorForStudent(student, index);

              return Card(
                color: const Color(0xFF1F2937),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: color.withOpacity(0.3)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showStudentActionsSheet(student, index),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(
                            child: Text(
                              student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      student.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (student.currentStreak > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('🔥', style: TextStyle(fontSize: 12)),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${student.currentStreak}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Age ${student.age} • Grade ${student.gradeLevel}',
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet, size: 14, color: Colors.purple),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${student.walletBalance} pts',
                                    style: const TextStyle(color: Colors.purple, fontSize: 12),
                                  ),
                                  if (student.pin.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    const Icon(Icons.pin, size: 14, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'PIN set',
                                      style: TextStyle(color: Colors.blue.shade300, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStudentSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
      ),
    );
  }
}