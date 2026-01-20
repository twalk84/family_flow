// FILE: lib/screens/student_selection_screen.dart
//
// Student selection screen with PIN protection.
// Entry point after login - user selects which profile to use.
//
// Flow:
// - Student PIN → StudentProfileScreen (read-only student view)
// - Parent PIN → DashboardScreen (full admin access)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models.dart';
import '../services/reward_service.dart';
import 'student_profile_screen.dart';
import 'dashboard_screen.dart';

class StudentSelectionScreen extends StatefulWidget {
  const StudentSelectionScreen({super.key});

  @override
  State<StudentSelectionScreen> createState() => _StudentSelectionScreenState();
}

class _StudentSelectionScreenState extends State<StudentSelectionScreen> {
  final List<Color> _fallbackPalette = const [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.pink,
    Colors.orange,
    Colors.teal,
    Colors.red,
    Colors.amber,
  ];

  Color _studentColor(Student s, int index) {
    final v = s.colorValue;
    if (v != 0) return Color(v);
    return _fallbackPalette[index % _fallbackPalette.length];
  }

  void _onStudentTap(Student student, Color color, List<Assignment> assignments) {
    // If student has no PIN, go directly to their profile
    if (student.pin.isEmpty) {
      _navigateToStudentProfile(student, color, assignments);
      return;
    }

    // Otherwise, prompt for PIN
    _showPinDialog(
      context: context,
      title: 'Enter PIN for ${student.name}',
      expectedPin: student.pin,
      onSuccess: () => _navigateToStudentProfile(student, color, assignments),
    );
  }

  void _navigateToStudentProfile(Student student, Color color, List<Assignment> assignments) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentProfileScreen(
          student: student,
          color: color,
          assignments: assignments.where((a) => a.studentId == student.id).toList(),
        ),
      ),
    );
  }

  void _onParentModeTap() async {
    final isPinSet = await RewardService.instance.isParentPinSet();

    if (!isPinSet) {
      // First time - prompt to set PIN
      if (!mounted) return;
      _showSetParentPinDialog();
      return;
    }

    if (!mounted) return;
    _showPinDialog(
      context: context,
      title: 'Enter Parent PIN',
      verifyWithFirestore: true,
      onSuccess: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DashboardScreen(),
          ),
        );
      },
    );
  }

  void _showSetParentPinDialog() {
    String pin = '';
    String confirmPin = '';
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('Set Parent PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create a PIN to protect parent mode.\nThis gives full access to manage students, rewards, and settings.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'PIN (4-6 digits)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onChanged: (v) => pin = v,
              ),
              const SizedBox(height: 12),
              TextField(
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onChanged: (v) => confirmPin = v,
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (pin.isEmpty || pin.length < 4) {
                  setDialogState(() => errorText = 'PIN must be at least 4 digits');
                  return;
                }
                if (pin != confirmPin) {
                  setDialogState(() => errorText = 'PINs do not match');
                  return;
                }

                await RewardService.instance.setParentPin(pin);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                // Now enter parent mode
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DashboardScreen(),
                  ),
                );
              },
              child: const Text('Set PIN'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinDialog({
    required BuildContext context,
    required String title,
    String? expectedPin,
    bool verifyWithFirestore = false,
    required VoidCallback onSuccess,
  }) {
    String enteredPin = '';
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PinInput(
                onPinChanged: (pin) => enteredPin = pin,
                onSubmit: () async {
                  bool valid = false;

                  if (verifyWithFirestore) {
                    valid = await RewardService.instance.verifyParentPin(enteredPin);
                  } else {
                    // Student PIN - empty PIN means no protection
                    if (expectedPin == null || expectedPin.isEmpty) {
                      valid = true;
                    } else {
                      valid = enteredPin == expectedPin;
                    }
                  }

                  if (valid) {
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    onSuccess();
                  } else {
                    setDialogState(() => errorText = 'Incorrect PIN');
                  }
                },
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    "Who's Learning Today?",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select your profile to continue',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: _buildStudentGrid(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestorePaths.studentsCol().snapshots(),
      builder: (context, studentsSnap) {
        if (studentsSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (studentsSnap.hasError) {
          return Center(child: Text('Error: ${studentsSnap.error}'));
        }

        final studentDocs = studentsSnap.data?.docs ?? [];
        final students = studentDocs.map((d) => Student.fromDoc(d)).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // Also stream assignments so we can pass them to StudentProfileScreen
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestorePaths.assignmentsCol().snapshots(),
          builder: (context, assignmentsSnap) {
            final assignmentDocs = assignmentsSnap.data?.docs ?? [];
            
            // Build lookup maps
            final studentsById = {for (final s in students) s.id: s};
            
            // We need subjects too for Assignment.fromDoc
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestorePaths.subjectsCol().snapshots(),
              builder: (context, subjectsSnap) {
                final subjectDocs = subjectsSnap.data?.docs ?? [];
                final subjects = subjectDocs.map((d) => Subject.fromDoc(d)).toList();
                final subjectsById = {for (final s in subjects) s.id: s};

                final assignments = assignmentDocs
                    .map((d) => Assignment.fromDoc(
                          d,
                          studentsById: studentsById,
                          subjectsById: subjectsById,
                        ))
                    .toList();

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: students.length + 1, // +1 for parent mode
                  itemBuilder: (context, index) {
                    if (index == students.length) {
                      // Parent mode card
                      return _ProfileCard(
                        label: 'Parent Mode',
                        color: Colors.grey.shade700,
                        icon: Icons.admin_panel_settings,
                        hasPin: true,
                        subtitle: 'Full access',
                        onTap: _onParentModeTap,
                      );
                    }

                    final student = students[index];
                    final color = _studentColor(student, index);
                    final hasPin = student.pin.isNotEmpty;

                    // Count assignments for this student
                    final studentAssignments = assignments.where((a) => a.studentId == student.id).toList();
                    final completed = studentAssignments.where((a) => a.isCompleted).length;
                    final total = studentAssignments.length;

                    return _ProfileCard(
                      label: student.name,
                      color: color,
                      icon: Icons.person,
                      hasPin: hasPin,
                      subtitle: total > 0 ? '$completed/$total done' : 'No assignments',
                      onTap: () => _onStudentTap(student, color, assignments),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ========================================
// Profile Card Widget
// ========================================

class _ProfileCard extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool hasPin;
  final String? subtitle;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.label,
    required this.color,
    required this.icon,
    required this.hasPin,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              if (hasPin)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock, size: 14, color: Colors.white38),
                    SizedBox(width: 4),
                    Text(
                      'PIN',
                      style: TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================
// PIN Input Widget
// ========================================

class _PinInput extends StatefulWidget {
  final ValueChanged<String> onPinChanged;
  final VoidCallback onSubmit;

  const _PinInput({
    required this.onPinChanged,
    required this.onSubmit,
  });

  @override
  State<_PinInput> createState() => _PinInputState();
}

class _PinInputState extends State<_PinInput> {
  String _pin = '';

  void _addDigit(String digit) {
    if (_pin.length >= 6) return;
    setState(() => _pin += digit);
    widget.onPinChanged(_pin);
  }

  void _removeDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
    widget.onPinChanged(_pin);
  }

  void _clear() {
    setState(() => _pin = '');
    widget.onPinChanged(_pin);
  }

  void _submit() {
    if (_pin.length >= 4) {
      widget.onSubmit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PIN display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _pin.length;
            return Container(
              width: 32,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: filled ? Colors.purple : Colors.white24,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                color: filled ? Colors.purple.withOpacity(0.2) : Colors.transparent,
              ),
              child: Center(
                child: filled
                    ? const Text('•', style: TextStyle(fontSize: 24))
                    : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Number pad
        SizedBox(
          width: 240,
          child: Column(
            children: [
              _buildRow(['1', '2', '3']),
              const SizedBox(height: 8),
              _buildRow(['4', '5', '6']),
              const SizedBox(height: 8),
              _buildRow(['7', '8', '9']),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildButton('⌫', _removeDigit, isAction: true),
                  _buildButton('0', () => _addDigit('0')),
                  _buildButton('✓', _submit, isAction: true, isPrimary: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildButton(d, () => _addDigit(d))).toList(),
    );
  }

  Widget _buildButton(
    String label,
    VoidCallback onTap, {
    bool isAction = false,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Ink(
          width: 64,
          height: 56,
          decoration: BoxDecoration(
            color: isPrimary
                ? Colors.purple
                : isAction
                    ? Colors.white10
                    : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isAction ? 20 : 24,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}