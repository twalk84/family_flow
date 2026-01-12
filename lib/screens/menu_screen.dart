// FILE: lib/screens/menu_screen.dart
//
// Menu (FamilyFlow) — Polished theme pass + clickable Due Today / Overdue
//
// Fixes:
// - Due Today now navigates (same as Overdue)
// - Counts are robust: normalizeDueDate() handles Timestamp / DateTime / ISO strings
// - If count is 0, we show a helpful snack (no “dead” buttons)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../firestore_paths.dart';
import '../core/models/models.dart' show normalizeDueDate;
import 'assignment_bucket_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  void _go(BuildContext context, String route) {
    Navigator.pushNamed(context, route);
  }

  String _todayYmd() => normalizeDueDate(DateTime.now());

  String _dueAsYmd(dynamic v) => normalizeDueDate(v);

  void _snack(BuildContext context, String msg, {Color? color}) {
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

  void _openBucket(BuildContext context, AssignmentBucket bucket, int count) {
    if (count <= 0) {
      _snack(
        context,
        bucket == AssignmentBucket.dueToday
            ? 'No incomplete assignments due today.'
            : 'No overdue assignments right now.',
        color: Colors.white24,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssignmentBucketScreen(bucket: bucket)),
    );
  }

  void _showAccountSheet(BuildContext context, {required String email}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.account_circle, color: Colors.white70),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(color: Colors.white12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_outline, color: Colors.white70),
                  title: const Text('Help'),
                  subtitle: const Text('Icons & symbols explained', style: TextStyle(color: Colors.white60)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _go(context, AppRoutes.help);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('Return to login screen', style: TextStyle(color: Colors.white60)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _accountChip(BuildContext context, String email) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showAccountSheet(context, email: email),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _heroHeader(BuildContext context, String email) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.purple.withOpacity(0.35)),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FamilyFlow',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your family’s homeschool command center',
                      style: TextStyle(color: Colors.white60),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _accountChip(context, email),
        ],
      ),
    );
  }

  Widget _metricPill({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final disabled = value == '0';

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white60)),
                const SizedBox(width: 8),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _todayAtAGlance() {
    final today = _todayYmd();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.assignmentsCol().snapshots(),
      builder: (context, snap) {
        int dueToday = 0;
        int overdue = 0;

        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final data = d.data();
            final completed = (data['completed'] == true);

            final due = _dueAsYmd(data['dueDate'] ?? data['due_date']);
            if (due.isEmpty) continue;

            if (!completed && due == today) dueToday++;
            if (!completed && due.compareTo(today) < 0) overdue++;
          }
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    "Today's at a glance",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricPill(
                    context: context,
                    icon: Icons.event_available,
                    label: 'Due today',
                    value: dueToday.toString(),
                    accent: Colors.greenAccent,
                    onTap: () => _openBucket(context, AssignmentBucket.dueToday, dueToday),
                  ),
                  _metricPill(
                    context: context,
                    icon: Icons.warning_amber,
                    label: 'Overdue',
                    value: overdue.toString(),
                    accent: Colors.orangeAccent,
                    onTap: () => _openBucket(context, AssignmentBucket.overdue, overdue),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                overdue > 0
                    ? 'Tip: Open Overdue to knock those out first.'
                    : 'Nice — no overdue assignments right now.',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconTint,
  }) {
    final tint = iconTint ?? Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Signed in';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final targetW = maxW > 980 ? 980.0 : maxW;

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: targetW,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          IconButton(
                            tooltip: 'Help',
                            onPressed: () => _go(context, AppRoutes.help),
                            icon: const Icon(Icons.help_outline, color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Account',
                            onPressed: () => _showAccountSheet(context, email: email),
                            icon: const Icon(Icons.account_circle, color: Colors.white70),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            _heroHeader(context, email),
                            const SizedBox(height: 14),
                            _todayAtAGlance(),
                            const SizedBox(height: 18),
                            _sectionTitle('Quick actions'),
                            _actionCard(
                              icon: Icons.dashboard,
                              title: 'Dashboard',
                              subtitle: 'Students, assignments, and profiles',
                              onTap: () => _go(context, AppRoutes.dashboard),
                              iconTint: Colors.purpleAccent,
                            ),
                            const SizedBox(height: 12),
                            _actionCard(
                              icon: Icons.calendar_today,
                              title: 'Daily Schedule',
                              subtitle: "Today’s due items and completion",
                              onTap: () => _go(context, AppRoutes.dailySchedule),
                              iconTint: Colors.greenAccent,
                            ),
                            const SizedBox(height: 12),
                            _actionCard(
                              icon: Icons.chat_bubble_outline,
                              title: 'Assistant',
                              subtitle: 'Create students / subjects / assignments',
                              onTap: () => _go(context, AppRoutes.assistant),
                              iconTint: Colors.blueAccent,
                            ),
                            const SizedBox(height: 12),
                            _actionCard(
                              icon: Icons.help_outline,
                              title: 'Help',
                              subtitle: 'Icons & symbols explained',
                              onTap: () => _go(context, AppRoutes.help),
                              iconTint: Colors.white,
                            ),
                            const SizedBox(height: 18),
                            OutlinedButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout, color: Colors.white70),
                              label: const Text('Sign out', style: TextStyle(color: Colors.white70)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                            const SizedBox(height: 10),
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
    );
  }
}
