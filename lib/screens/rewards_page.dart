// FILE: lib/screens/rewards_page.dart
//
// Student rewards page - wallet hub, reward store, navigation to history.
// Only shows rewards assigned to the current student.

import 'package:flutter/material.dart';

import '../models.dart';
import '../core/models/reward_models.dart';
import '../services/reward_service.dart';
import 'points_history_screen.dart';
import 'my_claims_screen.dart';
import 'group_rewards_tab.dart';

class RewardsPage extends StatefulWidget {
  final Student student;

  const RewardsPage({
    super.key,
    required this.student,
  });

  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> with TickerProviderStateMixin {
  // ...existing code...
  final _rewardService = RewardService.instance;
  late TabController _tabController;
  
  // Point allocation tracking: rewardId -> points allocated
  final Map<String, int> _allocations = {};
  int _totalAllocated = 0;

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

  void _updateAllocation(String rewardId, int points) {
    setState(() {
      if (points <= 0) {
        _allocations.remove(rewardId);
      } else {
        _allocations[rewardId] = points;
      }
      _totalAllocated = _allocations.values.fold(0, (a, b) => a + b);
    });
  }

  void _showPointAllocationDialog(Reward reward, int balance) {
    int allocatedPoints = _allocations[reward.id] ?? 0;
    TextEditingController controller = TextEditingController(text: allocatedPoints.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Allocate Points to ${reward.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reward cost: ${reward.pointCost} points',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              'Available: ${balance - _totalAllocated + allocatedPoints} points',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Points to allocate',
                hintText: '0 - ${balance - _totalAllocated + allocatedPoints}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateAllocation(reward.id, 0);
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            onPressed: () {
              final points = int.tryParse(controller.text) ?? 0;
              final maxAvailable = balance - _totalAllocated + allocatedPoints;
              if (points < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cannot allocate negative points')),
                );
                return;
              }
              if (points > maxAvailable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Only $maxAvailable points available')),
                );
                return;
              }
              _updateAllocation(reward.id, points);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAllocationSummary(int balance) {
    if (_allocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points allocated yet')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Confirm Point Allocations'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current balance: $balance points',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(
                'Total allocating: $_totalAllocated points',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Remaining: ${balance - _totalAllocated} points',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Allocations:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._allocations.entries.map((entry) {
                return Text(
                  '• ${entry.key}: ${entry.value} points',
                  style: const TextStyle(color: Colors.white70),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _applyAllocations();
            },
            child: const Text('Confirm All'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyAllocations() async {
    try {
      for (final entry in _allocations.entries) {
        final rewardId = entry.key;

        // Claim the reward
        await _rewardService.claimReward(
          studentId: widget.student.id,
          studentName: widget.student.name,
          rewardId: rewardId,
        );
      }

      if (!mounted) return;
      setState(() => _allocations.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rewards claimed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showClaimConfirmation(Reward reward, int balance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Claim ${reward.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will cost ${reward.pointCost} points.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Your balance after: ${balance - reward.pointCost} points',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _claimReward(reward);
            },
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }

  Future<void> _claimReward(Reward reward) async {
    try {
      await _rewardService.claimReward(
        studentId: widget.student.id,
        studentName: widget.student.name,
        rewardId: reward.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Claimed ${reward.name}!'),
          backgroundColor: Colors.green,
        ),
      );
    } on InsufficientBalanceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Not enough points. Need ${e.shortfall} more.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.student.name}'s Rewards"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Individual Rewards'),
            Tab(text: 'Group Rewards'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildIndividualRewardsTab(),
          GroupRewardsTab(student: widget.student),
        ],
      ),
    );
  }

  Widget _buildIndividualRewardsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final targetW = maxW > 600 ? 600.0 : maxW;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: targetW,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Wallet Card
                _WalletCard(studentId: widget.student.id),
                const SizedBox(height: 20),

                // Available Rewards
                const Text(
                  'Available Rewards',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _RewardsList(
                  studentId: widget.student.id,
                  onAllocate: _showPointAllocationDialog,
                  allocations: _allocations,
                ),
                const SizedBox(height: 12),
                // Confirm allocations button
                StreamBuilder<int>(
                  stream: RewardService.instance.streamWalletBalance(widget.student.id),
                  builder: (context, balanceSnap) {
                    final balance = balanceSnap.data ?? 0;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: Text(
                          _totalAllocated > 0
                              ? 'Confirm Allocations ($_totalAllocated points)'
                              : 'No allocations yet',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _totalAllocated > 0 ? Colors.green : Colors.grey,
                        ),
                        onPressed: _totalAllocated > 0
                            ? () => _showAllocationSummary(balance)
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Navigation buttons
                Row(
                  children: [
                    Expanded(
                      child: _NavButton(
                        icon: Icons.history,
                        label: 'Points History',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PointsHistoryScreen(
                              student: widget.student,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NavButton(
                        icon: Icons.card_giftcard,
                        label: 'My Claims',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyClaimsScreen(
                              student: widget.student,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ========================================
// Wallet Card
// ========================================

class _WalletCard extends StatelessWidget {
  final String studentId;

  const _WalletCard({required this.studentId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: RewardService.instance.streamWalletBalance(studentId),
      builder: (context, balanceSnap) {
        final balance = balanceSnap.data ?? 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '💰 WALLET',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$balance',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                'points',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ========================================
// Rewards List - Filtered for current student
// ========================================

class _RewardsList extends StatelessWidget {
  final String studentId;
  final void Function(Reward reward, int balance) onAllocate;
  final Map<String, int> allocations;

  const _RewardsList({
    required this.studentId,
    required this.onAllocate,
    required this.allocations,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: RewardService.instance.streamWalletBalance(studentId),
      builder: (context, balanceSnap) {
        final balance = balanceSnap.data ?? 0;

        // Use the student-filtered stream
        return StreamBuilder<List<Reward>>(
          stream: RewardService.instance.streamActiveRewardsForStudent(studentId),
          builder: (context, rewardsSnap) {
            if (rewardsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final rewards = rewardsSnap.data ?? [];

            if (rewards.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Center(
                  child: Text(
                    'No rewards available yet.\nAsk your parent to add some!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              );
            }

            return Column(
              children: rewards.map((reward) {
                return _RewardCard(
                  reward: reward,
                  balance: balance,
                  allocatedPoints: allocations[reward.id] ?? 0,
                  onAllocate: () => onAllocate(reward, balance),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

// ========================================
// Reward Card
// ========================================

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final int balance;
  final int allocatedPoints;
  final VoidCallback onAllocate;

  const _RewardCard({
    required this.reward,
    required this.balance,
    required this.allocatedPoints,
    required this.onAllocate,
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

  @override
  Widget build(BuildContext context) {
    final canAfford = reward.canAfford(balance);
    final pointsNeeded = reward.pointsNeeded(balance);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white12,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Tier badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _tierColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _tierColor.withOpacity(0.5)),
            ),
            child: Center(
              child: Text(
                reward.tier.emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name and cost
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                if (allocatedPoints > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${reward.pointCost} points total',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${reward.pointCost - allocatedPoints} remaining',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    '${reward.pointCost} points',
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                if (!canAfford && allocatedPoints == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Need $pointsNeeded more',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (reward.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reward.description,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Allocate button (always visible)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: onAllocate,
            child: const Text('Allocate'),
          ),
        ],
      ),
    );
  }
}

// ========================================
// Navigation Button
// ========================================

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: Colors.white70),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
