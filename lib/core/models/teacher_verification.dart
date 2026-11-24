/// Where a teacher stands with Camiva's trust check.
///
/// A teacher is never called verified before an Camiva admin approves the
/// documents: submitting moves them to [pending] and no further.
enum VerificationStatus {
  required$('required'),
  pending('pending'),
  verified('verified'),
  rejected('rejected');

  const VerificationStatus(this.value);
  final String value;

  static VerificationStatus fromString(String? value) => switch (value) {
        'pending' => VerificationStatus.pending,
        'verified' => VerificationStatus.verified,
        'rejected' => VerificationStatus.rejected,
        _ => VerificationStatus.required$,
      };

  bool get isVerified => this == VerificationStatus.verified;

  /// Wording that never overstates where the teacher actually is.
  String get label => switch (this) {
        VerificationStatus.required$ => 'Verification required',
        VerificationStatus.pending => 'Verification pending',
        VerificationStatus.verified => 'Verified',
        VerificationStatus.rejected => 'Needs correction',
      };

  String get message => switch (this) {
        VerificationStatus.required$ =>
          'Send your ID and a qualification document so Camiva can verify you.',
        VerificationStatus.pending =>
          'Camiva is checking your documents. This usually takes a short while.',
        VerificationStatus.verified =>
          'Camiva has verified your documents.',
        VerificationStatus.rejected =>
          'Camiva needs a correction before you can continue.',
      };
}

/// The kind of identity document submitted.
enum IdentityDocType {
  nationalId('national_id', 'National ID'),
  passport('passport', 'Passport'),
  driversLicence('drivers_licence', "Driver's licence");

  const IdentityDocType(this.value, this.label);
  final String value;
  final String label;

  static IdentityDocType? fromString(String? value) => switch (value) {
        'national_id' => IdentityDocType.nationalId,
        'passport' => IdentityDocType.passport,
        'drivers_licence' => IdentityDocType.driversLicence,
        _ => null,
      };
}

/// A teacher's verification record.
class TeacherVerification {
  const TeacherVerification({
    required this.teacherId,
    required this.status,
    this.identityDocType,
    this.qualificationTitle,
    this.submittedAt,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String teacherId;
  final VerificationStatus status;
  final IdentityDocType? identityDocType;
  final String? qualificationTitle;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  /// What Camiva asked to be corrected. Only set when rejected.
  final String? rejectionReason;

  static const none = TeacherVerification(
    teacherId: '',
    status: VerificationStatus.required$,
  );

  factory TeacherVerification.fromMap(Map<String, dynamic> map) {
    DateTime? parse(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return TeacherVerification(
      teacherId: (map['teacher_id'] as String?) ?? '',
      status: VerificationStatus.fromString(map['status'] as String?),
      identityDocType:
          IdentityDocType.fromString(map['identity_doc_type'] as String?),
      qualificationTitle: map['qualification_title'] as String?,
      submittedAt: parse('submitted_at'),
      reviewedAt: parse('reviewed_at'),
      rejectionReason: map['rejection_reason'] as String?,
    );
  }
}
