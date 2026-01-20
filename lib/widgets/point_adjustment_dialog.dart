// FILE: lib/widgets/point_adjustment_dialog.dart
//
// Dialog for parents to manually adjust a student's point balance.

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../services/reward_service.dart';

class PointAdjustmentDialog extends StatefulWidget {
  final Student student;

  const PointAdjustmentDialog({
    super.key,
    required this.student,
  });

  /// Show the dialog and return true if adjustment was made
  static Future<bool> show(BuildContext context, Student student) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => PointAdjustmentDialog(student: student),
    );
    return result ?? false;
  }

  @override
  State<PointAdjustmentDialog> createState() => _PointAdjustmentDialogState();
}

class _PointAdjustmentDialogState extends State<PointAdjustmentDialog> {
  final _pointsController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isAdding = true; // true = add, false = remove
  String? _errorText;
  bool _isLoading = false;

  @override
  void dispose() {
    _pointsController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pointsText = _pointsController.text.trim();
    final reason = _reasonController.text.trim();

    if (pointsText.isEmpty) {
      setState(() => _errorText = 'Enter a point amount');
      return;
    }

    final points = int.tryParse(pointsText);
    if (points == null || points <= 0) {
      setState(() => _errorText = 'Enter a valid positive number');
      return;
    }

    if (reason.isEmpty) {
      setState(() => _errorText = 'Please provide a reason');
      return;
    }

    final adjustedPoints = _isAdding ? points : -points;

    setState(() {
      _errorText = null;
      _isLoading = true;
    });

    try {
      await RewardService.instance.adjustPoints(
        studentId: widget.student.id,
        points: adjustedPoints,
        reason: reason,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on InsufficientBalanceException catch (e) {
      setState(() {
        _errorText = 'Cannot remove ${e.required} points. Balance is only ${e.available}.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorText = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: Text('Adjust Points for ${widget.student.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current balance
            StreamBuilder<int>(
              stream: RewardService.instance.streamWalletBalance(widget.student.id),
              builder: (context, snap) {
                final balance = snap.data ?? 0;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text('Current balance: ', style: TextStyle(color: Colors.white60)),
                      Text(
                        '$balance points',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Add/Remove toggle
            Row(
              children: [
                Expanded(
                  child: _ToggleButton(
                    label: 'Add Points',
                    icon: Icons.add,
                    isSelected: _isAdding,
                    color: Colors.green,
                    onTap: () => setState(() => _isAdding = true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ToggleButton(
                    label: 'Remove Points',
                    icon: Icons.remove,
                    isSelected: !_isAdding,
                    color: Colors.red,
                    onTap: () => setState(() => _isAdding = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Points amount
            TextField(
              controller: _pointsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Points',
                hintText: 'e.g., 50',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  _isAdding ? Icons.add : Icons.remove,
                  color: _isAdding ? Colors.green : Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Reason
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g., Bonus for helping sibling',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isAdding ? Colors.green : Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isAdding ? 'Add Points' : 'Remove Points'),
        ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white60,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}