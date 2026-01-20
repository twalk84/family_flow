// FILE: lib/screens/reward_admin_screen.dart
//
// Parent-only screen for managing rewards and fulfilling claims.
// Supports assigning rewards to specific students.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../core/models/reward_models.dart';
import '../services/reward_service.dart';

class RewardAdminScreen extends StatefulWidget {
  const RewardAdminScreen({super.key});

  @override
  State<RewardAdminScreen> createState() => _RewardAdminScreenState();
}

class _RewardAdminScreenState extends State<RewardAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    
    // Track which students are selected (empty = all students)
    Set<String> selectedStudentIds = {};
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
                
                // Student Assignment Section
                const Text(
                  'Assign to Students',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                
                // All Students toggle
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
                    assignedStudentIds: assignToAll ? [] : selectedStudentIds.toList(),
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
              ),
              const _PendingClaimsTab(),
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

  const _RewardsTab({
    required this.students,
    required this.onAddReward,
  });

  @override
  Widget build(BuildContext context) {
    final studentMap = {for (final s in students) s.id: s};

    return StreamBuilder<List<Reward>>(
      stream: RewardService.instance.streamAllRewards(),
      builder: (context, snap) {
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
              )),
            ],
            if (inactive.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Disabled Rewards',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 12),
              ...inactive.map((r) => _RewardAdminCard(
                reward: r,
                students: students,
                studentMap: studentMap,
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

  const _RewardAdminCard({
    required this.reward,
    required this.students,
    required this.studentMap,
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
    if (reward.isForAllStudents) {
      return 'All students';
    }
    final names = reward.assignedStudentIds
        .map((id) => studentMap[id]?.name ?? 'Unknown')
        .toList();
    if (names.length <= 2) {
      return names.join(', ');
    }
    return '${names.take(2).join(', ')} +${names.length - 2} more';
  }

  void _showEditDialog(BuildContext context) {
    final nameController = TextEditingController(text: reward.name);
    final pointsController = TextEditingController(text: reward.pointCost.toString());
    final descController = TextEditingController(text: reward.description);
    
    Set<String> selectedStudentIds = Set.from(reward.assignedStudentIds);
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
                
                // Student Assignment Section
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
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
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
                final points = int.tryParse(pointsController.text.trim());
                if (points == null || points <= 0) return;

                if (!assignToAll && selectedStudentIds.isEmpty) return;

                await RewardService.instance.updateReward(
                  rewardId: reward.id,
                  name: nameController.text.trim(),
                  pointCost: points,
                  description: descController.text.trim(),
                  assignedStudentIds: assignToAll ? [] : selectedStudentIds.toList(),
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleActive(BuildContext context) async {
    if (reward.isActive) {
      await RewardService.instance.disableReward(reward.id);
    } else {
      await RewardService.instance.enableReward(reward.id);
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
          color: reward.isActive
              ? _tierColor.withOpacity(0.4)
              : Colors.white12,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
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
          const SizedBox(height: 8),
          
          // Show assignment info
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
          const SizedBox(height: 4),
          Text(
            'Claimed ${reward.timesClaimedTotal} times',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
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

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return DateFormat('MMM d, yyyy').format(date);
  }

  void _fulfillClaim(BuildContext context) async {
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
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Student and reward info
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

          // Fulfill button
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
