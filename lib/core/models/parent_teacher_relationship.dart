/// Lifecycle status of a [ParentTeacherRelationship].
enum RelationshipStatus {
  requested,
  accepted,
  rejected,
  cancelled,
  suspended;

  static RelationshipStatus fromString(String? value) {
    return switch (value) {
      'requested' => RelationshipStatus.requested,
      'accepted' => RelationshipStatus.accepted,
      'rejected' => RelationshipStatus.rejected,
      'cancelled' => RelationshipStatus.cancelled,
      'suspended' => RelationshipStatus.suspended,
      _ => throw FormatException('Unsupported relationship status: $value'),
    };
  }

  String get value => name;
}

/// The teaching arrangement between a parent's [studentId] and a [teacherId].
///
/// This is the MVP's core relationship. It is deliberately scoped to a single
/// student so that the same teacher can teach multiple children — including
/// several children of the same parent — as distinct relationships.
///
/// There is no separate `Class` entity in the MVP: the relationship itself is
/// the teaching arrangement.
class ParentTeacherRelationship {
  const ParentTeacherRelationship({
    required this.id,
    required this.parentId,
    required this.studentId,
    required this.teacherId,
    required this.subject,
    required this.level,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// The Supabase Auth user id of the parent who owns the student.
  final String parentId;

  /// The [Student] this arrangement is for.
  final String studentId;

  /// The Supabase Auth user id of the teacher.
  final String teacherId;

  final String subject;
  final String level;
  final RelationshipStatus status;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory ParentTeacherRelationship.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final parentId = map['parent_id'] as String?;
    final studentId = map['student_id'] as String?;
    final teacherId = map['teacher_id'] as String?;
    final subject = map['subject'] as String?;
    final level = map['level'] as String?;
    final status = map['status'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null ||
        parentId == null ||
        studentId == null ||
        teacherId == null ||
        subject == null ||
        level == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException(
          'Parent-teacher relationship row is missing required data.');
    }

    return ParentTeacherRelationship(
      id: id,
      parentId: parentId,
      studentId: studentId,
      teacherId: teacherId,
      subject: subject,
      level: level,
      status: RelationshipStatus.fromString(status),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  /// Builds the insert payload for a new relationship request.
  /// A newly created relationship always starts as [RelationshipStatus.requested].
  Map<String, dynamic> toInsertMap({required String parentId}) {
    return {
      'parent_id': parentId,
      'student_id': studentId,
      'teacher_id': teacherId,
      'subject': subject.trim(),
      'level': level.trim(),
      'status': RelationshipStatus.requested.value,
    };
  }
}
