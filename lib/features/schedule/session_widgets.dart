import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson_reminder.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/teacher_availability.dart';
import '../../core/models/teaching_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import 'schedule_format.dart';

/// Colour language for session status (section 24 of the brief):
///   blue = scheduled/upcoming · green = completed · orange = attention (missed)
///   · grey = cancelled.
class _StatusVisual {
  const _StatusVisual(this.fg, this.bg);
  final Color fg;
  final Color bg;

  static _StatusVisual of(SessionStatus status) => switch (status) {
        SessionStatus.scheduled =>
          const _StatusVisual(AppColors.primary, AppColors.primaryLight),
        SessionStatus.completed =>
          const _StatusVisual(AppColors.success, AppColors.successLight),
        SessionStatus.missed =>
          const _StatusVisual(AppColors.warning, AppColors.warningLight),
        SessionStatus.cancelled =>
          const _StatusVisual(AppColors.grey500, AppColors.grey100),
      };
}

/// A small pill stating a session's status.
class SessionStatusBadge extends StatelessWidget {
  const SessionStatusBadge({super.key, required this.status});
  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final v = _StatusVisual.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: v.bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.caption
            .copyWith(color: v.fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The teaching-mode + location line for a session ("In person · Bastos" /
/// "Online").
String sessionModeLabel(LessonSession s) {
  if (s.teachingMode == TeachingMode.online) return 'Online';
  final loc = s.locationLabel;
  return loc == null ? 'In person' : 'In person · $loc';
}

/// A schedule card where the TIME is visually dominant, with a subject badge,
/// the other person's name, teaching mode, and a status pill.
///
/// [personName]/[personKind] is who the viewer cares about — the student (for a
/// teacher) or the teacher (for a parent).
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.personName,
    this.personKind = AvatarKind.person,
    this.showDay = false,
    this.onTap,
    this.trailing,
  });

  final LessonSession session;
  final String personName;
  final AvatarKind personKind;

  /// When true, the time column also shows the day ("Today" / "Tomorrow").
  final bool showDay;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dominant time column.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDay)
                    Text(
                      dayLabel(session.localStart, now),
                      style: AppTextStyles.caption
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  Text(
                    clockLabel(session.localStart),
                    style: AppTextStyles.h2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: session.status.isScheduled
                          ? AppColors.grey900
                          : AppColors.grey500,
                    ),
                  ),
                  Text(
                    durationLabel(session.durationMinutes),
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const SizedBox(width: AppConstants.space16),
              Container(width: 1, height: 52, color: AppColors.divider),
              const SizedBox(width: AppConstants.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName,
                      style: AppTextStyles.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppConstants.space8),
                    Wrap(
                      spacing: AppConstants.space8,
                      runSpacing: AppConstants.space4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SubjectChip(subject: session.subject),
                        SessionStatusBadge(status: session.status),
                      ],
                    ),
                    const SizedBox(height: AppConstants.space8),
                    Row(
                      children: [
                        Icon(
                          session.teachingMode == TeachingMode.online
                              ? Icons.videocam_outlined
                              : Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.grey500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(sessionModeLabel(session),
                              style: AppTextStyles.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    if ((session.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: AppConstants.space8),
                      Text('“${session.note!.trim()}”',
                          style: AppTextStyles.bodySmall
                              .copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppConstants.space8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact "next lesson" highlight used on parent surfaces.
///
///   Daniel's next lesson
///   4:00 PM · Today
///   Mathematics · with Jam Ransom
///   Online / In person · Bastos
class NextLessonCard extends StatelessWidget {
  const NextLessonCard({
    super.key,
    required this.title,
    required this.session,
    this.onTap,
  });

  final String title;
  final LessonSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppTextStyles.label
                      .copyWith(color: AppColors.primaryDark)),
              const SizedBox(height: AppConstants.space8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(clockLabel(session.localStart),
                      style: AppTextStyles.h1
                          .copyWith(color: AppColors.primaryDark)),
                  const SizedBox(width: AppConstants.space8),
                  Text(dayLabel(session.localStart, now),
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.primaryDark)),
                ],
              ),
              const SizedBox(height: AppConstants.space4),
              Text(
                '${session.subject} · with ${session.teacherName ?? 'your teacher'}',
                style: AppTextStyles.body.copyWith(color: AppColors.grey900),
              ),
              const SizedBox(height: AppConstants.space8),
              Row(
                children: [
                  Icon(
                    session.teachingMode == TeachingMode.online
                        ? Icons.videocam_outlined
                        : Icons.location_on_outlined,
                    size: 15,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 4),
                  Text(sessionModeLabel(session),
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.primaryDark)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A read-only weekly availability display, used on the public teacher profile.
class AvailabilityView extends StatelessWidget {
  const AvailabilityView({super.key, required this.availability});
  final WeeklyAvailability availability;

  @override
  Widget build(BuildContext context) {
    final lines = availabilitySummaryLines(availability);
    if (lines.isEmpty) {
      return Text('Not set yet',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey500));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.space4),
            child: Row(
              children: [
                const Icon(Icons.schedule,
                    size: 15, color: AppColors.grey500),
                const SizedBox(width: AppConstants.space8),
                Text(line, style: AppTextStyles.bodyLarge),
              ],
            ),
          ),
      ],
    );
  }
}

/// A quiet, tappable in-app reminder banner. Surfaced on Home when a lesson is
/// within its reminder window. Not a push notification — an in-app alert driven
/// by the real session (see [LessonReminderPlanner]).
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key, required this.reminder, this.onTap});
  final LessonReminder reminder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningLight,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Text(
                  reminder.message,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.grey900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
