import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/student.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';
import 'student_scope.dart';

/// The student's Learning tab: their scheduled lessons and the learning
/// activities their teachers have set. Read-only — a student consumes learning
/// here, they do not administer anything.
class StudentLearningScreen extends StatelessWidget {
  const StudentLearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning')),
      body: SafeArea(
        child: StudentRecordLoader(
          builder: (context, student) => _StudentLearningBody(student: student),
        ),
      ),
    );
  }
}

class _StudentLearningBody extends StatefulWidget {
  const _StudentLearningBody({required this.student});

  final Student student;

  @override
  State<_StudentLearningBody> createState() => _StudentLearningBodyState();
}

class _StudentLearningBodyState extends State<_StudentLearningBody> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LessonSession> _sessions = const [];
  List<LearningActivity> _activities = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    final studentId = widget.student.id;
    final sessionService = LessonSessionServiceScope.of(context);
    final activityService = LearningActivityServiceScope.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      sessionService.fetchMyStudentSessions(studentId),
      activityService.fetchActivitiesForStudent(studentId),
    ]);
    if (!mounted) return;

    final sessionResult = results[0] as LessonSessionResult;
    final activityResult = results[1] as ActivityResult;

    setState(() {
      _sessions = sessionResult is LessonSessionListSuccess
          ? sessionResult.sessions
          : const <LessonSession>[];
      _activities = activityResult is ActivityListSuccess
          ? activityResult.activities
          : const <LearningActivity>[];
      _errorMessage = activityResult is ActivityFailure
          ? activityResult.message
          : (sessionResult is LessonSessionFailure
              ? sessionResult.message
              : null);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty && _activities.isEmpty) {
      return AppEmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No learning yet',
        message: _errorMessage ??
            'When a teacher schedules a lesson or sets work for you, it '
                'appears here.',
        actionLabel: 'Refresh',
        onAction: _load,
      );
    }

    final now = DateTime.now();
    final upcoming = _sessions
        .where((s) => s.status.isScheduled && s.scheduledAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final past = _sessions.where((s) => !upcoming.contains(s)).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pageHorizontalPadding,
          AppConstants.space16,
          AppConstants.pageHorizontalPadding,
          AppConstants.space32,
        ),
        children: [
          if (upcoming.isNotEmpty) ...[
            const SectionHeader(title: 'Upcoming lessons'),
            TileGroup(
              children: [
                for (final session in upcoming) _SessionTile(session: session),
              ],
            ),
            const SizedBox(height: AppConstants.space24),
          ],
          if (_activities.isNotEmpty) ...[
            const SectionHeader(title: 'Work set by my teachers'),
            TileGroup(
              children: [
                for (final activity in _activities)
                  _ActivityRow(activity: activity),
              ],
            ),
            const SizedBox(height: AppConstants.space24),
          ],
          if (past.isNotEmpty) ...[
            const SectionHeader(title: 'Past lessons'),
            TileGroup(
              children: [
                for (final session in past) _SessionTile(session: session),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final LessonSession session;

  @override
  Widget build(BuildContext context) {
    final start = session.scheduledAt.toLocal();
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppConstants.space16),
      leading: const Icon(Icons.event_outlined, color: AppColors.primary),
      title: Text(session.subject, style: AppTextStyles.body),
      subtitle: Text(
        '${formatShortDate(start)} · $hh:$mm · ${session.status.label}',
        style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final LearningActivity activity;

  @override
  Widget build(BuildContext context) {
    final due = activity.dueDate;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppConstants.space16),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.tagBorder, width: 0.8),
        ),
        child: PhosphorIcon(
          activity.activityType.phosphorIcon,
          size: 18,
          color: AppColors.primary,
        ),
      ),
      title: Text(activity.topic, style: AppTextStyles.body),
      subtitle: Text(
        [
          activity.activityType.label,
          activity.subject,
          if (due != null) 'Due ${formatShortDate(due)}',
        ].join(' · '),
        style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
      ),
    );
  }
}
