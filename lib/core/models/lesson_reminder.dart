import 'lesson_session.dart';

/// Who a reminder is being shown to. The copy differs slightly per audience.
enum ReminderAudience { teacher, parent }

/// A single, computed reminder for a scheduled lesson.
///
/// Reminders are NOT stored: they are derived from the actual [LessonSession]
/// (its [LessonSession.scheduledAt] and [LessonSession.reminderMinutesBefore]).
/// This keeps the first implementation free of push infrastructure while still
/// being driven by real session data — a push/notification backend can later
/// consume exactly the same planner output.
class LessonReminder {
  const LessonReminder({
    required this.session,
    required this.audience,
    required this.minutesUntilStart,
  });

  final LessonSession session;
  final ReminderAudience audience;

  /// Whole minutes from "now" until the lesson starts (>= 0).
  final int minutesUntilStart;

  /// A short, audience-appropriate reminder line.
  ///
  ///   Teacher: "Class in 30 minutes · Daniel · Mathematics"
  ///   Parent:  "Daniel's Mathematics lesson starts in 30 minutes."
  String get message {
    final mins = minutesUntilStart;
    final whenPhrase = mins <= 0
        ? 'now'
        : mins == 1
            ? 'in 1 minute'
            : 'in $mins minutes';
    switch (audience) {
      case ReminderAudience.teacher:
        return 'Class $whenPhrase · ${session.childName} · ${session.subject}';
      case ReminderAudience.parent:
        final child = session.childName;
        return "$child's ${session.subject} lesson starts $whenPhrase.";
    }
  }
}

/// Pure, side-effect-free reminder computation.
///
/// Given the real sessions and the current time, it decides which sessions are
/// currently "within their reminder window" — i.e. now is at or after
/// `scheduledAt - reminderMinutesBefore` and strictly before the lesson start.
/// Only [SessionStatus.scheduled] sessions in the future qualify; cancelled,
/// missed, completed, and already-started/past sessions never produce a
/// reminder.
abstract final class LessonReminderPlanner {
  /// The active reminders at [now], soonest lesson first.
  static List<LessonReminder> due(
    List<LessonSession> sessions, {
    required ReminderAudience audience,
    required DateTime now,
  }) {
    final reminders = <LessonReminder>[];
    for (final s in sessions) {
      if (!s.status.isScheduled) continue;
      final start = s.localStart;
      // Lesson must still be in the future.
      if (!start.isAfter(now)) continue;
      final windowOpens = start.subtract(
        Duration(minutes: s.reminderMinutesBefore),
      );
      // Reminder is due only once we've entered its window.
      if (now.isBefore(windowOpens)) continue;

      final minutesUntil = start.difference(now).inMinutes;
      reminders.add(LessonReminder(
        session: s,
        audience: audience,
        minutesUntilStart: minutesUntil < 0 ? 0 : minutesUntil,
      ));
    }
    reminders.sort(
      (a, b) => a.session.localStart.compareTo(b.session.localStart),
    );
    return reminders;
  }

  /// Whether [session] would fire a reminder at [now]. Convenience wrapper used
  /// by tests and single-session checks.
  static bool isReminderDue(LessonSession session, {required DateTime now}) {
    return due([session], audience: ReminderAudience.teacher, now: now)
        .isNotEmpty;
  }
}
