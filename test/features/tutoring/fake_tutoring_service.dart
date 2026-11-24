import 'package:edu237/core/models/service_plan.dart';
import 'package:edu237/core/models/teacher_verification.dart';
import 'package:edu237/core/models/tutoring_agreement.dart';
import 'package:edu237/core/services/tutoring_service.dart';

/// A scripted [TutoringService].
///
/// It mirrors the two server-side rules the flow depends on: a teacher cannot
/// propose before being verified, and only the parent can confirm.
class FakeTutoringService implements TutoringService {
  FakeTutoringService({
    this.verification = TeacherVerification.none,
    this.agreement,
    this.expected,
    this.submitMovesToPending = true,
    this.plan = const TeacherServicePlan(
      state: ServicePlanState.notStarted,
      amount: 3000,
      currency: 'XAF',
    ),
    this.failWith,
  });

  TeacherVerification verification;
  TutoringAgreement? agreement;
  ExpectedPayment? expected;

  /// Submitting documents makes a teacher 'pending', never 'verified'.
  final bool submitMovesToPending;
  String? failWith;

  final List<Map<String, Object?>> proposals = [];
  final List<String> confirmed = [];
  final List<({String id, String? reason})> declined = [];
  final List<String> uploads = [];

  /// The teacher's service plan state, and what they agreed to.
  TeacherServicePlan plan;
  final List<String> acceptedTerms = [];

  @override
  Future<TutoringResult> fetchMyVerification() async =>
      VerificationSuccess(verification);

  @override
  Future<String?> uploadVerificationDoc({
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async {
    uploads.add(fileName);
    return 'teacher-1/$fileName';
  }

  @override
  Future<TutoringResult> submitVerification({
    required String identityDocPath,
    required IdentityDocType identityDocType,
    required String qualificationDocPath,
    String? qualificationTitle,
  }) async {
    if (failWith != null) return TutoringFailure(failWith!);
    verification = TeacherVerification(
      teacherId: 'teacher-1',
      status: submitMovesToPending
          ? VerificationStatus.pending
          : verification.status,
      identityDocType: identityDocType,
      qualificationTitle: qualificationTitle,
      submittedAt: DateTime(2026, 8, 18),
    );
    return VerificationSuccess(verification);
  }

  @override
  Future<TutoringResult> fetchAgreement(String relationshipId) async =>
      AgreementSuccess(agreement);

  @override
  Future<TutoringResult> proposeAgreement({
    required String relationshipId,
    required String subject,
    required DateTime startDate,
    required LessonFrequency frequency,
    required int lessonsPerWeek,
    required int lessonMinutes,
    required int price,
    required PriceUnit priceUnit,
    required TeachingModeChoice teachingMode,
    String? locationArea,
    AgreementPaymentMethod paymentMethod = AgreementPaymentMethod.edu237,
    PaymentFrequency paymentFrequency = PaymentFrequency.perMonth,
  }) async {
    // The server refuses this; the fake refuses it too, so a UI that skipped
    // the gate would fail the test rather than pass it.
    if (!verification.status.isVerified) {
      return const TutoringFailure('Complete your verification first');
    }
    if (failWith != null) return TutoringFailure(failWith!);

    proposals.add({
      'relationshipId': relationshipId,
      'subject': subject,
      'startDate': startDate,
      'frequency': frequency,
      'lessonsPerWeek': lessonsPerWeek,
      'lessonMinutes': lessonMinutes,
      'price': price,
      'priceUnit': priceUnit,
      'teachingMode': teachingMode,
      'locationArea': locationArea,
      'paymentMethod': paymentMethod,
      'paymentFrequency': paymentFrequency,
    });
    agreement = fakeAgreement(
      price: price,
      priceUnit: priceUnit,
      lessonsPerWeek: lessonsPerWeek,
      paymentMethod: paymentMethod,
    );
    return AgreementSuccess(agreement);
  }

  @override
  Future<TutoringResult> confirmAgreement(String agreementId) async {
    if (failWith != null) return TutoringFailure(failWith!);
    confirmed.add(agreementId);
    agreement = fakeAgreement(status: AgreementStatus.confirmed);
    return AgreementSuccess(agreement);
  }

  @override
  Future<TutoringResult> declineAgreement({
    required String agreementId,
    String? reason,
  }) async {
    if (failWith != null) return TutoringFailure(failWith!);
    declined.add((id: agreementId, reason: reason));
    agreement = fakeAgreement(status: AgreementStatus.declined);
    return AgreementSuccess(agreement);
  }

  @override
  Future<TutoringResult> fetchExpectedPayment(String agreementId) async =>
      ExpectedPaymentSuccess(expected);

  @override
  Future<TutoringResult> fetchServicePlan() async => ServicePlanSuccess(plan);

  @override
  Future<TutoringResult> acceptTerms({
    required String termsText,
    String? requestId,
  }) async {
    if (failWith != null) return TutoringFailure(failWith!);
    acceptedTerms.add(termsText);
    return const TermsAcceptedSuccess();
  }
}

TutoringAgreement fakeAgreement({
  String id = 'agr-1',
  AgreementStatus status = AgreementStatus.proposed,
  int price = 5000,
  PriceUnit priceUnit = PriceUnit.perLesson,
  int lessonsPerWeek = 2,
  int lessonMinutes = 60,
  TeachingModeChoice teachingMode = TeachingModeChoice.inPerson,
  String? locationArea = 'Bastos',
  AgreementPaymentMethod paymentMethod = AgreementPaymentMethod.edu237,
}) =>
    TutoringAgreement(
      id: id,
      relationshipId: 'rel-1',
      parentId: 'parent-1',
      teacherId: 'teacher-1',
      studentId: 'student-1',
      subject: 'Mathematics',
      startDate: DateTime(2026, 8, 18),
      frequency: LessonFrequency.twiceWeekly,
      lessonsPerWeek: lessonsPerWeek,
      lessonMinutes: lessonMinutes,
      price: price,
      priceUnit: priceUnit,
      currency: 'XAF',
      teachingMode: teachingMode,
      locationArea: locationArea,
      paymentMethod: paymentMethod,
      paymentFrequency: PaymentFrequency.perMonth,
      status: status,
      proposedAt: DateTime(2026, 8, 17),
      parentConfirmedAt:
          status == AgreementStatus.confirmed || status == AgreementStatus.active
              ? DateTime(2026, 8, 17)
              : null,
    );

ExpectedPayment fakeExpected({
  int amount = 10000,
  bool isCamivaManaged = true,
}) =>
    ExpectedPayment(
      amount: amount,
      currency: 'XAF',
      dueOn: DateTime(2026, 8, 18),
      frequency: PaymentFrequency.perMonth,
      isCamivaManaged: isCamivaManaged,
    );

/// A verified teacher, for tests that need to get past the trust gate.
TeacherVerification fakeAgreementVerification() => const TeacherVerification(
      teacherId: 'teacher-1',
      status: VerificationStatus.verified,
    );
