/// Lifecycle status of a [TeacherRequest].
enum TeacherRequestStatus {
  pending,
  accepted,
  declined,
  cancelled;

  static TeacherRequestStatus fromString(String? value) {
    return switch (value) {
      'pending' => TeacherRequestStatus.pending,
      'accepted' => TeacherRequestStatus.accepted,
      'declined' => TeacherRequestStatus.declined,
      'cancelled' => TeacherRequestStatus.cancelled,
      _ => throw FormatException('Unsupported teacher request status: $value'),
    };
  }

  String get value => name;

  /// True when this status counts as "active" for the duplicate-prevention
  /// index (pending or accepted).
  bool get isActive => this == pending || this == accepted;
}

/// A parent's request asking a teacher to teach one of their children.
///
/// parent → student → teacher
///
/// A [TeacherRequest] is distinct from a [ParentTeacherRelationship]: the
/// relationship is created only after the teacher accepts. Until then only
/// this request row exists.
class TeacherRequest {
  const TeacherRequest({
    required this.id,
    required this.parentId,
    required this.studentId,
    required this.teacherId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.studentName,
    this.studentForm,
    this.studentSubjects = const <String>[],
  });

  final String id;

  /// Supabase Auth user id of the parent who made the request.
  final String parentId;

  /// ID of the [Student] this request is for.
  final String studentId;

  /// Supabase Auth user id of the teacher being requested.
  final String teacherId;

  final TeacherRequestStatus status;

  final DateTime createdAt;
  final DateTime updatedAt;

  // --- Child identity snapshot (denormalised onto the request) --------------
  // These are written server-side by a BEFORE INSERT trigger from the owning
  // parent's `students` row, so the teacher — who can always read requests
  // addressed to them — always has safe context to identify the child (name,
  // Form, subjects) for ANY request status, without reading the students table
  // and without weakening RLS. They are read-only from the client's view.

  /// The child's name at request time.
  final String? studentName;

  /// The child's Form/class at request time (e.g. "Form 4").
  final String? studentForm;

  /// The child's subjects at request time.
  final List<String> studentSubjects;

  /// Whether the request carries enough context to identify the child.
  bool get hasChildContext => (studentName ?? '').trim().isNotEmpty;

  /// Child's name for display, or a safe fallback.
  String get childName =>
      (studentName ?? '').trim().isNotEmpty ? studentName!.trim() : 'Child';

  factory TeacherRequest.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final parentId = map['parent_id'] as String?;
    final studentId = map['student_id'] as String?;
    final teacherId = map['teacher_id'] as String?;
    final status = map['status'] as String?;
    final createdAt = map['created_at'] as String?;
    final updatedAt = map['updated_at'] as String?;

    if (id == null ||
        parentId == null ||
        studentId == null ||
        teacherId == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Teacher request row is missing required data.');
    }

    final rawSubjects = map['student_subjects'];
    final subjects = rawSubjects is List
        ? rawSubjects.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    return TeacherRequest(
      id: id,
      parentId: parentId,
      studentId: studentId,
      teacherId: teacherId,
      status: TeacherRequestStatus.fromString(status),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      studentName: map['student_name'] as String?,
      studentForm: map['student_form'] as String?,
      studentSubjects: subjects,
    );
  }

  /// Insert payload for a new pending request.
  /// The database assigns id, created_at, updated_at.
  Map<String, dynamic> toInsertMap() {
    return {
      'parent_id': parentId,
      'student_id': studentId,
      'teacher_id': teacherId,
      'status': TeacherRequestStatus.pending.value,
    };
  }
}
