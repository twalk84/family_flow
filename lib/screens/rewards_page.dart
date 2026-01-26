// FILE: lib/screens/rewards_page.dart
//
// Student rewards page - wallet hub, reward store, navigation to history.
// Only shows rewards assigned to the current student.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../core/models/reward_models.dart';
import '../services/reward_service.dart';
import '../firestore_paths.dart';
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
  final _rewardService = RewardService.instance;
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

  Future<void> _updateAllocation(Reward reward, int currentAllocation, int newAmount, int balance) async {
    try {
      await _rewardService.setAllocation(
        studentId: widget.student.id,
        rewardId: reward.id,
        rewardName: reward.name,
        newAmount: newAmount,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Allocation updated for ${reward.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 1500),
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

  void _showPointAllocationDialog(Reward reward, int balance, int currentAllocation) {
    TextEditingController controller = TextEditingController(text: currentAllocation.toString());
    // Points available to allocate = Wallet Balance (because allocated points are already deducted)
    // Wait, if I am increasing allocation, I need more points from wallet.
    // If I am decreasing, I get points back.
    // So "Max Available" for NEW allocation = Current Allocation + Wallet Balance.
    final maxPotentialAllocation = currentAllocation + balance;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
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
            const SizedBox(height: 8),
            Text(
              'Currently allocated: $currentAllocation points',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Wallet balance: $balance points',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Total to allocate',
                // Max is reward cost or what they can afford
                hintText: '0 - ${reward.pointCost < maxPotentialAllocation ? reward.pointCost : maxPotentialAllocation}',
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
          if (currentAllocation > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _updateAllocation(reward, currentAllocation, 0, balance);
              },
              child: const Text('Clear Allocation', style: TextStyle(color: Colors.redAccent)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            onPressed: () {
              final points = int.tryParse(controller.text) ?? 0;
              final maxAffordable = maxPotentialAllocation;
              
              if (points < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cannot allocate negative points')),
                );
                return;
              }
              if (points > reward.pointCost) {
                 ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Cannot allocate more than cost (${reward.pointCost})')),
                );
                return;
              }
              if (points > maxAffordable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Not enough points (Max: $maxAffordable)')),
                );
                return;
              }
              
              if (points == currentAllocation) {
                Navigator.pop(context);
                return;
              }

              Navigator.pop(context);
              _updateAllocation(reward, currentAllocation, points, balance);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
    // Wrap in StreamBuilder to get real-time student updates (for rewardAllocations)
    return StreamBuilder<DocumentSnapshot>(
      stream: FirestorePaths.studentDoc(widget.student.id).snapshots(),
      builder: (context, studentSnap) {
        if (!studentSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Parse latest student data
        final currentStudent = Student.fromDoc(studentSnap.data as DocumentSnapshot<Map<String, dynamic>>);
        
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
                    _WalletCard(student: currentStudent),
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
                      student: currentStudent,
                      onAllocate: _showPointAllocationDialog,
                      onClaim: _showClaimConfirmation,
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
      },
    );
  }
}

// ========================================
// Wallet Card
// ========================================

class _WalletCard extends StatelessWidget {
  final Student student;

  const _WalletCard({required this.student});

  @override
  Widget build(BuildContext context) {
    final balance = student.walletBalance;

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
  }
}

// ========================================
// Rewards List - Filtered for current student
// ========================================

class _RewardsList extends StatelessWidget {
  final Student student;
  final void Function(Reward reward, int balance, int currentAllocation) onAllocate;
  final void Function(Reward reward, int balance) onClaim;

  const _RewardsList({
    required this.student,
    required this.onAllocate,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final balance = student.walletBalance;
    final allocations = student.rewardAllocations;

    // Use the student-filtered stream
    return StreamBuilder<List<Reward>>(
      stream: RewardService.instance.streamActiveRewardsForStudent(student.id),
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
              onAllocate: () => onAllocate(reward, balance, allocations[reward.id] ?? 0),
              onClaim: () => onClaim(reward, balance),
            );
          }).toList(),
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
  final VoidCallback onClaim;

  const _RewardCard({
    required this.reward,
    required this.balance,
    required this.allocatedPoints,
    required this.onAllocate,
    required this.onClaim,
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
    // Needed: cost - allocated. If allocated > cost (shouldn't happen), then 0 needed.
    // Wait, reward.pointsNeeded(balance) uses wallet balance.
    // We want to show how much MORE is needed.
    // Points needed = Reward Cost - Allocated - Wallet Balance.
    // But points are already deducted from wallet when allocated.
    // So if Cost=100, Allocated=40, Wallet=10.
    // User has effectively 50 points (40 already paid, 10 available).
    // Needed = 100 - 40 - 10 = 50.
    
    final remainingCost = reward.pointCost - allocatedPoints;
    final actuallyCanAfford = balance >= remainingCost;
    final pointsShort = remainingCost - balance;

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
                      Row(
                        children: [
                          Text(
                            '$allocatedPoints allocated',
                            style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (remainingCost > 0)
                            Text(
                              '$remainingCost left',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
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
                  
                if (!actuallyCanAfford && allocatedPoints == 0)
                   // Fallback logic if nothing allocated
                   Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Need ${reward.pointCost - balance} more',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else if (!actuallyCanAfford)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Need $pointsShort more',
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
          Column(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: onAllocate,
                child: const Text('Allocate'),
              ),
              if (allocatedPoints > 0 && actuallyCanAfford)
                 Padding(
                   padding: const EdgeInsets.only(top: 8),
                   child: SizedBox(
                     height: 30,
                     child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: onClaim,
                        child: const Text('Claim', style: TextStyle(fontSize: 12)),
                     ),
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
