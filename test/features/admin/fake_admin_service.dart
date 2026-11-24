import 'package:edu237/core/models/payment_transaction.dart';
import 'package:edu237/core/models/teacher_verification.dart';
import 'package:edu237/core/models/withdrawal.dart';
import 'package:edu237/core/services/admin_service.dart';

/// An in-memory [AdminService] for widget tests.
///
/// It mirrors the real contract that matters: the server decides who is an
/// admin, and settling records a reference rather than moving money.
class FakeAdminService implements AdminService {
  FakeAdminService({
    this.isAdmin = true,
    List<PendingWithdrawal>? pending,
    List<SettledWithdrawal>? recent,
    List<AdminPayment>? payments,
    List<AdminBillingRow>? billing,
    List<PendingVerification>? verifications,
    List<AdminUserSummary>? users,
    Map<String, AdminUserDetail>? userDetails,
    this.totals = AdminTotals.empty,
    this.push = PushOutcome.notConfigured,
    this.failure,
  })  : pending = pending ?? const [],
        recent = recent ?? const [],
        payments = payments ?? const [],
        billing = billing ?? const [],
        verifications = verifications ?? const [],
        users = users ?? const [],
        userDetails = userDetails ?? const {};

  bool isAdmin;
  List<PendingWithdrawal> pending;
  List<SettledWithdrawal> recent;
  List<AdminPayment> payments;
  List<AdminBillingRow> billing;
  List<PendingVerification> verifications;
  List<AdminUserSummary> users;
  Map<String, AdminUserDetail> userDetails;
  final AdminTotals totals;

  /// What the push attempt reports back. The in-app reminder always lands.
  final PushOutcome push;

  /// When set, every listing call fails with this message - used to prove a
  /// non-admin sees nothing useful even if they reach the screen.
  final String? failure;

  final List<({String id, String reference})> sent = [];
  final List<({String id, String reason})> rejected = [];
  final List<String> reminded = [];
  final List<({String id, bool approved, String? reason})> reviewed = [];
  final List<String> openedDocs = [];

  /// When false, a signed link cannot be created - the screen must say so
  /// rather than pretending the document opened.
  bool canSignDocs = true;

  @override
  Future<AdminResult> checkAdminAccess() async => AdminAccessSuccess(isAdmin);

  @override
  Future<AdminResult> fetchPendingWithdrawals() async {
    if (failure != null) return AdminFailure(failure!);
    return PendingWithdrawalsSuccess(pending);
  }

  @override
  Future<AdminResult> fetchRecentWithdrawals() async {
    if (failure != null) return AdminFailure(failure!);
    return SettledWithdrawalsSuccess(recent);
  }

  @override
  Future<AdminResult> fetchRecentPayments() async {
    if (failure != null) return AdminFailure(failure!);
    return AdminPaymentsSuccess(payments);
  }

  @override
  Future<AdminResult> fetchTotals() async {
    if (failure != null) return AdminFailure(failure!);
    return AdminTotalsSuccess(totals);
  }

  @override
  Future<AdminResult> fetchBillingOverview() async {
    if (failure != null) return AdminFailure(failure!);
    return AdminBillingSuccess(billing);
  }

  @override
  Future<AdminResult> sendPaymentReminder(String relationshipId) async {
    if (failure != null) return AdminFailure(failure!);
    reminded.add(relationshipId);
    return ReminderSentSuccess(push: push);
  }

  @override
  Future<AdminResult> fetchPendingVerifications() async {
    if (failure != null) return AdminFailure(failure!);
    return PendingVerificationsSuccess(verifications);
  }

  @override
  Future<AdminResult> reviewVerification({
    required String teacherId,
    required bool approve,
    String? reason,
  }) async {
    if (failure != null) return AdminFailure(failure!);
    if (!approve && (reason ?? '').trim().isEmpty) {
      return const AdminFailure('Say what needs correcting.');
    }
    reviewed.add((id: teacherId, approved: approve, reason: reason));
    verifications =
        verifications.where((v) => v.teacherId != teacherId).toList();
    return VerificationReviewedSuccess(approved: approve);
  }

  @override
  Future<AdminResult> fetchUsers({String? query, String? roleFilter}) async {
    if (failure != null) return AdminFailure(failure!);
    var result = users;
    if (roleFilter != null && roleFilter.isNotEmpty && roleFilter != 'all') {
      result = result.where((u) => u.role.name == roleFilter).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      result = result
          .where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              (u.phone ?? '').contains(q))
          .toList();
    }
    return AdminUsersSuccess(result);
  }

  @override
  Future<AdminResult> fetchUserDetail(String userId) async {
    if (failure != null) return AdminFailure(failure!);
    final detail = userDetails[userId];
    if (detail != null) return AdminUserDetailSuccess(detail);
    final summary = users.where((u) => u.id == userId).firstOrNull;
    if (summary != null) {
      return AdminUserDetailSuccess(AdminUserDetail(
        id: summary.id,
        email: summary.email,
        name: summary.name,
        phone: summary.phone,
        role: summary.role,
        profileComplete: summary.profileComplete,
        createdAt: summary.createdAt,
        updatedAt: summary.updatedAt,
      ));
    }
    return const AdminFailure('User not found.');
  }

  @override
  Future<String?> verificationDocUrl(String path) async {
    openedDocs.add(path);
    return canSignDocs ? 'https://example.test/signed/$path' : null;
  }

  @override
  Future<AdminResult> markWithdrawalSent({
    required String withdrawalId,
    required String reference,
  }) async {
    if (reference.trim().isEmpty) {
      return const AdminFailure('Enter the payment reference.');
    }
    sent.add((id: withdrawalId, reference: reference));
    pending = pending.where((w) => w.id != withdrawalId).toList();
    return const AdminActionSuccess(WithdrawalStatus.successful);
  }

  @override
  Future<AdminResult> rejectWithdrawal({
    required String withdrawalId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) return const AdminFailure('Enter a reason.');
    rejected.add((id: withdrawalId, reason: reason));
    pending = pending.where((w) => w.id != withdrawalId).toList();
    return const AdminActionSuccess(WithdrawalStatus.cancelled);
  }
}

PendingWithdrawal fakePending({
  String id = 'w1',
  String teacherName = 'Jam Ransom',
  int amount = 5000,
  String phone = '670123456',
}) =>
    PendingWithdrawal(
      id: id,
      teacherId: 'teacher-1',
      teacherName: teacherName,
      amount: amount,
      currency: 'XAF',
      payoutMedium: 'mobile money',
      payoutPhone: phone,
      requestedAt: DateTime(2026, 8, 13),
    );

AdminPayment fakeAdminPayment({
  String id = 'pay-1',
  PaymentPurpose purpose = PaymentPurpose.tutoringPayment,
  PaymentStatus status = PaymentStatus.successful,
  int amount = 5000,
  String? parentName = 'Mrs Ayuk',
  String? teacherName = 'Jam Ransom',
  String? childName = 'Favour',
}) =>
    AdminPayment(
      id: id,
      purpose: purpose,
      amount: amount,
      currency: 'XAF',
      status: status,
      parentName: parentName,
      teacherName: teacherName,
      childName: childName,
      providerTransId: 'FAPSHI-123',
      createdAt: DateTime(2026, 8, 13),
      paidAt: DateTime(2026, 8, 13),
    );

AdminBillingRow fakeBillingRow({
  String relationshipId = 'rel-1',
  String childName = 'Favour',
  String parentName = 'Mrs Ayuk',
  String teacherName = 'Jam Ransom',
  int monthlyAmount = 20000,
  int paidThisPeriod = 5000,
  int? balance,
}) =>
    AdminBillingRow(
      relationshipId: relationshipId,
      parentName: parentName,
      teacherName: teacherName,
      childName: childName,
      monthlyAmount: monthlyAmount,
      paidThisPeriod: paidThisPeriod,
      balance: balance ?? (monthlyAmount - paidThisPeriod),
      currency: 'XAF',
      startedOn: DateTime(2026, 8, 1),
      nextDueOn: DateTime(2026, 9, 1),
    );

PendingVerification fakePendingVerification({
  String teacherId = 'teacher-1',
  String teacherName = 'Jam Ransom',
  IdentityDocType? idType = IdentityDocType.nationalId,
  String? qualificationTitle = 'BSc Mathematics',
}) =>
    PendingVerification(
      teacherId: teacherId,
      teacherName: teacherName,
      identityDocPath: '$teacherId/id.jpg',
      qualificationDocPath: '$teacherId/cert.jpg',
      identityDocType: idType,
      qualificationTitle: qualificationTitle,
      submittedAt: DateTime(2026, 8, 19),
    );
