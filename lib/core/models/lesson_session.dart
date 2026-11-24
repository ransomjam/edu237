import 'teaching_mode.dart';

/// Lifecycle of a [LessonSession]. Deliberately a flat set, not a state
/// machine: a session is Scheduled until the teacher records how it went.
enum SessionStatus {
  scheduled,
  completed,
  cancelled,
  missed;

  static SessionStatus fromString(String? value) => switch (value) {
        'scheduled' => SessionStatus.scheduled,
        'completed' => SessionStatus.completed,
        'cancelled' => SessionStatus.cancelled,
        'missed' => SessionStatus.missed,
        _ => SessionStatus.scheduled,
      };

  String get value => name;

  String get label => switch (this) {
        SessionStatus.scheduled => 'Scheduled',
        SessionStatus.completed => 'Completed',
        SessionStatus.cancelled => 'Cancelled',
        SessionStatus.missed => 'Missed',
      };

  bool get isScheduled => this == SessionStatus.scheduled;
}

/// One actual, scheduled lesson built on top of an accepted
/// parent_teacher_relationship.
///
/// The relationship is the source of truth for who teaches whom; the identity
/// fields ([teacherId], [studentId], [parentId]) are derived server-side from
/// it and are read-only here. [studentName] / [teacherName] are read-only
/// display snapshots so both sides can render a card without extra joins.
class LessonSession {
  const LessonSession({
    required this.id,
    required this.relationshipId,
    required this.teacherId,
    required this.studentId,
    required this.parentId,
    required this.subject,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.teachingMode,
    this.locationArea,
    this.locationCity,
    required this.status,
    this.note,
    this.reminderMinutesBefore = 30,
    this.studentName,
    this.teacherName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String relationshipId;
  final String teacherId;
  final String studentId;
  final String parentId;
  final String subject;

  /// Lesson start. Stored as UTC in Postgres; use [localStart] for display.
  final DateTime scheduledAt;
  final int durationMinutes;
  final TeachingMode teachingMode;

  /// Coarse in-person location — area/neighbourhood and city only, never a
  /// precise address. Null for online lessons.
  final String? locationArea;
  final String? locationCity;

  final SessionStatus status;

  /// Optional short teacher note added during follow-up.
  final String? note;

  /// Minutes before [scheduledAt] a reminder should fire (MVP default 30).
  final int reminderMinutesBefore;

  final String? studentName;
  final String? teacherName;

  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get localStart => scheduledAt.toLocal();

  DateTime get localEnd =>
      localStart.add(Duration(minutes: durationMinutes));

  /// The instant a reminder for this session is due.
  DateTime get reminderTime =>
      scheduledAt.subtract(Duration(minutes: reminderMinutesBefore));

  /// A coarse in-person location label ("Bastos" / "Bastos, Yaoundé"), or null.
  String? get locationLabel {
    final a = (locationArea ?? '').trim();
    final c = (locationCity ?? '').trim();
    if (a.isNotEmpty && c.isNotEmpty) return '$a, $c';
    if (a.isNotEmpty) return a;
    if (c.isNotEmpty) return c;
    return null;
  }

  /// True once the lesson's end time has passed (used to offer follow-up).
  bool hasEnded(DateTime now) => now.isAfter(localEnd);

  String get childName =>
      (studentName ?? '').trim().isNotEmpty ? studentName!.trim() : 'Student';

  factory LessonSession.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final relationshipId = map['relationship_id'] as String?;
    final teacherId = map['teacher_id'] as String?;
    final studentId = map['student_id'] as String?;
    final parentId = map['parent_id'] as String?;
    final subject = map['subject'] as String?;
    final scheduledAt = map['scheduled_at'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    // Build a descriptive message listing every null field for easy debugging.
    final missing = <String>[
      if (id == null) 'id',
      if (relationshipId == null) 'relationship_id',
      if (teacherId == null) 'teacher_id',
      if (studentId == null) 'student_id',
      if (parentId == null) 'parent_id',
      if (subject == null) 'subject',
      if (scheduledAt == null) 'scheduled_at',
      if (createdAt == null) 'created_at',
      if (updatedAt == null) 'updated_at',
    ];
    if (missing.isNotEmpty) {
      throw FormatException(
          'Lesson session row is missing required fields: ${missing.join(', ')}. '
          'Row keys: ${map.keys.toList()}');
    }

    return LessonSession(
      id: id!,
      relationshipId: relationshipId!,
      teacherId: teacherId!,
      studentId: studentId!,
      parentId: parentId!,
      subject: subject!,
      scheduledAt: DateTime.parse(scheduledAt!),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
      teachingMode: TeachingMode.fromString(map['teaching_mode'] as String?),
      locationArea: map['location_area'] as String?,
      locationCity: map['location_city'] as String?,
      status: SessionStatus.fromString(map['status'] as String?),
      note: map['note'] as String?,
      reminderMinutesBefore:
          (map['reminder_minutes_before'] as num?)?.toInt() ?? 30,
      studentName: map['student_name'] as String?,
      teacherName: map['teacher_name'] as String?,
      createdAt: DateTime.parse(createdAt!),
      updatedAt: DateTime.parse(updatedAt!),
    );
  }

  /// Insert payload. Identity fields are intentionally omitted — the database
  /// derives teacher_id / student_id / parent_id from [relationshipId].
  Map<String, dynamic> toInsertMap() {
    return {
      'relationship_id': relationshipId,
      'subject': subject,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'teaching_mode': teachingMode.value,
      'location_area': (locationArea?.trim().isEmpty ?? true)
          ? null
          : locationArea!.trim(),
      'location_city': (locationCity?.trim().isEmpty ?? true)
          ? null
          : locationCity!.trim(),
      'reminder_minutes_before': reminderMinutesBefore,
    };
  }

  LessonSession copyWith({
    SessionStatus? status,
    String? note,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) {
    return LessonSession(
      id: id,
      relationshipId: relationshipId,
      teacherId: teacherId,
      studentId: studentId,
      parentId: parentId,
      subject: subject,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      teachingMode: teachingMode,
      locationArea: locationArea,
      locationCity: locationCity,
      status: status ?? this.status,
      note: note ?? this.note,
      reminderMinutesBefore: reminderMinutesBefore,
      studentName: studentName,
      teacherName: teacherName,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
