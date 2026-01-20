// FILE: lib/services/progress_service.dart
//
// Progress tracking service for Life OS curriculum.
// Handles: streaks, badges, completion tracking, metrics (WPM), improvement bonuses.
//
// Called by AssignmentMutations when assignments are completed.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import '../core/models/progress_models.dart';
import '../core/firestore/firestore_paths.dart';
import 'course_config_service.dart';

class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  final _cfg = CourseConfigService.instance;

  // =====================
  // Main Entry Point
  // =====================

  /// Called when an assignment is completed.
  /// Updates daily activity, streaks, completion, metrics, and checks badges.
  Future<ProgressUpdateResult> recordActivity({
    required Assignment assignment,
    required int? gradePercent,
    int? wpm,
    double? accuracy,
    int? minutesPracticed,
  }) async {
    final studentId = assignment.studentId.trim();
    final subjectId = assignment.subjectId.trim();

    if (studentId.isEmpty || subjectId.isEmpty) {
      return ProgressUpdateResult.empty();
    }

    final today = _todayString();
    final configId = await _resolveConfigId(assignment);
    final config = configId.isEmpty ? null : await _cfg.getConfig(configId);

    // Run all updates in a transaction for consistency
    return FirebaseFirestore.instance.runTransaction((tx) async {
      // 1. Get or create daily activity doc
      final dailyRef = FirestorePaths.dailyActivityDoc(studentId, today);
      final dailySnap = await tx.get(dailyRef);
      final daily = dailySnap.exists
          ? DailyActivity.fromDoc(dailySnap)
          : DailyActivity.empty(today);

      // 2. Get or create subject progress doc
      final progressRef = FirestorePaths.subjectProgressDoc(studentId, subjectId);
      final progressSnap = await tx.get(progressRef);
      final progress = progressSnap.exists
          ? SubjectProgress.fromDoc(progressSnap)
          : SubjectProgress.empty(subjectId, courseConfigId: configId);

      // 3. Update daily activity
      final updatedDaily = _updateDailyActivity(
        daily: daily,
        subjectId: subjectId,
        configId: configId,
        categoryKey: assignment.categoryKey,
        minutesPracticed: minutesPracticed,
        wpm: wpm,
        accuracy: accuracy,
      );

      // 4. Calculate new streak
      final updatedStreak = _calculateStreak(
        currentStreak: progress.streak,
        today: today,
        config: config,
      );

      // 5. Update completion tracking
      final updatedCompletion = _updateCompletion(
        completion: progress.completion,
        assignment: assignment,
        config: config,
      );

      // 6. Update mastery tracking
      final updatedMastery = _updateMastery(
        mastery: progress.mastery,
        assignment: assignment,
        gradePercent: gradePercent,
        config: config,
      );

      // 7. Update metrics (WPM, accuracy)
      final metricsResult = _updateMetrics(
        metrics: progress.metrics,
        wpm: wpm,
        accuracy: accuracy,
        config: config,
      );

      // 8. Update activity counts
      final updatedActivityCounts = _updateActivityCounts(
        counts: progress.activityCounts,
        gradePercent: gradePercent,
        categoryKey: assignment.categoryKey,
      );

      // 9. Build updated progress
      final updatedProgress = SubjectProgress(
        subjectId: subjectId,
        courseConfigId: configId,
        streak: updatedStreak,
        completion: updatedCompletion,
        mastery: updatedMastery,
        metrics: metricsResult.metrics,
        activityCounts: updatedActivityCounts,
      );

      // 10. Check for new badges
      final newBadges = await _checkBadgeUnlocks(
        tx: tx,
        studentId: studentId,
        subjectId: subjectId,
        progress: updatedProgress,
        config: config,
        wpm: wpm,
        assignment: assignment,
      );

      // 11. Write updates
      tx.set(dailyRef, updatedDaily.toMap(), SetOptions(merge: true));
      tx.set(progressRef, updatedProgress.toMap(), SetOptions(merge: true));

      return ProgressUpdateResult(
        streakCurrent: updatedStreak.current,
        streakBonusPercent: updatedStreak.currentBonusPercent,
        newBadges: newBadges,
        improvementBonusPoints: metricsResult.improvementBonus,
        wpmImprovement: metricsResult.wpmImprovement,
      );
    });
  }

  /// Called when an assignment is uncompleted (reversed).
  /// Decrements completion counts but does NOT reverse streaks or badges.
  Future<void> reverseActivity({
    required Assignment assignment,
  }) async {
    final studentId = assignment.studentId.trim();
    final subjectId = assignment.subjectId.trim();

    if (studentId.isEmpty || subjectId.isEmpty) return;

    final progressRef = FirestorePaths.subjectProgressDoc(studentId, subjectId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(progressRef);
      if (!snap.exists) return;

      final progress = SubjectProgress.fromDoc(snap);

      // Decrement completion count
      final newCompleted = (progress.completion.totalAssignmentsCompleted - 1)
          .clamp(0, double.infinity)
          .toInt();

      tx.update(progressRef, {
        'completion.totalAssignmentsCompleted': newCompleted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // =====================
  // Daily Activity
  // =====================

  DailyActivity _updateDailyActivity({
    required DailyActivity daily,
    required String subjectId,
    required String configId,
    required String categoryKey,
    int? minutesPracticed,
    int? wpm,
    double? accuracy,
  }) {
    final existing = daily.subjectActivities[subjectId];

    final categories = List<String>.from(existing?.categoriesCompleted ?? []);
    if (categoryKey.isNotEmpty && !categories.contains(categoryKey)) {
      categories.add(categoryKey);
    }

    final updatedSubjectActivity = SubjectDailyActivity(
      courseConfigId: configId,
      categoriesCompleted: categories,
      minutesPracticed: (existing?.minutesPracticed ?? 0) + (minutesPracticed ?? 0),
      assignmentsCompleted: (existing?.assignmentsCompleted ?? 0) + 1,
      wpm: wpm ?? existing?.wpm,
      accuracy: accuracy ?? existing?.accuracy,
    );

    final updatedActivities = Map<String, SubjectDailyActivity>.from(daily.subjectActivities);
    updatedActivities[subjectId] = updatedSubjectActivity;

    final totalMinutes = updatedActivities.values
        .fold<int>(0, (sum, a) => sum + a.minutesPracticed);

    return DailyActivity(
      date: daily.date,
      subjectActivities: updatedActivities,
      totalMinutes: totalMinutes,
    );
  }

  // =====================
  // Streak Calculation
  // =====================

  Streak _calculateStreak({
    required Streak currentStreak,
    required String today,
    Map<String, dynamic>? config,
  }) {
    final lastDate = currentStreak.lastActivityDate;

    // First activity ever
    if (lastDate.isEmpty) {
      return Streak(
        current: 1,
        longest: 1,
        lastActivityDate: today,
        currentBonusPercent: 0.0,
      );
    }

    // Same day — no streak change
    if (lastDate == today) {
      return currentStreak;
    }

    final lastDt = DateTime.tryParse(lastDate);
    final todayDt = DateTime.tryParse(today);

    if (lastDt == null || todayDt == null) {
      return currentStreak.copyWith(lastActivityDate: today);
    }

    final diff = todayDt.difference(lastDt).inDays;

    int newCurrent;
    if (diff == 1) {
      // Consecutive day — increment streak
      newCurrent = currentStreak.current + 1;
    } else if (diff > 1) {
      // Missed day(s) — reset streak
      final resetOnMiss = _getStreakResetOnMiss(config);
      newCurrent = resetOnMiss ? 1 : currentStreak.current + 1;
    } else {
      // diff <= 0 (shouldn't happen, but handle it)
      newCurrent = currentStreak.current;
    }

    final newLongest = newCurrent > currentStreak.longest
        ? newCurrent
        : currentStreak.longest;

    final bonusPercent = _calculateStreakBonus(newCurrent, config);

    return Streak(
      current: newCurrent,
      longest: newLongest,
      lastActivityDate: today,
      currentBonusPercent: bonusPercent,
    );
  }

  double _calculateStreakBonus(int streakDays, Map<String, dynamic>? config) {
    if (config == null) return 0.0;

    final rewards = (config['rewards'] as Map?)?.cast<String, dynamic>();
    if (rewards == null) return 0.0;

    final streak = (rewards['streak'] as Map?)?.cast<String, dynamic>();
    if (streak == null) return 0.0;

    final enabled = streak['enabled'] == true;
    if (!enabled) return 0.0;

    final maxBonus = _asDouble(streak['maxBonusPercent'], fallback: 0.5);

    // Check for bonusSchedule (new format)
    final schedule = streak['bonusSchedule'];
    if (schedule is List && schedule.isNotEmpty) {
      double bonus = 0.0;
      for (final tier in schedule) {
        if (tier is! Map) continue;
        final daysRequired = _asInt(tier['daysRequired'], fallback: 0);
        final tierBonus = _asDouble(tier['bonusPercent'], fallback: 0.0);
        if (streakDays >= daysRequired && tierBonus > bonus) {
          bonus = tierBonus;
        }
      }
      return bonus.clamp(0.0, maxBonus);
    }

    // Fallback to bonusPercentPerDay (old format)
    final perDay = _asDouble(streak['bonusPercentPerDay'], fallback: 0.01);
    return (streakDays * perDay).clamp(0.0, maxBonus);
  }

  bool _getStreakResetOnMiss(Map<String, dynamic>? config) {
    if (config == null) return true;
    final rewards = (config['rewards'] as Map?)?.cast<String, dynamic>();
    final streak = (rewards?['streak'] as Map?)?.cast<String, dynamic>();
    return streak?['resetOnMissedDay'] != false;
  }

  // =====================
  // Completion Tracking
  // =====================

  Completion _updateCompletion({
    required Completion completion,
    required Assignment assignment,
    Map<String, dynamic>? config,
  }) {
    // Increment total completed
    final newTotal = completion.totalAssignmentsCompleted + 1;

    // TODO: Track specific lesson/chapter/module completion
    // This would require parsing assignment name or metadata to determine
    // which curriculum item was completed, then checking if all items
    // in a lesson/chapter/module are done.

    return Completion(
      modulesCompleted: completion.modulesCompleted,
      lessonsCompleted: completion.lessonsCompleted,
      chaptersCompleted: completion.chaptersCompleted,
      readingSetsCompleted: completion.readingSetsCompleted,
      totalAssignmentsCompleted: newTotal,
      totalAssignmentsPossible: completion.totalAssignmentsPossible,
    );
  }

  // =====================
  // Mastery Tracking
  // =====================

  Mastery _updateMastery({
    required Mastery mastery,
    required Assignment assignment,
    int? gradePercent,
    Map<String, dynamic>? config,
  }) {
    // Only track mastery for topic tests (or other mastery-eligible categories)
    if (assignment.categoryKey != 'topic_test' || gradePercent == null) {
      return mastery;
    }

    final testId = _extractTestId(assignment);
    if (testId.isEmpty) return mastery;

    final updatedScores = Map<String, int>.from(mastery.topicTestScores);
    updatedScores[testId] = gradePercent;

    final masteryThreshold = _getMasteryThreshold(config);
    final updatedMasteryAchieved = List<String>.from(mastery.masteryAchieved);

    if (gradePercent >= masteryThreshold && !updatedMasteryAchieved.contains(testId)) {
      updatedMasteryAchieved.add(testId);
    }

    return Mastery(
      topicTestScores: updatedScores,
      masteryAchieved: updatedMasteryAchieved,
      flashcardBox7Categories: mastery.flashcardBox7Categories,
    );
  }

  String _extractTestId(Assignment assignment) {
    // Try to extract test ID from assignment name or metadata
    // Format: "Topic Test 1: Foundations" -> "topic_test_1"
    final name = assignment.name.toLowerCase();
    final match = RegExp(r'topic\s*test\s*(\d+)').firstMatch(name);
    if (match != null) {
      return 'topic_test_${match.group(1)}';
    }
    // Fallback to assignment ID
    return assignment.id;
  }

  int _getMasteryThreshold(Map<String, dynamic>? config) {
    if (config == null) return 95;

    // Check multipliers for topic_test mastery threshold
    final rewards = (config['rewards'] as Map?)?.cast<String, dynamic>();
    final multipliers = rewards?['multipliers'];

    if (multipliers is List) {
      for (final m in multipliers) {
        if (m is! Map) continue;
        final when = (m['when'] as Map?)?.cast<String, dynamic>();
        if (when?['categoryKey'] == 'topic_test') {
          return _asInt(when?['minGradePercent'], fallback: 95);
        }
      }
    }

    // Old format
    if (multipliers is Map) {
      final mastery = (multipliers['topic_test_mastery'] as Map?)?.cast<String, dynamic>();
      return _asInt(mastery?['minPercent'], fallback: 95);
    }

    return 95;
  }

  // =====================
  // Metrics (WPM, Accuracy)
  // =====================

  _MetricsResult _updateMetrics({
    required ProgressMetrics metrics,
    int? wpm,
    double? accuracy,
    Map<String, dynamic>? config,
  }) {
    if (wpm == null && accuracy == null) {
      return _MetricsResult(metrics: metrics, improvementBonus: 0, wpmImprovement: 0);
    }

    int newBaseline = metrics.wpmBaseline;
    int newCurrent = metrics.wpmCurrent;
    int newHigh = metrics.wpmHigh;
    double newAccuracyAvg = metrics.accuracyAverage;
    int improvementBonus = 0;
    int wpmImprovement = 0;

    if (wpm != null) {
      // Set baseline if not set
      if (newBaseline == 0) {
        newBaseline = wpm;
      }

      newCurrent = wpm;

      if (wpm > newHigh) {
        newHigh = wpm;
      }

      // Calculate improvement from baseline
      wpmImprovement = newCurrent - newBaseline;

      // Check for improvement bonus
      improvementBonus = _calculateImprovementBonus(
        improvement: wpmImprovement,
        currentAccuracy: accuracy,
        baselineAccuracy: newAccuracyAvg,
        config: config,
      );
    }

    if (accuracy != null) {
      // Simple rolling average (could be improved with proper windowing)
      if (newAccuracyAvg == 0) {
        newAccuracyAvg = accuracy;
      } else {
        newAccuracyAvg = (newAccuracyAvg + accuracy) / 2;
      }
    }

    final updatedMetrics = ProgressMetrics(
      wpmBaseline: newBaseline,
      wpmCurrent: newCurrent,
      wpmHigh: newHigh,
      accuracyAverage: newAccuracyAvg,
      lastTestDate: _todayString(),
      improvementBonusesEarned: metrics.improvementBonusesEarned + (improvementBonus > 0 ? 1 : 0),
    );

    return _MetricsResult(
      metrics: updatedMetrics,
      improvementBonus: improvementBonus,
      wpmImprovement: wpmImprovement,
    );
  }

  int _calculateImprovementBonus({
    required int improvement,
    double? currentAccuracy,
    double? baselineAccuracy,
    Map<String, dynamic>? config,
  }) {
    if (config == null || improvement <= 0) return 0;

    final rewards = (config['rewards'] as Map?)?.cast<String, dynamic>();
    final impBonus = (rewards?['improvementBonus'] as Map?)?.cast<String, dynamic>();

    if (impBonus == null || impBonus['enabled'] != true) return 0;

    // Check accuracy requirement
    final requiresSameOrBetter = impBonus['requiresSameOrBetterAccuracy'] == true;
    if (requiresSameOrBetter &&
        currentAccuracy != null &&
        baselineAccuracy != null &&
        currentAccuracy < baselineAccuracy) {
      return 0;
    }

    // Find matching threshold
    final thresholds = impBonus['thresholds'];
    if (thresholds is! List) return 0;

    int bonus = 0;
    for (final t in thresholds) {
      if (t is! Map) continue;
      final threshold = _asInt(t['improvement'], fallback: 0);
      final points = _asInt(t['points'], fallback: 0);
      if (improvement >= threshold && points > bonus) {
        bonus = points;
      }
    }

    return bonus;
  }

  // =====================
  // Activity Counts
  // =====================

  ActivityCounts _updateActivityCounts({
    required ActivityCounts counts,
    int? gradePercent,
    required String categoryKey,
  }) {
    if (gradePercent == null) return counts;

    int at95 = counts.activitiesAt95Plus;
    int at97 = counts.activitiesAt97Plus;
    int perfectTests = counts.lessonsWithPerfectTest;

    if (gradePercent >= 95) at95++;
    if (gradePercent >= 97) at97++;
    if (gradePercent == 100 && categoryKey == 'end_of_lesson_test') {
      perfectTests++;
    }

    return ActivityCounts(
      activitiesAt95Plus: at95,
      activitiesAt97Plus: at97,
      lessonsWithPerfectTest: perfectTests,
    );
  }

  // =====================
  // Badge Checking
  // =====================

  Future<List<BadgeEarned>> _checkBadgeUnlocks({
    required Transaction tx,
    required String studentId,
    required String subjectId,
    required SubjectProgress progress,
    Map<String, dynamic>? config,
    int? wpm,
    required Assignment assignment,
  }) async {
    if (config == null) return [];

    final badges = config['badges'];
    if (badges is! List) return [];

    final earnedBadges = <BadgeEarned>[];

    for (final badgeDef in badges) {
      if (badgeDef is! Map) continue;
      final badge = badgeDef.cast<String, dynamic>();

      final badgeId = badge['id']?.toString() ?? '';
      if (badgeId.isEmpty) continue;

      // Check if already earned
      final badgeRef = FirestorePaths.badgeEarnedDoc(studentId, badgeId);
      final existingSnap = await tx.get(badgeRef);
      if (existingSnap.exists) continue;

      // Check unlock criteria
      final unlocked = _checkBadgeCriteria(
        badge: badge,
        progress: progress,
        wpm: wpm,
      );

      if (unlocked) {
        final newBadge = BadgeEarned(
          badgeId: badgeId,
          courseConfigId: progress.courseConfigId,
          subjectId: subjectId,
          title: badge['title']?.toString() ?? '',
          description: badge['description']?.toString() ?? '',
          tier: badge['tier']?.toString() ?? '',
          category: badge['category']?.toString() ?? '',
          triggerData: {
            'assignmentId': assignment.id,
            'assignmentName': assignment.name,
            if (wpm != null) 'wpm': wpm,
          },
        );

        tx.set(badgeRef, newBadge.toMap());
        earnedBadges.add(newBadge);
      }
    }

    return earnedBadges;
  }

  bool _checkBadgeCriteria({
    required Map<String, dynamic> badge,
    required SubjectProgress progress,
    int? wpm,
  }) {
    final criteria = (badge['unlockCriteria'] as Map?)?.cast<String, dynamic>();
    if (criteria == null) return false;

    final type = criteria['type']?.toString() ?? '';

    switch (type) {
      case 'metric_threshold':
        final metric = criteria['metric']?.toString();
        final threshold = _asInt(criteria['threshold'], fallback: 0);
        if (metric == 'wpm') {
          return (wpm ?? progress.metrics.wpmCurrent) >= threshold;
        }
        return false;

      case 'streak':
        final daysRequired = _asInt(criteria['daysRequired'], fallback: 0);
        return progress.streak.current >= daysRequired;

      case 'count_threshold':
        final condition = criteria['condition']?.toString() ?? '';
        final threshold = _asInt(criteria['threshold'], fallback: 0);

        switch (condition) {
          case 'activities_at_95':
            return progress.activityCounts.activitiesAt95Plus >= threshold;
          case 'activities_at_97':
            return progress.activityCounts.activitiesAt97Plus >= threshold;
          case 'lessons_with_perfect_test':
            return progress.activityCounts.lessonsWithPerfectTest >= threshold;
          default:
            return false;
        }

      case 'module_completion':
        final moduleId = criteria['moduleId']?.toString() ?? '';
        return progress.completion.modulesCompleted.contains(moduleId);

      case 'course_completion':
        // Check if all modules are completed
        // This would need the total module count from config
        // For now, simplified check
        return false; // TODO: Implement full course completion check

      default:
        return false;
    }
  }

  // =====================
  // Helpers
  // =====================

  Future<String> _resolveConfigId(Assignment a) async {
    if (a.courseConfigId.trim().isNotEmpty) return a.courseConfigId.trim();

    if (a.subjectId.trim().isNotEmpty) {
      final subSnap = await FirestorePaths.subjectsCol().doc(a.subjectId).get();
      final data = subSnap.data();
      final v = data?['courseConfigId'] ?? data?['course_config_id'];
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }

    return '';
  }

  String _todayString() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  // =====================
  // Public Getters
  // =====================

  /// Get progress for a student in a subject
  Future<SubjectProgress?> getProgress(String studentId, String subjectId) async {
    final snap = await FirestorePaths.subjectProgressDoc(studentId, subjectId).get();
    if (!snap.exists) return null;
    return SubjectProgress.fromDoc(snap);
  }

  /// Get all badges earned by a student
  Future<List<BadgeEarned>> getBadges(String studentId) async {
    final snap = await FirestorePaths.badgesEarnedCol(studentId).get();
    return snap.docs.map((d) => BadgeEarned.fromDoc(d)).toList();
  }

  /// Get badges for a specific subject
  Future<List<BadgeEarned>> getBadgesForSubject(String studentId, String subjectId) async {
    final snap = await FirestorePaths.badgesEarnedCol(studentId)
        .where('subjectId', isEqualTo: subjectId)
        .get();
    return snap.docs.map((d) => BadgeEarned.fromDoc(d)).toList();
  }

  /// Get daily activity for a date range
  Future<List<DailyActivity>> getDailyActivities(
    String studentId, {
    required String startDate,
    required String endDate,
  }) async {
    final snap = await FirestorePaths.dailyActivityCol(studentId)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDate)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endDate)
        .get();
    return snap.docs.map((d) => DailyActivity.fromDoc(d)).toList();
  }

  /// Stream progress for real-time UI updates
  Stream<SubjectProgress?> streamProgress(String studentId, String subjectId) {
    return FirestorePaths.subjectProgressDoc(studentId, subjectId)
        .snapshots()
        .map((snap) => snap.exists ? SubjectProgress.fromDoc(snap) : null);
  }

  /// Stream badges for real-time UI updates
  Stream<List<BadgeEarned>> streamBadges(String studentId) {
    return FirestorePaths.badgesEarnedCol(studentId)
        .orderBy('unlockedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => BadgeEarned.fromDoc(d)).toList());
  }
}

// =====================
// Result Classes
// =====================

class ProgressUpdateResult {
  final int streakCurrent;
  final double streakBonusPercent;
  final List<BadgeEarned> newBadges;
  final int improvementBonusPoints;
  final int wpmImprovement;

  const ProgressUpdateResult({
    required this.streakCurrent,
    required this.streakBonusPercent,
    required this.newBadges,
    required this.improvementBonusPoints,
    required this.wpmImprovement,
  });

  factory ProgressUpdateResult.empty() => const ProgressUpdateResult(
        streakCurrent: 0,
        streakBonusPercent: 0.0,
        newBadges: [],
        improvementBonusPoints: 0,
        wpmImprovement: 0,
      );

  bool get hasBadges => newBadges.isNotEmpty;
  bool get hasImprovementBonus => improvementBonusPoints > 0;
}

class _MetricsResult {
  final ProgressMetrics metrics;
  final int improvementBonus;
  final int wpmImprovement;

  const _MetricsResult({
    required this.metrics,
    required this.improvementBonus,
    required this.wpmImprovement,
  });
}