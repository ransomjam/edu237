import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';
import '../payments/activate_relationship_screen.dart';
import '../payments/relationship_contact_card.dart';
import '../schedule/lesson_followup.dart';
import '../schedule/session_widgets.dart';

/// Route arguments carrying both the student and the relationship they belong
/// to, so the screen can show the relationship's contact details (which are
/// gated on activation) rather than just the child record.
class TeacherStudentDetailArgs {
  const TeacherStudentDetailArgs({
    required this.student,
    required this.relationshipId,
  });

  final Student student;
  final String relationshipId;
}

class TeacherStudentDetailScreen extends StatefulWidget {
  const TeacherStudentDetailScreen({
    super.key,
    required this.student,
    this.relationshipId,
  });

  final Student student;

  /// Null when the screen is reached without relationship context; the contact
  /// section is then simply not shown.
  final String? relationshipId;

  @override
  State<TeacherStudentDetailScreen> createState() =>
      _TeacherStudentDetailScreenState();
}

class _TeacherStudentDetailScreenState
    extends State<TeacherStudentDetailScreen> {
  bool _isLoadingActivities = true;
  bool _initialLoadDone = false;
  List<LearningActivity> _recentActivities = [];
  List<LessonSession> _sessions = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadActivities();
      _loadSessions();
    }
  }

  Future<void> _loadActivities() async {
    setState(() => _isLoadingActivities = true);

    final result = await LearningActivityServiceScope.of(context)
        .fetchActivitiesForStudent(widget.student.id);
    if (!mounted) return;

    if (result is ActivityListSuccess) {
      setState(() {
        _recentActivities = result.activities.take(5).toList();
        _isLoadingActivities = false;
      });
    } else {
      setState(() => _isLoadingActivities = false);
    }
  }

  Future<void> _loadSessions() async {
    final result = await LessonSessionServiceScope.of(context)
        .fetchTeacherSessionsForStudent(widget.student.id);
    if (!mounted) return;
    if (result is LessonSessionListSuccess) {
      setState(() => _sessions = result.sessions);
    }
  }

  Future<void> _scheduleLesson() async {
    final scheduled = await context
        .push<bool>(AppRoutes.scheduleLesson, extra: widget.student);
    if (scheduled == true && mounted) _loadSessions();
  }

  /// Opens the activation flow for this relationship. The screen itself decides
  /// whether anything is actually owed.
  Future<void> _activate(String childName) async {
    final id = widget.relationshipId;
    if (id == null) return;
    final done = await context.push<bool>(
      AppRoutes.activateRelationship,
      extra: ActivateRelationshipArgs(
        relationshipId: id,
        childName: childName,
        subject: widget.student.subjects.isEmpty
            ? null
            : widget.student.subjects.first,
      ),
    );
    if (done == true && mounted) setState(() {});
  }

  Future<void> _followUp(LessonSession s) async {
    final updated = await showLessonFollowUpSheet(context, s);
    if (updated != null && mounted) _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final student = widget.student;
    final form = student.qualifiedLevelLabel ?? l10n.childDetailNotSet;
    final subjects = student.subjects;

    return Scaffold(
      appBar: AppBar(
        title: Text(student.name),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppAvatar(
                      name: student.name, size: 52, kind: AvatarKind.child),
                  const SizedBox(width: AppConstants.space12),
                  Expanded(
                    child: Text(student.name, style: AppTextStyles.h1),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.space8,
                      vertical: AppConstants.space4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      l10n.connectedBadge,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.space16),
              Text(l10n.childDetailClassLabel, style: AppTextStyles.h3),
              const SizedBox(height: AppConstants.space8),
              Text(form, style: AppTextStyles.bodyLarge),
              const SizedBox(height: AppConstants.space24),
              Text(l10n.childDetailSubjectsLabel, style: AppTextStyles.h3),
              const SizedBox(height: AppConstants.space8),
              if (subjects.isEmpty)
                Text(
                  l10n.childDetailNoSubjects,
                  style: AppTextStyles.body.copyWith(color: AppColors.grey500),
                )
              else
                Wrap(
                  spacing: AppConstants.space8,
                  runSpacing: AppConstants.space8,
                  children: [
                    for (final subject in subjects)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space12,
                          vertical: AppConstants.space4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(
                          subject,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: AppConstants.space24),

              // ---- Family contact ----
              // Shown locked until the relationship's activation condition is
              // satisfied; the details themselves never reach the app before
              // then.
              if (widget.relationshipId != null) ...[
                RelationshipContactCard(
                  relationshipId: widget.relationshipId!,
                  lockedTitle: 'Family contact',
                  onActivate: () => _activate(student.name),
                ),
                const SizedBox(height: AppConstants.space32),
              ] else
                const SizedBox(height: AppConstants.space8),

              // ---- Lessons Section ----
              _buildLessonsSection(),
              const SizedBox(height: AppConstants.space32),

              // ---- Learning Section ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Learning', style: AppTextStyles.h2),
                  if (_recentActivities.length > 4)
                    TextButton(
                      onPressed: () => context.push(
                        AppRoutes.teacherActivityList,
                        extra: student,
                      ),
                      child: const Text('View all'),
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.space12),

              if (_isLoadingActivities)
                const Center(child: CircularProgressIndicator())
              else if (_recentActivities.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppConstants.space24),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(AppConstants.radius),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 40, color: AppColors.grey500),
                      const SizedBox(height: AppConstants.space12),
                      Text(
                        'No learning activities yet.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.grey500),
                      ),
                      const SizedBox(height: AppConstants.space4),
                      Text(
                        'Add one for this student.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.grey500),
                      ),
                    ],
                  ),
                )
              else
                ...List.generate(_recentActivities.length, (i) {
                  final activity = _recentActivities[i];
                  return Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppConstants.space8),
                    child: GestureDetector(
                      onTap: () async {
                        await context.push(
                          AppRoutes.teacherActivityDetail,
                          extra: activity,
                        );
                        if (mounted) _loadActivities();
                      },
                      child: AppCard(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _typeColor(activity.activityType),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd),
                              ),
                              alignment: Alignment.center,
                              child: PhosphorIcon(
                                activity.activityType.phosphorIcon,
                                size: 22,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: AppConstants.space12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(activity.topic,
                                      style: AppTextStyles.h3),
                                  const SizedBox(
                                      height: AppConstants.space4),
                                  Text(
                                    '${activity.activityType.label} · ${activity.subject}',
                                    style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.grey500),
                                  ),
                                  if (activity.dueDate != null) ...[
                                    const SizedBox(
                                        height: AppConstants.space4),
                                    Text(
                                      'Due ${_formatDate(activity.dueDate!)}',
                                      style: AppTextStyles.bodySmall
                                          .copyWith(
                                              color: AppColors.grey500),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.grey300),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: AppConstants.space16),
              AppButton(
                label: 'Add learning activity',
                isFullWidth: true,
                leading: const Icon(Icons.add, size: 18),
                onPressed: () async {
                  await context.push(
                    AppRoutes.createActivity,
                    extra: student,
                  );
                  if (mounted) _loadActivities();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLessonsSection() {
    final now = DateTime.now();
    final followUp = _sessions
        .where((s) => s.status.isScheduled && s.hasEnded(now))
        .toList()
      ..sort((a, b) => b.localStart.compareTo(a.localStart));
    final upcoming = _sessions
        .where((s) => s.status.isScheduled && !s.hasEnded(now))
        .toList()
      ..sort((a, b) => a.localStart.compareTo(b.localStart));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lessons', style: AppTextStyles.h2),
        const SizedBox(height: AppConstants.space12),
        AppButton(
          label: 'Schedule lesson',
          isFullWidth: true,
          leading: const Icon(Icons.event_available, size: 18),
          onPressed: _scheduleLesson,
        ),
        if (followUp.isNotEmpty) ...[
          const SizedBox(height: AppConstants.space16),
          SectionHeader(title: 'Needs follow-up'),
          for (final s in followUp) ...[
            SessionCard(
              session: s,
              personName: s.childName,
              personKind: AvatarKind.child,
              showDay: true,
              onTap: () => _followUp(s),
              trailing: const Icon(Icons.rate_review_outlined,
                  color: AppColors.warning),
            ),
            const SizedBox(height: AppConstants.space12),
          ],
        ],
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: AppConstants.space16),
          SectionHeader(title: 'Upcoming'),
          for (final s in upcoming) ...[
            SessionCard(
              session: s,
              personName: s.childName,
              personKind: AvatarKind.child,
              showDay: true,
            ),
            const SizedBox(height: AppConstants.space12),
          ],
        ],
      ],
    );
  }

  Color _typeColor(ActivityType type) => switch (type) {
        ActivityType.lesson => AppColors.primaryLight,
        ActivityType.practice => AppColors.warningLight,
        ActivityType.homework => AppColors.successLight,
        ActivityType.revision => AppColors.errorLight,
      };

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}
