import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const String routeName = '/help';

  @override
  Widget build(BuildContext context) {
    final sections = <_HelpSection>[
      _HelpSection(
        title: 'Assistant',
        items: const [
          _HelpItem(
            leading: Icon(Icons.smart_toy_outlined),
            title: 'AI Assistant',
            description:
                'Chat interface that can suggest actions (like adding assignments) and the app can execute them.',
          ),
          _HelpItem(
            leading: _Emoji('🟣'),
            title: 'Your message bubble',
            description: 'Messages you send appear aligned to the right.',
          ),
          _HelpItem(
            leading: _Emoji('⚙️'),
            title: 'System message',
            description:
                'Status updates from the app (auth warnings, action results, configuration hints).',
          ),
          _HelpItem(
            leading: Icon(Icons.link_off),
            title: 'Connection error',
            description:
                'Means the app could not reach the assistant endpoint (URL wrong, service down, or blocked).',
          ),
        ],
      ),
      _HelpSection(
        title: 'Assignments',
        items: const [
          _HelpItem(
            leading: _Emoji('✅'),
            title: 'Completed',
            description: 'The assignment was marked done.',
          ),
          _HelpItem(
            leading: _Emoji('⏳'),
            title: 'Pending',
            description: 'Not completed yet.',
          ),
          _HelpItem(
            leading: _Emoji('📅'),
            title: 'Due date',
            description: 'The date/time the assignment is due.',
          ),
          _HelpItem(
            leading: _Emoji('⚠️'),
            title: 'Needs attention',
            description: 'Warnings (missing setup, auth issues, invalid response, etc.).',
          ),
        ],
      ),
      _HelpSection(
        title: 'Students',
        items: const [
          _HelpItem(
            leading: Icon(Icons.person_outline),
            title: 'Student',
            description: 'A student profile in your roster.',
          ),
          _HelpItem(
            leading: Icon(Icons.archive_outlined),
            title: 'Archived',
            description:
                'Hidden from normal views (used later for “delete student” safer behavior).',
          ),
        ],
      ),
      _HelpSection(
        title: 'Security',
        items: const [
          _HelpItem(
            leading: Icon(Icons.lock_outline),
            title: 'Protected action',
            description:
                'Some actions require extra confirmation (PIN or re-auth) before they run.',
          ),
        ],
      ),
      _HelpSection(
        title: 'Coming soon',
        items: const [
          _HelpItem(
            leading: _Emoji('😊'),
            title: 'Mood',
            description:
                'Mood per student (next feature). You’ll pick an emoji that represents how they’re doing.',
          ),
          _HelpItem(
            leading: _Emoji('⭐'),
            title: 'Points / Achievements',
            description:
                'Later: points awarded on completion + prizes / redemptions with history.',
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Symbols')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: sections.length,
        itemBuilder: (context, index) => _SectionCard(section: sections[index]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _HelpSection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          children: section.items.map((item) {
            return ListTile(
              leading: item.leading,
              title: Text(item.title),
              subtitle: Text(item.description),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _HelpSection {
  final String title;
  final List<_HelpItem> items;
  _HelpSection({required this.title, required this.items});
}

class _HelpItem {
  final Widget leading;
  final String title;
  final String description;
  const _HelpItem({
    required this.leading,
    required this.title,
    required this.description,
  });
}

class _Emoji extends StatelessWidget {
  final String emoji;
  const _Emoji(this.emoji);

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white10,
      child: Text(emoji, style: const TextStyle(fontSize: 18)),
    );
  }
}
