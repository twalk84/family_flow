// FILE: lib/widgets/progress_header.dart
//
// Progress header widget for Subject Detail Screen.
// Shows completion progress, badges earned, and streak info.

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/models/progress_models.dart';
import '../services/progress_service.dart';

class ProgressHeader extends StatelessWidget {
  final Student student;
  final Subject subject;

  const ProgressHeader({
    super.key,
    required this.student,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubjectProgress?>(
      stream: ProgressService.instance.streamProgress(student.id, subject.id),
      builder: (context, snap) {
        final progress = snap.data;

        // Default values if no progress yet
        final completed = progress?.completion.totalAssignmentsCompleted ?? 0;
        final total = progress?.completion.totalAssignmentsPossible ?? 0;
        final percent = total > 0 ? (completed / total * 100) : 0.0;
        final streak = progress?.streak.current ?? 0;
        final streakBonus = progress?.streak.currentBonusPercent ?? 0.0;
        final badgesEarned = progress?.completion.modulesCompleted.length ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1F2937),
                const Color(0xFF1F2937).withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COURSE PROGRESS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 12),

              // Progress bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percent / 100,
                        minHeight: 12,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _progressColor(percent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$completed of $total assignments',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),

              // Stats row
              Row(
                children: [
                  _StatBadge(
                    icon: Icons.emoji_events,
                    label: '$badgesEarned badges',
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 12),
                  if (streak > 0)
                    _StatBadge(
                      icon: Icons.local_fire_department,
                      label: '$streak day${streak == 1 ? '' : 's'}',
                      color: Colors.orange,
                      suffix: streakBonus > 0
                          ? ' (+${(streakBonus * 100).toStringAsFixed(0)}%)'
                          : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _progressColor(double percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 50) return Colors.blue;
    if (percent >= 25) return Colors.orange;
    return Colors.purple;
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? suffix;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.color,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (suffix != null)
            Text(
              suffix!,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}