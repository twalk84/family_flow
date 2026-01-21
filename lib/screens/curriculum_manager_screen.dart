// FILE: lib/screens/curriculum_manager_screen.dart
//
// Parent-only screen for managing curricula:
// - View available course configs (from JSON)
// - Enroll students in curricula
// - Assign lessons one-at-a-time or in batches
// - Track progress per student per curriculum
//
// Access: Parent PIN required (enforced by caller)

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

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    setState(() => _loading = true);
    
    try {
      // Load available configs from service
      // For now, we'll use a hardcoded list - you can expand this
      // to scan assets or Firestore for available configs
      final configIds = [
        'general_chemistry_v1',
        'touch_typing_v1',
        'biological_science_v1',
        'british_literature_v1',
        'saxon_math_76',
        'wheelocks_latin',
      ];

      final configs = <Map<String, dynamic>>[];
      for (final id in configIds) {
        try {
          final config = await _configService.getConfig(id);
          if (config != null) {
            configs.add({
              'id': id,
              'config': config,
            });
          }
        } catch (e) {
          debugPrint('Failed to load config $id: $e');
        }
      }

      setState(() {
        _availableConfigs = configs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Failed to load curricula: $e', color: Colors.red);
    }
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

  String _todayYmd() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
  // Get curriculum display info
  // ============================================================

  String _getConfigName(Map<String, dynamic> config) {
    return config['name']?.toString() ?? config['id']?.toString() ?? 'Unknown';
  }

  String _getConfigDescription(Map<String, dynamic> config) {
    return config['description']?.toString() ?? '';
  }

  int _getTotalLessons(Map<String, dynamic> config) {
    final assignments = config['assignments'];
    if (assignments is List) return assignments.length;
    
    final totalLessons = config['totalLessons'];
    if (totalLessons is int) return totalLessons;
    
    return 0;
  }

  String _getConfigIcon(String configId) {
    if (configId.contains('math')) return '📐';
    if (configId.contains('chem')) return '🧪';
    if (configId.contains('bio')) return '🧬';
    if (configId.contains('latin')) return '🏛️';
    if (configId.contains('lit')) return '📚';
    if (configId.contains('typing')) return '⌨️';
    if (configId.contains('spanish')) return '🇪🇸';
    if (configId.contains('german')) return '🇩🇪';
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
                Text(
                  _getConfigDescription(config),
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_getTotalLessons(config)} total lessons',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),

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

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Enrolling creates a link between the student and curriculum. '
                          'Use "Manage" to assign individual lessons.',
                          style: TextStyle(color: Colors.blue.shade200, fontSize: 12),
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
        // Create or update enrollment record
        await FirestorePaths.subjectProgressCol(studentId).doc(configId).set({
          'courseConfigId': configId,
          'enrolledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      _snack('Enrolled ${studentIds.length} student(s) in $configName', color: Colors.green);
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

    // Get assignments defined in config
    final configAssignments = (config['assignments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Get categories for point values
    final categories = (config['categories'] as Map?)?.cast<String, dynamic>() ?? {};

    // Find which lessons are already assigned
    final assignedOrders = existingAssignments
        .where((a) => a.courseConfigId == configId)
        .map((a) => a.orderInCourse)
        .toSet();

    // Find next unassigned
    final unassigned = configAssignments
        .where((a) {
          final order = a['order'] as int? ?? 0;
          return !assignedOrders.contains(order);
        })
        .toList();

    await _showSmoothSheet<void>(
      title: '$configName - ${student.name}',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final completed = existingAssignments
                .where((a) => a.courseConfigId == configId && a.isCompleted)
                .length;
            final total = configAssignments.length;
            final assigned = assignedOrders.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress
                Text(
                  'Progress: $completed completed / $assigned assigned / $total total',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total > 0 ? assigned / total : 0,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total > 0 ? completed / total : 0,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                ),
                const SizedBox(height: 16),

                // Quick assign buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
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
                    OutlinedButton.icon(
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text('Assign Next 5'),
                      onPressed: unassigned.isEmpty
                          ? null
                          : () async {
                              final toAssign = unassigned.take(5).toList();
                              for (final lesson in toAssign) {
                                await _assignLesson(
                                  student: student,
                                  configId: configId,
                                  lessonData: lesson,
                                  categories: categories,
                                  linkedSubject: linkedSubject,
                                );
                              }
                              Navigator.pop(sheetContext);
                              _snack('Assigned ${toAssign.length} lessons', color: Colors.green);
                            },
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),

                // Unassigned lessons
                Row(
                  children: [
                    const Text('Upcoming', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      '${unassigned.length} remaining',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (unassigned.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 10),
                        Text('All lessons assigned!', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  )
                else
                  ...unassigned.take(10).map((lesson) {
                    final order = lesson['order'] as int? ?? 0;
                    final name = lesson['name']?.toString() ?? 'Lesson $order';
                    final categoryKey = lesson['category']?.toString() ?? 'lesson';
                    final categoryData = categories[categoryKey] as Map<String, dynamic>? ?? {};
                    final points = categoryData['pointsBase'] as int? ?? 10;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: Text('$order', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('$points pts • $categoryKey'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
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

                if (unassigned.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${unassigned.length - 10} more...',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),

                // Assigned lessons
                const Text('Assigned', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                ...existingAssignments
                    .where((a) => a.courseConfigId == configId)
                    .take(10)
                    .map((a) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.isCompleted ? Icons.check_circle : Icons.circle_outlined,
                      color: a.isCompleted ? Colors.green : Colors.white38,
                    ),
                    title: Text(
                      a.name,
                      style: TextStyle(
                        fontSize: 14,
                        decoration: a.isCompleted ? TextDecoration.lineThrough : null,
                        color: a.isCompleted ? Colors.white54 : null,
                      ),
                    ),
                    subtitle: Text(
                      a.isCompleted
                          ? 'Completed${a.grade != null ? ' • ${a.grade}%' : ''}'
                          : 'Due: ${a.dueDate}',
                      style: const TextStyle(fontSize: 12),
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
    required Map<String, dynamic> lessonData,
    required Map<String, dynamic> categories,
    required Subject? linkedSubject,
  }) async {
    final order = lessonData['order'] as int? ?? 0;
    final name = lessonData['name']?.toString() ?? 'Lesson $order';
    final categoryKey = lessonData['category']?.toString() ?? 'lesson';
    final categoryData = categories[categoryKey] as Map<String, dynamic>? ?? {};
    final points = categoryData['pointsBase'] as int? ?? 10;
    final gradable = categoryData['gradable'] as bool? ?? true;

    try {
      await AssignmentMutations.createAssignment(
        studentId: student.id,
        subjectId: linkedSubject?.id ?? '',
        name: name,
        dueDate: _todayYmd(),
        pointsBase: points,
        gradable: gradable,
        courseConfigId: configId,
        categoryKey: categoryKey,
        orderInCourse: order,
      );

      _snack('Assigned: $name', color: Colors.green);
    } catch (e) {
      _snack('Failed to assign: $e', color: Colors.red);
    }
  }

  // ============================================================
  // Build
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
              stream: FirestorePaths.studentsCol().snapshots(),
              builder: (context, studentsSnap) {
                final students = studentsSnap.data?.docs.map(Student.fromDoc).toList() ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirestorePaths.subjectsCol().snapshots(),
                  builder: (context, subjectsSnap) {
                    final subjects = subjectsSnap.data?.docs.map(Subject.fromDoc).toList() ?? [];

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirestorePaths.assignmentsCol().snapshots(),
                      builder: (context, assignmentsSnap) {
                        final assignments = assignmentsSnap.data?.docs
                                .map((d) => Assignment.fromDoc(d))
                                .toList() ??
                            [];

                        if (_availableConfigs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.library_books_outlined, size: 64, color: Colors.white24),
                                const SizedBox(height: 16),
                                const Text(
                                  'No curricula available',
                                  style: TextStyle(fontSize: 18, color: Colors.white60),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Add course config JSON files to get started.',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ],
                            ),
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
                            final icon = _getConfigIcon(configId);
                            final totalLessons = _getTotalLessons(config);

                            // Find enrolled students
                            final enrolledStudents = students.where((s) {
                              return assignments.any((a) =>
                                  a.studentId == s.id && a.courseConfigId == configId);
                            }).toList();

                            // Find linked subject
                            final linkedSubject = subjects.cast<Subject?>().firstWhere(
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
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                '$totalLessons lessons',
                                                style: const TextStyle(color: Colors.white60, fontSize: 13),
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
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Enrolled Students',
                                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                      ),
                                      const SizedBox(height: 8),
                                      ...enrolledStudents.map((s) {
                                        final studentAssignments = assignments
                                            .where((a) =>
                                                a.studentId == s.id &&
                                                a.courseConfigId == configId)
                                            .toList();
                                        final completed = studentAssignments
                                            .where((a) => a.isCompleted)
                                            .length;
                                        final assigned = studentAssignments.length;

                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.blue.withOpacity(0.2),
                                            child: Text(
                                              s.name.isNotEmpty ? s.name[0] : '?',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          title: Text(s.name),
                                          subtitle: Text(
                                            '$completed/$assigned assigned (${totalLessons - assigned} remaining)',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          trailing: TextButton(
                                            onPressed: () => _showManageCurriculumSheet(
                                              configData: configData,
                                              student: s,
                                              existingAssignments: studentAssignments,
                                              linkedSubject: linkedSubject,
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
            ),
    );
  }
}