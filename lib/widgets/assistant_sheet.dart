// FILE: lib/widgets/assistant_sheet.dart
//
// Assistant chat UI. Uses AssistantClient + runs actions via AssistantActionRunner.run(action).
// Supports both single action and list of actions.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../assistant_action_runner.dart';
import '../assistant_client.dart';
import '../firestore_paths.dart';

class AssistantSheet extends StatefulWidget {
  final String? teacherMood;
  final Future<void> Function(String? mood)? onSetTeacherMood;

  const AssistantSheet({
    super.key,
    this.teacherMood,
    this.onSetTeacherMood,
  });

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _client = AssistantClient();

  bool _sending = false;
  final List<_ChatMsg> _msgs = [];

  void _add(String role, String text) {
    setState(() => _msgs.add(_ChatMsg(role: role, text: text)));
  }

  Future<void> _runAction(dynamic action) async {
    final out = await AssistantActionRunner.run(action);
    if (out != null && out.trim().isNotEmpty) {
      _add('system', '✅ ${out.trim()}');
    }
  }

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: 'user', text: msg));
      _ctrl.clear();
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _add('system', '⚠️ You must be signed in.');
        return;
      }

      final idToken = await user.getIdToken();

      final res = await _client.chat(
        text: msg,
        familyId: FirestorePaths.familyId(),
        userId: user.uid,
        userEmail: user.email,
        idToken: idToken, // ✅ now supported
      );

      if (res.reply.trim().isNotEmpty) {
        _add('assistant', res.reply.trim());
      }

      if (res.action != null) {
        if (res.action is List) {
          for (final a in (res.action as List)) {
            await _runAction(a);
          }
        } else {
          await _runAction(res.action);
        }
      }
    } catch (e) {
      _add('system', '⚠️ Assistant failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Widget _teacherMoodPill() {
    final cb = widget.onSetTeacherMood;
    if (cb == null) return const SizedBox.shrink();

    final current = (widget.teacherMood == null || widget.teacherMood!.trim().isEmpty)
        ? null
        : widget.teacherMood!.trim();

    const moods = <String?>['�', '😔', '😐', '😊', '🤩', '😡', '😴', '🤒', '🔥', null];

    return PopupMenuButton<String?>(
      tooltip: 'Set teacher mood',
      onSelected: cb,
      itemBuilder: (_) => [
        for (final m in moods)
          PopupMenuItem<String?>(
            value: m,
            child: Text(m ?? 'Clear'),
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
            const Text('Mood:', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 8),
            Text(current ?? '🙂', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 6,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Assistant',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _teacherMoodPill(),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _msgs.length,
                  itemBuilder: (context, i) {
                    final m = _msgs[i];
                    final isUser = m.role == 'user';
                    final isSystem = m.role == 'system';

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Colors.purple.withOpacity(0.35)
                              : isSystem
                                  ? Colors.orange.withOpacity(0.18)
                                  : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          m.text,
                          style: TextStyle(color: Colors.white.withOpacity(0.92)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask me to add students, subjects, assignments…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  final String role; // user | assistant | system
  final String text;
  _ChatMsg({required this.role, required this.text});
}
