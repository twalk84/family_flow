// FILE: lib/screens/daily_schedule_screen.dart
//
// Improved transitions:
// - Month / Week / Day are mutually exclusive panels
// - Selecting Week or Day hides Month automatically
// - Selecting Month hides Week and shows Month + Day list
// - Smooth animated transitions
//
// Updated in this version:
// - ✅ Student colors use Student.colorValue when set (matches dashboard/profile colors)
// - ✅ Month cell overflow fix (adapts when cells are too short; hides dots if needed)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firestore_paths.dart';
import '../models.dart';

enum ScheduleViewMode { day, week }

class DailyScheduleScreen extends StatefulWidget {
  final List<Assignment> assignments; // still accepted for compatibility
  final List<Student> students;
  final Future<void> Function(String assignmentId, int? grade) onComplete;
  final bool useLiveFirestore;

  const DailyScheduleScreen({
    super.key,
    required this.assignments,
    required this.students,
    required this.onComplete,
    this.useLiveFirestore = true,
  });

  @override
  State<DailyScheduleScreen> createState() => _DailyScheduleScreenState();
}

class _DailyScheduleScreenState extends State<DailyScheduleScreen> {
  late DateTime _selectedDate;
  String? _selectedStudentId;

  /// Month panel visibility
  bool _showMonth = false;

  /// Day or Week list mode
  ScheduleViewMode _viewMode = ScheduleViewMode.day;

  /// Month being displayed in the month grid (always first day of month)
  late DateTime _calendarMonth;

  // local optimistic UI state (so the row flips immediately)
  final Map<String, _LocalCompletion> _local = {};

  // fallback palette (used only if student has no saved color)
  final List<Color> _fallbackPalette = const [
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  // ---------- helpers ----------

  String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _prettyDate(DateTime date) {
    final today = DateTime.now();
    final selected = DateTime(date.year, date.month, date.day);
    final t = DateTime(today.year, today.month, today.day);

    if (selected == t) return 'Today';
    if (selected == t.add(const Duration(days: 1))) return 'Tomorrow';
    if (selected == t.subtract(const Duration(days: 1))) return 'Yesterday';

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _monthLabel(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _studentColor(String studentId) {
    final idx = widget.students.indexWhere((s) => s.id == studentId);
    if (idx < 0) return Colors.grey;

    final st = widget.students[idx];
    final v = st.colorValue;
    if (v != 0) return Color(v);

    return _fallbackPalette[idx % _fallbackPalette.length];
  }

  bool _isCompleted(Assignment a) => _local[a.id]?.completed ?? a.isCompleted;
  int? _grade(Assignment a) => _local[a.id]?.grade ?? a.grade;

  // ---------- mode transitions ----------

  void _setDayMode() {
    setState(() {
      _viewMode = ScheduleViewMode.day;
      _showMonth = false; // hide month panel
    });
  }

  void _setWeekMode() {
    setState(() {
      _viewMode = ScheduleViewMode.week;
      _showMonth = false; // hide month panel
    });
  }

  void _toggleMonth() {
    setState(() {
      // Month means: show month panel + day list (not week list)
      _viewMode = ScheduleViewMode.day;
      _showMonth = !_showMonth;
      _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    });
  }

  // ---------- summaries for dots + previews ----------

  Map<String, _DateSummary> _summariesByDate(List<Assignment> all) {
    final out = <String, _DateSummary>{};

    for (final a in all) {
      final due = a.dueDate.trim();
      if (due.isEmpty) continue;

      if (_selectedStudentId != null && a.studentId != _selectedStudentId) continue;

      final s = out.putIfAbsent(due, () => _DateSummary());
      s.assignmentCount += 1;
      s.studentIds.add(a.studentId);
    }

    out.forEach((_, s) {
      final colors = s.studentIds.map(_studentColor).toList();
      colors.sort((a, b) => a.value.compareTo(b.value));
      s.studentColors = colors;
    });

    return out;
  }

  void _showDayPreview(DateTime date, _DateSummary? summary) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${months[date.month - 1]} ${date.day}';
    final count = summary?.assignmentCount ?? 0;
    final students = summary?.studentIds.length ?? 0;

    if (count == 0) return _snack('$label: no assignments due');

    final sSuffix = students == 1 ? 'student' : 'students';
    final aSuffix = count == 1 ? 'assignment' : 'assignments';
    _snack('$label: $count $aSuffix due • $students $sSuffix');
  }

  // ---------- filtering ----------

  List<Assignment> _assignmentsForDate(List<Assignment> all, DateTime date) {
    final dateStr = _yyyyMmDd(date);

    final filtered = all.where((a) {
      final matchesDate = a.dueDate == dateStr;
      final matchesStudent = _selectedStudentId == null || a.studentId == _selectedStudentId;
      return matchesDate && matchesStudent;
    }).toList();

    filtered.sort((a, b) {
      final ac = _isCompleted(a) ? 1 : 0;
      final bc = _isCompleted(b) ? 1 : 0;
      if (ac != bc) return ac.compareTo(bc);
      final s = a.studentName.compareTo(b.studentName);
      if (s != 0) return s;
      final sub = a.subjectName.compareTo(b.subjectName);
      if (sub != 0) return sub;
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  List<Assignment> _overdueAssignments(List<Assignment> all) {
    final todayStr = _yyyyMmDd(DateTime.now());
    return all.where((a) {
      final done = _isCompleted(a);
      return !done && a.dueDate.isNotEmpty && a.dueDate.compareTo(todayStr) < 0;
    }).toList();
  }

  // ---------- completion actions ----------

  Future<void> _setCompleted(Assignment a, {required bool completed, int? grade}) async {
    setState(() {
      _local[a.id] = _LocalCompletion(completed: completed, grade: grade ?? _grade(a));
    });

    try {
      if (completed) {
        await widget.onComplete(a.id, grade);
      } else {
        await FirestorePaths.assignmentsCol().doc(a.id).set(
          {'completed': false, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _local.remove(a.id));
      _snack('Update failed: $e', color: Colors.red);
    }
  }

  void _showGradeDialog(Assignment a) {
    final gradeController = TextEditingController(text: _grade(a)?.toString() ?? '');

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text('Complete: ${a.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${a.studentName} • ${a.subjectName}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: gradeController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Grade % (optional)',
                hintText: 'e.g. 95',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await _setCompleted(a, completed: true, grade: null);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Complete (No Grade)'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final raw = gradeController.text.trim();
              final g = int.tryParse(raw);
              if (g == null || g < 0 || g > 100) {
                _snack('Enter a grade 0–100, or choose “Complete (No Grade)”.', color: Colors.orange);
                return;
              }
              await _setCompleted(a, completed: true, grade: g);
              if (mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: const Text('Complete w/ Grade'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  // ---------- UI bits ----------

  Widget _studentChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            label: 'All',
            selected: _selectedStudentId == null,
            onTap: () => setState(() => _selectedStudentId = null),
          ),
          ...widget.students.map((s) {
            return _chip(
              label: s.name,
              selected: _selectedStudentId == s.id,
              onTap: () => setState(() => _selectedStudentId = s.id),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.purple : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewToggle() {
    final isDay = _viewMode == ScheduleViewMode.day;

    return ToggleButtons(
      isSelected: [isDay, !isDay],
      onPressed: (i) {
        if (i == 0) {
          _setDayMode();
        } else {
          _setWeekMode();
        }
      },
      borderRadius: BorderRadius.circular(999),
      constraints: const BoxConstraints(minHeight: 36, minWidth: 68),
      children: const [
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Day')),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Week')),
      ],
    );
  }

  // ---------- month panel ----------

  Widget _monthPanel(List<Assignment> allAssignments) {
    final summaries = _summariesByDate(allAssignments);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _showMonth
          ? Padding(
              key: const ValueKey('monthPanel'),
              padding: const EdgeInsets.only(top: 10),
              child: _MonthDotsCalendar(
                month: _calendarMonth,
                selectedDate: _selectedDate,
                summariesByDate: summaries,
                onPrevMonth: () => setState(() {
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
                }),
                onNextMonth: () => setState(() {
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
                }),
                onTapDay: (date, summary) {
                  setState(() {
                    _selectedDate = date;
                    _calendarMonth = DateTime(date.year, date.month, 1);
                    _viewMode = ScheduleViewMode.day;
                  });
                  _showDayPreview(date, summary);
                },
              ),
            )
          : const SizedBox(key: ValueKey('noMonth')),
    );
  }

  // ---------- week strip ----------

  List<DateTime> _next7Days() {
    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));
  }

  Widget _weekStrip(List<Assignment> allAssignments) {
    final summaries = _summariesByDate(allAssignments);
    final days = _next7Days();

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _viewMode == ScheduleViewMode.week
          ? SizedBox(
              key: const ValueKey('weekStrip'),
              height: 108,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: days.map((d) {
                    final key = _yyyyMmDd(d);
                    final summary = summaries[key];
                    final dots = summary?.studentColors ?? const <Color>[];
                    final count = summary?.assignmentCount ?? 0;

                    final isSelected =
                        d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _selectedDate = d;
                            _calendarMonth = DateTime(d.year, d.month, 1);
                          });
                          _showDayPreview(d, summary);
                        },
                        child: Container(
                          width: 78,
                          height: 90,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.purple.withOpacity(0.30) : const Color(0xFF1F2937),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isSelected ? Colors.purple.withOpacity(0.65) : Colors.white12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(weekdays[d.weekday - 1], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('${months[d.month - 1]} ${d.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (dots.isNotEmpty)
                                Row(
                                  children: [
                                    for (final c in dots.take(4))
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                                      ),
                                    if (dots.length > 4)
                                      Text(
                                        '+${dots.length - 4}',
                                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                                      ),
                                  ],
                                )
                              else
                                const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(count == 0 ? '' : '$count', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            )
          : const SizedBox(key: ValueKey('noWeekStrip')),
    );
  }

  // ---------- list bodies ----------

  Widget _assignmentCard(Assignment a) {
    final done = _isCompleted(a);
    final grade = _grade(a);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: done ? null : () => _showGradeDialog(a),
          child: Ink(
            decoration: BoxDecoration(
              color: done ? Colors.green.withOpacity(0.10) : const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: done ? Colors.green.withOpacity(0.30) : Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(done ? Icons.check_circle : Icons.circle_outlined, color: done ? Colors.green : Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${a.subjectName} • ${a.studentName}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (grade != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$grade%', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: done ? 'Undo completion' : 'Mark complete (no grade)',
                    onPressed: () => _setCompleted(a, completed: !done, grade: grade),
                    icon: Icon(done ? Icons.undo : Icons.check, color: done ? Colors.orange : Colors.green),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayBody(List<Assignment> allAssignments) {
    final list = _assignmentsForDate(allAssignments, _selectedDate);

    if (list.isEmpty) {
      return Center(
        child: Text('No assignments for this day.', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      );
    }

    return ListView.builder(
      key: const ValueKey('dayList'),
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) => _assignmentCard(list[i]),
    );
  }

  Widget _weekBody(List<Assignment> allAssignments) {
    final days = _next7Days();
    final sections = <Widget>[];
    int totalItems = 0;

    for (final d in days) {
      final list = _assignmentsForDate(allAssignments, d);
      if (list.isEmpty) continue;
      totalItems += list.length;

      final doneCount = list.where(_isCompleted).length;

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_prettyDate(d)} • ${_yyyyMmDd(d)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              Text('$doneCount/${list.length}', style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );

      sections.addAll(list.map((a) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _assignmentCard(a),
          )));
    }

    if (totalItems == 0) {
      return Center(
        child: Text('No assignments in the next 7 days.', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      );
    }

    return ListView(
      key: const ValueKey('weekList'),
      padding: const EdgeInsets.only(bottom: 16),
      children: sections,
    );
  }

  Widget _listPanel(List<Assignment> allAssignments) {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _viewMode == ScheduleViewMode.day ? _dayBody(allAssignments) : _weekBody(allAssignments),
      ),
    );
  }

  // ---------- header ----------

  Widget _buildHeader(List<Assignment> allAssignments) {
    final todayList = _assignmentsForDate(allAssignments, _selectedDate);
    final completed = todayList.where(_isCompleted).length;
    final total = todayList.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => setState(() {
                  _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(_prettyDate(_selectedDate), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: () => setState(() {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                  _calendarMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                }),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: _showMonth ? 'Hide month' : 'Show month',
                onPressed: _toggleMonth,
                icon: Icon(_showMonth ? Icons.calendar_month : Icons.calendar_today),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _viewToggle(),
              const Spacer(),
              Text(_monthLabel(_calendarMonth), style: const TextStyle(color: Colors.white60)),
            ],
          ),
          _monthPanel(allAssignments),
          const SizedBox(height: 10),
          _studentChips(),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: Colors.white10,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('$completed of $total completed (selected day)', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ---------- build ----------

  List<Assignment> _mapDocsToAssignments(QuerySnapshot<Map<String, dynamic>> snap) {
    final studentsById = {for (final s in widget.students) s.id: s};
    return snap.docs.map((d) => Assignment.fromDoc(d, studentsById: studentsById)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final targetW = maxW > 900 ? 900.0 : maxW;

          Widget buildWithAssignments(List<Assignment> all) {
            final overdue = _overdueAssignments(all);
            final isToday = _yyyyMmDd(_selectedDate) == _yyyyMmDd(DateTime.now());

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: targetW,
                child: Column(
                  children: [
                    _buildHeader(all),
                    _weekStrip(all),
                    _listPanel(all),
                    if (isToday && overdue.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.orange.withOpacity(0.2),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${overdue.length} overdue assignment${overdue.length == 1 ? '' : 's'} not completed.',
                                style: const TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          if (widget.useLiveFirestore) {
            if (user == null) return const Center(child: Text('Sign in required.'));

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestorePaths.assignmentsCol().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final docs = snap.data;
                if (docs == null) return const Center(child: Text('No data.'));
                final all = _mapDocsToAssignments(docs);
                return buildWithAssignments(all);
              },
            );
          }

          return buildWithAssignments(widget.assignments);
        },
      ),
    );
  }
}

class _LocalCompletion {
  final bool completed;
  final int? grade;
  const _LocalCompletion({required this.completed, required this.grade});
}

class _DateSummary {
  int assignmentCount = 0;
  final Set<String> studentIds = <String>{};
  List<Color> studentColors = const <Color>[];
}

class _MonthDotsCalendar extends StatelessWidget {
  final DateTime month; // first day of month
  final DateTime selectedDate;
  final Map<String, _DateSummary> summariesByDate;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final void Function(DateTime date, _DateSummary? summary) onTapDay;

  const _MonthDotsCalendar({
    required this.month,
    required this.selectedDate,
    required this.summariesByDate,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onTapDay,
  });

  String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = _daysInMonth(month.year, month.month);
    final firstWeekdayIndex = (first.weekday - 1) % 7;

    final totalCells = firstWeekdayIndex + days;
    final rows = (totalCells / 7).ceil();

    final weekLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPrevMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final w in weekLabels)
                Expanded(
                  child: Center(
                    child: Text(w, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (int r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (int c = 0; c < 7; c++) Expanded(child: _buildCell(firstWeekdayIndex, days, r, c)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ✅ OVERFLOW FIX: adapts to tight height constraints (e.g., when cells get squished).
  // If the cell is too short, we hide dots instead of overflowing.
  Widget _buildCell(int offset, int days, int row, int col) {
    final cellIndex = row * 7 + col;
    final dayNum = cellIndex - offset + 1;

    if (dayNum < 1 || dayNum > days) return const SizedBox(height: 44);

    final date = DateTime(month.year, month.month, dayNum);
    final dateKey = _yyyyMmDd(date);

    final summary = summariesByDate[dateKey];
    final dots = summary?.studentColors ?? const <Color>[];

    final isSelected = _sameDay(date, selectedDate);
    final today = DateTime.now();
    final isToday = _sameDay(date, today);

    const maxDots = 4;
    final shown = dots.length > maxDots ? dots.take(maxDots).toList() : dots;
    final extra = dots.length - shown.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowDots = constraints.maxHeight >= 36 && shown.isNotEmpty;

          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTapDay(date, summary),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.purple.withOpacity(0.35) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? Colors.purple.withOpacity(0.70)
                      : isToday
                          ? Colors.white24
                          : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: canShowDots ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                  if (canShowDots)
                    Row(
                      children: [
                        for (final color in shown)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                        if (extra > 0)
                          Text(
                            '+$extra',
                            style: const TextStyle(color: Colors.white60, fontSize: 10),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
