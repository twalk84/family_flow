// FILE: lib/screens/group_rewards_tab.dart
//
// Group Rewards tab - allows students to contribute points to shared group goals.
// Shows active group rewards, progress bars, and contribution options.

import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../services/reward_service.dart';

class GroupRewardsTab extends StatefulWidget {
  final Student student;

  const GroupRewardsTab({
    super.key,
    required this.student,
  });

  @override
  State<GroupRewardsTab> createState() => _GroupRewardsTabState();
}

class _GroupRewardsTabState extends State<GroupRewardsTab> {
  final _rewardService = RewardService.instance;
  final Map<String, int> _contributionAmounts = {};

  int _getProgressPercent(Map<String, dynamic> reward) {
    final pointsNeeded = reward['pointsNeeded'] as int? ?? 0;
    if (pointsNeeded == 0) return 0;
    final pointsContributed = reward['pointsContributed'] as int? ?? 0;
    return ((pointsContributed / pointsNeeded) * 100).toInt();
  }

  int _getPointsRemaining(Map<String, dynamic> reward) {
    final pointsNeeded = reward['pointsNeeded'] as int? ?? 0;
    final pointsContributed = reward['pointsContributed'] as int? ?? 0;
    return (pointsNeeded - pointsContributed).clamp(0, pointsNeeded);
  }

  bool _isCompleted(Map<String, dynamic> reward) {
    final pointsNeeded = reward['pointsNeeded'] as int? ?? 0;
    final pointsContributed = reward['pointsContributed'] as int? ?? 0;
    return pointsContributed >= pointsNeeded;
  }

  int _getContributorCount(Map<String, dynamic> reward) {
    final contributions = reward['studentContributions'] as Map? ?? {};
    return contributions.length;
  }

  int _getStudentContribution(Map<String, dynamic> reward, String studentId) {
    final contributions = reward['studentContributions'] as Map? ?? {};
    return (contributions[studentId] as int?) ?? 0;
  }

  void _showContributionDialog(Map<String, dynamic> reward, int balance) {
    final rewardId = reward['id'] as String;
    int pledgedAmount = _contributionAmounts[rewardId] ?? 0;
    TextEditingController controller = TextEditingController(text: pledgedAmount.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Contribute to ${reward['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Help reach the group goal!',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              'Points needed: ${_getPointsRemaining(reward)} / ${reward['pointsNeeded']}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Contributors: ${_getContributorCount(reward)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Points to contribute',
                hintText: '0 - ${balance.clamp(0, _getPointsRemaining(reward))}',
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () async {
              final points = int.tryParse(controller.text) ?? 0;
              final maxAvailable = balance.clamp(0, _getPointsRemaining(reward));

              if (points <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a positive number')),
                );
                return;
              }

              if (points > maxAvailable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Only $maxAvailable points available'
                      '${balance < _getPointsRemaining(reward) ? ' (insufficient balance)' : ''}',
                    ),
                  ),
                );
                return;
              }

              try {
                await _rewardService.contributeToGroupReward(
                  groupRewardId: rewardId,
                  studentId: widget.student.id,
                  points: points,
                );

                if (mounted) {
                  setState(() {
                    _contributionAmounts[rewardId] = 0;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Contributed $points points!'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Contribute'),
          ),
        ],
      ),
    );
  }

  void _showRewardDetails(Map<String, dynamic> reward) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        color: const Color(0xFF111827),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reward['name'] as String? ?? 'Group Reward',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              reward['description'] as String? ?? '',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 24,
                child: LinearProgressIndicator(
                  value: _getProgressPercent(reward) / 100,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                    _isCompleted(reward) ? Colors.green : Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_getProgressPercent(reward)}% (${reward['pointsContributed'] as int? ?? 0}/${reward['pointsNeeded']})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _rewardService.streamWalletBalance(widget.student.id),
      builder: (context, balanceSnap) {
        final balance = balanceSnap.data ?? 0;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _rewardService.streamActiveGroupRewardsForStudent(widget.student.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final rewards = snapshot.data ?? [];

            if (rewards.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people,
                        size: 64,
                        color: Colors.white30,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No group rewards yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Group rewards will appear when the parent creates them',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rewards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final reward = rewards[index];
                final studentContribution = _getStudentContribution(reward, widget.student.id);
                final canContribute = !_isCompleted(reward) && balance > 0;

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isCompleted(reward)
                          ? Colors.green.withOpacity(0.3)
                          : Colors.blue.withOpacity(0.3),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _showRewardDetails(reward),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
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
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.people,
                                          size: 18,
                                          color: Colors.blue[400],
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            reward['name'] as String? ?? 'Group Reward',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_isCompleted(reward))
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(
                                              Icons.check_circle,
                                              size: 16,
                                              color: Colors.green,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_getContributorCount(reward)} contributors • Your contribution: $studentContribution pts',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 20,
                              child: LinearProgressIndicator(
                                value: (_getProgressPercent(reward) / 100)
                                    .clamp(0, 1)
                                    .toDouble(),
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation(
                                  _isCompleted(reward) ? Colors.green : Colors.blue,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_getProgressPercent(reward)}% (${reward['pointsContributed'] as int? ?? 0}/${reward['pointsNeeded']})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (canContribute)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.add_circle_outline, size: 18),
                                label: const Text('Contribute Points'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showContributionDialog(reward, balance),
                              ),
                            )
                          else if (_isCompleted(reward))
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.withOpacity(0.5)),
                              ),
                              child: const Center(
                                child: Text(
                                  '✓ Completed!',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                          else if (balance <= 0)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.red.withOpacity(0.5)),
                              ),
                              child: const Center(
                                child: Text(
                                  'Insufficient balance',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
