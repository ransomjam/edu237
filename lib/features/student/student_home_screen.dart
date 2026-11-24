import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';
import 'student_scope.dart';

/// The signed-in student's Home.
///
/// Deliberately *not* a second parent dashboard. A student sees their own
/// learning and nothing else: no children to manage, no requests to approve,
/// no money. Everything here is read-only apart from opening their profile.
class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StudentRecordLoader(
          builder: (context, student) => _StudentHomeBody(student: student),
        ),
      ),
    );
  }
}

class _StudentHomeBody extends StatefulWidget {
  const _StudentHomeBody({required this.student});

  final Student student;

  @override
  State<_StudentHomeBody> createState() => _StudentHomeBodyState();
}

class _StudentHomeBodyState extends State<_StudentHomeBody> {
  bool _isLoading = true;
  List<TeacherProfile> _teachers = const [];
  List<LessonSession> _upcoming = const [];
  List<LearningActivity> _activities = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    final studentId = widget.student.id;
    final relationshipService =
        ParentTeacherRelationshipServiceScope.of(context);
    final teacherProfileService = TeacherProfileServiceScope.of(context);
    final sessionService = LessonSessionServiceScope.of(context);
    final activityService = LearningActivityServiceScope.of(context);

    final results = await Future.wait([
      relationshipService.fetchRelationshipsForStudent(studentId),
      teacherProfileService.fetchTeachers(),
      sessionService.fetchMyStudentSessions(studentId),
      activityService.fetchActivitiesForStudent(studentId),
    ]);

    if (!mounted) return;

    // Connected teachers = accepted relationships, resolved to profiles.
    final relationshipResult = results[0] as RelationshipResult;
    final connectedIds = <String>{};
    if (relationshipResult is RelationshipListSuccess) {
      for (final r in relationshipResult.relationships) {
        if (r.status == RelationshipStatus.accepted) {
          connectedIds.add(r.teacherId);
        }
      }
    }

    final profileResult = results[1] as TeacherProfileResult;
    final teachers = profileResult is TeacherProfileListSuccess
        ? profileResult.profiles
            .where((t) => connectedIds.contains(t.userId))
            .toList()
        : <TeacherProfile>[];

    final sessionResult = results[2] as LessonSessionResult;
    final now = DateTime.now();
    final upcoming = sessionResult is LessonSessionListSuccess
        ? (sessionResult.sessions
            .where((s) =>
                s.status.isScheduled && s.scheduledAt.toLocal().isAfter(now))
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)))
        : <LessonSession>[];

    final activityResult = results[3] as ActivityResult;
    final activities = activityResult is ActivityListSuccess
        ? activityResult.activities
        : <LearningActivity>[];

    setState(() {
      _teachers = teachers;
      _upcoming = upcoming;
      _activities = activities;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;

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
          _StudentHeader(student: student),
          const SizedBox(height: AppConstants.space24),

          const SectionHeader(title: 'My subjects'),
          const SizedBox(height: AppConstants.space8),
          if (student.subjects.isEmpty)
            const _QuietNote(
              text: 'No subjects yet. Add them from your profile.',
            )
          else
            Wrap(
              spacing: AppConstants.space8,
              runSpacing: AppConstants.space8,
              children: [
                for (final subject in student.subjects)
                  SubjectChip(subject: subject),
              ],
            ),
          const SizedBox(height: AppConstants.space24),

          const SectionHeader(title: 'Next lesson'),
          const SizedBox(height: AppConstants.space8),
          if (_isLoading)
            const _LoadingRow()
          else if (_upcoming.isEmpty)
            const _QuietNote(text: 'No lesson scheduled yet.')
          else
            _UpcomingLessonCard(session: _upcoming.first),
          const SizedBox(height: AppConstants.space24),

          const SectionHeader(title: 'My teachers'),
          const SizedBox(height: AppConstants.space8),
          if (_isLoading)
            const _LoadingRow()
          else if (_teachers.isEmpty)
            const _QuietNote(
              text: 'No teachers connected yet.',
            )
          else
            TileGroup(
              children: [
                for (final teacher in _teachers)
                  PersonTile(
                    name: teacher.fullNameWithTitle,
                    subtitle: teacher.subjects.take(3).join(' · '),
                    imageUrl: teacher.photoUrl,
                    kind: AvatarKind.teacher,
                  ),
              ],
            ),
          const SizedBox(height: AppConstants.space24),

          const SectionHeader(title: 'Recent learning'),
          const SizedBox(height: AppConstants.space8),
          if (_isLoading)
            const _LoadingRow()
          else if (_activities.isEmpty)
            const _QuietNote(text: 'Nothing here yet.')
          else
            TileGroup(
              children: [
                for (final activity in _activities.take(3))
                  _ActivityTile(activity: activity),
              ],
            ),
        ],
      ),
    );
  }
}

/// Avatar, name and current class — the student's own identity, nothing else.
class _StudentHeader extends StatelessWidget {
  const _StudentHeader({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(name: student.name, size: 56, kind: AvatarKind.child),
        const SizedBox(width: AppConstants.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(student.name, style: AppTextStyles.h1),
              const SizedBox(height: 2),
              StudentLevelLine(
                student: student,
                style: AppTextStyles.body.copyWith(color: AppColors.grey700),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('student_home_profile'),
          tooltip: 'My profile',
          icon: const PhosphorIcon(PhosphorIcons.user, size: 20, color: AppColors.grey700),
          onPressed: () => context.go(AppRoutes.profile),
        ),
      ],
    );
  }
}

class _UpcomingLessonCard extends StatelessWidget {
  const _UpcomingLessonCard({required this.session});

  final LessonSession session;

  @override
  Widget build(BuildContext context) {
    final start = session.scheduledAt.toLocal();
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          const PhosphorIcon(PhosphorIcons.calendarCheck,
              color: AppColors.primary, size: 22),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.subject,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatShortDate(start)} · $hh:$mm'
                  '${session.teacherName == null ? '' : ' · ${session.teacherName}'}',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.grey700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final LearningActivity activity;

  @override
  Widget build(BuildContext context) {
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
        '${activity.activityType.label} · ${activity.subject}',
        style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
      ),
    );
  }
}

class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(color: AppColors.grey500),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppConstants.space12),
      child: SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
