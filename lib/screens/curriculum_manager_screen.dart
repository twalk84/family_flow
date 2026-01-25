// FILE: lib/screens/curriculum_manager_screen.dart
//
// Global Curriculum Manager (Firestore + Storage-backed configs)
//
// ✅ Updates:
// - Loads curricula list from Firestore collection: /courseConfigs (active == true)
// - Uses CourseConfigService.getConfig(id) which now fetches Firestore -> Storage JSON (with asset fallback)
// - Keeps stabilized streams + smooth sheet UX
// - ✅ Adds Delete Curriculum: Subject + Assignments + Progress (+ optional point reversal via service)
//
// ✅ NEW FIXES (Unassigned + Edit Subject Title):
// - ✅ Ensures a Subject doc exists for each curriculum (courseConfigId == configId)
// - ✅ Assignments created from curriculum ALWAYS get a real subjectId (never '')
// - ✅ Assignments also store subjectName/studentName for consistent UI display
// - ✅ Adds Rename Subject (updates subject doc + backfills assignments + updates subjectProgress)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/firestore/firestore_paths.dart';
import '../core/models/models.dart';

import '../services/assignment_mutations.dart';
import '../services/course_config_service.dart';
import '../services/subject_delete_service.dart';

class CurriculumManagerScreen extends StatefulWidget {
  const CurriculumManagerScreen({super.key});

  @override
  State<CurriculumManagerScreen> createState() => _CurriculumManagerScreenState();
}

class _CurriculumManagerScreenState extends State<CurriculumManagerScreen> {
  final _configService = CourseConfigService.instance;

  List<Map<String, dynamic>> _availableConfigs = [];
  bool _loading = true;

  // SENIOR FIX: Define streams as members to prevent recreation during build cycles
  late Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _subjectsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _assignmentsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _progressStream;

  @override
  void initState() {
    super.initState();

    // Initialize all connections ONCE to prevent "flashing" resets
    _studentsStream = FirestorePaths.studentsCol().snapshots();
    _subjectsStream = FirestorePaths.subjectsCol().snapshots();
    _assignmentsStream = FirestorePaths.assignmentsCol().snapshots();
    _progressStream = FirebaseFirestore.instance.collectionGroup('subjectProgress').snapshots();

    _loadConfigs();
  }

  // ============================================================
  // GLOBAL LOADING: Firestore list -> Storage JSON via service
  // ============================================================

  Future<void> _loadConfigs() async {
    setState(() => _loading = true);

    try {
      // 1) Try global list from Firestore
      final globalIds = await _fetchActiveGlobalConfigIds();

      // 2) Fallback list (assets) if global list empty or unavailable
      final ids = globalIds.isNotEmpty ? globalIds : _fallbackLocalConfigIds();

      final configs = <Map<String, dynamic>>[];

      // Load each config via service (global first, then asset fallback)
      for (final id in ids) {
        try {
          final config = await _configService.getConfig(id);
          if (config != null) {
            configs.add({'id': id, 'config': config});
          }
        } catch (e) {
          debugPrint('Failed to load config $id: $e');
        }
      }

      // Sort by display name for a clean UI
      configs.sort((a, b) {
        final an = _getConfigName((a['config'] as Map<String, dynamic>));
        final bn = _getConfigName((b['config'] as Map<String, dynamic>));
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });

      setState(() {
        _availableConfigs = configs;
        _loading = false;
      });

      if (globalIds.isEmpty) {
        _snack('No active global curricula found. Showing local fallback list.', color: Colors.orange);
      }
    } catch (e) {
      setState(() => _loading = false);
      _snack('Failed to load curricula: $e', color: Colors.red);
    }
  }

  Future<List<String>> _fetchActiveGlobalConfigIds() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('courseConfigs')
          .where('active', isEqualTo: true)
          .get();

      // Prefer explicit "id" field if present, else doc id
      final ids = snap.docs
          .map((d) {
            final data = d.data();
            final raw = (data['id'] ?? d.id).toString().trim();
            return raw;
          })
          .where((id) => id.isNotEmpty)
          .toList();

      // De-dup while preserving order
      final seen = <String>{};
      final unique = <String>[];
      for (final id in ids) {
        if (seen.add(id)) unique.add(id);
      }
      return unique;
    } catch (e) {
      debugPrint('Global courseConfigs fetch failed: $e');
      return [];
    }
  }

  List<String> _fallbackLocalConfigIds() {
    // Keep this list as a safety net for offline/dev or before publishing globals
    return const [
      'general_chemistry_v1',
      'touch_typing_v1',
      'biological_science_v1',
      'british_literature_v1',
      'saxon_math_76',
      'wheelocks_latin_v1',
      'deutsche_sprachlehre_v1',
      'madrigals_spanish_v1',
      'russian_in_exercises_v1',
    ];
  }

  // ============================================================
  // UI Helpers
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

  String _todayYmd() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ✅ Always compute counts from live Firestore snapshot docs.
  (int assigned, int completed) _countsForStudentConfig({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> assignmentDocs,
    required String studentId,
    required String configId,
  }) {
    int assigned = 0;
    int completed = 0;

    for (final doc in assignmentDocs) {
      final data = doc.data();

      final sid = (data['studentId'] ?? data['student_id'] ?? '').toString().trim();
      if (sid != studentId) continue;

      final cid = (data['courseConfigId'] ?? data['course_config_id'] ?? '').toString().trim();
      if (cid != configId) continue;

      assigned++;
      final isDone = (data['completed'] == true) || (data['isCompleted'] == true);
      if (isDone) completed++;
    }

    return (assigned, completed);
  }

  // ============================================================
  // ✅ SUBJECT ENSURE + RENAME (Fixes "Unassigned")
  // ============================================================

  Future<Subject> _ensureSubjectForConfig({
    required String configId,
    required String configName,
    required List<Subject> subjects,
  }) async {
    // 1) If already exists, return it.
    for (final s in subjects) {
      if (s.courseConfigId.trim() == configId.trim()) {
        return s;
      }
    }

    // 2) Create a subject doc (family-level) for this curriculum.
    final safeName = configName.trim().isNotEmpty ? configName.trim() : configId.trim();
    final docRef = FirestorePaths.subjectsCol().doc();

    await docRef.set({
      'name': safeName,
      'nameLower': safeName.toLowerCase(),
      'courseConfigId': configId.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return Subject(
      id: docRef.id,
      name: safeName,
      courseConfigId: configId.trim(),
    );
  }

  Future<void> _renameSubjectDialog({
    required Subject subject,
    required String courseConfigId,
    required List<Student> allStudents,
  }) async {
    final c = TextEditingController(text: subject.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Rename Subject'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Subject name',
            hintText: 'e.g. Touch Typing',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      _snack('Subject name cannot be empty.', color: Colors.orange);
      return;
    }

    // Progress dialog
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
              Text('Updating subject name...'),
            ],
          ),
        ),
      ),
    );

    try {
      // 1) Update subject doc
      await FirestorePaths.subjectsCol().doc(subject.id).set({
        'name': trimmed,
        'nameLower': trimmed.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) Backfill assignments that reference this subject so UI always shows the new name
      // (Batch in chunks to respect Firestore limits)
      final query = await FirestorePaths.assignmentsCol().where('subjectId', isEqualTo: subject.id).get();
      final docs = query.docs;

      const int chunkSize = 450;
      for (int i = 0; i < docs.length; i += chunkSize) {
        final batch = FirebaseFirestore.instance.batch();
        final slice = docs.skip(i).take(chunkSize);
        for (final d in slice) {
          batch.update(d.reference, {
            'subjectName': trimmed,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      // 3) Update subjectProgress docs for all students enrolled in this config
      // (Doc id is configId in your design)
      for (final s in allStudents) {
        await FirestorePaths.subjectProgressCol(s.id).doc(courseConfigId).set({
          'subjectId': subject.id,
          'subjectName': trimmed,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context); // close progress
      _snack('Renamed subject to "$trimmed".', color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress
      _snack('Rename failed: $e', color: Colors.red);
    }
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
        final availableHeight = size.height - viewInsets - 40;
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
                  maxHeight: size.height * 0.88 > availableHeight ? availableHeight : size.height * 0.88,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      Flexible(
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
  // Get curriculum display info
  // ============================================================

  String _getConfigName(Map<String, dynamic> config) {
    return config['title']?.toString() ?? config['name']?.toString() ?? 'Unknown';
  }

  String _getConfigDescription(Map<String, dynamic> config) {
    return config['subtitle']?.toString() ?? config['description']?.toString() ?? '';
  }

  int _getTotalLessons(Map<String, dynamic> config) {
    final curriculum = config['curriculum'];
    if (curriculum is Map) {
      return (curriculum['totalLessons'] is num) ? (curriculum['totalLessons'] as num).toInt() : 0;
    }
    final assignments = config['assignments'];
    if (assignments is List) return assignments.length;
    return 0;
  }

  String _getConfigIcon(String configId) {
    final id = configId.toLowerCase();
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

  // ============================================================
  // Enroll Student in Curriculum
  // ============================================================

  Future<void> _showEnrollSheet(
    Map<String, dynamic> configData,
    List<Student> students,
    List<Subject> subjects,
  ) async {
    final configId = configData['id'] as String;
    final config = configData['config'] as Map<String, dynamic>;
    final configName = _getConfigName(config);
    final selectedStudents = <String>{};

    await _showSmoothSheet<void>(
      title: 'Enroll in $configName',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Students', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (students.isEmpty)
                  const Text('No students available.', style: TextStyle(color: Colors.white60))
                else
                  ...students.map((s) {
                    final isSelected = selectedStudents.contains(s.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (v) {
                        setSheetState(() {
                          if (v == true) {
                            selectedStudents.add(s.id);
                          } else {
                            selectedStudents.remove(s.id);
                          }
                        });
                      },
                      title: Text(s.name),
                      subtitle: Text('Grade ${s.gradeLevel}'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
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
                        icon: const Icon(Icons.check),
                        label: Text('Enroll ${selectedStudents.length}'),
                        onPressed: selectedStudents.isEmpty
                            ? null
                            : () async {
                                // ✅ Ensure subject exists so assignments will never be "Unassigned"
                                final ensuredSubject = await _ensureSubjectForConfig(
                                  configId: configId,
                                  configName: configName,
                                  subjects: subjects,
                                );

                                await _enrollStudents(
                                  configId: configId,
                                  configName: configName,
                                  studentIds: selectedStudents.toList(),
                                  subjectId: ensuredSubject.id,
                                  subjectName: ensuredSubject.name,
                                );
                                if (mounted) Navigator.pop(sheetContext);
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

  Future<void> _enrollStudents({
    required String configId,
    required String configName,
    required List<String> studentIds,

    // ✅ Added: store subject linkage on progress docs
    required String subjectId,
    required String subjectName,
  }) async {
    try {
      for (final studentId in studentIds) {
        await FirestorePaths.subjectProgressCol(studentId).doc(configId).set({
          'courseConfigId': configId,
          'studentId': studentId, // Required for filtering logic

          // ✅ Helps downstream UI and repair tools
          'subjectId': subjectId,
          'subjectName': subjectName,

          'enrolledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      _snack('Enrolled successfully in $configName', color: Colors.green);
    } catch (e) {
      _snack('Enrollment failed: $e', color: Colors.red);
    }
  }

  // ============================================================
  // Manage Curriculum (Assign Lessons)
  // ============================================================

  Future<void> _showManageCurriculumSheet({
    required Map<String, dynamic> configData,
    required Student student,
    required List<Assignment> existingAssignments,
    required Subject? linkedSubject,
  }) async {
    final configId = configData['id'] as String;
    final config = configData['config'] as Map<String, dynamic>;
    final configName = _getConfigName(config);

    final curriculum = config['curriculum'];
    List configAssignments = [];
    if (curriculum is Map && curriculum['modules'] is List) {
      for (final module in (curriculum['modules'] as List)) {
        if (module is Map && module['lessons'] is List) {
          configAssignments.addAll(module['lessons'] as List);
        }
      }
    } else {
      configAssignments = (config['assignments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    }

    final categories = (config['categories'] as Map?)?.cast<String, dynamic>() ??
        (config['grading']?['categories'] as Map?)?.cast<String, dynamic>() ??
        {};

    final assignedOrders = existingAssignments
        .where((a) => a.courseConfigId == configId)
        .map((a) => a.orderInCourse)
        .toSet();

    final unassigned = configAssignments.where((a) {
      final order = (a is Map) ? ((a['index'] as int?) ?? (a['order'] as int?) ?? 0) : 0;
      return !assignedOrders.contains(order);
    }).toList();

    await _showSmoothSheet<void>(
      title: '$configName - ${student.name}',
      builder: (sheetContext) {
        // Batch selection state
        final selectedIndices = <int>{};
        bool batchMode = false;
        
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final completed = existingAssignments.where((a) => a.courseConfigId == configId && a.isCompleted).length;
            final assignedCount = assignedOrders.length;
            final totalCount = configAssignments.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress: $completed completed / $assignedCount assigned / $totalCount total'),
                const SizedBox(height: 16),
                // Batch selection state
                if (!batchMode) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Assign Next'),
                    onPressed: unassigned.isEmpty
                        ? null
                        : () async {
                            final dueDate = await _pickDueDate();
                            if (dueDate == null) return;

                            await _assignLesson(
                              student: student,
                              configId: configId,
                              lessonData: unassigned.first,
                              categories: categories,
                              linkedSubject: linkedSubject,
                              dueDate: dueDate,
                            );
                            Navigator.pop(sheetContext);
                          },
                  ),
                ] else ...[
                  if (selectedIndices.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('${selectedIndices.length} selected'),
                        const Spacer(),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                          onPressed: () => setSheetState(() => selectedIndices.clear()),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Assign All'),
                          onPressed: () async {
                            final dueDate = await _pickDueDate();
                            if (dueDate == null) return;

                            for (final idx in selectedIndices) {
                              if (idx < unassigned.length) {
                                await _assignLesson(
                                  student: student,
                                  configId: configId,
                                  lessonData: unassigned[idx],
                                  categories: categories,
                                  linkedSubject: linkedSubject,
                                  dueDate: dueDate,
                                );
                              }
                            }
                            if (mounted) Navigator.pop(sheetContext);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Text('Select lessons to assign in batch', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                  ],
                ],
                Row(
                  children: [
                    if (!batchMode)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.checklist),
                        label: const Text('Batch Mode'),
                        onPressed: () => setSheetState(() => batchMode = true),
                      ),
                    if (batchMode)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Exit Batch'),
                        onPressed: () {
                          selectedIndices.clear();
                          setSheetState(() => batchMode = false);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const Text('Upcoming', style: TextStyle(fontWeight: FontWeight.bold)),
                ...unassigned.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lesson = entry.value;
                  if (lesson is! Map) return const SizedBox.shrink();
                  
                  final order = (lesson['index'] as int?) ?? (lesson['order'] as int?) ?? 0;
                  final title = lesson['title']?.toString() ?? lesson['name']?.toString() ?? 'Lesson $order';
                  final isSelected = selectedIndices.contains(idx);
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: batchMode
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (_) {
                              setSheetState(() {
                                if (isSelected) {
                                  selectedIndices.remove(idx);
                                } else {
                                  selectedIndices.add(idx);
                                }
                              });
                            },
                          )
                        : null,
                    title: Text(title),
                    onTap: batchMode
                        ? () {
                            setSheetState(() {
                              if (isSelected) {
                                selectedIndices.remove(idx);
                              } else {
                                selectedIndices.add(idx);
                              }
                            });
                          }
                        : null,
                    trailing: batchMode
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.blue),
                            onPressed: () async {
                              final dueDate = await _pickDueDate();
                              if (dueDate == null) return;

                              await _assignLesson(
                                student: student,
                                configId: configId,
                                lessonData: lesson,
                                categories: categories,
                                linkedSubject: linkedSubject,
                                dueDate: dueDate,
                              );
                              Navigator.pop(sheetContext);
                            },
                          ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _pickDueDate() async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      ),
    );
    
    if (result == null) return null;
    
    // Format as YYYY-MM-DD
    return '${result.year.toString().padLeft(4, '0')}-'
           '${result.month.toString().padLeft(2, '0')}-'
           '${result.day.toString().padLeft(2, '0')}';
  }

  Future<void> _assignLesson({
    required Student student,
    required String configId,
    required dynamic lessonData,
    required Map<String, dynamic> categories,
    required Subject? linkedSubject,
    required String dueDate,
  }) async {
    final order = (lessonData is Map) ? ((lessonData['index'] as int?) ?? (lessonData['order'] as int?) ?? 0) : 0;

    final name = (lessonData is Map)
        ? (lessonData['title']?.toString() ?? lessonData['name']?.toString() ?? 'Lesson $order')
        : 'Lesson $order';

    final categoryKey = (lessonData is Map) ? (lessonData['category']?.toString() ?? 'lesson') : 'lesson';

    int points = 10;
    if (categories.containsKey(categoryKey)) {
      final cat = categories[categoryKey];
      if (cat is Map) {
        final raw = (cat['pointsEach'] ?? cat['pointsBase'] ?? 10);
        points = raw is num ? raw.toInt() : 10;
      }
    }

    try {
      // ✅ HARD FIX: Guarantee a real subjectId so UI never shows "Unassigned"
      Subject subject;
      if (linkedSubject != null && linkedSubject.id.trim().isNotEmpty) {
        subject = linkedSubject;
      } else {
        // Create/ensure the subject now (in case enroll happened earlier without subject existing)
        subject = await _ensureSubjectForConfig(
          configId: configId,
          configName: configId, // fallback; UI will likely use config name elsewhere
          subjects: const <Subject>[],
        );

        // The subjects stream will catch up, but we already have the subject object here.
      }

      await AssignmentMutations.createAssignment(
        studentId: student.id,
        subjectId: subject.id,
        name: name,
        dueDate: dueDate,
        pointsBase: points,
        gradable: true,
        courseConfigId: configId,
        categoryKey: categoryKey,
        orderInCourse: order,

        // ✅ Store display names so every UI shows correct label immediately.
        studentName: student.name,
        subjectName: subject.name,
      );

      _snack('Assigned: $name', color: Colors.green);

      // ✅ Cosmetic: force repaint so counts update immediately
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Failed to assign: $e', color: Colors.red);
    }
  }

  // ============================================================
  // Delete Curriculum (Subject + related data)
  // ============================================================

  Future<void> _deleteSubjectCascade({
    required Subject subject,
    required String courseConfigId,
    required int linkedAssignmentCount,
    required List<String> studentIds,
  }) async {
    // Count badges for dialog (optional)
    int badgeCount = 0;
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('badgesEarned')
          .where('subjectId', isEqualTo: subject.id)
          .get();
      badgeCount = snap.docs.length;
    } catch (_) {}

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Delete Subject + Cleanup?'),
              content: Text(
                'This will permanently delete:\n'
                '• Subject: "${subject.name}"\n'
                '• Assignments linked to it: $linkedAssignmentCount\n'
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
        subjectId: subject.id,
        courseConfigId: courseConfigId,
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
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      _snack('Delete failed: $e', color: Colors.red);
    }
  }
  Future<void> _repairAssignmentsForConfig({
    required String configId,
    required Subject subject,
  }) async {
    // Pull assignments that match this curriculum (support both field styles)
    final a1 = await FirestorePaths.assignmentsCol()
        .where('courseConfigId', isEqualTo: configId)
        .get();
  
    QuerySnapshot<Map<String, dynamic>> a2;
    try {
      a2 = await FirestorePaths.assignmentsCol()
          .where('course_config_id', isEqualTo: configId)
          .get();
    } catch (_) {
      // If no index / field doesn’t exist widely, ignore snake query.
      a2 = await FirestorePaths.assignmentsCol().limit(0).get();
    }
  
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in a1.docs) {
      byId[d.id] = d;
    }
    for (final d in a2.docs) {
      byId[d.id] = d;
    }
  
    final docs = byId.values.toList();
    if (docs.isEmpty) {
      _snack('No assignments found for $configId.', color: Colors.orange);
      return;
    }
  
    int fixed = 0;
  
    // Batch in chunks (Firestore limit safety)
    const chunkSize = 450;
    for (int i = 0; i < docs.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final slice = docs.skip(i).take(chunkSize);
  
      for (final d in slice) {
        final data = d.data();
  
        final sid = (data['subjectId'] ?? data['subject_id'] ?? '').toString().trim();
        final sname = (data['subjectName'] ?? data['subject_name'] ?? '').toString().trim();
  
        final needsId = sid.isEmpty || sid != subject.id;
        final needsName = sname.isEmpty || sname != subject.name;
  
        if (!needsId && !needsName) continue;
  
        batch.update(d.reference, {
          'subjectId': subject.id,
          'subject_id': subject.id,
          'subjectName': subject.name,
          'subject_name': subject.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        fixed++;
      }
  
      await batch.commit();
    }
  
    _snack('Repair complete: fixed $fixed assignments.', color: Colors.green);
  }

  // ============================================================
  // Build (Stabilized Nested Streams)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curriculum Manager'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfigs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _studentsStream,
              builder: (context, studentsSnap) {
                final students = studentsSnap.data?.docs.map(Student.fromDoc).toList() ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _subjectsStream,
                  builder: (context, subjectsSnap) {
                    final subjects = subjectsSnap.data?.docs.map(Subject.fromDoc).toList() ?? [];

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _assignmentsStream,
                      builder: (context, assignmentsSnap) {
                        // ✅ Keep raw docs for accurate counting
                        final assignmentDocs =
                            assignmentsSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        final assignments = assignmentDocs.map((d) => Assignment.fromDoc(d)).toList();

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _progressStream,
                          builder: (context, progressSnap) {
                            if (progressSnap.connectionState == ConnectionState.waiting && students.isNotEmpty) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            if (progressSnap.hasError) {
                              return Center(
                                child: Text(
                                  'Stream Error: ${progressSnap.error}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              );
                            }

                            final progressDocs = progressSnap.data?.docs ?? [];

                            if (_availableConfigs.isEmpty) {
                              return const Center(
                                child: Text('No curricula available.', style: TextStyle(color: Colors.white60)),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _availableConfigs.length,
                              itemBuilder: (context, index) {
                                final configData = _availableConfigs[index];
                                final configId = configData['id'] as String;
                                final config = configData['config'] as Map<String, dynamic>;

                                final configName = _getConfigName(config);
                                final configDesc = _getConfigDescription(config);
                                final icon = _getConfigIcon(configId);
                                final totalLessons = _getTotalLessons(config);

                                final enrolledStudents = students.where((s) {
                                  return progressDocs.any((p) {
                                    final data = p.data();
                                    final pStudentId = data['studentId']?.toString() ?? '';
                                    final pConfigId = data['courseConfigId']?.toString() ?? '';
                                    return pStudentId == s.id && pConfigId == configId;
                                  });
                                }).toList();

                                final Subject? matchedSubject = subjects.cast<Subject?>().firstWhere(
                                      (s) => s?.courseConfigId == configId,
                                      orElse: () => null,
                                    );

                                final linkedAssignmentCount = matchedSubject == null
                                    ? 0
                                    : assignments.where((a) => a.subjectId == matchedSubject.id).length;

                                final allStudentIds = students.map((s) => s.id).toList();

                                return Card(
                                  color: const Color(0xFF1F2937),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(color: Colors.white12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(icon, style: const TextStyle(fontSize: 28)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    configName,
                                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                  ),
                                                  if (configDesc.isNotEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Text(
                                                        configDesc,
                                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                                      ),
                                                    ),
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      '$totalLessons lessons',
                                                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            OutlinedButton(
                                              onPressed: () => _showEnrollSheet(configData, students, subjects),
                                              child: const Text('Enroll'),
                                            ),

                                            // ✅ Rename Subject (creates subject if missing, then renames)
                                            const SizedBox(width: 8),
                                            IconButton(
                                              tooltip: 'Rename subject',
                                              icon: const Icon(Icons.edit, color: Colors.white70),
                                              onPressed: () async {
                                                final subject = matchedSubject ??
                                                    await _ensureSubjectForConfig(
                                                      configId: configId,
                                                      configName: configName,
                                                      subjects: subjects,
                                                    );
                                                await _renameSubjectDialog(
                                                  subject: subject,
                                                  courseConfigId: configId,
                                                  allStudents: students,
                                                );
                                              },
                                            ),

                                            if (matchedSubject != null) ...[
                                              const SizedBox(width: 4),
                                              IconButton(
                                                tooltip: 'Delete subject + assignments + progress',
                                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                                onPressed: () => _deleteSubjectCascade(
                                                  subject: matchedSubject,
                                                  courseConfigId: configId,
                                                  linkedAssignmentCount: linkedAssignmentCount,
                                                  studentIds: allStudentIds,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (enrolledStudents.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          const Divider(color: Colors.white12),
                                          const Text(
                                            'Enrolled Students',
                                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                          ),
                                          const SizedBox(height: 8),
                                          ...enrolledStudents.map((s) {
                                            final studentAssignments = assignments
                                                .where((a) => a.studentId == s.id && a.courseConfigId == configId)
                                                .toList();

                                            final (assignedCount, completed) = _countsForStudentConfig(
                                              assignmentDocs: assignmentDocs,
                                              studentId: s.id,
                                              configId: configId,
                                            );

                                            return ListTile(
                                              key: ValueKey('counts_${configId}_${s.id}_${assignedCount}_${completed}'),
                                              contentPadding: EdgeInsets.zero,
                                              leading: CircleAvatar(child: Text(s.name.isNotEmpty ? s.name[0] : '?')),
                                              title: Text(s.name),
                                              subtitle: Text('$completed completed / $assignedCount assigned'),
                                              trailing: TextButton(
                                                onPressed: () async {
                                                  final subject = matchedSubject ??
                                                      await _ensureSubjectForConfig(
                                                        configId: configId,
                                                        configName: configName,
                                                        subjects: subjects,
                                                      );

                                                  await _showManageCurriculumSheet(
                                                    configData: configData,
                                                    student: s,
                                                    existingAssignments: studentAssignments,
                                                    linkedSubject: subject,
                                                  );
                                                },
                                                child: const Text('Manage'),
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
