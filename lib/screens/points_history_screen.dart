// FILE: lib/screens/points_history_screen.dart
//
// Full transaction history for a student - audit trail of all point changes.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../core/models/reward_models.dart';
import '../services/reward_service.dart';

class PointsHistoryScreen extends StatefulWidget {
  final Student student;

  const PointsHistoryScreen({
    super.key,
    required this.student,
  });

  @override
  State<PointsHistoryScreen> createState() => _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends State<PointsHistoryScreen> {
  String _filterType = 'all'; // all, earnings, spending

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Points History'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final targetW = maxW > 600 ? 600.0 : maxW;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: targetW,
              child: Column(
                children: [
                  // Balance header
                  _BalanceHeader(studentId: widget.student.id),

                  // Filter chips
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _filterType == 'all',
                          onTap: () => setState(() => _filterType = 'all'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Earnings',
                          selected: _filterType == 'earnings',
                          onTap: () => setState(() => _filterType = 'earnings'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Spending',
                          selected: _filterType == 'spending',
                          onTap: () => setState(() => _filterType = 'spending'),
                        ),
                      ],
                    ),
                  ),

                  // Transaction list
                  Expanded(
                    child: StreamBuilder<List<WalletTransaction>>(
                      stream: RewardService.instance.streamWalletHistory(
                        widget.student.id,
                        limit: 100,
                      ),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        var transactions = snap.data ?? [];

                        // Apply filter
                        if (_filterType == 'earnings') {
                          transactions = transactions.where((t) => t.isEarning).toList();
                        } else if (_filterType == 'spending') {
                          transactions = transactions.where((t) => t.isSpending).toList();
                        }

                        if (transactions.isEmpty) {
                          return const Center(
                            child: Text(
                              'No transactions yet',
                              style: TextStyle(color: Colors.white60),
                            ),
                          );
                        }

                        // Group by date
                        final grouped = _groupByDate(transactions);

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: grouped.length,
                          itemBuilder: (context, index) {
                            final group = grouped[index];
                            return _DateGroup(
                              date: group.date,
                              transactions: group.transactions,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_TransactionGroup> _groupByDate(List<WalletTransaction> transactions) {
    final Map<String, List<WalletTransaction>> byDate = {};

    for (final txn in transactions) {
      final date = txn.createdAt != null
          ? DateFormat('yyyy-MM-dd').format(txn.createdAt!)
          : 'Unknown';
      byDate.putIfAbsent(date, () => []).add(txn);
    }

    final groups = byDate.entries
        .map((e) => _TransactionGroup(date: e.key, transactions: e.value))
        .toList();

    // Sort by date descending
    groups.sort((a, b) => b.date.compareTo(a.date));

    return groups;
  }
}

class _TransactionGroup {
  final String date;
  final List<WalletTransaction> transactions;

  _TransactionGroup({required this.date, required this.transactions});
}

// ========================================
// Balance Header
// ========================================

class _BalanceHeader extends StatelessWidget {
  final String studentId;

  const _BalanceHeader({required this.studentId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: RewardService.instance.streamWalletBalance(studentId),
      builder: (context, snap) {
        final balance = snap.data ?? 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1F2937),
            border: Border(
              bottom: BorderSide(color: Colors.white12),
            ),
          ),
          child: Column(
            children: [
              const Text(
                'Current Balance',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 4),
              Text(
                '$balance points',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
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
// Filter Chip
// ========================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.purple : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ========================================
// Date Group
// ========================================

class _DateGroup extends StatelessWidget {
  final String date;
  final List<WalletTransaction> transactions;

  const _DateGroup({
    required this.date,
    required this.transactions,
  });

  String get _displayDate {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final txnDate = DateTime(parsed.year, parsed.month, parsed.day);

    if (txnDate == today) return 'Today';
    if (txnDate == yesterday) return 'Yesterday';

    return DateFormat('MMMM d, yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _displayDate,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white60,
            ),
          ),
        ),
        ...transactions.map((txn) => _TransactionCard(transaction: txn)),
      ],
    );
  }
}

// ========================================
// Transaction Card
// ========================================

class _TransactionCard extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionCard({required this.transaction});

  IconData get _icon {
    switch (transaction.type) {
      case WalletTransactionType.deposit:
        return Icons.add_circle;
      case WalletTransactionType.reversal:
        return Icons.remove_circle;
      case WalletTransactionType.redemption:
        return Icons.card_giftcard;
      case WalletTransactionType.adjustment:
        return Icons.edit;
      case WalletTransactionType.streakBonus:
        return Icons.local_fire_department;
      case WalletTransactionType.improvementBonus:
        return Icons.trending_up;
    }
  }

  Color get _iconColor {
    if (transaction.isEarning) return Colors.green;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final points = transaction.points;
    final isPositive = points > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: _iconColor, size: 20),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.displayTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (transaction.displaySubtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    transaction.displaySubtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
                // Show grade if available
                if (transaction.gradePercent != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Score: ${transaction.gradePercent}%',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Points
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (isPositive ? Colors.green : Colors.red).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${isPositive ? '+' : ''}$points',
              style: TextStyle(
                color: isPositive ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}