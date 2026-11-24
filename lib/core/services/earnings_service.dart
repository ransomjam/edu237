import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_errors.dart';
import '../models/payment_reminder.dart';
import '../models/payment_transaction.dart';
import '../models/teacher_earnings.dart';
import '../models/withdrawal.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class EarningsResult {
  const EarningsResult();
}

final class EarningsSuccess extends EarningsResult {
  const EarningsSuccess(this.earnings);
  final TeacherEarnings earnings;
}

final class EarningsHistorySuccess extends EarningsResult {
  const EarningsHistorySuccess(this.payments);
  final List<PaymentTransaction> payments;
}

final class WithdrawalSuccess extends EarningsResult {
  const WithdrawalSuccess(this.withdrawal);
  final Withdrawal withdrawal;
}

final class WithdrawalListSuccess extends EarningsResult {
  const WithdrawalListSuccess(this.withdrawals);
  final List<Withdrawal> withdrawals;
}

final class WithdrawalStatusSuccess extends EarningsResult {
  const WithdrawalStatusSuccess(this.status);
  final WithdrawalStatus status;
}

final class PayoutAccountSuccess extends EarningsResult {
  const PayoutAccountSuccess(this.account);

  /// Null when the teacher has not set a payout destination yet.
  final PayoutAccount? account;
}

final class ServiceFeeSuccess extends EarningsResult {
  const ServiceFeeSuccess(this.period);

  /// Null when no service fee is configured — nothing is owed.
  final ServiceFeePeriod? period;
}

final class EarningsFailure extends EarningsResult {
  const EarningsFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// The teacher's money surface: what they have earned, and moving it out.
///
/// Every figure here is derived server-side from the transaction ledger. The
/// app displays it; it never computes, stores or adjusts a balance, and it
/// cannot mark a withdrawal successful.
abstract class EarningsService {
  /// Available / pending / lifetime, derived from the ledger.
  Future<EarningsResult> fetchEarnings();

  /// The successful tutoring payments behind those figures.
  Future<EarningsResult> fetchEarningsHistory();

  Future<EarningsResult> fetchPayoutAccount();

  /// Saves the signed-in teacher's own payout destination. A teacher can only
  /// ever write their own row.
  Future<EarningsResult> savePayoutAccount({
    required String phone,
    required String medium,
    String? accountName,
  });

  /// Requests a payout. The eligible amount is re-checked server-side against
  /// the ledger, so a client cannot withdraw more than it has earned.
  Future<EarningsResult> requestWithdrawal(int amount);

  Future<EarningsResult> fetchWithdrawals();

  /// Asks the backend to re-check a payout with Fapshi.
  Future<EarningsResult> verifyWithdrawal(String withdrawalId);

  /// Opens (or returns) the teacher's current service-fee period. Returns a
  /// null period when no service fee is configured.
  Future<EarningsResult> fetchServiceFeePeriod();

  /// Records that the service-fee reminder was actually shown to the teacher.
  Future<EarningsResult> markServiceFeeReminded(String periodId);
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase + Edge Functions
// ---------------------------------------------------------------------------

class SupabaseEarningsService implements EarningsService {
  SupabaseEarningsService(this._client);

  final SupabaseClient _client;

  @override
  Future<EarningsResult> fetchEarnings() async {
    if (_client.auth.currentUser == null) {
      return const EarningsFailure('Please sign in again.');
    }
    try {
      final rows = await _client.rpc('teacher_earnings_summary');
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const EarningsSuccess(TeacherEarnings.empty);
      return EarningsSuccess(
        TeacherEarnings.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> fetchEarningsHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return const EarningsFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('payment_history')
          .select()
          .eq('teacher_id', user.id)
          .eq('purpose', PaymentPurpose.tutoringPayment.value)
          .order('created_at', ascending: false);
      return EarningsHistorySuccess(
        (rows as List<dynamic>)
            .map((r) => PaymentTransaction.fromMap(r as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> fetchPayoutAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return const EarningsFailure('Please sign in again.');
    try {
      final row = await _client
          .from('teacher_payout_accounts')
          .select()
          .eq('teacher_id', user.id)
          .maybeSingle();
      return PayoutAccountSuccess(
        row == null ? null : PayoutAccount.fromMap(row),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> savePayoutAccount({
    required String phone,
    required String medium,
    String? accountName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return const EarningsFailure('Please sign in again.');
    final trimmed = phone.trim();
    if (!PayoutAccount.isValidPhone(trimmed)) {
      return const EarningsFailure('Enter a valid number, e.g. 670000000.');
    }
    try {
      final row = await _client
          .from('teacher_payout_accounts')
          .upsert(
            PayoutAccount(
              teacherId: user.id,
              medium: medium,
              phone: trimmed,
              accountName: accountName,
            ).toUpsertMap(),
            onConflict: 'teacher_id',
          )
          .select()
          .single();
      return PayoutAccountSuccess(PayoutAccount.fromMap(row));
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> requestWithdrawal(int amount) async {
    if (_client.auth.currentUser == null) {
      return const EarningsFailure('Please sign in again.');
    }
    if (amount <= 0) {
      return const EarningsFailure('Enter an amount to withdraw.');
    }
    try {
      final response = await _client.functions.invoke(
        'withdrawals-request',
        body: {'amount': amount},
      );
      final data = response.data;
      if (data is! Map) return const EarningsFailure(genericPaymentError);
      if (data['error'] != null) {
        return EarningsFailure(_friendlyBackendMessage(data['error'].toString()));
      }
      // The backend answers with the withdrawal's real state, which is never
      // 'successful' at this point — only a confirmed payout settles it.
      return WithdrawalStatusSuccess(
        WithdrawalStatus.fromString(data['status'] as String?),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> fetchWithdrawals() async {
    final user = _client.auth.currentUser;
    if (user == null) return const EarningsFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('withdrawals')
          .select()
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);
      return WithdrawalListSuccess(
        (rows as List<dynamic>)
            .map((r) => Withdrawal.fromMap(r as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> verifyWithdrawal(String withdrawalId) async {
    try {
      final response = await _client.functions.invoke(
        'payments-verify',
        body: {'withdrawalId': withdrawalId},
      );
      final data = response.data;
      if (data is! Map || data['status'] == null) {
        return const EarningsFailure(genericPaymentError);
      }
      return WithdrawalStatusSuccess(
        WithdrawalStatus.fromString(data['status'] as String?),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> fetchServiceFeePeriod() async {
    if (_client.auth.currentUser == null) {
      return const EarningsFailure('Please sign in again.');
    }
    try {
      final row = await _client.rpc('ensure_service_fee_period');
      if (row == null) return const ServiceFeeSuccess(null);
      return ServiceFeeSuccess(
        ServiceFeePeriod.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  @override
  Future<EarningsResult> markServiceFeeReminded(String periodId) async {
    try {
      final row = await _client.rpc(
        'mark_service_fee_reminded',
        params: {'p_period_id': periodId},
      );
      if (row == null) return const ServiceFeeSuccess(null);
      return ServiceFeeSuccess(
        ServiceFeePeriod.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return EarningsFailure(_friendlyError(e));
    }
  }

  /// Shared with PaymentService so both surfaces classify failures identically
  /// (see payment_errors.dart).
  String _friendlyError(Object e) => friendlyPaymentError(e);

  String _friendlyBackendMessage(String raw) => safePaymentMessage(raw);
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredEarningsService implements EarningsService {
  const UnconfiguredEarningsService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<EarningsResult> fetchEarnings() async =>
      const EarningsSuccess(TeacherEarnings.empty);

  @override
  Future<EarningsResult> fetchEarningsHistory() async =>
      const EarningsHistorySuccess(<PaymentTransaction>[]);

  @override
  Future<EarningsResult> fetchPayoutAccount() async =>
      const PayoutAccountSuccess(null);

  @override
  Future<EarningsResult> savePayoutAccount({
    required String phone,
    required String medium,
    String? accountName,
  }) async =>
      const EarningsFailure(_message);

  @override
  Future<EarningsResult> requestWithdrawal(int amount) async =>
      const EarningsFailure(_message);

  @override
  Future<EarningsResult> fetchWithdrawals() async =>
      const WithdrawalListSuccess(<Withdrawal>[]);

  @override
  Future<EarningsResult> verifyWithdrawal(String withdrawalId) async =>
      const EarningsFailure(_message);

  @override
  Future<EarningsResult> fetchServiceFeePeriod() async =>
      const ServiceFeeSuccess(null);

  @override
  Future<EarningsResult> markServiceFeeReminded(String periodId) async =>
      const ServiceFeeSuccess(null);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class EarningsServiceScope extends InheritedWidget {
  const EarningsServiceScope({
    super.key,
    required this.earningsService,
    required super.child,
  });

  final EarningsService earningsService;

  static EarningsService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EarningsServiceScope>();
    assert(scope != null, 'No EarningsServiceScope found in widget tree.');
    return scope!.earningsService;
  }

  @override
  bool updateShouldNotify(EarningsServiceScope oldWidget) =>
      earningsService != oldWidget.earningsService;
}
