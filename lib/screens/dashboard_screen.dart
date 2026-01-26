// FILE: lib/screens/dashboard_screen.dart
//
// Dashboard (FamilyOS)
//
// UPDATED:
// - Add Student: initializes currentStreak, longestStreak, lastCompletionDate
// - Add Assignment: includes pointsBase and gradable fields
// - Assignment completion: uses AssignmentMutations.setCompleted() for proper points/streak tracking
// - Shows streak info on student cards
// - Assignments tab now browses: Student -> Subject -> Assignments (drill-down on narrow, 3-column on wide)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_config.dart';
import 'student_manager_screen.dart';
import 'curriculum_manager_screen.dart';
import '../firestore_paths.dart';
import '../models.dart';
import '../services/assignment_mutations.dart';
import '../widgets/app_scaffolds.dart';
import '../widgets/assistant_sheet.dart';
import 'daily_schedule_screen.dart';
import 'student_profile_screen.dart';
import 'reward_admin_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool openScheduleOnStart;

  const DashboardScreen({super.key, this.openScheduleOnStart = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController; // narrow layout only
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;

  String? teacherMood;
  bool _autoOpenedSchedule = false;

  // Assignments browser (Student -> Subject -> Assignments)
  String? _assignBrowserStudentId;
  String? _assignBrowserSubjectId;

  // Subjects search UI
  final TextEditingController _subjectSearchCtrl = TextEditingController();
  String _subjectQuery = '';

  final List<Color> _defaultStudentPalette = const [
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
    // Narrow layout uses 3 tabs: Students / Assignments / Subjects
    _tabController = TabController(length: 3, vsync: this);

    _settingsSub = FirestorePaths.settingsDoc().snapshots().listen((doc) {
      if (!mounted) return;
      final d = doc.data();
      setState(() {
        teacherMood = d == null ? null : (d['teacherMood'] as String?);
      });
    });

    _subjectSearchCtrl.addListener(() {
      final q = _subjectSearchCtrl.text.trim();
      if (q == _subjectQuery) return;
      if (!mounted) return;
      setState(() => _subjectQuery = q);
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _tabController.dispose();
    _subjectSearchCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // Helpers
  // ============================================================

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

  Future<void> _setTeacherMood(String? mood) async {
    await FirestorePaths.settingsDoc().set(
      {'teacherMood': mood, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  String _todayYmd() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Color _colorForStudent(Student student, int index) {
    final v = student.colorValue;
    if (v != 0) return Color(v);
    return _defaultStudentPalette[index % _defaultStudentPalette.length];
  }

  // ============================================================
  // Smooth Bottom Sheet (general-purpose)
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
  // Firestore mutations - NOW USING AssignmentMutations
  // ============================================================

  /// UPDATED: Now uses AssignmentMutations for proper points/streak tracking
  Future<CompletionResult?> _completeAssignment(
    Assignment a, {
    required int? grade,
    String? completionDate,
  }) async {
    try {
      final result = await AssignmentMutations.setCompleted(
        a,
        completed: true,
        gradePercent: grade,
        completionDate: completionDate,
      );
      return result;
    } catch (e) {
      _snack('Completion failed: $e', color: Colors.red);
      return null;
    }
  }

  /// UPDATED: Now uses AssignmentMutations for proper reversal
  Future<void> _uncompleteAssignment(Assignment a) async {
    try {
      await AssignmentMutations.setCompleted(
        a,
        completed: false,
      );
    } catch (e) {
      _snack('Update failed: $e', color: Colors.red);
    }
  }

  Future<void> _deleteAssignment(String assignmentId) async {
    await FirestorePaths.assignmentsCol().doc(assignmentId).delete();
  }

  // Streak reset - UPDATED to use new field names
  Future<void> _resetStudentStreak(Student s) async {
    await FirestorePaths.studentsCol().doc(s.id).set(
      {
        'currentStreak': 0,
        'longestStreak': s.longestStreak, // keep longest
        'lastCompletionDate': '',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _resetAllStudentStreaks(List<Student> students) async {
    const limit = 450;
    final refs =
        students.map((s) => FirestorePaths.studentsCol().doc(s.id)).toList();

    for (var i = 0; i < refs.length; i += limit) {
      final chunk = refs.sublist(
          i, (i + limit) > refs.length ? refs.length : (i + limit));
      final batch = FirebaseFirestore.instance.batch();
      for (final r in chunk) {
        batch.set(
          r,
          {
            'currentStreak': 0,
            'lastCompletionDate': '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> _renameSubject(Subject subject, String newName) async {
    await FirestorePaths.subjectsCol().doc(subject.id).set(
      {
        'name': newName,
        'nameLower': newName.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _confirmDeleteSubject({
    required Subject subject,
    required List<Student> students,
    required List<Assignment> allAssignments,
  }) async {
    final related = allAssignments.where((a) => a.subjectId == subject.id).toList();
    final completed = related.where((a) => a.isCompleted).toList();

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1F2937),
            title: const Text('Delete subject?'),
            content: Text(
              'This will delete:\n'
              '• Subject: "${subject.name}"\n'
              '• Assignments linked to it: ${related.length}\n\n'
              'If any of those assignments were completed, points/streaks will be reversed first.\n\n'
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF1F2937),
        content: SizedBox(
          height: 90,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Deleting subject...'),
            ],
          ),
        ),
      ),
    );

    try {
      // 1) Reverse points/streaks for completed assignments first
      for (final a in completed) {
        await AssignmentMutations.setCompleted(a, completed: false);
      }

      // 2) Delete the assignments linked to this subject
      final refs =
          related.map((a) => FirestorePaths.assignmentsCol().doc(a.id)).toList(growable: false);
      await _batchDeleteDocs(refs);

      // 3) Delete the subject document
      await FirestorePaths.subjectsCol().doc(subject.id).delete();

      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      _snack('Deleted "${subject.name}" (${related.length} assignments).',
          color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      _snack('Delete failed: $e', color: Colors.red);
    }
  }

  // ============================================================
  // Student demo cleanup + utilities
  // ============================================================

  Future<void> _showStudentsManageSheet({
    required List<Student> students,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage Students',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use this to remove demo data before entering real students.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.restart_alt, color: Colors.orangeAccent),
                title: const Text('Reset ALL streaks (set to 0)'),
                subtitle: const Text('Keeps students + assignments.'),
                onTap: () async {
                  Navigator.pop(context);
                  await _confirmResetAllStreaks(students);
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Delete ALL students (and their assignments)'),
                subtitle: const Text('This cannot be undone.'),
                onTap: () async {
                  Navigator.pop(context);
                  await _confirmDeleteAllStudents();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResetAllStreaks(List<Student> students) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Reset all streaks?'),
        content: const Text(
          'This will set streak = 0 for ALL students. Assignments are unchanged.',
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
        await _resetAllStudentStreaks(students);
        _snack('All streaks reset.', color: Colors.orange);
      } catch (e) {
        _snack('Reset failed: $e', color: Colors.red);
      }
    }
  }

  Future<void> _confirmDeleteAllStudents() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete all students?'),
        content: const Text(
          'This will delete ALL students and ALL assignments for those students. '
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
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteAllStudentsAndTheirAssignments();
    }
  }

  Future<void> _deleteAllStudentsAndTheirAssignments() async {
    try {
      final studentsSnap = await FirestorePaths.studentsCol().get();
      final studentIds = studentsSnap.docs.map((d) => d.id).toList();

      for (final sid in studentIds) {
        final q = await FirestorePaths.assignmentsCol()
            .where('studentId', isEqualTo: sid)
            .get();
        await _batchDeleteDocs(q.docs.map((d) => d.reference).toList());
      }

      await _batchDeleteDocs(studentsSnap.docs.map((d) => d.reference).toList());

      _snack('All students deleted.', color: Colors.green);
    } catch (e) {
      _snack('Delete failed: $e', color: Colors.red);
    }
  }

  Future<void> _batchDeleteDocs(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    const limit = 450;
    for (var i = 0; i < refs.length; i += limit) {
      final chunk = refs.sublist(
          i, (i + limit) > refs.length ? refs.length : (i + limit));
      final batch = FirebaseFirestore.instance.batch();
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  // ============================================================
  // Add flows (smooth sheets)
  // ============================================================

  /// UPDATED: Now initializes streak fields
  Future<void> _showAddStudentDialog() async {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    int selectedColorValue = _defaultStudentPalette.first.value;

    await _showSmoothSheet<void>(
      title: 'Add Student',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student Info',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                    helperText: 'Student login (view/claim rewards only).',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _defaultStudentPalette.map((c) {
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

                          // UPDATED: Include new streak fields
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

  Future<void> _showAddSubjectDialog() async {
    final nameCtrl = TextEditingController();

    await _showSmoothSheet<void>(
      title: 'Add Subject',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subject Name',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'e.g. Math, Latin, Science',
                border: OutlineInputBorder(),
              ),
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
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Add'),
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        _snack('Subject name is required.', color: Colors.orange);
                        return;
                      }

                      await FirestorePaths.subjectsCol().add({
                        'name': name,
                        'nameLower': name.toLowerCase(),
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) Navigator.pop(sheetContext);
                      _snack('Subject added.', color: Colors.green);
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

  /// UPDATED: Now includes pointsBase and gradable fields
  Future<void> _showAddAssignmentDialog({
    required List<Student> students,
    required List<Subject> subjects,
  }) async {
    if (students.isEmpty) {
      _snack('Add a student first.', color: Colors.orange);
      return;
    }
    if (subjects.isEmpty) {
      _snack('Add a subject first.', color: Colors.orange);
      return;
    }

    String studentId = students.first.id;
    String subjectId = subjects.first.id;

    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: _todayYmd());
    final pointsCtrl = TextEditingController(text: '10');
    bool gradable = true;

    await _showSmoothSheet<void>(
      title: 'Add Assignment',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: studentId,
                  decoration: const InputDecoration(
                    labelText: 'Student',
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF374151),
                  items: students
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => studentId = v ?? studentId),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: subjectId,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF374151),
                  items: subjects
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => subjectId = v ?? subjectId),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Assignment Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Due Date (YYYY-MM-DD)',
                    helperText: 'Date only, e.g. 2025-12-30',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Points & Grading',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: pointsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Points',
                          helperText: 'Base pts',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Requires Grade?',
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Yes'),
                                selected: gradable,
                                onSelected: (_) => setSheetState(() => gradable = true),
                                selectedColor: Colors.blue.withOpacity(0.3),
                              ),
                              ChoiceChip(
                                label: const Text('Pass/Fail'),
                                selected: !gradable,
                                onSelected: (_) => setSheetState(() => gradable = false),
                                selectedColor: Colors.blue.withOpacity(0.3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gradable
                              ? 'Requires 90%+ to earn points'
                              : 'Earns full points on completion',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
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
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add'),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final due = dateCtrl.text.trim();
                          final points = int.tryParse(pointsCtrl.text.trim()) ?? 10;

                          if (name.isEmpty || due.isEmpty) {
                            _snack('Name and due date are required.', color: Colors.orange);
                            return;
                          }

                          await AssignmentMutations.createAssignment(
                            studentId: studentId,
                            subjectId: subjectId,
                            name: name,
                            dueDate: due,
                            pointsBase: points,
                            gradable: gradable,
                          );

                          if (mounted) Navigator.pop(sheetContext);
                          _snack('Assignment added.', color: Colors.green);
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
  // Assignment actions (smooth) - UPDATED with proper completion flow
  // ============================================================

  Future<void> _showAssignmentActionsSheet(Assignment a) async {
    final gradeCtrl = TextEditingController(text: a.grade?.toString() ?? '');
    final completionDateCtrl = TextEditingController(text: _todayYmd());

    await _showSmoothSheet<void>(
      title: 'Assignment',
      builder: (sheetContext) {
        final done = a.isCompleted;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${a.subjectName} • ${a.studentName}',
                  style: const TextStyle(color: Colors.white60),
                ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.stars, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      '${a.pointsBase} base points • ${a.gradable ? 'Graded (90% min)' : 'Pass/Fail'}',
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
                              final result = await _completeAssignment(
                                a,
                                grade: null,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && mounted) {
                                Navigator.pop(sheetContext);
                                _showCompletionFeedback(result, a.pointsBase);
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
                              final result = await _completeAssignment(
                                a,
                                grade: null,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && mounted) {
                                Navigator.pop(sheetContext);
                                _snack('Completed (0 points - no grade)', color: Colors.orange);
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

                              final compDate = completionDateCtrl.text.trim();
                              final result = await _completeAssignment(
                                a,
                                grade: g,
                                completionDate: compDate.isEmpty ? null : compDate,
                              );

                              if (result != null && mounted) {
                                Navigator.pop(sheetContext);
                                _showCompletionFeedback(result, a.pointsBase, grade: g);
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
                                const Text('Points earned',
                                    style: TextStyle(color: Colors.green, fontSize: 12)),
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
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
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
                      await _uncompleteAssignment(a);
                      if (mounted) Navigator.pop(sheetContext);
                      _snack('Marked incomplete.', color: Colors.orange);
                    },
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 10),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: const Text('Delete assignment',
                      style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('This cannot be undone.',
                      style: TextStyle(color: Colors.white60)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _showDeleteAssignmentConfirmSheet(a);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCompletionFeedback(CompletionResult result, int basePoints, {int? grade}) {
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

    _snack(msg, color: color);
  }

  Future<void> _showDeleteAssignmentConfirmSheet(Assignment a) async {
    await _showSmoothSheet<void>(
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
                        await _deleteAssignment(a.id);
                        if (mounted) Navigator.pop(sheetContext);
                        _snack('Deleted.', color: Colors.redAccent);
                      } catch (e) {
                        _snack('Delete failed: $e', color: Colors.red);
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

  // ============================================================
  // Student quick actions (streak reset)
  // ============================================================

  Future<void> _showStudentActionsSheet(Student s) async {
    await _showSmoothSheet<void>(
      title: 'Student',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Grade ${s.gradeLevel} • Age ${s.age}',
                style: const TextStyle(color: Colors.white60)),
            if (s.currentStreak > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(
                      '${s.currentStreak} day streak',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (s.streakBonusPercent > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+${(s.streakBonusPercent * 100).round()}% bonus',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restart_alt, color: Colors.orangeAccent),
              title: const Text('Reset streak (set to 0)'),
              subtitle: const Text('Keeps assignments; just resets the streak counter.'),
              onTap: () async {
                try {
                  await _resetStudentStreak(s);
                  if (mounted) Navigator.pop(sheetContext);
                  _snack('Streak reset for ${s.name}.', color: Colors.orange);
                } catch (e) {
                  _snack('Reset failed: $e', color: Colors.red);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // Subjects: detail + edit
  // ============================================================

  Future<void> _showEditSubjectSheet(Subject subject) async {
    final ctrl = TextEditingController(text: subject.name);

    await _showSmoothSheet<void>(
      title: 'Edit Subject',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rename', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Subject name',
                border: OutlineInputBorder(),
              ),
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
                      final name = ctrl.text.trim();
                      if (name.isEmpty) {
                        _snack('Name is required.', color: Colors.orange);
                        return;
                      }
                      try {
                        await _renameSubject(subject, name);
                        if (mounted) Navigator.pop(sheetContext);
                        _snack('Subject updated.', color: Colors.green);
                      } catch (e) {
                        _snack('Update failed: $e', color: Colors.red);
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

  Future<void> _showSubjectDetailSheet({
    required Subject subject,
    required List<Student> students,
    required List<Assignment> assignments,
  }) async {
    final subjectAssignments = assignments.where((a) => a.subjectId == subject.id).toList();

    final byStudent = <String, List<Assignment>>{};
    for (final a in subjectAssignments) {
      byStudent.putIfAbsent(a.studentId, () => <Assignment>[]).add(a);
    }

    final studentById = {for (final s in students) s.id: s};

    final rows = byStudent.entries.map((e) {
      final sid = e.key;
      final list = e.value;
      final completed = list.where((x) => x.isCompleted).length;
      return _SubjectStudentRow(
        studentId: sid,
        studentName: studentById[sid]?.name ?? (list.isNotEmpty ? list.first.studentName : ''),
        total: list.length,
        completed: completed,
      );
    }).toList();

    rows.sort((a, b) {
      final ai = a.incomplete;
      final bi = b.incomplete;
      if (ai != bi) return bi.compareTo(ai);
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });

    final sample = [...subjectAssignments];
    sample.sort((a, b) {
      final ac = a.isCompleted ? 1 : 0;
      final bc = b.isCompleted ? 1 : 0;
      if (ac != bc) return ac.compareTo(bc);
      if (a.dueDate.isEmpty && b.dueDate.isNotEmpty) return 1;
      if (a.dueDate.isNotEmpty && b.dueDate.isEmpty) return -1;
      return a.dueDate.compareTo(b.dueDate);
    });
    final upcomingSample = sample.take(10).toList();

    await _showSmoothSheet<void>(
      title: 'Subject',
      builder: (sheetContext) {
        final totalA = subjectAssignments.length;
        final totalDone = subjectAssignments.where((x) => x.isCompleted).length;
        final totalStudents = rows.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subject.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _showEditSubjectSheet(subject);
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _confirmDeleteSubject(
                      subject: subject,
                      students: students,
                      allAssignments: assignments,
                    );
                  },
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pillStat(label: 'Assignments', value: '$totalA'),
                _pillStat(label: 'Completed', value: '$totalDone'),
                _pillStat(label: 'Students', value: '$totalStudents'),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text('Students with assignments', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text('No assignments are linked to this subject yet.',
                  style: TextStyle(color: Colors.grey[500]))
            else
              Column(
                children: rows.map((r) {
                  final st = studentById[r.studentId];
                  final idx = st == null ? 0 : students.indexWhere((s) => s.id == st.id);
                  final color = st == null
                      ? Colors.grey
                      : _colorForStudent(st, idx < 0 ? 0 : idx);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r.studentName.isEmpty ? '(Unknown student)' : r.studentName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${r.completed}/${r.total}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            const Text('Sample assignments', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (upcomingSample.isEmpty)
              Text('No assignments yet.', style: TextStyle(color: Colors.grey[500]))
            else
              Column(
                children: upcomingSample.map((a) {
                  final done = a.isCompleted;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: done ? Colors.green.withOpacity(0.10) : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: done ? Colors.green.withOpacity(0.25) : Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Icon(done ? Icons.check_circle : Icons.circle_outlined,
                            color: done ? Colors.green : Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: done ? TextDecoration.lineThrough : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                a.studentName,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          a.dueDate.isEmpty ? '—' : a.dueDate,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _pillStat({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ============================================================
  // Navigation
  // ============================================================

  void _openStudentProfile(Student student, Color color, List<Assignment> allAssignments) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentProfileScreen(
          student: student,
          color: color,
          assignments: allAssignments.where((x) => x.studentId == student.id).toList(),
        ),
      ),
    );
  }

  void _openDailySchedule({
    required List<Student> students,
    required List<Assignment> assignments,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyScheduleScreen(
          students: students,
          assignments: assignments,
          onComplete: (id, grade) async {
            final a = assignments.firstWhere((x) => x.id == id);
            await _completeAssignment(a, grade: grade);
          },
        ),
      ),
    );
  }

  void _openAssistantSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AssistantSheet(),
    );
  }

  void _openRewardAdmin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RewardAdminScreen()),
    );
  }

  // ============================================================
  // UI pieces
  // ============================================================

  Widget _moodBar() {
    final moodText = teacherMood ?? 'Not set';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.coffee, color: Colors.white),
          const SizedBox(width: 10),
          const Text('Mood:', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              moodText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<String?>(
            tooltip: 'Change mood',
            onSelected: (m) => _setTeacherMood(m),
            itemBuilder: (_) => [
              ...AppConfig.availableMoods.map(
                (m) => PopupMenuItem<String?>(
                  value: m,
                  child: Text(m, style: const TextStyle(fontSize: 20)),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String?>(value: null, child: Text('Clear mood')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text('Change', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final bg = (color ?? Colors.white).withOpacity(0.10);
    final br = (color ?? Colors.white).withOpacity(0.22);

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color ?? Colors.white),
        label: Text(label, style: TextStyle(color: color ?? Colors.white)),
        style: TextButton.styleFrom(
          backgroundColor: bg,
          shape: const StadiumBorder(),
          side: BorderSide(color: br),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 900;

    Future<bool> _confirmBackNavigation() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Leave Dashboard?'),
          content: const Text(
            'You will be returned to the student selection screen and will need to enter your PIN again. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );

      return result ?? false;
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.studentsCol().snapshots(),
      builder: (context, studentsSnap) {
        if (!studentsSnap.hasData) return const LoadingScaffold();
        final students = studentsSnap.data!.docs.map(Student.fromDoc).toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestorePaths.subjectsCol().snapshots(),
          builder: (context, subjectsSnap) {
            if (!subjectsSnap.hasData) return const LoadingScaffold();
            final subjects = subjectsSnap.data!.docs.map(Subject.fromDoc).toList();

            final studentsById = {for (final s in students) s.id: s};
            final subjectsById = {for (final s in subjects) s.id: s};

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestorePaths.assignmentsCol().orderBy('dueDate').snapshots(),
              builder: (context, assignmentsSnap) {
                if (!assignmentsSnap.hasData) return const LoadingScaffold();

                final assignments = assignmentsSnap.data!.docs
                    .map((d) => Assignment.fromDoc(
                          d,
                          studentsById: studentsById,
                          subjectsById: subjectsById,
                        ))
                    .toList();

                if (widget.openScheduleOnStart && !_autoOpenedSchedule) {
                  _autoOpenedSchedule = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _openDailySchedule(students: students, assignments: assignments);
                  });
                }

                List<Widget> buildActions() {
                  if (isNarrow) {
                    return [
                      IconButton(
                        tooltip: 'Add Student',
                        icon: const Icon(Icons.person_add_alt_1),
                        onPressed: _showAddStudentDialog,
                      ),
                      IconButton(
                        tooltip: "Today's Schedule",
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _openDailySchedule(students: students, assignments: assignments),
                      ),
                      IconButton(
                        tooltip: 'Add Assignment',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _showAddAssignmentDialog(students: students, subjects: subjects),
                      ),
                      IconButton(
                        tooltip: 'Manage Rewards',
                        icon: const Icon(Icons.card_giftcard),
                        onPressed: _openRewardAdmin,
                      ),
                      IconButton(
                        tooltip: 'Assistant',
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: _openAssistantSheet,
                      ),
                      IconButton(
                        tooltip: 'Manage Students',
                        icon: const Icon(Icons.manage_accounts),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StudentManagerScreen()),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Curriculum',
                        icon: const Icon(Icons.library_books),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CurriculumManagerScreen()),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout),
                        onPressed: _signOut,
                      ),
                    ];
                  }

                  return [
                    _pillButton(
                      icon: Icons.person_add_alt_1,
                      label: 'Add Student',
                      onPressed: _showAddStudentDialog,
                    ),
                    _pillButton(
                      icon: Icons.bookmark_add,
                      label: 'Add Subject',
                      onPressed: _showAddSubjectDialog,
                    ),
                    _pillButton(
                      icon: Icons.calendar_today,
                      label: 'Schedule',
                      onPressed: () => _openDailySchedule(students: students, assignments: assignments),
                    ),
                    _pillButton(
                      icon: Icons.add_circle_outline,
                      label: 'Add Assignment',
                      onPressed: () => _showAddAssignmentDialog(students: students, subjects: subjects),
                    ),
                    _pillButton(
                      icon: Icons.card_giftcard,
                      label: 'Rewards',
                      onPressed: _openRewardAdmin,
                    ),
                    _pillButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'Assistant',
                      onPressed: _openAssistantSheet,
                    ),
                    _pillButton(
                      icon: Icons.manage_accounts,
                      label: 'Students',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StudentManagerScreen()),
                      ),
                    ),
                    _pillButton(
                      icon: Icons.library_books,
                      label: 'Curriculum',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CurriculumManagerScreen()),
                      ),
                    ),
                    _pillButton(
                      icon: Icons.logout,
                      label: 'Sign out',
                      onPressed: _signOut,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                  ];
                }

                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop) return;
                    final shouldPop = await _confirmBackNavigation();
                    if (shouldPop && mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: Scaffold(
                    appBar: AppBar(
                      title: const Text('FamilyOS'),
                      actions: buildActions(),
                    ),
                    body: SafeArea(
                      child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = constraints.maxWidth;
                        final targetW = maxW > 1100 ? 1100.0 : maxW;

                        return Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: targetW,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isNarrow
                                        ? 'Tap tabs • Drill into Assignments (Student → Subject → List)'
                                        : 'Students always visible • Assignments/Subjects on right',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                  ),
                                  const SizedBox(height: 12),
                                  _moodBar(),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: isNarrow
                                        ? Column(
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1F2937),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: TabBar(
                                                  controller: _tabController,
                                                  indicatorSize: TabBarIndicatorSize.tab,
                                                  tabs: const [
                                                    Tab(icon: Icon(Icons.people), text: 'Students'),
                                                    Tab(icon: Icon(Icons.assignment), text: 'Assignments'),
                                                    Tab(icon: Icon(Icons.book), text: 'Subjects'),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Expanded(
                                                child: TabBarView(
                                                  controller: _tabController,
                                                  children: [
                                                    _studentsPanel(students, assignments),
                                                    _assignmentsPanel(
                                                      assignments,
                                                      students: students,
                                                      subjects: subjects,
                                                    ),
                                                    _subjectsPanel(
                                                      subjects: subjects,
                                                      students: students,
                                                      assignments: assignments,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _studentsPanel(students, assignments),
                                              ),
                                              const SizedBox(width: 24),
                                              Expanded(
                                                flex: 2,
                                                child: DefaultTabController(
                                                  length: 2,
                                                  child: Column(
                                                    children: [
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1F2937),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const TabBar(
                                                          indicatorSize: TabBarIndicatorSize.tab,
                                                          tabs: [
                                                            Tab(icon: Icon(Icons.assignment), text: 'Assignments'),
                                                            Tab(icon: Icon(Icons.book), text: 'Subjects'),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 12),
                                                      Expanded(
                                                        child: TabBarView(
                                                          children: [
                                                            _assignmentsPanel(
                                                              assignments,
                                                              students: students,
                                                              subjects: subjects,
                                                            ),
                                                            _subjectsPanel(
                                                              subjects: subjects,
                                                              students: students,
                                                              assignments: assignments,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
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
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ============================================================
  // Panels - UPDATED with streak display + assignments browser
  // ============================================================

  Widget _studentsPanel(List<Student> students, List<Assignment> assignments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Students (${students.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Manage students',
              onPressed: () => _showStudentsManageSheet(students: students),
              icon: const Icon(Icons.manage_accounts),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final color = _colorForStudent(student, index);

              final studentAssignments =
                  assignments.where((a) => a.studentId == student.id).toList();
              final total = studentAssignments.length;
              final completed = studentAssignments.where((a) => a.isCompleted).length;

              return GestureDetector(
                onTap: () => _openStudentProfile(student, color, assignments),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'avatar_${student.id}',
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(
                            child: Text(
                              student.name.isNotEmpty ? student.name[0] : '?',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    student.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (student.currentStreak > 0) ...[
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
                                  const SizedBox(width: 4),
                                ],
                                const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
                              ],
                            ),
                            Text(
                              'Age ${student.age} • Grade ${student.gradeLevel}',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: total > 0 ? completed / total : 0,
                              backgroundColor: Colors.grey[800],
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$completed/$total completed',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Student actions',
                        icon: const Icon(Icons.more_horiz, color: Colors.white70),
                        onPressed: () => _showStudentActionsSheet(student),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Assignments browser:
  /// - Narrow: drill down (Students -> Subjects -> Assignments)
  /// - Wide: 3 columns side-by-side
  Widget _assignmentsPanel(
    List<Assignment> assignments, {
    required List<Student> students,
    required List<Subject> subjects,
  }) {
    const unassignedKey = '__unassigned__';

    final subjectsById = {for (final s in subjects) s.id: s};
    final studentsById = {for (final s in students) s.id: s};

    // Group by student
    final byStudent = <String, List<Assignment>>{};
    for (final a in assignments) {
      final sid = a.studentId.trim();
      if (sid.isEmpty) continue;
      byStudent.putIfAbsent(sid, () => <Assignment>[]).add(a);
    }

    // Show ALL students, even if no assignments (so the browser always matches your roster)
    final studentOrder = [...students]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    int pendingCount(List<Assignment> list) => list.where((a) => !a.isCompleted).length;

    Color studentDot(Student s) =>
        s.colorValue != 0 ? Color(s.colorValue) : Colors.white24;

    void selectStudent(String sid) {
      setState(() {
        _assignBrowserStudentId = sid;
        _assignBrowserSubjectId = null;
      });
    }

    void selectSubject(String key) {
      setState(() {
        _assignBrowserSubjectId = key;
      });
    }

    void goBack() {
      setState(() {
        if (_assignBrowserSubjectId != null) {
          _assignBrowserSubjectId = null;
        } else {
          _assignBrowserStudentId = null;
        }
      });
    }

    void clearAll() {
      setState(() {
        _assignBrowserStudentId = null;
        _assignBrowserSubjectId = null;
      });
    }

    Widget studentsList() {
      if (studentOrder.isEmpty) {
        return Center(
          child: Text('No students yet.', style: TextStyle(color: Colors.grey[600])),
        );
      }

      return ListView.separated(
        itemCount: studentOrder.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, i) {
          final s = studentOrder[i];
          final list = byStudent[s.id] ?? const <Assignment>[];
          final pending = pendingCount(list);
          final total = list.length;

          final selected = _assignBrowserStudentId == s.id;

          return ListTile(
            onTap: () => selectStudent(s.id),
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: studentDot(s),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
            ),
            title: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.w600),
            ),
            subtitle: Text(
              total == 0 ? 'No assignments' : '$pending pending • $total total',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            selected: selected,
            selectedTileColor: Colors.purple.withOpacity(0.12),
          );
        },
      );
    }

    Widget subjectsListForStudent(String studentId) {
      final list = byStudent[studentId] ?? const <Assignment>[];

      if (list.isEmpty) {
        return Center(
          child: Text('No assignments for this student.', style: TextStyle(color: Colors.grey[600])),
        );
      }

      final bySubject = <String, List<Assignment>>{};
      for (final a in list) {
        final key = a.subjectId.trim().isEmpty ? unassignedKey : a.subjectId.trim();
        bySubject.putIfAbsent(key, () => <Assignment>[]).add(a);
      }

      // ordered keys: subjects in your subjects list (alphabetical), then Unassigned
      final subjectKeys = <String>[];

      final presentSubjectIds = bySubject.keys.where((k) => k != unassignedKey).toSet();
      final subjectObjs = subjects.where((s) => presentSubjectIds.contains(s.id)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      subjectKeys.addAll(subjectObjs.map((s) => s.id));
      if (bySubject.containsKey(unassignedKey)) subjectKeys.add(unassignedKey);

      String subjectLabel(String key) {
        if (key == unassignedKey) return 'Unassigned';
        return subjectsById[key]?.name ?? 'Unknown Subject';
      }

      return ListView.separated(
        itemCount: subjectKeys.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, i) {
          final key = subjectKeys[i];
          final items = bySubject[key] ?? const <Assignment>[];
          final pending = pendingCount(items);
          final total = items.length;

          final selected = _assignBrowserSubjectId == key;

          return ListTile(
            onTap: () => selectSubject(key),
            leading: const Icon(Icons.book, color: Colors.white54, size: 20),
            title: Text(
              subjectLabel(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.w600),
            ),
            subtitle: Text(
              '$pending pending • $total total',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            selected: selected,
            selectedTileColor: Colors.purple.withOpacity(0.12),
          );
        },
      );
    }

    Widget assignmentsList(String studentId, String subjectKey) {
      final list = byStudent[studentId] ?? const <Assignment>[];
      final filtered = list.where((a) {
        final key = a.subjectId.trim().isEmpty ? unassignedKey : a.subjectId.trim();
        return key == subjectKey;
      }).toList();

      filtered.sort((a, b) {
        final ac = a.isCompleted ? 1 : 0;
        final bc = b.isCompleted ? 1 : 0;
        if (ac != bc) return ac.compareTo(bc);

        final ad = a.dueDate.trim();
        final bd = b.dueDate.trim();
        if (ad.isEmpty && bd.isNotEmpty) return 1;
        if (ad.isNotEmpty && bd.isEmpty) return -1;
        final dcmp = ad.compareTo(bd);
        if (dcmp != 0) return dcmp;

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (filtered.isEmpty) {
        return Center(
          child: Text('No assignments here.', style: TextStyle(color: Colors.grey[600])),
        );
      }

      return ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, i) {
          final a = filtered[i];
          final done = a.isCompleted;

          return ListTile(
            onTap: () => _showAssignmentActionsSheet(a),
            onLongPress: () => _showDeleteAssignmentConfirmSheet(a),
            leading: Icon(
              done ? Icons.check_circle : Icons.circle_outlined,
              color: done ? Colors.green : Colors.white38,
              size: 20,
            ),
            title: Text(
              a.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? Colors.white70 : Colors.white,
              ),
            ),
            subtitle: Text(
              a.dueDate.isEmpty ? 'No due date' : 'Due: ${a.dueDate}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (a.pointsBase > 0)
                  Text('${a.pointsBase} pts',
                      style: const TextStyle(color: Colors.amber, fontSize: 11)),
                if (a.grade != null)
                  Text(
                    '${a.grade}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: (a.grade ?? 0) >= 90 ? Colors.green : Colors.orange,
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    String titleText() {
      if (_assignBrowserStudentId == null) return 'Assignments';
      final st = studentsById[_assignBrowserStudentId!];
      if (_assignBrowserSubjectId == null) return st?.name ?? 'Student';

      final sk = _assignBrowserSubjectId!;
      final subjectName =
          (sk == unassignedKey) ? 'Unassigned' : (subjectsById[sk]?.name ?? 'Subject');
      return '${st?.name ?? 'Student'} • $subjectName';
    }

    Widget header() {
      final canGoBack = _assignBrowserStudentId != null;

      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            if (canGoBack)
              IconButton(
                tooltip: 'Back',
                onPressed: goBack,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Text(
                titleText(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canGoBack)
              TextButton(
                onPressed: clearAll,
                child: const Text('Clear'),
              ),
            if (!canGoBack && studentOrder.isNotEmpty)
              Text(
                '${studentOrder.length} student${studentOrder.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;

        final sid = _assignBrowserStudentId;
        final sub = _assignBrowserSubjectId;

        // Narrow: drill-down
        if (!wide) {
          Widget body;
          if (sid == null) {
            body = studentsList();
          } else if (sub == null) {
            body = subjectsListForStudent(sid);
          } else {
            body = assignmentsList(sid, sub);
          }

          return Column(
            children: [
              header(),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: body,
                ),
              ),
            ],
          );
        }

        // Wide: 3 columns
        return Column(
          children: [
            header(),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  // Students
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: studentsList(),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Subjects
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: sid == null
                          ? Center(child: Text('Select a student', style: TextStyle(color: Colors.grey[600])))
                          : subjectsListForStudent(sid),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Assignments
                  Expanded(
                    flex: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: (sid == null || sub == null)
                          ? Center(child: Text('Select a subject', style: TextStyle(color: Colors.grey[600])))
                          : assignmentsList(sid, sub),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _subjectsPanel({
    required List<Subject> subjects,
    required List<Student> students,
    required List<Assignment> assignments,
  }) {
    final assignmentCountBySubject = <String, int>{};
    final studentSetBySubject = <String, Set<String>>{};

    for (final a in assignments) {
      assignmentCountBySubject[a.subjectId] = (assignmentCountBySubject[a.subjectId] ?? 0) + 1;
      (studentSetBySubject[a.subjectId] ??= <String>{}).add(a.studentId);
    }

    final sorted = [...subjects]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final q = _subjectQuery.toLowerCase();
    final filtered = q.isEmpty ? sorted : sorted.where((s) => s.name.toLowerCase().contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Subjects (${subjects.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Add Subject',
              onPressed: _showAddSubjectDialog,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _subjectSearchCtrl,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search subjects...',
            filled: true,
            fillColor: const Color(0xFF1F2937),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _subjectQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _subjectSearchCtrl.clear();
                      FocusScope.of(context).unfocus();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (_subjectQuery.isNotEmpty)
          Text(
            'Showing ${filtered.length} of ${subjects.length}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No subjects match "${_subjectQuery.trim()}".',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final s = filtered[index];
                    final aCount = assignmentCountBySubject[s.id] ?? 0;
                    final stuCount = studentSetBySubject[s.id]?.length ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showSubjectDetailSheet(
                            subject: s,
                            students: students,
                            assignments: assignments,
                          ),
                          onLongPress: () => _confirmDeleteSubject(
                            subject: s,
                            students: students,
                            allAssignments: assignments,
                          ),
                          child: Ink(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.book, color: Colors.white70),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$aCount assignment${aCount == 1 ? '' : 's'} • $stuCount student${stuCount == 1 ? '' : 's'}',
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit subject',
                                  icon: const Icon(Icons.edit, color: Colors.white70),
                                  onPressed: () => _showEditSubjectSheet(s),
                                ),
                                IconButton(
                                  tooltip: 'Delete subject',
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _confirmDeleteSubject(
                                    subject: s,
                                    students: students,
                                    allAssignments: assignments,
                                  ),
                                ),
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
    );
  }
}

class _SubjectStudentRow {
  final String studentId;
  final String studentName;
  final int total;
  final int completed;

  const _SubjectStudentRow({
    required this.studentId,
    required this.studentName,
    required this.total,
    required this.completed,
  });

  int get incomplete => total - completed;
}
