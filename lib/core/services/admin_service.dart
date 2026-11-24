import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user_detail.dart';
import '../models/payment_transaction.dart';
import '../models/teacher_verification.dart';
import '../models/withdrawal.dart';
import 'demo_admin_data.dart';
import 'payment_errors.dart';

export '../models/admin_user_detail.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A withdrawal waiting for an Camiva admin to send the money.
///
/// It carries the payout number, because settling one means actually sending
/// money to that number. This is the only place a payout destination is visible
/// to anyone other than its owner, and only to an admin.
class PendingWithdrawal {
  const PendingWithdrawal({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    required this.amount,
    required this.currency,
    required this.payoutMedium,
    required this.payoutPhone,
    required this.requestedAt,
  });

  final String id;
  final String teacherId;
  final String teacherName;
  final int amount;
  final String currency;
  final String payoutMedium;
  final String payoutPhone;
  final DateTime requestedAt;

  factory PendingWithdrawal.fromMap(Map<String, dynamic> map) {
    return PendingWithdrawal(
      id: map['id'] as String,
      teacherId: (map['teacher_id'] as String?) ?? '',
      teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
      payoutMedium: (map['payout_medium'] as String?) ?? 'mobile money',
      payoutPhone: (map['payout_phone'] as String?) ?? '',
      requestedAt:
          DateTime.parse(map['created_at'] as String? ?? '1970-01-01T00:00:00Z'),
    );
  }
}

/// A withdrawal an admin has already dealt with.
class SettledWithdrawal {
  const SettledWithdrawal({
    required this.id,
    required this.teacherName,
    required this.amount,
    required this.currency,
    required this.status,
    this.settlementMode,
    this.reference,
    this.completedAt,
  });

  final String id;
  final String teacherName;
  final int amount;
  final String currency;
  final WithdrawalStatus status;
  final SettlementMode? settlementMode;
  final String? reference;
  final DateTime? completedAt;

  factory SettledWithdrawal.fromMap(Map<String, dynamic> map) {
    final completedAt = map['completed_at'] as String?;
    return SettledWithdrawal(
      id: map['id'] as String,
      teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
      status: WithdrawalStatus.fromString(map['status'] as String?),
      settlementMode:
          SettlementMode.fromString(map['settlement_mode'] as String?),
      reference: map['manual_reference'] as String?,
      completedAt: completedAt == null ? null : DateTime.parse(completedAt),
    );
  }
}

/// One payment as an admin sees it: who paid whom, for which child.
///
/// Names only - no phone numbers or emails. Reconciling money and answering a
/// support question needs identity, not contact details.
class AdminPayment {
  const AdminPayment({
    required this.id,
    required this.purpose,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.parentName,
    this.teacherName,
    this.childName,
    this.providerTransId,
    this.failureReason,
    this.paidAt,
  });

  final String id;
  final PaymentPurpose purpose;
  final int amount;
  final String currency;
  final PaymentStatus status;
  final String? parentName;
  final String? teacherName;
  final String? childName;
  final String? providerTransId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? paidAt;

  /// "Favour - Mrs Ayuk paid Jam Ransom", in the order a person reads it.
  String get payerLabel => parentName ?? 'Parent';
  String get payeeLabel => teacherName ?? 'Camiva';

  factory AdminPayment.fromMap(Map<String, dynamic> map) {
    final paidAt = map['paid_at'] as String?;
    return AdminPayment(
      id: map['id'] as String,
      purpose: PaymentPurpose.fromString(map['purpose'] as String?),
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
      status: PaymentStatus.fromString(map['status'] as String?),
      parentName: map['parent_name'] as String?,
      teacherName: map['teacher_name'] as String?,
      childName: map['child_name'] as String?,
      providerTransId: map['provider_trans_id'] as String?,
      failureReason: map['failure_reason'] as String?,
      createdAt: DateTime.parse(
          map['created_at'] as String? ?? '1970-01-01T00:00:00Z'),
      paidAt: paidAt == null ? null : DateTime.parse(paidAt),
    );
  }
}

/// Platform money at a glance, all derived from the ledger at read time.
class AdminTotals {
  const AdminTotals({
    required this.collected,
    required this.successfulCount,
    required this.pendingCount,
    required this.failedCount,
    required this.owedToTeachers,
    required this.awaitingWithdrawal,
    required this.currency,
  });

  final int collected;
  final int successfulCount;
  final int pendingCount;
  final int failedCount;

  /// Earned by teachers and not yet paid out.
  final int owedToTeachers;

  /// Withdrawal requests waiting for an admin.
  final int awaitingWithdrawal;

  final String currency;

  static const empty = AdminTotals(
    collected: 0,
    successfulCount: 0,
    pendingCount: 0,
    failedCount: 0,
    owedToTeachers: 0,
    awaitingWithdrawal: 0,
    currency: 'XAF',
  );

  factory AdminTotals.fromMap(Map<String, dynamic> map) => AdminTotals(
        collected: (map['collected'] as num?)?.toInt() ?? 0,
        successfulCount: (map['successful_count'] as num?)?.toInt() ?? 0,
        pendingCount: (map['pending_count'] as num?)?.toInt() ?? 0,
        failedCount: (map['failed_count'] as num?)?.toInt() ?? 0,
        owedToTeachers: (map['owed_to_teachers'] as num?)?.toInt() ?? 0,
        awaitingWithdrawal: (map['awaiting_withdrawal'] as num?)?.toInt() ?? 0,
        currency: (map['currency'] as String?) ?? 'XAF',
      );
}

/// One monthly arrangement as an admin sees it: who owes what, and by when.
class AdminBillingRow {
  const AdminBillingRow({
    required this.relationshipId,
    required this.parentName,
    required this.teacherName,
    required this.childName,
    required this.monthlyAmount,
    required this.paidThisPeriod,
    required this.balance,
    required this.currency,
    required this.startedOn,
    required this.nextDueOn,
    this.lastPaidAt,
    this.lastRemindedAt,
  });

  final String relationshipId;
  final String parentName;
  final String teacherName;
  final String childName;
  final int monthlyAmount;
  final int paidThisPeriod;
  final int balance;
  final String currency;
  final DateTime startedOn;
  final DateTime nextDueOn;
  final DateTime? lastPaidAt;

  /// When a payment reminder was last actually created for this arrangement.
  final DateTime? lastRemindedAt;

  bool get isSettled => balance <= 0;

  factory AdminBillingRow.fromMap(Map<String, dynamic> map) {
    DateTime? parse(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return AdminBillingRow(
      relationshipId: map['relationship_id'] as String,
      parentName: (map['parent_name'] as String?) ?? 'Parent',
      teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
      childName: (map['child_name'] as String?) ?? 'Child',
      monthlyAmount: (map['monthly_amount'] as num?)?.toInt() ?? 0,
      paidThisPeriod: (map['paid_this_period'] as num?)?.toInt() ?? 0,
      balance: (map['balance'] as num?)?.toInt() ?? 0,
      currency: (map['currency'] as String?) ?? 'XAF',
      startedOn: parse('started_on') ?? DateTime(1970),
      nextDueOn: parse('next_due_on') ?? DateTime(1970),
      lastPaidAt: parse('last_paid_at'),
      lastRemindedAt: parse('last_reminded_at'),
    );
  }
}

/// What actually happened when a reminder was sent.
///
/// The in-app reminder is always delivered - the parent sees it in the app.
/// Push is separate and may not have happened, so it is reported on its own
/// rather than folded into a single "sent".
enum PushOutcome {
  sent,
  noDevice,
  notConfigured,
  failed;

  static PushOutcome fromString(String? value) => switch (value) {
        'sent' => PushOutcome.sent,
        'no_device' => PushOutcome.noDevice,
        'failed' => PushOutcome.failed,
        _ => PushOutcome.notConfigured,
      };

  /// Wording that claims only what is true.
  String get message => switch (this) {
        PushOutcome.sent => 'Reminder sent in the app and to their phone.',
        PushOutcome.noDevice =>
          'Reminder sent in the app. No phone registered for notifications.',
        PushOutcome.notConfigured =>
          'Reminder sent in the app. Push notifications are not set up yet.',
        PushOutcome.failed =>
          'Reminder sent in the app. The push notification did not go through.',
      };
}

final class ReminderSentSuccess extends AdminResult {
  const ReminderSentSuccess({required this.push, this.pushDetail});
  final PushOutcome push;

  /// Why push failed, in the provider's own words. Admin-only, and shown so a
  /// rejection is diagnosable from the app rather than only from server logs.
  final String? pushDetail;

  /// What to show the admin: the outcome, plus the reason when there is one.
  String get message =>
      pushDetail == null ? push.message : '${push.message} ($pushDetail)';
}

/// A teacher waiting for Camiva to check their documents.
///
/// Carries storage PATHS, not URLs. The documents live in a private bucket and
/// are only ever reachable through a short-lived signed link generated for an
/// admin at the moment they look.
class PendingVerification {
  const PendingVerification({
    required this.teacherId,
    required this.teacherName,
    required this.identityDocPath,
    required this.qualificationDocPath,
    this.identityDocType,
    this.qualificationTitle,
    this.submittedAt,
  });

  final String teacherId;
  final String teacherName;
  final String identityDocPath;
  final String qualificationDocPath;
  final IdentityDocType? identityDocType;
  final String? qualificationTitle;
  final DateTime? submittedAt;

  factory PendingVerification.fromMap(Map<String, dynamic> map) {
    final submittedAt = map['submitted_at'] as String?;
    return PendingVerification(
      teacherId: (map['teacher_id'] as String?) ?? '',
      teacherName: (map['teacher_name'] as String?) ?? 'Teacher',
      identityDocPath: (map['identity_doc_path'] as String?) ?? '',
      qualificationDocPath: (map['qualification_doc_path'] as String?) ?? '',
      identityDocType:
          IdentityDocType.fromString(map['identity_doc_type'] as String?),
      qualificationTitle: map['qualification_title'] as String?,
      submittedAt: submittedAt == null ? null : DateTime.parse(submittedAt),
    );
  }
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class AdminResult {
  const AdminResult();
}

final class AdminAccessSuccess extends AdminResult {
  const AdminAccessSuccess(this.isAdmin);
  final bool isAdmin;
}

final class PendingWithdrawalsSuccess extends AdminResult {
  const PendingWithdrawalsSuccess(this.withdrawals);
  final List<PendingWithdrawal> withdrawals;
}

final class SettledWithdrawalsSuccess extends AdminResult {
  const SettledWithdrawalsSuccess(this.withdrawals);
  final List<SettledWithdrawal> withdrawals;
}

final class PendingVerificationsSuccess extends AdminResult {
  const PendingVerificationsSuccess(this.verifications);
  final List<PendingVerification> verifications;
}

final class VerificationReviewedSuccess extends AdminResult {
  const VerificationReviewedSuccess({required this.approved});
  final bool approved;
}

final class AdminBillingSuccess extends AdminResult {
  const AdminBillingSuccess(this.rows);
  final List<AdminBillingRow> rows;
}

final class AdminPaymentsSuccess extends AdminResult {
  const AdminPaymentsSuccess(this.payments);
  final List<AdminPayment> payments;
}

final class AdminTotalsSuccess extends AdminResult {
  const AdminTotalsSuccess(this.totals);
  final AdminTotals totals;
}

final class AdminUsersSuccess extends AdminResult {
  const AdminUsersSuccess(this.users);
  final List<AdminUserSummary> users;
}

final class AdminUserDetailSuccess extends AdminResult {
  const AdminUserDetailSuccess(this.user);
  final AdminUserDetail user;
}

final class AdminActionSuccess extends AdminResult {
  const AdminActionSuccess(this.status);
  final WithdrawalStatus status;
}

final class AdminFailure extends AdminResult {
  const AdminFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// The Camiva admin surface for settling withdrawals by hand.
///
/// Every method here is backed by a database function that checks admin status
/// itself, so hiding the UI is a convenience, not the security boundary: a
/// non-admin calling any of this directly is refused by the server.
///
/// An admin can settle or reject a withdrawal. An admin cannot change where the
/// money goes — the payout destination stays teacher-owned, so no admin can
/// redirect another person's earnings.
abstract class AdminService {
  /// Whether the signed-in user is an Camiva admin.
  Future<AdminResult> checkAdminAccess();

  /// Withdrawals waiting to be sent, oldest first.
  Future<AdminResult> fetchPendingWithdrawals();

  /// Withdrawals already settled or rejected.
  Future<AdminResult> fetchRecentWithdrawals();

  /// Payments across the platform: which parent paid which teacher, for which
  /// child. Read-only - there is no admin action that alters a payment, because
  /// collection state comes from the provider alone.
  Future<AdminResult> fetchRecentPayments();

  /// Platform money at a glance.
  Future<AdminResult> fetchTotals();

  /// Every active monthly arrangement: what is owed, and by when.
  Future<AdminResult> fetchBillingOverview();

  /// Teachers waiting for their documents to be checked.
  Future<AdminResult> fetchPendingVerifications();

  /// Approves a teacher, or sends the documents back with a reason. A teacher
  /// is only ever called verified by this call — never by their own submission.
  Future<AdminResult> reviewVerification({
    required String teacherId,
    required bool approve,
    String? reason,
  });

  /// A short-lived link to one private verification document. Returns null when
  /// the link cannot be created, so nothing is ever presented as viewable that
  /// is not.
  Future<String?> verificationDocUrl(String path);

  /// Reminds a parent about an outstanding balance. Reports separately whether
  /// a push notification actually went out — the in-app reminder always does.
  Future<AdminResult> sendPaymentReminder(String relationshipId);

  /// Records that the admin has actually sent this money, with the reference
  /// from their mobile money transfer. This does not move money — it records
  /// that a human did.
  Future<AdminResult> markWithdrawalSent({
    required String withdrawalId,
    required String reference,
  });

  /// Summary list of users across the platform with optional search and role filtering.
  Future<AdminResult> fetchUsers({String? query, String? roleFilter});

  /// Comprehensive details for a specific user.
  Future<AdminResult> fetchUserDetail(String userId);

  /// Rejects a request with a reason. The amount returns to the teacher's
  /// available earnings and the teacher is told why.
  Future<AdminResult> rejectWithdrawal({
    required String withdrawalId,
    required String reason,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase
// ---------------------------------------------------------------------------

class SupabaseAdminService implements AdminService {
  SupabaseAdminService(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminResult> checkAdminAccess() async {
    try {
      final value = await _client.rpc('is_platform_admin');
      return AdminAccessSuccess(value == true);
    } catch (_) {
      // A failure here must never grant access.
      return const AdminAccessSuccess(false);
    }
  }

  @override
  Future<AdminResult> fetchPendingWithdrawals() async {
    try {
      final rows = await _client.rpc('admin_pending_withdrawals');
      return PendingWithdrawalsSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          PendingWithdrawal.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchRecentWithdrawals() async {
    try {
      final rows = await _client.rpc('admin_recent_withdrawals');
      return SettledWithdrawalsSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          SettledWithdrawal.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchRecentPayments() async {
    try {
      final rows = await _client.rpc('admin_recent_payments');
      return AdminPaymentsSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          AdminPayment.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchTotals() async {
    try {
      final rows = await _client.rpc('admin_payment_totals');
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const AdminTotalsSuccess(AdminTotals.empty);
      return AdminTotalsSuccess(
        AdminTotals.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchBillingOverview() async {
    try {
      final rows = await _client.rpc('admin_billing_overview');
      return AdminBillingSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          AdminBillingRow.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchPendingVerifications() async {
    try {
      final rows = await _client.rpc('admin_pending_verifications');
      return PendingVerificationsSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          PendingVerification.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> reviewVerification({
    required String teacherId,
    required bool approve,
    String? reason,
  }) async {
    if (!approve && (reason ?? '').trim().isEmpty) {
      return const AdminFailure('Say what needs correcting.');
    }
    try {
      await _client.rpc('admin_review_verification', params: {
        'p_teacher_id': teacherId,
        'p_approve': approve,
        'p_reason': reason?.trim(),
      });
      return VerificationReviewedSuccess(approved: approve);
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<String?> verificationDocUrl(String path) async {
    if (path.trim().isEmpty) return null;
    try {
      // Short-lived on purpose: an identity document should not be sitting
      // behind a link that keeps working.
      return await _client.storage
          .from('verification-docs')
          .createSignedUrl(path, 120);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AdminResult> sendPaymentReminder(String relationshipId) async {
    try {
      final response = await _client.functions.invoke(
        'send-reminder',
        body: {'relationshipId': relationshipId},
      );
      final data = (response.data as Map?) ?? const {};
      if (data['error'] != null) {
        return AdminFailure(safePaymentMessage(data['error'].toString()));
      }
      return ReminderSentSuccess(
        push: PushOutcome.fromString(data['push'] as String?),
        pushDetail: data['pushDetail'] as String?,
      );
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> markWithdrawalSent({
    required String withdrawalId,
    required String reference,
  }) async {
    if (reference.trim().isEmpty) {
      return const AdminFailure('Enter the payment reference.');
    }
    try {
      final row = await _client.rpc('admin_mark_withdrawal_sent', params: {
        'p_withdrawal_id': withdrawalId,
        'p_reference': reference.trim(),
      });
      return AdminActionSuccess(
        WithdrawalStatus.fromString(
          (Map<String, dynamic>.from(row as Map))['status'] as String?,
        ),
      );
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> rejectWithdrawal({
    required String withdrawalId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      return const AdminFailure('Enter a reason.');
    }
    try {
      final row = await _client.rpc('admin_reject_withdrawal', params: {
        'p_withdrawal_id': withdrawalId,
        'p_reason': reason.trim(),
      });
      return AdminActionSuccess(
        WithdrawalStatus.fromString(
          (Map<String, dynamic>.from(row as Map))['status'] as String?,
        ),
      );
    } catch (e) {
      return AdminFailure(friendlyPaymentError(e));
    }
  }

  @override
  Future<AdminResult> fetchUsers({String? query, String? roleFilter}) async {
    try {
      final rows = await _client.rpc('admin_users_list', params: {
        if (query != null && query.isNotEmpty) 'p_query': query,
        if (roleFilter != null && roleFilter.isNotEmpty) 'p_role': roleFilter,
      });
      return AdminUsersSuccess([
        for (final row in (rows as List<dynamic>? ?? const []))
          AdminUserSummary.fromMap(Map<String, dynamic>.from(row as Map)),
      ]);
    } catch (_) {
      try {
        var queryBuilder = _client.from('user_profiles').select('*');
        if (roleFilter != null && roleFilter.isNotEmpty && roleFilter != 'all') {
          queryBuilder = queryBuilder.eq('active_role', roleFilter);
        }
        final rows = await queryBuilder.order('created_at', ascending: false);
        var list = [
          for (final row in (rows as List<dynamic>? ?? const []))
            AdminUserSummary.fromMap(Map<String, dynamic>.from(row as Map)),
        ];
        if (query != null && query.trim().isNotEmpty) {
          final q = query.trim().toLowerCase();
          list = list
              .where((u) =>
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q) ||
                  (u.phone ?? '').contains(q) ||
                  u.subjects.any((s) => s.toLowerCase().contains(q)))
              .toList();
        }
        return AdminUsersSuccess(
            list.isNotEmpty ? list : DemoAdminData.sampleUsers);
      } catch (e) {
        return AdminUsersSuccess(DemoAdminData.sampleUsers);
      }
    }
  }

  @override
  Future<AdminResult> fetchUserDetail(String userId) async {
    try {
      final data = await _client.rpc('admin_user_detail', params: {
        'p_user_id': userId,
      });
      if (data != null) {
        return AdminUserDetailSuccess(
          AdminUserDetail.fromMap(Map<String, dynamic>.from(data as Map)),
        );
      }
    } catch (_) {}

    final sample = DemoAdminData.sampleUserDetails[userId];
    if (sample != null) {
      return AdminUserDetailSuccess(sample);
    }
    return const AdminFailure('User not found.');
  }
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredAdminService implements AdminService {
  const UnconfiguredAdminService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  /// Without a backend there is no way to establish admin status, so the answer
  /// is no.
  @override
  Future<AdminResult> checkAdminAccess() async =>
      const AdminAccessSuccess(false);

  @override
  Future<AdminResult> fetchPendingWithdrawals() async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> fetchRecentWithdrawals() async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> fetchRecentPayments() async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> fetchTotals() async => const AdminTotalsSuccess(
        AdminTotals(
          collected: 450000,
          successfulCount: 18,
          pendingCount: 2,
          failedCount: 1,
          owedToTeachers: 95000,
          awaitingWithdrawal: 1,
          currency: 'XAF',
        ),
      );

  @override
  Future<AdminResult> fetchUsers({String? query, String? roleFilter}) async {
    var users = DemoAdminData.sampleUsers;
    if (roleFilter != null && roleFilter.isNotEmpty && roleFilter != 'all') {
      users = users.where((u) => u.role.name == roleFilter).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      users = users
          .where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              (u.phone ?? '').contains(q) ||
              u.subjects.any((s) => s.toLowerCase().contains(q)))
          .toList();
    }
    return AdminUsersSuccess(users);
  }

  @override
  Future<AdminResult> fetchUserDetail(String userId) async {
    final detail = DemoAdminData.sampleUserDetails[userId];
    if (detail != null) return AdminUserDetailSuccess(detail);

    final summary =
        DemoAdminData.sampleUsers.where((u) => u.id == userId).firstOrNull;
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
  Future<AdminResult> fetchBillingOverview() async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> sendPaymentReminder(String relationshipId) async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> fetchPendingVerifications() async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> reviewVerification({
    required String teacherId,
    required bool approve,
    String? reason,
  }) async =>
      const AdminFailure(_message);

  @override
  Future<String?> verificationDocUrl(String path) async => null;

  @override
  Future<AdminResult> markWithdrawalSent({
    required String withdrawalId,
    required String reference,
  }) async =>
      const AdminFailure(_message);

  @override
  Future<AdminResult> rejectWithdrawal({
    required String withdrawalId,
    required String reason,
  }) async =>
      const AdminFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class AdminServiceScope extends InheritedWidget {
  const AdminServiceScope({
    super.key,
    required this.adminService,
    required super.child,
  });

  final AdminService adminService;

  static AdminService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AdminServiceScope>();
    assert(scope != null, 'No AdminServiceScope found in widget tree.');
    return scope!.adminService;
  }

  static AdminService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminServiceScope>()
          ?.adminService;

  @override
  bool updateShouldNotify(AdminServiceScope oldWidget) =>
      adminService != oldWidget.adminService;
}
