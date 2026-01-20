// FILE: lib/screens/student_profile_screen.dart
//
// Student profile screen with:
// - Mood tracking
// - Edit student (name/age/grade/color/PIN/notes)
// - Delete student (and their assignments)
// - Wallet preview + link to Rewards Page

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../widgets/mood_picker.dart';
import '../services/reward_service.dart';
import 'rewards_page.dart';

class StudentProfileScreen extends StatefulWidget {
  final Student student;
  final Color color; // fallback color (legacy)
  final List<Assignment> assignments;

  const StudentProfileScreen({
    super.key,
    required this.student,
    required this.color,
    required this.assignments,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
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

  DocumentReference<Map<String, dynamic>> get _studentRef =>
      FirestorePaths.studentsCol().doc(widget.student.id);

  Color _effectiveColor(Student s) {
    if (s.colorValue != 0) return Color(s.colorValue);
    return widget.color;
  }

  int get totalAssignments => widget.assignments.length;
  int get completedAssignments => widget.assignments.where((a) => a.isCompleted).length;
  int get incompleteAssignments => totalAssignments - completedAssignments;

  double get averageGrade {
    final graded = widget.assignments.where((a) => a.grade != null).toList();
    if (graded.isEmpty) return 0.0;
    final sum = graded.fold<num>(0.0, (prev, a) => prev + (a.grade ?? 0));
    return sum / graded.length;
  }

  Map<String, List<Assignment>> get assignmentsBySubject {
    final result = <String, List<Assignment>>{};
    for (final a in widget.assignments) {
      final key = a.subjectName.isEmpty ? 'Unassigned' : a.subjectName;
      result.putIfAbsent(key, () => []);
      result[key]!.add(a);
    }
    return result;
  }

  Future<void> _setMood(String? mood) async {
    await _studentRef.set(
      {
        'mood': mood,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _showEditStudentSheet(Student current) async {
    final nameCtrl = TextEditingController(text: current.name);
    final ageCtrl = TextEditingController(text: current.age.toString());
    final gradeCtrl = TextEditingController(text: current.gradeLevel);
    final pinCtrl = TextEditingController(text: current.pin);
    final notesCtrl = TextEditingController(text: current.notes);

    int selectedColorValue = current.colorValue != 0
        ? current.colorValue
        : (_effectiveColor(current).value);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Edit Student',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Age'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: gradeCtrl,
                        decoration: const InputDecoration(labelText: 'Grade Level'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Student PIN (optional)',
                    helperText: 'Student login (view/claim rewards only).',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Goals, accommodations, preferences, etc.',
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Color',
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
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
                        onPressed: () => Navigator.pop(context),
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
                          if (name.isEmpty) return;

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
                            'pin': pin,
                            'notes': notes,
                            'updatedAt': FieldValue.serverTimestamp(),
                          };

                          await _studentRef.set(payload, SetOptions(merge: true));

                          if (mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteStudent(Student current) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete student?'),
        content: Text(
          'This will delete "${current.name}" and all assignments for this student. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteStudentAndAssignments(current.id);
      if (mounted) Navigator.pop(context); // return to dashboard
    }
  }

  Future<void> _deleteStudentAndAssignments(String studentId) async {
    try {
      // Delete assignments for this student
      final q = await FirestorePaths.assignmentsCol()
          .where('studentId', isEqualTo: studentId)
          .get();

      await _batchDeleteDocs(q.docs.map((d) => d.reference).toList());

      // Delete student doc
      await _studentRef.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _batchDeleteDocs(List<DocumentReference<Map<String, dynamic>>> refs) async {
    const limit = 450;
    for (var i = 0; i < refs.length; i += limit) {
      final chunk = refs.sublist(i, (i + limit) > refs.length ? refs.length : (i + limit));
      final batch = FirebaseFirestore.instance.batch();
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 420;

    final labelDone = narrow ? 'Done' : 'Completed';
    final labelPending = narrow ? 'Todo' : 'Remaining';
    final labelAvg = narrow ? 'Avg' : 'Avg Grade';

    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _studentRef.snapshots(),
      builder: (context, snap) {
        final doc = snap.data;
        final student = (doc != null && doc.exists)
            ? Student.fromDoc(doc)
            : widget.student;

        final c = _effectiveColor(student);

        final data = doc?.data();
        final mood = data?['mood'] as String?;

        return Scaffold(
          appBar: AppBar(
            title: Text(student.name),
            actions: [
              IconButton(
                tooltip: 'Edit student',
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditStudentSheet(student),
              ),
              IconButton(
                tooltip: 'Delete student',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDeleteStudent(student),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Hero(
                      tag: 'avatar_${student.id}',
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(31),
                        ),
                        child: Center(
                          child: Text(
                            student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                          ),
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
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Age ${student.age} • Grade ${student.gradeLevel}',
                            style: const TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (student.pin.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('PIN: ${student.pin}', style: const TextStyle(color: Colors.white60)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ========================================
                // NEW: Wallet Preview Card
                // ========================================
                _WalletPreviewCard(student: student),

                const SizedBox(height: 16),

                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        value: '$totalAssignments',
                        label: 'Total',
                        color: c,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: '$completedAssignments',
                        label: labelDone,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: '$incompleteAssignments',
                        label: labelPending,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: averageGrade == 0.0 ? '—' : averageGrade.toStringAsFixed(1),
                        label: labelAvg,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Mood
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.mood, size: 18, color: Colors.white70),
                          SizedBox(width: 8),
                          Text('Mood', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (uid == null)
                        const Text(
                          'You must be signed in to set mood.',
                          style: TextStyle(color: Colors.redAccent),
                        )
                      else
                        MoodPicker(
                          value: mood,
                          onChanged: (m) => _setMood(m),
                        ),
                    ],
                  ),
                ),

                if (student.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(student.notes, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Assignments by subject
                Text(
                  'Assignments',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                ...assignmentsBySubject.entries.map((entry) {
                  final subject = entry.key;
                  final items = entry.value;

                  final done = items.where((a) => a.isCompleted).length;
                  final total = items.length;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                subject,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '$done/$total',
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...items.take(10).map((a) {
                          final completed = a.isCompleted;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  completed ? Icons.check_circle : Icons.circle_outlined,
                                  size: 18,
                                  color: completed ? Colors.green : Colors.white24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    a.name,
                                    style: TextStyle(
                                      color: completed ? Colors.white70 : Colors.white,
                                      decoration: completed ? TextDecoration.lineThrough : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (a.grade != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      '${a.grade}%',
                                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        if (items.length > 10)
                          Text(
                            '+ ${items.length - 10} more…',
                            style: const TextStyle(color: Colors.white60),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ========================================
// NEW: Wallet Preview Card
// ========================================

class _WalletPreviewCard extends StatelessWidget {
  final Student student;

  const _WalletPreviewCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: RewardService.instance.streamWalletBalance(student.id),
      builder: (context, snap) {
        final balance = snap.data ?? student.walletBalance;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RewardsPage(student: student),
              ),
            ),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 32, color: Colors.white70),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wallet Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$balance points',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'View Rewards →',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
