// Learning activity domain models.
//
// A [LearningActivity] is a lightweight record created by a teacher
// for one or more connected students. It replaces the previous
// heavy-weight lesson/assignment/submission model with a
// select-tap-confirm workflow.

/// The kind of learning activity.
enum ActivityType {
  lesson,
  practice,
  homework,
  revision;

  /// Human-readable label.
  String get label => switch (this) {
        lesson => 'Lesson',
        practice => 'Practice',
        homework => 'Homework',
        revision => 'Revision',
      };

  /// Phosphor icon name for quick visual identification.
  String get phosphorIcon => switch (this) {
        lesson => 'book-open',
        practice => 'pencil-simple',
        homework => 'file-text',
        revision => 'arrow-clockwise',
      };

  /// Deprecated: emojis removed across Camiva UI. Returns empty string.
  String get emoji => '';

  /// Parse from database string.
  static ActivityType fromString(String value) => switch (value) {
        'lesson' => lesson,
        'practice' => practice,
        'homework' => homework,
        'revision' => revision,
        _ => lesson,
      };
}

/// Per-student status for a learning activity.
enum ActivityStatus {
  upcoming,
  inProgress,
  completed,
  needsAttention;

  /// Human-readable label.
  String get label => switch (this) {
        upcoming => 'Upcoming',
        inProgress => 'In progress',
        completed => 'Completed',
        needsAttention => 'Needs attention',
      };

  /// Database string.
  String get value => switch (this) {
        upcoming => 'upcoming',
        inProgress => 'in_progress',
        completed => 'completed',
        needsAttention => 'needs_attention',
      };

  /// Parse from database string.
  static ActivityStatus fromString(String value) => switch (value) {
        'upcoming' => upcoming,
        'in_progress' => inProgress,
        'completed' => completed,
        'needs_attention' => needsAttention,
        _ => upcoming,
      };
}

/// A learning activity created by a teacher.
class LearningActivity {
  const LearningActivity({
    required this.id,
    required this.teacherId,
    required this.subject,
    required this.form,
    required this.topic,
    required this.activityType,
    this.note,
    this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String teacherId;
  final String subject;
  final String form;
  final String topic;
  final ActivityType activityType;
  final String? note;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LearningActivity.fromMap(Map<String, dynamic> map) {
    return LearningActivity(
      id: map['id'] as String,
      teacherId: map['teacher_id'] as String,
      subject: map['subject'] as String,
      form: map['form'] as String,
      topic: map['topic'] as String,
      activityType: ActivityType.fromString(map['activity_type'] as String),
      note: map['note'] as String?,
      dueDate: map['due_date'] != null
          ? DateTime.parse(map['due_date'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'teacher_id': teacherId,
        'subject': subject,
        'form': form,
        'topic': topic,
        'activity_type': activityType.name,
        'note': note,
        'due_date': dueDate?.toIso8601String().split('T')[0],
      };

  LearningActivity copyWith({
    String? id,
    String? teacherId,
    String? subject,
    String? form,
    String? topic,
    ActivityType? activityType,
    String? note,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LearningActivity(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      subject: subject ?? this.subject,
      form: form ?? this.form,
      topic: topic ?? this.topic,
      activityType: activityType ?? this.activityType,
      note: note ?? this.note,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// A recipient row linking a student to a learning activity with status.
class ActivityRecipient {
  const ActivityRecipient({
    required this.id,
    required this.activityId,
    required this.studentId,
    required this.status,
    this.teacherNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final String studentId;
  final ActivityStatus status;
  final String? teacherNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ActivityRecipient.fromMap(Map<String, dynamic> map) {
    return ActivityRecipient(
      id: map['id'] as String,
      activityId: map['activity_id'] as String,
      studentId: map['student_id'] as String,
      status: ActivityStatus.fromString(map['status'] as String),
      teacherNote: map['teacher_note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  ActivityRecipient copyWith({
    String? id,
    String? activityId,
    String? studentId,
    ActivityStatus? status,
    String? teacherNote,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ActivityRecipient(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      studentId: studentId ?? this.studentId,
      status: status ?? this.status,
      teacherNote: teacherNote ?? this.teacherNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
