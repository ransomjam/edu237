import 'package:flutter/material.dart';

/// One recurring weekly availability window for a teacher — e.g. "Monday
/// 4:00 PM – 8:00 PM". A weekday with no [AvailabilitySlot] means the teacher is
/// unavailable that day.
///
/// [weekday] follows Dart's [DateTime.weekday] convention: Monday = 1 …
/// Sunday = 7, so it maps 1:1 to a scheduled lesson's `scheduledAt.weekday`.
/// Times are stored as minutes from midnight (0–1440) so there is no timezone
/// or date ambiguity — this is a weekly shape, not a calendar.
@immutable
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  /// 1 = Monday … 7 = Sunday (matches [DateTime.weekday]).
  final int weekday;

  /// Minutes from midnight the window opens (e.g. 16:00 → 960).
  final int startMinute;

  /// Minutes from midnight the window closes (e.g. 20:00 → 1200; 24:00 → 1440).
  final int endMinute;

  TimeOfDay get start =>
      TimeOfDay(hour: startMinute ~/ 60, minute: startMinute % 60);

  /// The closing time as a [TimeOfDay]. 1440 (midnight next day) is clamped to
  /// 23:59 for display, which is only ever used as a picker bound.
  TimeOfDay get end {
    final m = endMinute >= 1440 ? 1439 : endMinute;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  /// True when [minute] (minutes from midnight) falls inside this window,
  /// treating the window as half-open [start, end).
  bool containsMinute(int minute) => minute >= startMinute && minute < endMinute;

  factory AvailabilitySlot.fromMap(Map<String, dynamic> map) {
    final weekday = (map['weekday'] as num?)?.toInt();
    final startMinute = (map['start_minute'] as num?)?.toInt();
    final endMinute = (map['end_minute'] as num?)?.toInt();
    if (weekday == null || startMinute == null || endMinute == null) {
      throw const FormatException('Availability row is missing required data.');
    }
    return AvailabilitySlot(
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  /// Insert payload for the signed-in teacher.
  Map<String, dynamic> toInsertMap({required String teacherId}) => {
        'teacher_id': teacherId,
        'weekday': weekday,
        'start_minute': startMinute,
        'end_minute': endMinute,
      };

  AvailabilitySlot copyWith({int? startMinute, int? endMinute}) =>
      AvailabilitySlot(
        weekday: weekday,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  @override
  bool operator ==(Object other) =>
      other is AvailabilitySlot &&
      other.weekday == weekday &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(weekday, startMinute, endMinute);
}

/// A teacher's full recurring weekly availability: at most one [AvailabilitySlot]
/// per weekday. This is the value object screens and services pass around.
@immutable
class WeeklyAvailability {
  WeeklyAvailability(List<AvailabilitySlot> slots)
      : _byWeekday = {for (final s in slots) s.weekday: s};

  const WeeklyAvailability._(this._byWeekday);

  static const WeeklyAvailability empty = WeeklyAvailability._({});

  final Map<int, AvailabilitySlot> _byWeekday;

  /// Weekday order used everywhere: Monday → Sunday.
  static const List<int> weekdayOrder = [1, 2, 3, 4, 5, 6, 7];

  bool get isEmpty => _byWeekday.isEmpty;
  bool get isNotEmpty => _byWeekday.isNotEmpty;

  /// All windows, ordered Monday → Sunday.
  List<AvailabilitySlot> get slots =>
      [for (final d in weekdayOrder) if (_byWeekday[d] != null) _byWeekday[d]!];

  AvailabilitySlot? forWeekday(int weekday) => _byWeekday[weekday];

  /// Whether the teacher is available at the given [when] (local time): there is
  /// a window on that weekday and [when]'s time falls inside it.
  bool isAvailableAt(DateTime when) {
    final slot = _byWeekday[when.weekday];
    if (slot == null) return false;
    return slot.containsMinute(when.hour * 60 + when.minute);
  }

  /// Whether a lesson of [durationMinutes] starting at [when] fits entirely
  /// within that day's window.
  bool canFit(DateTime when, int durationMinutes) {
    final slot = _byWeekday[when.weekday];
    if (slot == null) return false;
    final startM = when.hour * 60 + when.minute;
    return startM >= slot.startMinute &&
        startM + durationMinutes <= slot.endMinute;
  }

  factory WeeklyAvailability.fromRows(List<Map<String, dynamic>> rows) =>
      WeeklyAvailability(rows.map(AvailabilitySlot.fromMap).toList());
}

/// Short weekday labels, indexed by [DateTime.weekday] (1–7).
const List<String> kWeekdayShort = [
  '', // 0 unused
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Full weekday labels, indexed by [DateTime.weekday] (1–7).
const List<String> kWeekdayLong = [
  '', // 0 unused
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats minutes-from-midnight as a 12-hour clock label, e.g. 960 → "4:00 PM".
String formatMinuteOfDay(int minute) {
  final m = minute >= 1440 ? 1440 : minute;
  final h24 = (m ~/ 60) % 24;
  final mm = m % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  var h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  final mmStr = mm.toString().padLeft(2, '0');
  return '$h12:$mmStr $period';
}

/// Formats a [TimeOfDay] as e.g. "4:00 PM".
String formatTimeOfDay(TimeOfDay t) => formatMinuteOfDay(t.hour * 60 + t.minute);

/// Builds a compact, human summary of a weekly availability, grouping runs of
/// consecutive weekdays that share the same window:
///
///   "Mon–Fri · 4:00 PM–8:00 PM"
///   "Sat · 9:00 AM–2:00 PM"
///
/// Returns an empty list when there is no availability.
List<String> availabilitySummaryLines(WeeklyAvailability availability) {
  final slots = availability.slots;
  if (slots.isEmpty) return const [];

  final lines = <String>[];
  var runStart = 0;
  while (runStart < slots.length) {
    var runEnd = runStart;
    // Extend the run while the weekday is consecutive AND the window identical.
    while (runEnd + 1 < slots.length &&
        slots[runEnd + 1].weekday == slots[runEnd].weekday + 1 &&
        slots[runEnd + 1].startMinute == slots[runStart].startMinute &&
        slots[runEnd + 1].endMinute == slots[runStart].endMinute) {
      runEnd++;
    }
    final first = slots[runStart];
    final last = slots[runEnd];
    final days = runStart == runEnd
        ? kWeekdayShort[first.weekday]
        : '${kWeekdayShort[first.weekday]}–${kWeekdayShort[last.weekday]}';
    final window =
        '${formatMinuteOfDay(first.startMinute)}–${formatMinuteOfDay(first.endMinute)}';
    lines.add('$days · $window');
    runStart = runEnd + 1;
  }
  return lines;
}
