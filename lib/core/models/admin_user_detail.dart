import 'user_role.dart';

/// One student / learner summary as seen in admin user relationships.
class AdminLinkedStudent {
  const AdminLinkedStudent({
    required this.id,
    required this.name,
    this.level,
    this.subsystem,
    this.subjects = const [],
  });

  final String id;
  final String name;
  final String? level;
  final String? subsystem;
  final List<String> subjects;

  factory AdminLinkedStudent.fromMap(Map<String, dynamic> map) {
    return AdminLinkedStudent(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Student',
      level: map['level'] as String? ?? map['grade_level'] as String?,
      subsystem: map['subsystem'] as String?,
      subjects: [
        for (final s in (map['subjects'] as List<dynamic>? ?? const []))
          s.toString(),
      ],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'level': level,
        'subsystem': subsystem,
        'subjects': subjects,
      };
}

/// Comprehensive details for a teacher user.
class AdminTeacherDetails {
  const AdminTeacherDetails({
    required this.displayName,
    this.bio,
    this.subjects = const [],
    this.forms = const [],
    this.hourlyRate = 0,
    this.teachingMode,
    this.town,
    this.neighbourhood,
    this.verificationStatus = 'unverified',
    this.identityDocPath,
    this.qualificationDocPath,
    this.qualificationTitle,
    this.payoutPhone,
    this.payoutMedium,
    this.totalEarnings = 0,
    this.availableBalance = 0,
    this.activeAgreementsCount = 0,
    this.students = const [],
  });

  final String displayName;
  final String? bio;
  final List<String> subjects;
  final List<String> forms;
  final int hourlyRate;
  final String? teachingMode;
  final String? town;
  final String? neighbourhood;
  final String verificationStatus;
  final String? identityDocPath;
  final String? qualificationDocPath;
  final String? qualificationTitle;
  final String? payoutPhone;
  final String? payoutMedium;
  final int totalEarnings;
  final int availableBalance;
  final int activeAgreementsCount;
  final List<AdminLinkedStudent> students;

  String get locationLabel {
    final t = (town ?? '').trim();
    final n = (neighbourhood ?? '').trim();
    if (t.isNotEmpty && n.isNotEmpty) return '$n, $t';
    if (t.isNotEmpty) return t;
    if (n.isNotEmpty) return n;
    return 'Cameroon';
  }

  factory AdminTeacherDetails.fromMap(Map<String, dynamic> map) {
    return AdminTeacherDetails(
      displayName: (map['display_name'] as String?) ?? 'Teacher',
      bio: map['bio'] as String?,
      subjects: [
        for (final s in (map['subjects'] as List<dynamic>? ?? const []))
          s.toString(),
      ],
      forms: [
        for (final f in (map['forms'] as List<dynamic>? ?? const []))
          f.toString(),
      ],
      hourlyRate: (map['hourly_rate'] as num?)?.toInt() ?? 0,
      teachingMode: map['teaching_mode'] as String?,
      town: map['town'] as String?,
      neighbourhood: map['neighbourhood'] as String?,
      verificationStatus:
          (map['verification_status'] as String?) ?? 'unverified',
      identityDocPath: map['identity_doc_path'] as String?,
      qualificationDocPath: map['qualification_doc_path'] as String?,
      qualificationTitle: map['qualification_title'] as String?,
      payoutPhone: map['payout_phone'] as String?,
      payoutMedium: map['payout_medium'] as String?,
      totalEarnings: (map['total_earnings'] as num?)?.toInt() ?? 0,
      availableBalance: (map['available_balance'] as num?)?.toInt() ?? 0,
      activeAgreementsCount:
          (map['active_agreements_count'] as num?)?.toInt() ?? 0,
      students: [
        for (final item in (map['students'] as List<dynamic>? ?? const []))
          AdminLinkedStudent.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }
}

/// Comprehensive details for a parent user.
class AdminParentDetails {
  const AdminParentDetails({
    this.children = const [],
    this.activeTeachers = const [],
    this.activeAgreementsCount = 0,
    this.totalPaid = 0,
    this.outstandingBalance = 0,
  });

  final List<AdminLinkedStudent> children;
  final List<String> activeTeachers;
  final int activeAgreementsCount;
  final int totalPaid;
  final int outstandingBalance;

  factory AdminParentDetails.fromMap(Map<String, dynamic> map) {
    return AdminParentDetails(
      children: [
        for (final item in (map['children'] as List<dynamic>? ?? const []))
          AdminLinkedStudent.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      activeTeachers: [
        for (final t in (map['active_teachers'] as List<dynamic>? ?? const []))
          t.toString(),
      ],
      activeAgreementsCount:
          (map['active_agreements_count'] as num?)?.toInt() ?? 0,
      totalPaid: (map['total_paid'] as num?)?.toInt() ?? 0,
      outstandingBalance: (map['outstanding_balance'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Comprehensive details for a student user.
class AdminStudentDetails {
  const AdminStudentDetails({
    required this.studentId,
    this.parentId,
    this.parentName,
    this.parentPhone,
    this.isSelfManaged = false,
    this.subsystem,
    this.level,
    this.series,
    this.subjects = const [],
    this.assignedTeachers = const [],
    this.totalSessions = 0,
  });

  final String studentId;
  final String? parentId;
  final String? parentName;
  final String? parentPhone;
  final bool isSelfManaged;
  final String? subsystem;
  final String? level;
  final String? series;
  final List<String> subjects;
  final List<String> assignedTeachers;
  final int totalSessions;

  factory AdminStudentDetails.fromMap(Map<String, dynamic> map) {
    return AdminStudentDetails(
      studentId: (map['student_id'] as String?) ?? '',
      parentId: map['parent_id'] as String?,
      parentName: map['parent_name'] as String?,
      parentPhone: map['parent_phone'] as String?,
      isSelfManaged: (map['is_self_managed'] as bool?) ?? false,
      subsystem: map['subsystem'] as String?,
      level: map['level'] as String? ?? map['grade_level'] as String?,
      series: map['series'] as String?,
      subjects: [
        for (final s in (map['subjects'] as List<dynamic>? ?? const []))
          s.toString(),
      ],
      assignedTeachers: [
        for (final t
            in (map['assigned_teachers'] as List<dynamic>? ?? const []))
          t.toString(),
      ],
      totalSessions: (map['total_sessions'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A compact user summary row for the Admin Users table.
class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.role,
    this.profileComplete = false,
    required this.createdAt,
    this.updatedAt,
    this.teacherVerificationStatus,
    this.childrenCount,
    this.studentsCount,
    this.subjects = const [],
    this.town,
    this.balance,
    this.totalEarnings,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final UserRole role;
  final bool profileComplete;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Quick summary fields
  final String? teacherVerificationStatus;
  final int? childrenCount;
  final int? studentsCount;
  final List<String> subjects;
  final String? town;
  final int? balance;
  final int? totalEarnings;

  String get roleLabel => switch (role) {
        UserRole.parent => 'Parent',
        UserRole.teacher => 'Teacher',
        UserRole.student => 'Student',
      };

  factory AdminUserSummary.fromMap(Map<String, dynamic> map) {
    final roleStr = map['active_role'] as String? ?? 'parent';
    final parsedRole = switch (roleStr) {
      'teacher' => UserRole.teacher,
      'student' => UserRole.student,
      _ => UserRole.parent,
    };

    return AdminUserSummary(
      id: (map['id'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'User',
      phone: map['phone'] as String?,
      role: parsedRole,
      profileComplete: (map['profile_complete'] as bool?) ?? false,
      createdAt: DateTime.parse(
          map['created_at'] as String? ?? '1970-01-01T00:00:00Z'),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
      teacherVerificationStatus: map['verification_status'] as String?,
      childrenCount: (map['children_count'] as num?)?.toInt(),
      studentsCount: (map['students_count'] as num?)?.toInt(),
      subjects: [
        for (final s in (map['subjects'] as List<dynamic>? ?? const []))
          s.toString(),
      ],
      town: map['town'] as String?,
      balance: (map['balance'] as num?)?.toInt(),
      totalEarnings: (map['total_earnings'] as num?)?.toInt(),
    );
  }
}

/// The full detailed user record, viewed when selecting a user in Admin.
class AdminUserDetail {
  const AdminUserDetail({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.role,
    this.profileComplete = false,
    required this.createdAt,
    this.updatedAt,
    this.teacherProfile,
    this.parentProfile,
    this.studentProfile,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final UserRole role;
  final bool profileComplete;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final AdminTeacherDetails? teacherProfile;
  final AdminParentDetails? parentProfile;
  final AdminStudentDetails? studentProfile;

  String get roleLabel => switch (role) {
        UserRole.parent => 'Parent',
        UserRole.teacher => 'Teacher',
        UserRole.student => 'Student',
      };

  factory AdminUserDetail.fromMap(Map<String, dynamic> map) {
    final roleStr = map['active_role'] as String? ?? 'parent';
    final parsedRole = switch (roleStr) {
      'teacher' => UserRole.teacher,
      'student' => UserRole.student,
      _ => UserRole.parent,
    };

    return AdminUserDetail(
      id: (map['id'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'User',
      phone: map['phone'] as String?,
      role: parsedRole,
      profileComplete: (map['profile_complete'] as bool?) ?? false,
      createdAt: DateTime.parse(
          map['created_at'] as String? ?? '1970-01-01T00:00:00Z'),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
      teacherProfile: map['teacher_profile'] != null
          ? AdminTeacherDetails.fromMap(
              Map<String, dynamic>.from(map['teacher_profile'] as Map))
          : null,
      parentProfile: map['parent_profile'] != null
          ? AdminParentDetails.fromMap(
              Map<String, dynamic>.from(map['parent_profile'] as Map))
          : null,
      studentProfile: map['student_profile'] != null
          ? AdminStudentDetails.fromMap(
              Map<String, dynamic>.from(map['student_profile'] as Map))
          : null,
    );
  }
}
