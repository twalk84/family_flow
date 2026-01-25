// FILE: lib/screens/reward_admin_screen.dart
//
// Parent-only screen for managing rewards and fulfilling claims.
// Supports assigning rewards to specific students.
// Includes: Create/Edit/Enable-Disable/Delete reward, and fulfill pending claims.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../core/models/reward_models.dart';
import '../core/models/group_reward_model.dart';
import '../services/reward_service.dart';

class RewardAdminScreen extends StatefulWidget {
  const RewardAdminScreen({super.key});

  @override
  State<RewardAdminScreen> createState() => _RewardAdminScreenState();
}

class _RewardAdminScreenState extends State<RewardAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Color _alpha(Color c, double opacity01) {
    final o = opacity01.clamp(0.0, 1.0);
    return c.withAlpha((o * 255).round());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddRewardDialog(List<Student> students) {
    final nameController = TextEditingController();
    final pointsController = TextEditingController();
    final descController = TextEditingController();

    String? errorText;

    // Track which students are selected (empty list = all students)
    final Set<String> selectedStudentIds = <String>{};
    bool assignToAll = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Add New Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Reward Name',
                    hintText: 'e.g., Ice Cream Trip',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pointsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Point Cost',
                    hintText: 'e.g., 500',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tier will be auto-assigned:\n'
                  '🥉 Bronze: 1-499  •  🥈 Silver: 500-1499\n'
                  '🥇 Gold: 1500-2999  •  💎 Platinum: 3000+',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g., Any flavor you want!',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                const Text(
                  'Assign to Students',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                CheckboxListTile(
                  value: assignToAll,
                  onChanged: (v) {
                    setDialogState(() {
                      assignToAll = v ?? true;
                      if (assignToAll) {
                        selectedStudentIds.clear();
                      }
                    });
                  },
                  title: const Text('All Students'),
                  subtitle: const Text('Available to everyone'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                if (!assignToAll) ...[
                  const Divider(color: Colors.white12),
                  const Text(
                    'Select specific students:',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  ...students.map((student) {
                    final isSelected = selectedStudentIds.contains(student.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            selectedStudentIds.add(student.id);
                          } else {
                            selectedStudentIds.remove(student.id);
                          }
                        });
                      },
                      title: Text(student.name),
                      subtitle: Text('Grade ${student.gradeLevel}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                ],

                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              onPressed: () async {
                final name = nameController.text.trim();
                final pointsStr = pointsController.text.trim();
                final desc = descController.text.trim();

                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Name is required');
                  return;
                }

                final points = int.tryParse(pointsStr);
                if (points == null || points <= 0) {
                  setDialogState(() => errorText = 'Enter a valid point amount');
                  return;
                }

                if (!assignToAll && selectedStudentIds.isEmpty) {
                  setDialogState(() => errorText = 'Select at least one student');
                  return;
                }

                try {
                  await RewardService.instance.createReward(
                    name: name,
                    pointCost: points,
                    description: desc,
                    assignedStudentIds:
                        assignToAll ? const [] : selectedStudentIds.toList(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('Created reward: $name'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  setDialogState(() => errorText = 'Error: $e');
                }
              },
              child: const Text('Create Reward'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.studentsCol().snapshots(),
      builder: (context, studentsSnap) {
        if (studentsSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manage Rewards')),
            body: Center(
              child: Text(
                'Error loading students:\n${studentsSnap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          );
        }

        if (studentsSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final students = (studentsSnap.data?.docs ?? [])
            .map((d) => Student.fromDoc(d))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Manage Rewards'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Rewards'),
                Tab(text: 'Pending Claims'),
                Tab(text: 'Group Rewards'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Reward',
                onPressed: () => _showAddRewardDialog(students),
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _RewardsTab(
                students: students,
                onAddReward: () => _showAddRewardDialog(students),
                alpha: _alpha,
              ),
              const _PendingClaimsTab(),
              _GroupRewardsAdminTab(students: students),
            ],
          ),
        );
      },
    );
  }
}

// ========================================
// Rewards Tab
// ========================================

class _RewardsTab extends StatelessWidget {
  final List<Student> students;
  final VoidCallback onAddReward;
  final Color Function(Color, double) alpha;

  const _RewardsTab({
    required this.students,
    required this.onAddReward,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    final studentMap = {for (final s in students) s.id: s};

    return StreamBuilder<List<Reward>>(
      stream: RewardService.instance.streamAllRewards(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error loading rewards:\n${snap.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rewards = snap.data ?? [];

        if (rewards.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.card_giftcard, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'No rewards yet',
                  style: TextStyle(fontSize: 18, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: onAddReward,
                  icon: const Icon(Icons.add),
                  label: const Text('Add First Reward'),
                ),
              ],
            ),
          );
        }

        final active = rewards.where((r) => r.isActive).toList();
        final inactive = rewards.where((r) => !r.isActive).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              const Text(
                'Active Rewards',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...active.map((r) => _RewardAdminCard(
                    reward: r,
                    students: students,
                    studentMap: studentMap,
                    alpha: alpha,
                  )),
            ],
            if (inactive.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Disabled Rewards',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: alpha(Colors.white, 0.5),
                ),
              ),
              const SizedBox(height: 12),
              ...inactive.map((r) => _RewardAdminCard(
                    reward: r,
                    students: students,
                    studentMap: studentMap,
                    alpha: alpha,
                  )),
            ],
          ],
        );
      },
    );
  }
}

// ========================================
// Reward Admin Card
// ========================================

class _RewardAdminCard extends StatelessWidget {
  final Reward reward;
  final List<Student> students;
  final Map<String, Student> studentMap;
  final Color Function(Color, double) alpha;

  const _RewardAdminCard({
    required this.reward,
    required this.students,
    required this.studentMap,
    required this.alpha,
  });

  Color get _tierColor {
    switch (reward.tier) {
      case RewardTier.bronze:
        return const Color(0xFFCD7F32);
      case RewardTier.silver:
        return const Color(0xFFC0C0C0);
      case RewardTier.gold:
        return const Color(0xFFFFD700);
      case RewardTier.platinum:
        return const Color(0xFFE5E4E2);
    }
  }

  String get _assignmentLabel {
    if (reward.isForAllStudents) return 'All students';

    final names = reward.assignedStudentIds
        .map((id) => studentMap[id]?.name ?? 'Unknown')
        .toList();

    if (names.isEmpty) return 'No students selected';

    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2} more';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete reward?'),
        content: Text(
          'This permanently deletes "${reward.name}".\n\n'
          'If you only want to hide it, use Disable instead.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await RewardService.instance.deleteReward(reward.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted reward: ${reward.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showEditDialog(BuildContext context) {
    final nameController = TextEditingController(text: reward.name);
    final pointsController =
        TextEditingController(text: reward.pointCost.toString());
    final descController = TextEditingController(text: reward.description);

    String? errorText;

    final Set<String> selectedStudentIds = Set<String>.from(reward.assignedStudentIds);
    bool assignToAll = reward.isForAllStudents;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Edit Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Reward Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pointsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Point Cost',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                const Text(
                  'Assign to Students',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                CheckboxListTile(
                  value: assignToAll,
                  onChanged: (v) {
                    setDialogState(() {
                      assignToAll = v ?? true;
                      if (assignToAll) {
                        selectedStudentIds.clear();
                      }
                    });
                  },
                  title: const Text('All Students'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                if (!assignToAll) ...[
                  const Divider(color: Colors.white12),
                  ...students.map((student) {
                    final isSelected = selectedStudentIds.contains(student.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            selectedStudentIds.add(student.id);
                          } else {
                            selectedStudentIds.remove(student.id);
                          }
                        });
                      },
                      title: Text(student.name),
                      subtitle: Text('Grade ${student.gradeLevel}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                ],

                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final points = int.tryParse(pointsController.text.trim());
                final desc = descController.text.trim();

                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Name is required');
                  return;
                }
                if (points == null || points <= 0) {
                  setDialogState(() => errorText = 'Enter a valid point amount');
                  return;
                }
                if (!assignToAll && selectedStudentIds.isEmpty) {
                  setDialogState(() => errorText = 'Select at least one student');
                  return;
                }

                try {
                  await RewardService.instance.updateReward(
                    rewardId: reward.id,
                    name: name,
                    pointCost: points,
                    description: desc,
                    assignedStudentIds:
                        assignToAll ? const [] : selectedStudentIds.toList(),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                } catch (e) {
                  setDialogState(() => errorText = 'Save failed: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context) async {
    try {
      if (reward.isActive) {
        await RewardService.instance.disableReward(reward.id);
      } else {
        await RewardService.instance.enableReward(reward.id);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reward.isActive ? 'Reward disabled' : 'Reward enabled'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reward.isActive ? alpha(_tierColor, 0.4) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                reward.tier.emoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: reward.isActive ? Colors.white : Colors.white38,
                      ),
                    ),
                    Text(
                      '${reward.pointCost} points',
                      style: TextStyle(
                        color: reward.isActive ? Colors.white60 : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
              if (!reward.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alpha(Colors.red, 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Disabled',
                    style: TextStyle(color: Colors.red, fontSize: 11),
                  ),
                ),
            ],
          ),

          if (reward.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reward.description,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],

          const SizedBox(height: 10),

          Row(
            children: [
              Icon(
                reward.isForAllStudents ? Icons.people : Icons.person,
                size: 14,
                color: Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _assignmentLabel,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            'Claimed ${reward.timesClaimedTotal} times',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: () => _showEditDialog(context),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _toggleActive(context),
                icon: Icon(
                  reward.isActive ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                ),
                label: Text(reward.isActive ? 'Disable' : 'Enable'),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Colors.redAccent),
                label: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ========================================
// Pending Claims Tab
// ========================================

class _PendingClaimsTab extends StatelessWidget {
  const _PendingClaimsTab();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RewardClaim>>(
      future: RewardService.instance.getAllPendingClaims(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error loading claims:\n${snap.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final claims = snap.data ?? [];

        if (claims.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'All caught up!',
                  style: TextStyle(fontSize: 18, color: Colors.white60),
                ),
                SizedBox(height: 8),
                Text(
                  'No pending claims to fulfill',
                  style: TextStyle(color: Colors.white38),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${claims.length} pending claim${claims.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ...claims.map((c) => _PendingClaimCard(claim: c)),
          ],
        );
      },
    );
  }
}

// ========================================
// Pending Claim Card
// ========================================

class _PendingClaimCard extends StatelessWidget {
  final RewardClaim claim;

  const _PendingClaimCard({required this.claim});

  Color _alpha(Color c, double opacity01) {
    final o = opacity01.clamp(0.0, 1.0);
    return c.withAlpha((o * 255).round());
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return DateFormat('MMM d, yyyy').format(date);
  }

  Future<void> _fulfillClaim(BuildContext context) async {
    try {
      await RewardService.instance.fulfillClaim(
        studentId: claim.studentId,
        claimId: claim.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fulfilled: ${claim.rewardName} for ${claim.studentName}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _alpha(Colors.orange, 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.white60),
                    const SizedBox(width: 6),
                    Text(
                      claim.studentName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${claim.tier.emoji} ${claim.rewardName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Claimed: ${_formatDate(claim.claimedAt)}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _fulfillClaim(context),
            child: const Text('Fulfill'),
          ),
        ],
      ),
    );
  }
}

// ========================================
// Group Rewards Admin Tab
// ========================================

class _GroupRewardsAdminTab extends StatefulWidget {
  final List<Student> students;

  const _GroupRewardsAdminTab({required this.students});

  @override
  State<_GroupRewardsAdminTab> createState() => _GroupRewardsAdminTabState();
}

class _GroupRewardsAdminTabState extends State<_GroupRewardsAdminTab> {
  late RewardService _rewardService;

  @override
  void initState() {
    super.initState();
    _rewardService = RewardService.instance;
  }

  void _showCreateGroupRewardDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final pointsController = TextEditingController();
    final Set<String> selectedStudentIds = <String>{};
    bool restrictToStudents = false;
    DateTime? expiresAt;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Create Group Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Reward Name',
                    hintText: 'e.g., Movie Night Fund',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What is this reward for?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Points Needed',
                    hintText: 'e.g., 1000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // Expiration date
                Row(
                  children: [
                    Text(
                      expiresAt == null
                          ? 'No expiration'
                          : 'Expires: ${expiresAt!.toString().split(' ')[0]}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => expiresAt = picked);
                        }
                      },
                      child: const Text('Set Date'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Restrict to students checkbox
                CheckboxListTile(
                  value: restrictToStudents,
                  onChanged: (value) {
                    setDialogState(() => restrictToStudents = value ?? false);
                  },
                  title: const Text('Restrict to specific students'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (restrictToStudents) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select students:',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        ...widget.students.map((student) {
                          final isSelected =
                              selectedStudentIds.contains(student.id);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value ?? false) {
                                  selectedStudentIds.add(student.id);
                                } else {
                                  selectedStudentIds.remove(student.id);
                                }
                              });
                            },
                            title: Text(student.name,
                                style: const TextStyle(fontSize: 13)),
                            contentPadding: EdgeInsets.zero,
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                final pointsStr = pointsController.text.trim();

                if (name.isEmpty || desc.isEmpty || pointsStr.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Please fill in all required fields')),
                  );
                  return;
                }

                final points = int.tryParse(pointsStr);
                if (points == null || points <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid points value')),
                  );
                  return;
                }

                try {
                  await _rewardService.createGroupReward(
                    name: name,
                    description: desc,
                    pointsNeeded: points,
                    allowedStudentIds: restrictToStudents
                        ? selectedStudentIds.toList()
                        : const [],
                    expiresAt: expiresAt,
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Group reward created successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupRewardDetails(GroupReward groupReward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text(groupReward.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description: ${groupReward.description}'),
              const SizedBox(height: 12),
              Text(
                  'Progress: ${groupReward.pointsContributed} / ${groupReward.pointsNeeded} points'),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (groupReward.pointsContributed /
                          groupReward.pointsNeeded)
                      .clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey[700],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    groupReward.isCompleted ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Contributors: ${groupReward.contributorCount}'),
              const SizedBox(height: 8),
              if (groupReward.expiresAt != null)
                Text(
                  'Expires: ${groupReward.expiresAt!.toString().split(' ')[0]}',
                  style: const TextStyle(color: Colors.orange),
                ),
              if (groupReward.isExpired)
                const Text('EXPIRED',
                    style: TextStyle(color: Colors.red, fontSize: 14)),
              const SizedBox(height: 16),
              const Text('Student Contributions:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(groupReward.studentContributions.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .map((entry) {
                    final studentId = entry.key;
                    String studentName = 'Unknown';
                    try {
                      final student = widget.students.firstWhere((s) => s.id == studentId);
                      studentName = student.name;
                    } catch (_) {}
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(studentName),
                          Text('${entry.value} pts',
                              style: const TextStyle(color: Colors.cyan)),
                        ],
                      ),
                    );
                  })
                  .toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => _showEditGroupContributionsDialog(groupReward),
            child: const Text('Edit Contributions'),
          ),
        ],
      ),
    );
  }

  void _showEditGroupContributionsDialog(GroupReward groupReward) {
    // Initialize controllers with current values
    final controllers = <String, TextEditingController>{};
    for (var student in widget.students) {
      final currentContribution = groupReward.studentContributions[student.id] ?? 0;
      controllers[student.id] = TextEditingController(text: currentContribution.toString());
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Edit Group Contributions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Student Contributions:'),
              const SizedBox(height: 8),
              ...widget.students.map((student) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(student.name),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: controllers[student.id],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedContributions = <String, int>{};
              controllers.forEach((studentId, controller) {
                updatedContributions[studentId] = int.tryParse(controller.text) ?? 0;
              });

              try {
                await RewardService.instance.updateGroupRewardContributions(
                  groupRewardId: groupReward.id,
                  studentContributions: updatedContributions,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group contributions updated')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteGroupReward(String groupRewardId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete Group Reward?'),
        content: const Text(
            'This will permanently delete this group reward and all contributions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .doc(FirestorePaths.groupRewardDoc(groupRewardId).path)
                    .delete();

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group reward deleted')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupRewardDialog,
        tooltip: 'Create Group Reward',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _rewardService.getActiveGroupRewardsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final groupRewards = (snapshot.data?.docs ?? [])
              .map((doc) => GroupReward.fromDoc(doc as DocumentSnapshot<Map<String, dynamic>>))
              .toList()
            ..sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));

          if (groupRewards.isEmpty) {
            return const Center(
              child: Text('No group rewards yet. Create one to get started!'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: groupRewards.length,
            itemBuilder: (context, index) {
              final reward = groupRewards[index];
              return Card(
                color: const Color(0xFF2D3748),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reward.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  reward.description,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (reward.isCompleted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withAlpha(100),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'REDEEMED',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (reward.isExpired && !reward.isCompleted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(100),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'EXPIRED',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${reward.pointsContributed} / ${reward.pointsNeeded} pts',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${reward.contributorCount} contributors',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.cyan,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (reward.pointsContributed / reward.pointsNeeded)
                              .clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.grey[700],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            reward.isCompleted
                                ? Colors.green
                                : Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _showGroupRewardDetails(reward),
                            child: const Text('Details'),
                          ),
                          const SizedBox(width: 8),
                          if (!reward.isCompleted)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                try {
                                  await _rewardService
                                      .redeemGroupReward(reward.id);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Group reward marked as redeemed'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              },
                              child: const Text('Redeem'),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.red, size: 18),
                            onPressed: () =>
                                _deleteGroupReward(reward.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
