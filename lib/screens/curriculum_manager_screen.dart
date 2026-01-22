// FILE: lib/screens/curriculum_manager_screen.dart
//
// Global Curriculum Manager (Firestore + Storage-backed configs)
//
// ✅ Updates:
// - Loads curricula list from Firestore collection: /courseConfigs (active == true)
// - Uses CourseConfigService.getConfig(id) which now fetches Firestore -> Storage JSON (with asset fallback)
// - Keeps your stabilized streams + smooth sheet UX
// - Falls back to a local hardcoded list if Firestore has no active configs yet (or read fails)
//
// NOTE:
// - Ensure you have Firestore rules allowing signed-in users to read /courseConfigs
// - Ensure Storage rules allow signed-in users to read /course-configs/*

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/firestore/firestore_paths.dart';
import '../core/models/models.dart';
import '../services/assignment_mutations.dart';
import '../services/course_config_service.dart';

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
      'wheelocks_latin_v1', // ✅ fixed id to match published config
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

  Future<void> _showEnrollSheet(Map<String, dynamic> configData, List<Student> students) async {
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
                                await _enrollStudents(
                                  configId: configId,
                                  configName: configName,
                                  studentIds: selectedStudents.toList(),
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
  }) async {
    try {
      for (final studentId in studentIds) {
        await FirestorePaths.subjectProgressCol(studentId).doc(configId).set({
          'courseConfigId': configId,
          'studentId': studentId, // Required for filtering logic
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
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Assign Next'),
                  onPressed: unassigned.isEmpty
                      ? null
                      : () async {
                          await _assignLesson(
                            student: student,
                            configId: configId,
                            lessonData: unassigned.first,
                            categories: categories,
                            linkedSubject: linkedSubject,
                          );
                          Navigator.pop(sheetContext);
                        },
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const Text('Upcoming', style: TextStyle(fontWeight: FontWeight.bold)),
                ...unassigned.take(6).map((lesson) {
                  if (lesson is! Map) return const SizedBox.shrink();
                  final order = (lesson['index'] as int?) ?? (lesson['order'] as int?) ?? 0;
                  final title = lesson['title']?.toString() ?? lesson['name']?.toString() ?? 'Lesson $order';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(title),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.blue),
                      onPressed: () async {
                        await _assignLesson(
                          student: student,
                          configId: configId,
                          lessonData: lesson,
                          categories: categories,
                          linkedSubject: linkedSubject,
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

  Future<void> _assignLesson({
    required Student student,
    required String configId,
    required dynamic lessonData,
    required Map<String, dynamic> categories,
    required Subject? linkedSubject,
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
      await AssignmentMutations.createAssignment(
        studentId: student.id,
        subjectId: linkedSubject?.id ?? '',
        name: name,
        dueDate: _todayYmd(),
        pointsBase: points,
        gradable: true,
        courseConfigId: configId,
        categoryKey: categoryKey,
        orderInCourse: order,
      );
      _snack('Assigned: $name', color: Colors.green);

      // ✅ Cosmetic: force repaint so counts update immediately
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Failed to assign: $e', color: Colors.red);
    }
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
                        final assignmentDocs = assignmentsSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
                                              onPressed: () => _showEnrollSheet(configData, students),
                                              child: const Text('Enroll'),
                                            ),
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
                                              // ✅ Interpolation ambiguity-proof (matches what we discussed)
                                              key: ValueKey('counts_${configId}_${s.id}_${assignedCount}_${completed}'),
                                              contentPadding: EdgeInsets.zero,
                                              leading: CircleAvatar(child: Text(s.name.isNotEmpty ? s.name[0] : '?')),
                                              title: Text(s.name),
                                              // ✅ Also ambiguity-proof (same reason)
                                              subtitle: Text('${completed} completed / ${assignedCount} assigned'),
                                              trailing: TextButton(
                                                onPressed: () => _showManageCurriculumSheet(
                                                  configData: configData,
                                                  student: s,
                                                  existingAssignments: studentAssignments,
                                                  linkedSubject: matchedSubject,
                                                ),
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
