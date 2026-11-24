import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teaching_mode.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import 'schedule_format.dart';

/// The single, simple "schedule a lesson" screen (Teacher → Student → Schedule).
///
/// Select → Tap → Confirm: subject, day (Today/Tomorrow/Choose date), an
/// availability-aware time, duration, mode, then Schedule. Nothing is typed.
class ScheduleLessonScreen extends StatefulWidget {
  const ScheduleLessonScreen({super.key, required this.student});

  final Student student;

  @override
  State<ScheduleLessonScreen> createState() => _ScheduleLessonScreenState();
}

class _ScheduleLessonScreenState extends State<ScheduleLessonScreen> {
  static const List<int> _durations = [
    30,
    45,
    60,
    75,
    90,
    105,
    120,
    150,
    180,
    210,
    240,
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  TeacherProfile? _profile;
  ParentTeacherRelationship? _relationship;
  List<LessonSession> _existing = const [];

  List<String> _subjects = const [];
  String? _subject;
  late DateTime _day; // date-only
  bool _customDay = false;
  int _duration = 60;
  TeachingMode? _mode;
  DateTime? _start;
  late FixedExtentScrollController _durationScrollController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    final initialHour = now.hour < 20 ? (now.hour + 1) : 10;
    _start = DateTime(_day.year, _day.month, _day.day, initialHour, 0);

    final initialDurationIndex = _durations.indexOf(_duration);
    _durationScrollController = FixedExtentScrollController(
      initialItem: initialDurationIndex >= 0 ? initialDurationIndex : 2,
    );
  }

  @override
  void dispose() {
    _durationScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      TeacherProfileServiceScope.of(context).fetchMyProfile(),
      ParentTeacherRelationshipServiceScope.of(context)
          .fetchMyRelationshipsAsTeacher(),
      LessonSessionServiceScope.of(context).fetchMyTeacherSessions(),
    ]);
    if (!mounted) return;

    final profileRes = results[0] as TeacherProfileResult;
    final relRes = results[1] as RelationshipResult;
    final sessRes = results[2] as LessonSessionResult;

    if (profileRes is TeacherProfileSuccess) _profile = profileRes.profile;

    if (relRes is RelationshipListSuccess) {
      _relationship = relRes.relationships
          .where((r) =>
              r.studentId == widget.student.id &&
              r.status == RelationshipStatus.accepted)
          .firstOrNull;
    }
    if (sessRes is LessonSessionListSuccess) _existing = sessRes.sessions;

    // Subjects offered: teacher subjects that also match the student, else all
    // teacher subjects (never leave the teacher with nothing to pick).
    final teacherSubjects = _profile?.subjects ?? const <String>[];
    final studentSubjects =
        widget.student.subjects.map((s) => s.toLowerCase()).toSet();
    final overlap = teacherSubjects
        .where((s) => studentSubjects.contains(s.toLowerCase()))
        .toList();
    _subjects = overlap.isNotEmpty ? overlap : teacherSubjects;
    _subject = _subjects.isNotEmpty ? _subjects.first : null;

    // Default mode from the teacher's supported modes.
    final mode = _profile?.teachingMode ?? TeachingMode.inPerson;
    _mode = mode == TeachingMode.online
        ? TeachingMode.online
        : TeachingMode.inPerson;

    if (_relationship == null) {
      _loadError =
          'You need an active connection with ${widget.student.name} before scheduling a lesson.';
    }

    setState(() => _isLoading = false);
  }

  /// The concrete modes the teacher can offer (never "both" as a session mode).
  List<TeachingMode> get _modeOptions {
    final m = _profile?.teachingMode ?? TeachingMode.inPerson;
    return switch (m) {
      TeachingMode.online => const [TeachingMode.online],
      TeachingMode.inPerson => const [TeachingMode.inPerson],
      TeachingMode.both => const [TeachingMode.online, TeachingMode.inPerson],
    };
  }

  Future<void> _pickCustomTime() async {
    final now = DateTime.now();
    final initial = _start != null
        ? TimeOfDay(hour: _start!.hour, minute: _start!.minute)
        : TimeOfDay(
            hour: now.hour < 20 ? (now.hour + 1) : 10,
            minute: 0,
          );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    final start = DateTime(
      _day.year,
      _day.month,
      _day.day,
      picked.hour,
      picked.minute,
    );
    setState(() {
      _start = start;
      _saveError = null;
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : _day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 90)),
    );
    if (picked == null) return;
    final newDay = DateTime(picked.year, picked.month, picked.day);
    final prevHour = _start?.hour ?? 10;
    final prevMin = _start?.minute ?? 0;
    setState(() {
      _day = newDay;
      _customDay = true;
      _start = DateTime(newDay.year, newDay.month, newDay.day, prevHour, prevMin);
      _saveError = null;
    });
  }

  void _selectQuickDay(int addDays) {
    final now = DateTime.now();
    final newDay = DateTime(now.year, now.month, now.day)
        .add(Duration(days: addDays));
    final prevHour = _start?.hour ?? (now.hour < 20 ? now.hour + 1 : 10);
    final prevMin = _start?.minute ?? 0;
    setState(() {
      _day = newDay;
      _customDay = false;
      _start = DateTime(newDay.year, newDay.month, newDay.day, prevHour, prevMin);
      _saveError = null;
    });
  }

  Future<void> _schedule() async {
    final rel = _relationship;
    final subject = _subject;
    final start = _start;
    final mode = _mode;
    if (rel == null || subject == null || start == null || mode == null) {
      setState(() => _saveError = 'Please choose a subject and a time.');
      return;
    }

    if (start.isBefore(DateTime.now())) {
      setState(() => _saveError = 'Please choose a future time.');
      return;
    }

    final end = start.add(Duration(minutes: _duration));
    final collides = _existing.where((s) => s.status.isScheduled).any((s) {
      final sStart = s.localStart;
      final sEnd = s.localEnd;
      return start.isBefore(sEnd) && sStart.isBefore(end);
    });
    if (collides) {
      setState(() => _saveError =
          'That time clashes with another scheduled lesson. Please choose a different time.');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final result = await LessonSessionServiceScope.of(context).createSession(
      relationshipId: rel.id,
      subject: subject,
      scheduledAt: start,
      durationMinutes: _duration,
      teachingMode: mode,
      locationArea: mode == TeachingMode.inPerson ? _profile?.area : null,
      locationCity: mode == TeachingMode.inPerson ? _profile?.city : null,
    );
    if (!mounted) return;

    if (result is LessonSessionSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lesson scheduled · ${dayTimeLabel(result.session.localStart, DateTime.now())}',
          ),
        ),
      );
      context.pop(true);
    } else if (result is LessonSessionFailure) {
      setState(() {
        _isSaving = false;
        _saveError = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule lesson')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_relationship == null) {
      return AppEmptyState(
        icon: Icons.link_off,
        title: 'Not connected yet',
        message: _loadError ??
            'You can only schedule lessons with a connected student.',
        actionLabel: 'Go back',
        onAction: () => context.pop(),
      );
    }

    final canSchedule = _subject != null && _start != null && _mode != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
            children: [
              // Student name and level header (clean typography without avatar icon)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.student.name, style: AppTextStyles.h2),
                  if (widget.student.qualifiedLevelLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.student.qualifiedLevelLabel!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.grey500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppConstants.space24),

              const _FieldLabel('Subject'),
              if (_subjects.isEmpty)
                Text('Add subjects to your profile to schedule a lesson.',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.grey500))
              else
                Wrap(
                  spacing: AppConstants.space8,
                  runSpacing: AppConstants.space8,
                  children: [
                    for (final s in _subjects)
                      _ChoiceChip(
                        label: s,
                        selected: _subject == s,
                        onTap: () => setState(() => _subject = s),
                      ),
                  ],
                ),
              const SizedBox(height: AppConstants.space24),

              const _FieldLabel('When?'),
              Wrap(
                spacing: AppConstants.space8,
                runSpacing: AppConstants.space8,
                children: [
                  _ChoiceChip(
                    label: 'Today',
                    selected: !_customDay && _isSameDay(_day, 0),
                    onTap: () => _selectQuickDay(0),
                  ),
                  _ChoiceChip(
                    label: 'Tomorrow',
                    selected: !_customDay && _isSameDay(_day, 1),
                    onTap: () => _selectQuickDay(1),
                  ),
                  _ChoiceChip(
                    label: _customDay
                        ? dayLabel(_day, DateTime.now())
                        : 'Choose date',
                    selected: _customDay,
                    icon: Icons.calendar_today,
                    onTap: _pickCustomDate,
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.space24),

              const _FieldLabel('Time'),
              _buildTimeSection(),
              const SizedBox(height: AppConstants.space24),

              const _FieldLabel('Duration'),
              _buildDurationWheel(),
              const SizedBox(height: AppConstants.space24),

              if (_modeOptions.length > 1) ...[
                const _FieldLabel('Mode'),
                Wrap(
                  spacing: AppConstants.space8,
                  runSpacing: AppConstants.space8,
                  children: [
                    for (final m in _modeOptions)
                      _ChoiceChip(
                        label: m == TeachingMode.online
                            ? 'Online'
                            : 'In person',
                        icon: m == TeachingMode.online
                            ? Icons.videocam_outlined
                            : Icons.handshake_outlined,
                        selected: _mode == m,
                        onTap: () => setState(() => _mode = m),
                      ),
                  ],
                ),
                const SizedBox(height: AppConstants.space24),
              ],

              if (_mode == TeachingMode.inPerson) _buildLocation(),

              if (_saveError != null) ...[
                const SizedBox(height: AppConstants.space16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppConstants.space12),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppConstants.radius),
                  ),
                  child: Text(_saveError!,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.error)),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.pageHorizontalPadding,
            AppConstants.space12,
            AppConstants.pageHorizontalPadding,
            AppConstants.space16,
          ),
          child: AppButton(
            label: 'Schedule lesson',
            isFullWidth: true,
            isLoading: _isSaving,
            onPressed: canSchedule ? _schedule : null,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSection() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _pickCustomTime,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _start != null ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _start != null ? clockLabel(_start!) : 'Select lesson time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _start != null ? AppColors.grey900 : AppColors.grey500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _start != null ? 'Tap to change time' : 'Tap to open clock',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grey500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationWheel() {
    return Container(
      height: 116,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: CupertinoPicker(
        scrollController: _durationScrollController,
        itemExtent: 38,
        useMagnifier: true,
        magnification: 1.15,
        selectionOverlay: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onSelectedItemChanged: (index) {
          setState(() {
            _duration = _durations[index];
          });
        },
        children: _durations.map((d) {
          final isSelected = _duration == d;
          return Center(
            child: Text(
              durationLabel(d),
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.grey700,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLocation() {
    final area = (_profile?.area ?? '').trim();
    final city = (_profile?.city ?? '').trim();
    final label = [area, city].where((e) => e.isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Location'),
        _InfoNote(
          icon: Icons.location_on_outlined,
          text: label.isEmpty
              ? 'Add a city/area to your profile to share an in-person location.'
              : 'In person · $label',
        ),
        const SizedBox(height: AppConstants.space24),
      ],
    );
  }

  bool _isSameDay(DateTime day, int addDays) {
    final now = DateTime.now();
    final target =
        DateTime(now.year, now.month, now.day).add(Duration(days: addDays));
    return day.year == target.year &&
        day.month == target.month &&
        day.day == target.day;
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.space12),
        child: SectionHeader(title: text),
      );
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16, vertical: AppConstants.space12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected ? AppColors.white : AppColors.grey500),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: selected ? AppColors.white : AppColors.grey900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.grey500),
          const SizedBox(width: AppConstants.space12),
          Expanded(
              child: Text(text,
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.grey700))),
        ],
      ),
    );
  }
}
