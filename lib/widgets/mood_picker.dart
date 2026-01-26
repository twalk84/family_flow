// FILE: lib/widgets/mood_picker.dart
//
// Compact mood picker used in Student Profile.
// - compact=true (default): shows only selected mood as a small pill; tap to change.
// - compact=false: shows full wrap of options.

import 'package:flutter/material.dart';
import '../app_config.dart';

class MoodPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  /// When true: shows only the selected mood (tap to change).
  /// When false: shows a wrap of all moods.
  final bool compact;

  const MoodPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = true,
  });

  static const String _noneToken = '__none__';

  @override
  Widget build(BuildContext context) {
    return compact ? _compactMenu(context) : _wrapPicker(context);
  }

  Widget _compactMenu(BuildContext context) {
    final mood = value;

    return PopupMenuButton<String>(
      tooltip: 'Change mood',
      onSelected: (v) => onChanged(v == _noneToken ? null : v),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: _noneToken,
          child: Text('Clear mood'),
        ),
        const PopupMenuDivider(),
        for (final m in AppConfig.availableMoods)
          PopupMenuItem<String>(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 22)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mood == null ? 'Mood' : 'Mood:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(mood ?? '🙂', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _wrapPicker(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip(
          context,
          label: 'None',
          selected: value == null,
          onTap: () => onChanged(null),
        ),
        for (final m in AppConfig.availableMoods)
          _chip(
            context,
            label: m,
            selected: value == m,
            onTap: () => onChanged(m),
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.purple.withOpacity(0.35) : Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.purple.withOpacity(0.6) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: label.length <= 2 ? 18 : 16, // emoji vs text
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
