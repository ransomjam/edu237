import '../../core/models/teacher_availability.dart';

/// Formats a lesson time as a 12-hour clock label, e.g. "4:00 PM".
String clockLabel(DateTime when) {
  final local = when.toLocal();
  return formatMinuteOfDay(local.hour * 60 + local.minute);
}

/// A friendly day label relative to [now]: "Today", "Tomorrow", or a weekday
/// with date like "Thu · 21 Aug".
String dayLabel(DateTime when, DateTime now) {
  final d = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${kWeekdayShort[when.weekday]} · ${when.day} ${_month(when.month)}';
}

/// Combined date + time, e.g. "Today · 4:00 PM".
String dayTimeLabel(DateTime when, DateTime now) =>
    '${dayLabel(when, now)} · ${clockLabel(when)}';

/// Which chronological bucket a session falls into for the schedule list.
enum ScheduleBucket { today, tomorrow, thisWeek, later, past }

ScheduleBucket bucketFor(DateTime when, DateTime now) {
  final d = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  if (diff < 0) return ScheduleBucket.past;
  if (diff == 0) return ScheduleBucket.today;
  if (diff == 1) return ScheduleBucket.tomorrow;
  if (diff <= 7) return ScheduleBucket.thisWeek;
  return ScheduleBucket.later;
}

String bucketLabel(ScheduleBucket bucket) => switch (bucket) {
      ScheduleBucket.today => 'Today',
      ScheduleBucket.tomorrow => 'Tomorrow',
      ScheduleBucket.thisWeek => 'This week',
      ScheduleBucket.later => 'Later',
      ScheduleBucket.past => 'Past',
    };

String _month(int m) => const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][m];

/// A short duration label, e.g. "1 hour", "1h 30 min", "45 min".
String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) {
    return h == 1 ? '1 hour' : '$h hours';
  }
  return '${h}h $m min';
}
