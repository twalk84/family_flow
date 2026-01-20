// FILE: lib/core/models/progress_models.dart
//
// Models for student progress tracking, badges, and daily activity.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart'; // for asInt, asDouble, asString, asBool, normalizeDueDate

// =====================
// Streak
// =====================
class Streak {
  final int current;
  final int longest;
  final String lastActivityDate; // "YYYY-MM-DD"
  final double currentBonusPercent;

  const Streak({
    required this.current,
    required this.longest,
    required this.lastActivityDate,
    required this.currentBonusPercent,
  });

  factory Streak.empty() => const Streak(
        current: 0,
        longest: 0,
        lastActivityDate: '',
        currentBonusPercent: 0.0,
      );

  factory Streak.fromMap(Map<String, dynamic>? data) {
    if (data == null) return Streak.empty();
    return Streak(
      current: asInt(data['current'], fallback: 0),
      longest: asInt(data['longest'], fallback: 0),
      lastActivityDate: asString(data['lastActivityDate'], fallback: ''),
      currentBonusPercent: asDouble(data['currentBonusPercent'], fallback: 0.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'current': current,
        'longest': longest,
        'lastActivityDate': lastActivityDate,
        'currentBonusPercent': currentBonusPercent,
      };

  Streak copyWith({
    int? current,
    int? longest,
    String? lastActivityDate,
    double? currentBonusPercent,
  }) =>
      Streak(
        current: current ?? this.current,
        longest: longest ?? this.longest,
        lastActivityDate: lastActivityDate ?? this.lastActivityDate,
        currentBonusPercent: currentBonusPercent ?? this.currentBonusPercent,
      );
}

// =====================
// Completion
// =====================
class Completion {
  final List<String> modulesCompleted;
  final List<String> lessonsCompleted;
  final List<String> chaptersCompleted;
  final List<String> readingSetsCompleted;
  final int totalAssignmentsCompleted;
  final int totalAssignmentsPossible;

  const Completion({
    required this.modulesCompleted,
    required this.lessonsCompleted,
    required this.chaptersCompleted,
    required this.readingSetsCompleted,
    required this.totalAssignmentsCompleted,
    required this.totalAssignmentsPossible,
  });

  factory Completion.empty() => const Completion(
        modulesCompleted: [],
        lessonsCompleted: [],
        chaptersCompleted: [],
        readingSetsCompleted: [],
        totalAssignmentsCompleted: 0,
        totalAssignmentsPossible: 0,
      );

  factory Completion.fromMap(Map<String, dynamic>? data) {
    if (data == null) return Completion.empty();
    return Completion(
      modulesCompleted: _stringList(data['modulesCompleted']),
      lessonsCompleted: _stringList(data['lessonsCompleted']),
      chaptersCompleted: _stringList(data['chaptersCompleted']),
      readingSetsCompleted: _stringList(data['readingSetsCompleted']),
      totalAssignmentsCompleted: asInt(data['totalAssignmentsCompleted'], fallback: 0),
      totalAssignmentsPossible: asInt(data['totalAssignmentsPossible'], fallback: 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'modulesCompleted': modulesCompleted,
        'lessonsCompleted': lessonsCompleted,
        'chaptersCompleted': chaptersCompleted,
        'readingSetsCompleted': readingSetsCompleted,
        'totalAssignmentsCompleted': totalAssignmentsCompleted,
        'totalAssignmentsPossible': totalAssignmentsPossible,
      };

  double get completionPercent => totalAssignmentsPossible > 0
      ? (totalAssignmentsCompleted / totalAssignmentsPossible * 100)
      : 0.0;
}

// =====================
// Mastery
// =====================
class Mastery {
  final Map<String, int> topicTestScores; // testId -> score %
  final List<String> masteryAchieved; // testIds with 95%+
  final List<String> flashcardBox7Categories;

  const Mastery({
    required this.topicTestScores,
    required this.masteryAchieved,
    required this.flashcardBox7Categories,
  });

  factory Mastery.empty() => const Mastery(
        topicTestScores: {},
        masteryAchieved: [],
        flashcardBox7Categories: [],
      );

  factory Mastery.fromMap(Map<String, dynamic>? data) {
    if (data == null) return Mastery.empty();

    final scoresRaw = data['topicTestScores'];
    final scores = <String, int>{};
    if (scoresRaw is Map) {
      for (final e in scoresRaw.entries) {
        scores[e.key.toString()] = asInt(e.value, fallback: 0);
      }
    }

    return Mastery(
      topicTestScores: scores,
      masteryAchieved: _stringList(data['masteryAchieved']),
      flashcardBox7Categories: _stringList(data['flashcardBox7Categories']),
    );
  }

  Map<String, dynamic> toMap() => {
        'topicTestScores': topicTestScores,
        'masteryAchieved': masteryAchieved,
        'flashcardBox7Categories': flashcardBox7Categories,
      };
}

// =====================
// Metrics (for skill courses like Typing)
// =====================
class ProgressMetrics {
  final int wpmBaseline;
  final int wpmCurrent;
  final int wpmHigh;
  final double accuracyAverage;
  final String lastTestDate;
  final int improvementBonusesEarned;

  const ProgressMetrics({
    required this.wpmBaseline,
    required this.wpmCurrent,
    required this.wpmHigh,
    required this.accuracyAverage,
    required this.lastTestDate,
    required this.improvementBonusesEarned,
  });

  factory ProgressMetrics.empty() => const ProgressMetrics(
        wpmBaseline: 0,
        wpmCurrent: 0,
        wpmHigh: 0,
        accuracyAverage: 0.0,
        lastTestDate: '',
        improvementBonusesEarned: 0,
      );

  factory ProgressMetrics.fromMap(Map<String, dynamic>? data) {
    if (data == null) return ProgressMetrics.empty();
    return ProgressMetrics(
      wpmBaseline: asInt(data['wpmBaseline'], fallback: 0),
      wpmCurrent: asInt(data['wpmCurrent'], fallback: 0),
      wpmHigh: asInt(data['wpmHigh'], fallback: 0),
      accuracyAverage: asDouble(data['accuracyAverage'], fallback: 0.0),
      lastTestDate: asString(data['lastTestDate'], fallback: ''),
      improvementBonusesEarned: asInt(data['improvementBonusesEarned'], fallback: 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'wpmBaseline': wpmBaseline,
        'wpmCurrent': wpmCurrent,
        'wpmHigh': wpmHigh,
        'accuracyAverage': accuracyAverage,
        'lastTestDate': lastTestDate,
        'improvementBonusesEarned': improvementBonusesEarned,
      };

  int get wpmImprovement => wpmCurrent - wpmBaseline;
}

// =====================
// Activity Counts (for badge unlock checks)
// =====================
class ActivityCounts {
  final int activitiesAt95Plus;
  final int activitiesAt97Plus;
  final int lessonsWithPerfectTest;

  const ActivityCounts({
    required this.activitiesAt95Plus,
    required this.activitiesAt97Plus,
    required this.lessonsWithPerfectTest,
  });

  factory ActivityCounts.empty() => const ActivityCounts(
        activitiesAt95Plus: 0,
        activitiesAt97Plus: 0,
        lessonsWithPerfectTest: 0,
      );

  factory ActivityCounts.fromMap(Map<String, dynamic>? data) {
    if (data == null) return ActivityCounts.empty();
    return ActivityCounts(
      activitiesAt95Plus: asInt(data['activitiesAt95Plus'], fallback: 0),
      activitiesAt97Plus: asInt(data['activitiesAt97Plus'], fallback: 0),
      lessonsWithPerfectTest: asInt(data['lessonsWithPerfectTest'], fallback: 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'activitiesAt95Plus': activitiesAt95Plus,
        'activitiesAt97Plus': activitiesAt97Plus,
        'lessonsWithPerfectTest': lessonsWithPerfectTest,
      };
}

// =====================
// SubjectProgress (main document)
// =====================
class SubjectProgress {
  final String subjectId;
  final String courseConfigId;

  final Streak streak;
  final Completion completion;
  final Mastery mastery;
  final ProgressMetrics metrics;
  final ActivityCounts activityCounts;

  final DateTime? updatedAt;
  final DateTime? createdAt;

  const SubjectProgress({
    required this.subjectId,
    required this.courseConfigId,
    required this.streak,
    required this.completion,
    required this.mastery,
    required this.metrics,
    required this.activityCounts,
    this.updatedAt,
    this.createdAt,
  });

  factory SubjectProgress.empty(String subjectId, {String courseConfigId = ''}) =>
      SubjectProgress(
        subjectId: subjectId,
        courseConfigId: courseConfigId,
        streak: Streak.empty(),
        completion: Completion.empty(),
        mastery: Mastery.empty(),
        metrics: ProgressMetrics.empty(),
        activityCounts: ActivityCounts.empty(),
      );

  factory SubjectProgress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SubjectProgress(
      subjectId: doc.id,
      courseConfigId: asString(data['courseConfigId'], fallback: ''),
      streak: Streak.fromMap(data['streak'] as Map<String, dynamic>?),
      completion: Completion.fromMap(data['completion'] as Map<String, dynamic>?),
      mastery: Mastery.fromMap(data['mastery'] as Map<String, dynamic>?),
      metrics: ProgressMetrics.fromMap(data['metrics'] as Map<String, dynamic>?),
      activityCounts: ActivityCounts.fromMap(data['activityCounts'] as Map<String, dynamic>?),
      updatedAt: _toDateTime(data['updatedAt']),
      createdAt: _toDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'subjectId': subjectId,
        'courseConfigId': courseConfigId,
        'streak': streak.toMap(),
        'completion': completion.toMap(),
        'mastery': mastery.toMap(),
        'metrics': metrics.toMap(),
        'activityCounts': activityCounts.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

// =====================
// BadgeEarned
// =====================
class BadgeEarned {
  final String badgeId;
  final String courseConfigId;
  final String subjectId;

  final String title;
  final String description;
  final String tier;
  final String category;

  final DateTime? unlockedAt;
  final Map<String, dynamic> triggerData;

  const BadgeEarned({
    required this.badgeId,
    required this.courseConfigId,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.tier,
    required this.category,
    this.unlockedAt,
    required this.triggerData,
  });

  factory BadgeEarned.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return BadgeEarned(
      badgeId: doc.id,
      courseConfigId: asString(data['courseConfigId'], fallback: ''),
      subjectId: asString(data['subjectId'], fallback: ''),
      title: asString(data['title'], fallback: ''),
      description: asString(data['description'], fallback: ''),
      tier: asString(data['tier'], fallback: ''),
      category: asString(data['category'], fallback: ''),
      unlockedAt: _toDateTime(data['unlockedAt']),
      triggerData: (data['triggerData'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  Map<String, dynamic> toMap() => {
        'badgeId': badgeId,
        'courseConfigId': courseConfigId,
        'subjectId': subjectId,
        'title': title,
        'description': description,
        'tier': tier,
        'category': category,
        'unlockedAt': FieldValue.serverTimestamp(),
        'triggerData': triggerData,
      };
}

// =====================
// DailyActivity
// =====================
class SubjectDailyActivity {
  final String courseConfigId;
  final List<String> categoriesCompleted;
  final int minutesPracticed;
  final int assignmentsCompleted;
  final int? wpm;
  final double? accuracy;

  const SubjectDailyActivity({
    required this.courseConfigId,
    required this.categoriesCompleted,
    required this.minutesPracticed,
    required this.assignmentsCompleted,
    this.wpm,
    this.accuracy,
  });

  factory SubjectDailyActivity.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const SubjectDailyActivity(
        courseConfigId: '',
        categoriesCompleted: [],
        minutesPracticed: 0,
        assignmentsCompleted: 0,
      );
    }
    return SubjectDailyActivity(
      courseConfigId: asString(data['courseConfigId'], fallback: ''),
      categoriesCompleted: _stringList(data['categoriesCompleted']),
      minutesPracticed: asInt(data['minutesPracticed'], fallback: 0),
      assignmentsCompleted: asInt(data['assignmentsCompleted'], fallback: 0),
      wpm: data['wpm'] == null ? null : asInt(data['wpm']),
      accuracy: data['accuracy'] == null ? null : asDouble(data['accuracy']),
    );
  }

  Map<String, dynamic> toMap() => {
        'courseConfigId': courseConfigId,
        'categoriesCompleted': categoriesCompleted,
        'minutesPracticed': minutesPracticed,
        'assignmentsCompleted': assignmentsCompleted,
        if (wpm != null) 'wpm': wpm,
        if (accuracy != null) 'accuracy': accuracy,
      };
}

class DailyActivity {
  final String date; // "YYYY-MM-DD"
  final Map<String, SubjectDailyActivity> subjectActivities; // subjectId -> activity
  final int totalMinutes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DailyActivity({
    required this.date,
    required this.subjectActivities,
    required this.totalMinutes,
    this.createdAt,
    this.updatedAt,
  });

  factory DailyActivity.empty(String date) => DailyActivity(
        date: date,
        subjectActivities: {},
        totalMinutes: 0,
      );

  factory DailyActivity.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final activitiesRaw = data['subjectActivities'];
    final activities = <String, SubjectDailyActivity>{};
    if (activitiesRaw is Map) {
      for (final e in activitiesRaw.entries) {
        activities[e.key.toString()] =
            SubjectDailyActivity.fromMap(e.value as Map<String, dynamic>?);
      }
    }

    return DailyActivity(
      date: doc.id,
      subjectActivities: activities,
      totalMinutes: asInt(data['totalMinutes'], fallback: 0),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'subjectActivities': subjectActivities.map((k, v) => MapEntry(k, v.toMap())),
        'totalMinutes': totalMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

// =====================
// Helpers
// =====================
List<String> _stringList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => e.toString()).toList();
  return [];
}

DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}