// FILE: lib/screens/student_profile_screen.dart
//
// Student profile screen with:
// - Profile picture upload
// - Mood tracking
// - Wallet preview + link to Rewards Page
// - Stats and achievements

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_config.dart';
import '../firestore_paths.dart';
import '../models.dart';
import '../widgets/mood_picker.dart';
import '../widgets/media_viewer.dart';
import '../services/storage_service.dart';
import '../services/reward_service.dart';
import '../services/course_config_service.dart';
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
  // Collapsible section states
  late bool _expandedCompletedThisWeek;
  late bool _expandedProgressBySubject;

  @override
  void initState() {
    super.initState();
    _expandedCompletedThisWeek = false;
    _expandedProgressBySubject = false;
  }

  DocumentReference<Map<String, dynamic>> get _studentRef =>
      FirestorePaths.studentsCol().doc(widget.student.id);

  Color _effectiveColor(Student s) {
    if (s.colorValue != 0) return Color(s.colorValue);
    return widget.color;
  }

  int get totalAssignments => widget.assignments.length;
  int get completedAssignments =>
      widget.assignments.where((a) => a.isCompleted).length;
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
      final key = a.subjectName.isNotEmpty
          ? a.subjectName
          : (a.subjectId.isNotEmpty ? a.subjectId : 'No Subject');
      result.putIfAbsent(key, () => []);
      result[key]!.add(a);
    }
    return result;
  }

  List<Assignment> get dueAssignments {
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    return widget.assignments.where((a) {
      if (a.isCompleted) return false;
      try {
        final parts = a.dueDate.split('-');
        if (parts.length != 3) return false;
        final due = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return due.isBefore(weekFromNow) || due.isAtSameMomentAs(weekFromNow);
      } catch (_) {
        return false;
      }
    }).toList()..sort((a, b) {
      try {
        final aParts = a.dueDate.split('-');
        final bParts = b.dueDate.split('-');
        final aDate = DateTime(
          int.parse(aParts[0]),
          int.parse(aParts[1]),
          int.parse(aParts[2]),
        );
        final bDate = DateTime(
          int.parse(bParts[0]),
          int.parse(bParts[1]),
          int.parse(bParts[2]),
        );
        return aDate.compareTo(bDate);
      } catch (_) {
        return 0;
      }
    });
  }

  List<Assignment> get overdueAssignments {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    return widget.assignments.where((a) {
      if (a.isCompleted) return false;
      try {
        final parts = a.dueDate.split('-');
        if (parts.length != 3) return false;
        final due = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return due.isBefore(todayDate);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  List<Assignment> get completedThisWeek {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return widget.assignments.where((a) {
      if (!a.isCompleted || a.completionDate.isEmpty) return false;
      try {
        final parts = a.completionDate.split('-');
        if (parts.length != 3) return false;
        final completed = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return completed.isAfter(weekAgo) &&
            completed.isBefore(now.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).toList()..sort((a, b) {
      try {
        final aParts = a.completionDate.split('-');
        final bParts = b.completionDate.split('-');
        if (aParts.length != 3 || bParts.length != 3) return 0;
        final aDate = DateTime(
          int.parse(aParts[0]),
          int.parse(aParts[1]),
          int.parse(aParts[2]),
        );
        final bDate = DateTime(
          int.parse(bParts[0]),
          int.parse(bParts[1]),
          int.parse(bParts[2]),
        );
        return bDate.compareTo(aDate);
      } catch (_) {
        return 0;
      }
    });
  }

  Map<String, double> get gradeBySubject {
    final result = <String, double>{};
    for (final a in widget.assignments) {
      if (a.grade == null) continue;
      final key = a.subjectName.isNotEmpty
          ? a.subjectName
          : (a.subjectId.isNotEmpty ? a.subjectId : 'No Subject');
      result.putIfAbsent(key, () => 0);

      if (!result.containsKey('${key}_count')) {
        result['${key}_count'] = 0;
      }
      result['${key}_count'] = result['${key}_count']! + 1;
      result[key] =
          (result[key]! * (result['${key}_count']! - 1) + a.grade!) /
          result['${key}_count']!;
    }
    return result;
  }

  Map<String, Map<String, int>> get progressBySubject {
    final result = <String, Map<String, int>>{};
    for (final entry in assignmentsBySubject.entries) {
      final completed = entry.value.where((a) => a.isCompleted).length;
      result[entry.key] = {'completed': completed, 'total': entry.value.length};
    }
    return result;
  }

  Future<Map<String, Map<String, dynamic>>> calculateCourseProgress() async {
    final result = <String, Map<String, dynamic>>{};
    final configService = CourseConfigService.instance;

    final assignmentsByCourse = <String, List<Assignment>>{};
    for (final a in widget.assignments) {
      if (a.courseConfigId.trim().isEmpty) continue;
      assignmentsByCourse.putIfAbsent(a.courseConfigId, () => []);
      assignmentsByCourse[a.courseConfigId]!.add(a);
    }

    for (final entry in assignmentsByCourse.entries) {
      final courseConfigId = entry.key;
      final assignments = entry.value;

      try {
        final config = await configService.getConfig(courseConfigId);
        if (config == null) {
          final completed = assignments.where((a) => a.isCompleted).length;
          result[courseConfigId] = {
            'completed': completed,
            'total': assignments.length,
            'percent': assignments.isNotEmpty
                ? ((completed / assignments.length) * 100).toStringAsFixed(1)
                : '0.0',
            'courseName': courseConfigId,
          };
          continue;
        }

        int totalLessons = 0;
        final curriculum = config['curriculum'] as Map<String, dynamic>? ?? {};
        totalLessons = curriculum['totalLessons'] as int? ?? 0;

        if (totalLessons == 0) {
          final modules = curriculum['modules'] as List? ?? [];
          for (final module in modules) {
            if (module is Map<String, dynamic>) {
              final lessons = module['lessons'] as List? ?? [];
              totalLessons += lessons.length;
            }
          }
        }

        if (totalLessons == 0) {
          final lessons = config['lessons'] as List? ?? [];
          totalLessons = lessons.length;
        }

        if (totalLessons == 0) {
          totalLessons = assignments.length;
        }

        final completedOrders = assignments
            .where((a) => a.isCompleted && a.orderInCourse > 0)
            .map((a) => a.orderInCourse)
            .toSet();

        int completed = completedOrders.length;

        if (completed == 0 && assignments.any((a) => a.isCompleted)) {
          completed = assignments.where((a) => a.isCompleted).length;
        }

        if (completed > totalLessons) {
          completed = totalLessons;
        }

        final percent = totalLessons > 0
            ? (completed / totalLessons * 100).toStringAsFixed(1)
            : '0.0';

        result[courseConfigId] = {
          'completed': completed,
          'total': totalLessons,
          'percent': percent,
          'courseName': (config['title'] as String?) ?? courseConfigId,
        };
      } catch (e) {
        final completed = assignments.where((a) => a.isCompleted).length;
        result[courseConfigId] = {
          'completed': completed,
          'total': assignments.length,
          'percent': assignments.isNotEmpty
              ? ((completed / assignments.length) * 100).toStringAsFixed(1)
              : '0.0',
          'courseName': courseConfigId,
        };
      }
    }

    return result;
  }

  List<String> get achievements {
    final badges = <String>[];

    if (widget.student.currentStreak >= 5) badges.add('🔥 5-Day Streak');
    if (widget.student.currentStreak >= 10) badges.add('🔥 10-Day Streak');
    if (widget.student.longestStreak >= 20) badges.add('⭐ 20-Day Best');

    if (completedAssignments >= 10) badges.add('✅ 10 Completed');
    if (completedAssignments >= 50) badges.add('🎯 50 Completed');

    if (averageGrade >= 90) badges.add('💯 A+ Average');
    if (averageGrade >= 80) badges.add('⭐ B+ Average');

    final perfectSubjects = gradeBySubject.entries
        .where((e) => !e.key.contains('_count') && e.value >= 95)
        .length;
    if (perfectSubjects > 0)
      badges.add(
        '🏆 Perfect Score in $perfectSubjects Subject${perfectSubjects > 1 ? 's' : ''}',
      );

    if (widget.assignments.isEmpty) badges.add('🚀 Getting Started');

    return badges;
  }

  Future<void> _setMood(String? mood) async {
    await _studentRef.set({
      'mood': mood,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _uploadProfilePicture(Student student) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading profile picture...')),
      );

      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance.ref(
        'students/${student.id}/profile_pic',
      );
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await _studentRef.update({
        'profilePictureUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _showDueAssignmentsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Due Soon & Overdue (${dueAssignments.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (dueAssignments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No assignments due soon!',
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: dueAssignments.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12),
                    itemBuilder: (context, i) {
                      final a = dueAssignments[i];
                      final now = DateTime.now();
                      try {
                        final parts = a.dueDate.split('-');
                        final due = DateTime(
                          int.parse(parts[0]),
                          int.parse(parts[1]),
                          int.parse(parts[2]),
                        );
                        final isOverdue = due.isBefore(now);

                        return ListTile(
                          leading: Icon(
                            isOverdue ? Icons.error : Icons.schedule,
                            color: isOverdue ? Colors.red : Colors.orange,
                          ),
                          title: Text(a.name),
                          subtitle: Text(
                            '${a.subjectName.isNotEmpty ? a.subjectName : 'No Subject'} • Due: ${a.dueDate}',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => _showAssignmentDetailsModal(a),
                        );
                      } catch (_) {
                        return ListTile(
                          leading: const Icon(
                            Icons.schedule,
                            color: Colors.grey,
                          ),
                          title: Text(a.name),
                          subtitle: const Text(
                            'Invalid due date',
                            style: TextStyle(color: Colors.white60),
                          ),
                        );
                      }
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOverdueAssignmentsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚠️ Overdue (${overdueAssignments.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              if (overdueAssignments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No overdue assignments! 🎉',
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: overdueAssignments.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12),
                    itemBuilder: (context, i) {
                      final a = overdueAssignments[i];
                      return ListTile(
                        leading: const Icon(Icons.error, color: Colors.red),
                        title: Text(a.name),
                        subtitle: Text(
                          '${a.subjectName.isNotEmpty ? a.subjectName : 'No Subject'} • Was due: ${a.dueDate}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _showAssignmentDetailsModal(a),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignmentDetailsModal(Assignment assignment) async {
    Navigator.pop(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assignment.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                'Subject',
                assignment.subjectName.isNotEmpty
                    ? assignment.subjectName
                    : 'No Subject',
              ),
              _DetailRow('Due Date', assignment.dueDate),
              _DetailRow(
                'Status',
                assignment.isCompleted ? '✅ Completed' : '⏳ Incomplete',
              ),
              if (assignment.isCompleted && assignment.completionDate.isNotEmpty)
                _DetailRow(
                  'Completed On',
                  assignment.completionDate,
                ),
              if (assignment.grade != null)
                _DetailRow('Grade', '${assignment.grade}%'),
              if (assignment.attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Attachments (${assignment.attachments.length})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                ...assignment.attachments.map((att) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => AppConfig.openExternalUrl(att.url),
                          child: Ink(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  att.type == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                                  color: att.type == 'pdf' ? Colors.redAccent : Colors.blueAccent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      if (att.type == 'image') {
                                        MediaViewer.show(context, att.url, att.name);
                                      } else {
                                        try {
                                          await AppConfig.openExternalUrl(att.url);
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Could not open file: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    child: Text(
                                      att.name,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.open_in_new, size: 20, color: Colors.white60),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1F2937),
                                        title: const Text('Delete attachment?'),
                                        content: const Text('This will remove the attached file permanently.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await StorageService.deleteFile(att.url);
                                      await FirestorePaths.assignmentsCol().doc(assignment.id).update({
                                        'attachments': FieldValue.arrayRemove([att.toMap()]),
                                        'attachmentUrl': FieldValue.delete(),
                                        'attachment_url': FieldValue.delete(),
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Attachment removed.')),
                                        );
                                        Navigator.pop(context); // Close modal since data changed
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          appBar: AppBar(title: Text(student.name)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'avatar_${student.id}',
                      child: GestureDetector(
                        onTap: () => _uploadProfilePicture(student),
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(31),
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: Center(
                            child: student.profilePictureUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(30),
                                    child: Image.network(
                                      student.profilePictureUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Text(
                                        student.name.isNotEmpty
                                            ? student.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Text(
                                        student.name.isNotEmpty
                                            ? student.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
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
                            Text(
                              'PIN: ${student.pin}',
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

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
                      Row(
                        children: const [
                          Icon(Icons.mood, size: 18, color: Colors.white70),
                          SizedBox(width: 8),
                          Text(
                            'Mood',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (uid == null)
                        const Text(
                          'You must be signed in to set mood.',
                          style: TextStyle(color: Colors.redAccent),
                        )
                      else
                        MoodPicker(value: mood, onChanged: (m) => _setMood(m)),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _WalletPreviewCard(student: student),

                const SizedBox(height: 16),

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
                        value: averageGrade == 0.0
                            ? '—'
                            : averageGrade.toStringAsFixed(1),
                        label: labelAvg,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),

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
                      Row(
                        children: const [
                          Icon(
                            Icons.local_fire_department,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Streak',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  student.currentStreak.toString(),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                                const Text(
                                  'Current',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  student.longestStreak.toString(),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                                const Text(
                                  'Best',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '+${(student.streakBonusPercent * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                const Text(
                                  'Bonus',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (dueAssignments.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showDueAssignmentsModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Due Soon',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${dueAssignments.length} assignment${dueAssignments.length > 1 ? 's' : ''} • Tap to view',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: Colors.white60,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                if (overdueAssignments.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showOverdueAssignmentsModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '⚠️ Overdue',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  Text(
                                    '${overdueAssignments.length} assignment${overdueAssignments.length > 1 ? 's' : ''} • Tap to view',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: Colors.white60,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                if (achievements.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.emoji_events,
                              size: 18,
                              color: Colors.amber,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Achievements',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final badge in achievements)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.amber.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                if (completedThisWeek.isNotEmpty)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: _expandedCompletedThisWeek,
                        onExpansionChanged: (expanded) {
                          setState(() => _expandedCompletedThisWeek = expanded);
                        },
                        leading: const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Colors.green,
                        ),
                        title: Text(
                          'Completed This Week (${completedThisWeek.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        iconColor: Colors.green,
                        collapsedIconColor: Colors.green,
                        children: [
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: completedThisWeek.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white12),
                            itemBuilder: (context, i) {
                              final a = completedThisWeek[i];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  0,
                                ),
                                leading: const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  a.name,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  a.subjectName.isNotEmpty
                                      ? a.subjectName
                                      : 'No Subject',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (a.attachments.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Icon(
                                          a.attachments.any((att) => att.type == 'pdf')
                                              ? Icons.picture_as_pdf
                                              : Icons.image,
                                          size: 16,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    if (a.grade != null)
                                      Text(
                                        '${a.grade}%',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () => _showAssignmentDetailsModal(a),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: _expandedProgressBySubject,
                      onExpansionChanged: (expanded) {
                        setState(() => _expandedProgressBySubject = expanded);
                      },
                      leading: const Icon(
                        Icons.bar_chart,
                        size: 18,
                        color: Colors.blue,
                      ),
                      title: const Text(
                        'Progress by Subject',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      iconColor: Colors.blue,
                      collapsedIconColor: Colors.blue,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: progressBySubject.entries.map((entry) {
                              final subject = entry.key;
                              final completed = entry.value['completed']!;
                              final total = entry.value['total']!;
                              final percent = total > 0
                                  ? (completed / total * 100).toStringAsFixed(0)
                                  : '0';
                              final grade = gradeBySubject[subject];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subject,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '$completed/$total',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white60,
                                          ),
                                        ),
                                        if (grade != null &&
                                            !grade.toString().endsWith(
                                              '_count',
                                            ))
                                          Text(
                                            '${grade.toStringAsFixed(1)}%',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: total > 0
                                            ? completed / total
                                            : 0,
                                        minHeight: 6,
                                        backgroundColor: Colors.white10,
                                        valueColor: AlwaysStoppedAnimation(
                                          grade != null &&
                                                  !grade.toString().endsWith(
                                                    '_count',
                                                  ) &&
                                                  grade >= 80
                                              ? Colors.green
                                              : Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                FutureBuilder<Map<String, Map<String, dynamic>>>(
                  future: calculateCourseProgress(),
                  builder: (context, snapshot) {
                    final courseProgress = snapshot.data ?? {};
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;

                    if (isLoading) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (courseProgress.isNotEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.school,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Course Progress (Lessons)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...courseProgress.entries.map((entry) {
                              final courseId = entry.key;
                              final data = entry.value;
                              final completed = data['completed'] as int? ?? 0;
                              final total = data['total'] as int? ?? 0;
                              final percent =
                                  double.tryParse(
                                    data['percent'] as String? ?? '0',
                                  ) ??
                                  0.0;
                              final courseName =
                                  (data['courseName'] as String?) ?? courseId;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            courseName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '$completed/$total lessons',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: total > 0
                                                  ? completed / total
                                                  : 0,
                                              minHeight: 8,
                                              backgroundColor: Colors.white10,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                    percent >= 80
                                                        ? Colors.green
                                                        : Colors.orange,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${percent.toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  },
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
                        const Text(
                          'Notes',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          student.notes,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
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
              MaterialPageRoute(builder: (_) => RewardsPage(student: student)),
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
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 32,
                    color: Colors.white70,
                  ),
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
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
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
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: c,
            ),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
