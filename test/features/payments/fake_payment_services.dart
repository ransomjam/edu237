import 'package:edu237/core/models/billing_summary.dart';
import 'package:edu237/core/models/fee_config.dart';
import 'package:edu237/core/models/parent_teacher_relationship.dart';
import 'package:edu237/core/models/payment_reminder.dart';
import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/models/teacher_earnings.dart';
import 'package:edu237/core/models/withdrawal.dart';
import 'package:edu237/core/services/earnings_service.dart';
import 'package:edu237/core/services/parent_teacher_relationship_service.dart';
import 'package:edu237/core/services/payment_service.dart';

/// A scripted PaymentService.
///
/// It records exactly what the UI asked for, which is how the tests check the
/// two rules that matter: the client never sends an amount, and it never
/// declares a payment successful — it only reports what the "server" returns.
class FakePaymentService implements PaymentService {
  FakePaymentService({
    this.config = FeeConfig.unknown,
    this.activationState = ActivationState.notRequired,
    this.quote = 5000,
    this.startStatus = PaymentStatus.pending,
    this.verifyStatuses = const [PaymentStatus.successful],
    this.contactRevealed = false,
    this.contactName,
    this.contactPhone,
    this.activity = TeacherActivity.none,
    this.reminders = const [],
    this.payments = const [],
    this.billing,
    this.failStartWith,
  });

  FeeConfig config;
  ActivationState activationState;
  int quote;
  PaymentStatus startStatus;

  /// Statuses returned by successive verifyPayment calls.
  List<PaymentStatus> verifyStatuses;

  bool contactRevealed;
  String? contactName;
  String? contactPhone;
  TeacherActivity activity;
  List<PaymentReminder> reminders;
  List<PaymentTransaction> payments;
  String? failStartWith;

  /// The monthly picture this arrangement has, if any.
  BillingSummary? billing;

  // ---- recorded calls ------------------------------------------------------
  final List<Map<String, Object?>> startCalls = [];

  /// The instalment each start proposed. Null means "server decides".
  final List<int?> startedAmounts = [];
  final List<String> verifiedPaymentIds = [];
  final List<String> readReminderIds = [];
  final List<Map<String, Object?>> supportRequests = [];
  int _verifyIndex = 0;

  @override
  Future<PaymentResult> fetchFeeConfig() async => FeeConfigSuccess(config);

  @override
  Future<PaymentResult> fetchActivationState(String relationshipId) async =>
      ActivationStateSuccess(activationState);

  @override
  Future<PaymentResult> fetchQuote({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
  }) async =>
      PaymentQuoteSuccess(amount: quote, currency: 'XAF');

  @override
  Future<PaymentResult> startPayment({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
    String? sessionId,
    String? payerPhone,
    int? amount,
  }) async {
    startedAmounts.add(amount);
    startCalls.add({
      'purpose': purpose,
      'relationshipId': relationshipId,
      'units': units,
      'sessionId': sessionId,
      'payerPhone': payerPhone,
    });
    if (failStartWith != null) return PaymentFailure(failStartWith!);
    return PaymentStartSuccess(paymentId: 'pay-1', status: startStatus);
  }

  @override
  Future<PaymentResult> verifyPayment(String paymentId) async {
    verifiedPaymentIds.add(paymentId);
    final status = _verifyIndex < verifyStatuses.length
        ? verifyStatuses[_verifyIndex]
        : verifyStatuses.last;
    _verifyIndex++;
    return PaymentStatusSuccess(status);
  }

  @override
  Future<PaymentResult> fetchPayment(String paymentId) async =>
      payments.isEmpty
          ? const PaymentFailure('Payment not found.')
          : PaymentSuccess(payments.first);

  @override
  Future<PaymentResult> fetchMyPaymentsAsParent() async =>
      PaymentListSuccess(payments);

  @override
  Future<PaymentResult> fetchMyPaymentsAsTeacher() async =>
      PaymentListSuccess(payments);

  @override
  Future<PaymentResult> fetchPaymentsForRelationship(
          String relationshipId) async =>
      PaymentListSuccess(payments);

  @override
  Future<PaymentResult> fetchRelationshipContact(String relationshipId) async =>
      ContactSuccess(
        revealed: contactRevealed,
        name: contactRevealed ? contactName : null,
        phone: contactRevealed ? contactPhone : null,
      );

  @override
  Future<PaymentResult> fetchBillingSummary(String relationshipId) async =>
      BillingSummarySuccess(billing);

  @override
  Future<PaymentResult> fetchReminders() async =>
      ReminderListSuccess(reminders);

  @override
  Future<PaymentResult> markReminderRead(String reminderId) async {
    readReminderIds.add(reminderId);
    return const PaymentActionSuccess();
  }

  @override
  Future<PaymentResult> fetchTeacherActivity(String teacherId) async =>
      TeacherActivitySuccess(activity);

  @override
  Future<PaymentResult> submitSupportRequest({
    required String message,
    String? paymentId,
    String? relationshipId,
    String? withdrawalId,
  }) async {
    supportRequests.add({
      'message': message,
      'paymentId': paymentId,
      'relationshipId': relationshipId,
      'withdrawalId': withdrawalId,
    });
    return const PaymentActionSuccess();
  }
}

/// A scripted EarningsService that behaves like the server: it never reports a
/// withdrawal as successful at request time.
class FakeEarningsService implements EarningsService {
  FakeEarningsService({
    this.earnings = TeacherEarnings.empty,
    this.history = const [],
    this.withdrawals = const [],
    this.account,
    this.serviceFee,
    this.requestResult = WithdrawalStatus.processing,
    this.requestFailure,
  });

  TeacherEarnings earnings;
  List<PaymentTransaction> history;
  List<Withdrawal> withdrawals;
  PayoutAccount? account;
  ServiceFeePeriod? serviceFee;
  WithdrawalStatus requestResult;
  String? requestFailure;

  final List<int> requestedAmounts = [];
  final List<String> verifiedWithdrawalIds = [];
  final List<String> remindedPeriodIds = [];
  final List<Map<String, Object?>> savedAccounts = [];

  @override
  Future<EarningsResult> fetchEarnings() async => EarningsSuccess(earnings);

  @override
  Future<EarningsResult> fetchEarningsHistory() async =>
      EarningsHistorySuccess(history);

  @override
  Future<EarningsResult> fetchPayoutAccount() async =>
      PayoutAccountSuccess(account);

  @override
  Future<EarningsResult> savePayoutAccount({
    required String phone,
    required String medium,
    String? accountName,
  }) async {
    if (!PayoutAccount.isValidPhone(phone)) {
      return const EarningsFailure('Enter a valid number, e.g. 670000000.');
    }
    savedAccounts.add({'phone': phone, 'medium': medium});
    account = PayoutAccount(
      teacherId: 'teacher-1',
      medium: medium,
      phone: phone,
    );
    return PayoutAccountSuccess(account);
  }

  @override
  Future<EarningsResult> requestWithdrawal(int amount) async {
    requestedAmounts.add(amount);
    if (requestFailure != null) return EarningsFailure(requestFailure!);
    return WithdrawalStatusSuccess(requestResult);
  }

  @override
  Future<EarningsResult> fetchWithdrawals() async =>
      WithdrawalListSuccess(withdrawals);

  @override
  Future<EarningsResult> verifyWithdrawal(String withdrawalId) async {
    verifiedWithdrawalIds.add(withdrawalId);
    return WithdrawalStatusSuccess(WithdrawalStatus.processing);
  }

  @override
  Future<EarningsResult> fetchServiceFeePeriod() async =>
      ServiceFeeSuccess(serviceFee);

  @override
  Future<EarningsResult> markServiceFeeReminded(String periodId) async {
    remindedPeriodIds.add(periodId);
    return ServiceFeeSuccess(serviceFee);
  }
}

/// The parent's accepted relationships, for the screens that offer "pay for
/// tutoring" against a real arrangement.
class FakeParentRelationshipService
    implements ParentTeacherRelationshipService {
  FakeParentRelationshipService({this.relationships = const []});

  List<ParentTeacherRelationship> relationships;

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsParent() async =>
      RelationshipListSuccess(relationships);

  @override
  Future<RelationshipResult> fetchMyRelationshipsAsTeacher() async =>
      const RelationshipListSuccess([]);

  @override
  Future<RelationshipResult> fetchRelationshipsForStudent(
          String studentId) async =>
      const RelationshipListSuccess([]);

  @override
  Future<RelationshipResult> requestRelationship({
    required String studentId,
    required String teacherId,
    required String subject,
    required String level,
  }) async =>
      const RelationshipFailure('unused');

  @override
  Future<RelationshipResult> updateStatus({
    required String relationshipId,
    required RelationshipStatus status,
  }) async =>
      const RelationshipFailure('unused');
}

// ---------------------------------------------------------------------------
// Test data builders
// ---------------------------------------------------------------------------

ParentTeacherRelationship fakeRelationship({
  String id = 'rel-1',
  String studentId = 'student-1',
  String teacherId = 'teacher-1',
  String subject = 'Mathematics',
  RelationshipStatus status = RelationshipStatus.accepted,
}) =>
    ParentTeacherRelationship(
      id: id,
      parentId: 'parent-1',
      studentId: studentId,
      teacherId: teacherId,
      subject: subject,
      level: 'Form 4',
      status: status,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );

PaymentTransaction fakePayment({
  String id = 'pay-1',
  PaymentPurpose purpose = PaymentPurpose.tutoringPayment,
  PaymentStatus status = PaymentStatus.successful,
  int amount = 5000,
  String? studentName = 'Daniel',
  String? teacherName = 'Jam Ransom',
  String? providerTransId = 'FAPSHI-123',
  String? relationshipId = 'rel-1',
}) =>
    PaymentTransaction(
      id: id,
      purpose: purpose,
      payerId: 'parent-1',
      parentId: 'parent-1',
      teacherId: 'teacher-1',
      studentId: 'student-1',
      relationshipId: relationshipId,
      amount: amount,
      currency: 'XAF',
      status: status,
      providerTransId: providerTransId,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
      paidAt: status == PaymentStatus.successful ? DateTime(2026, 8, 13) : null,
      studentName: studentName,
      teacherName: teacherName,
    );

FeeConfig fakeConfig({
  int? activationFee = 1000,
  bool activationRequired = true,
  int? serviceFee,
}) =>
    FeeConfig(
      currency: 'XAF',
      teacherServiceFeeAmount: serviceFee,
      teacherServiceFeeIntervalDays: 30,
      matchActivationFeeAmount: activationFee,
      matchActivationRequired: activationRequired,
      settlementDelayHours: 24,
      minWithdrawalAmount: 100,
    );
