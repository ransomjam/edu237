import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import 'lesson_followup.dart';
import 'schedule_format.dart';
import 'session_widgets.dart';

/// The teacher's upcoming schedule as a simple chronological list (Today,
/// Tomorrow, This week, Later) plus a "Needs follow-up" group for lessons whose
/// time has passed but that haven't been marked yet.
class TeacherScheduleScreen extends StatefulWidget {
  const TeacherScheduleScreen({super.key});

  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
  bool _isLoading = true;
  String? _error;
  List<LessonSession> _sessions = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result =
        await LessonSessionServiceScope.of(context).fetchMyTeacherSessions();
    if (!mounted) return;
    if (result is LessonSessionListSuccess) {
      setState(() {
        _sessions = result.sessions;
        _isLoading = false;
      });
    } else if (result is LessonSessionFailure) {
      setState(() {
        _error = result.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _followUp(LessonSession s) async {
    final updated = await showLessonFollowUpSheet(context, s);
    if (updated != null && mounted) _load();
  }

  Future<void> _onAddLesson() async {
    final relResult = await ParentTeacherRelationshipServiceScope.of(context)
        .fetchMyRelationshipsAsTeacher();
    if (!mounted) return;

    if (relResult is! RelationshipListSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load connected students.')),
      );
      return;
    }

    final accepted = relResult.relationships
        .where((r) => r.status == RelationshipStatus.accepted)
        .toList();

    if (accepted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have no connected students to schedule with yet.'),
        ),
      );
      return;
    }

    final studentIds = accepted.map((r) => r.studentId).toSet().toList();
    final studentRes = await StudentServiceScope.of(context)
        .fetchStudentsByIds(studentIds);
    if (!mounted) return;

    if (studentRes is! StudentListSuccess || studentRes.students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load student profiles.')),
      );
      return;
    }

    final students = studentRes.students;
    Student? chosenStudent;

    if (students.length == 1) {
      chosenStudent = students.first;
    } else {
      chosenStudent = await showModalBottomSheet<Student>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select student to schedule',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.grey900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, idx) {
                        final s = students[idx];
                        final level = s.qualifiedLevelLabel ?? s.schoolLevel ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          title: Text(
                            s.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: level.isNotEmpty
                              ? Text(level, style: AppTextStyles.caption)
                              : null,
                          trailing: const Icon(Icons.arrow_forward_ios_rounded,
                              size: 14, color: AppColors.grey500),
                          onTap: () => Navigator.of(ctx).pop(s),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (chosenStudent == null || !mounted) return;

    final scheduled = await context.push<bool>(
      AppRoutes.scheduleLesson,
      extra: chosenStudent,
    );
    if (scheduled == true && mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Schedule a lesson',
            onPressed: _onAddLesson,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onAddLesson,
        tooltip: 'Schedule lesson',
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load your schedule',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    final now = DateTime.now();
    final needsFollowUp = _sessions
        .where((s) => s.status.isScheduled && s.hasEnded(now))
        .toList()
      ..sort((a, b) => b.localStart.compareTo(a.localStart));
    final upcoming = _sessions
        .where((s) => s.status.isScheduled && !s.hasEnded(now))
        .toList()
      ..sort((a, b) => a.localStart.compareTo(b.localStart));

    if (needsFollowUp.isEmpty && upcoming.isEmpty) {
      return AppEmptyState(
        icon: Icons.event_available_outlined,
        title: 'No lessons scheduled',
        message: 'Lessons you schedule with your students will appear here.',
        actionLabel: 'Schedule a lesson',
        onAction: _onAddLesson,
      );
    }

    final buckets = <ScheduleBucket, List<LessonSession>>{};
    for (final s in upcoming) {
      buckets.putIfAbsent(bucketFor(s.localStart, now), () => []).add(s);
    }
    const order = [
      ScheduleBucket.today,
      ScheduleBucket.tomorrow,
      ScheduleBucket.thisWeek,
      ScheduleBucket.later,
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          if (needsFollowUp.isNotEmpty) ...[
            SectionHeader(title: 'Needs follow-up'),
            for (final s in needsFollowUp) ...[
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
            const SizedBox(height: AppConstants.space12),
          ],
          for (final bucket in order)
            if ((buckets[bucket] ?? const []).isNotEmpty) ...[
              SectionHeader(title: bucketLabel(bucket)),
              for (final s in buckets[bucket]!) ...[
                SessionCard(
                  session: s,
                  personName: s.childName,
                  personKind: AvatarKind.child,
                  showDay: bucket == ScheduleBucket.thisWeek ||
                      bucket == ScheduleBucket.later,
                ),
                const SizedBox(height: AppConstants.space12),
              ],
              const SizedBox(height: AppConstants.space12),
            ],
        ],
      ),
    );
  }
}
