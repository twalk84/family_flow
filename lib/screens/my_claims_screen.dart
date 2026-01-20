// FILE: lib/screens/my_claims_screen.dart
//
// Student's reward claim history - pending and fulfilled claims.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../core/models/reward_models.dart';
import '../services/reward_service.dart';

class MyClaimsScreen extends StatelessWidget {
  final Student student;

  const MyClaimsScreen({
    super.key,
    required this.student,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Claims'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final targetW = maxW > 600 ? 600.0 : maxW;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: targetW,
              child: StreamBuilder<List<RewardClaim>>(
                stream: RewardService.instance.streamClaimsForStudent(student.id),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final claims = snap.data ?? [];

                  if (claims.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              size: 64,
                              color: Colors.white24,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No claims yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white60,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Claim rewards from your Rewards page\nto see them here!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Separate pending and fulfilled
                  final pending = claims.where((c) => c.isPending).toList();
                  final fulfilled = claims.where((c) => c.isFulfilled).toList();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (pending.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Pending',
                          subtitle: '${pending.length} awaiting fulfillment',
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        ...pending.map((c) => _ClaimCard(claim: c)),
                        const SizedBox(height: 24),
                      ],
                      if (fulfilled.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Fulfilled',
                          subtitle: '${fulfilled.length} completed',
                          color: Colors.green,
                        ),
                        const SizedBox(height: 12),
                        ...fulfilled.map((c) => _ClaimCard(claim: c)),
                      ],
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================================
// Section Header
// ========================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ========================================
// Claim Card
// ========================================

class _ClaimCard extends StatelessWidget {
  final RewardClaim claim;

  const _ClaimCard({required this.claim});

  Color get _tierColor {
    switch (claim.tier) {
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

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isPending = claim.isPending;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending
              ? Colors.orange.withOpacity(0.3)
              : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Tier icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _tierColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _tierColor.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(
                claim.tier.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  claim.rewardName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Claimed: ${_formatDate(claim.claimedAt)}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                if (claim.isFulfilled && claim.fulfilledAt != null) ...[
                  Text(
                    'Fulfilled: ${_formatDate(claim.fulfilledAt)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Cost: ${claim.pointCost} points',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (isPending ? Colors.orange : Colors.green).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isPending ? Colors.orange : Colors.green).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  claim.status.emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  claim.status.displayName,
                  style: TextStyle(
                    color: isPending ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}