import 'lesson_session.dart';
import 'teacher_availability.dart';

/// Availability-aware time-slot generation — the heart of "only offer times the
/// teacher is actually free". Pure and side-effect-free so it can be unit
/// tested without a backend.
///
/// Given a [day], the teacher's [availability], the chosen [durationMinutes],
/// and the teacher's [existing] sessions (across ALL their students, for
/// collision detection), it returns the concrete start times that:
///   * fall entirely within that weekday's availability window,
///   * are not in the past (relative to [now]),
///   * do not overlap another SCHEDULED session (no double-booking).
///
/// [stepMinutes] controls the granularity of offered start times (default 30).
List<DateTime> candidateStartTimes({
  required DateTime day,
  required WeeklyAvailability availability,
  required int durationMinutes,
  required List<LessonSession> existing,
  required DateTime now,
  int stepMinutes = 30,
}) {
  // If the teacher has configured availability for this day, use it.
  // Otherwise, default to standard daytime hours (07:00 to 21:00) so scheduling
  // always works out of the box regardless of availability configuration.
  final slot = availability.forWeekday(day.weekday) ??
      AvailabilitySlot(
        weekday: day.weekday,
        startMinute: 7 * 60, // 07:00 AM
        endMinute: 21 * 60,  // 09:00 PM
      );

  // Only scheduled sessions can cause a collision.
  final busy = existing.where((s) => s.status.isScheduled).toList();

  final result = <DateTime>[];
  for (var startM = slot.startMinute;
      startM + durationMinutes <= slot.endMinute;
      startM += stepMinutes) {
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      startM ~/ 60,
      startM % 60,
    );
    if (!start.isAfter(now)) continue; // no past (or exactly-now) starts

    final end = start.add(Duration(minutes: durationMinutes));
    final collides = busy.any((s) {
      final sStart = s.localStart;
      final sEnd = s.localEnd;
      // Half-open overlap test.
      return start.isBefore(sEnd) && sStart.isBefore(end);
    });
    if (collides) continue;

    result.add(start);
  }
  return result;
}
