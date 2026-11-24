import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_errors.dart';
import '../models/billing_summary.dart';
import '../models/fee_config.dart';
import '../models/payment_reminder.dart';
import '../models/payment_transaction.dart';
import '../models/teacher_earnings.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class PaymentResult {
  const PaymentResult();
}

final class FeeConfigSuccess extends PaymentResult {
  const FeeConfigSuccess(this.config);
  final FeeConfig config;
}

final class ActivationStateSuccess extends PaymentResult {
  const ActivationStateSuccess(this.state);
  final ActivationState state;
}

/// A payment has been STARTED. The status is always pending: nothing here means
/// the money arrived.
final class PaymentStartSuccess extends PaymentResult {
  const PaymentStartSuccess({
    required this.paymentId,
    required this.status,
    this.checkoutUrl,
    this.method,
  });

  final String paymentId;
  final PaymentStatus status;

  /// Fapshi-hosted checkout link to open, when the hosted flow is used.
  final String? checkoutUrl;

  /// 'initiate' or 'direct' — how the provider was asked to collect.
  final String? method;
}

/// What the server would charge for a payment, asked before charging it.
final class PaymentQuoteSuccess extends PaymentResult {
  const PaymentQuoteSuccess({required this.amount, required this.currency});
  final int amount;
  final String currency;
}

final class PaymentSuccess extends PaymentResult {
  const PaymentSuccess(this.payment);
  final PaymentTransaction payment;
}

final class PaymentListSuccess extends PaymentResult {
  const PaymentListSuccess(this.payments);
  final List<PaymentTransaction> payments;
}

final class PaymentStatusSuccess extends PaymentResult {
  const PaymentStatusSuccess(this.status);
  final PaymentStatus status;
}

/// The counterpart's contact details, or a locked result when the activation
/// condition has not been satisfied.
final class BillingSummarySuccess extends PaymentResult {
  const BillingSummarySuccess(this.summary);

  /// Null when the teacher has not set a monthly fee for this arrangement.
  final BillingSummary? summary;
}

final class ContactSuccess extends PaymentResult {
  const ContactSuccess({required this.revealed, this.name, this.phone});
  final bool revealed;
  final String? name;
  final String? phone;
}

final class ReminderListSuccess extends PaymentResult {
  const ReminderListSuccess(this.reminders);
  final List<PaymentReminder> reminders;
}

final class TeacherActivitySuccess extends PaymentResult {
  const TeacherActivitySuccess(this.activity);
  final TeacherActivity activity;
}

final class PaymentActionSuccess extends PaymentResult {
  const PaymentActionSuccess();
}

final class PaymentFailure extends PaymentResult {
  const PaymentFailure(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Everything the app does with money.
///
/// Two rules shape this interface:
///
///   * The app never sends an amount. It says what is being paid for; the
///     server decides what that costs.
///   * The app never reports success. It can start a payment and ask the
///     server to re-check it, but only a provider-confirmed status — recorded
///     server-side — moves a transaction out of pending.
abstract class PaymentService {
  /// Current pricing. Amounts may be null, meaning "not configured, not
  /// charged".
  Future<PaymentResult> fetchFeeConfig();

  /// Whether this relationship still needs its activation payment.
  Future<PaymentResult> fetchActivationState(String relationshipId);

  /// What the server would charge for this payment. Screens show this figure,
  /// so the amount a user approves is the amount the server writes.
  Future<PaymentResult> fetchQuote({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
  });

  /// Starts a payment through the Camiva backend, which calls Fapshi.
  ///
  /// [units] applies only to a tutoring payment (how many sessions/hours are
  /// being paid for); the price per unit comes from the teacher's rate.
  Future<PaymentResult> startPayment({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
    String? sessionId,
    String? payerPhone,
    int? amount,
  });

  /// Asks the backend to re-check this payment with Fapshi and apply whatever
  /// the provider says. Used while a payment screen is waiting, because a
  /// webhook can be late.
  Future<PaymentResult> verifyPayment(String paymentId);

  Future<PaymentResult> fetchPayment(String paymentId);

  /// A parent's payment history.
  Future<PaymentResult> fetchMyPaymentsAsParent();

  /// Payments a teacher is party to — their earnings history and their own
  /// Camiva fees.
  Future<PaymentResult> fetchMyPaymentsAsTeacher();

  Future<PaymentResult> fetchPaymentsForRelationship(String relationshipId);

  /// The counterpart's contact details for a relationship. Returns a locked
  /// result unless the relationship's activation condition is satisfied.
  Future<PaymentResult> fetchRelationshipContact(String relationshipId);

  /// The monthly picture for a relationship: fee, what has been paid this
  /// period, what is left, and when the next one falls due. Returns a null
  /// summary when the teacher has not set a monthly fee.
  Future<PaymentResult> fetchBillingSummary(String relationshipId);

  /// The signed-in user's in-app reminders.
  Future<PaymentResult> fetchReminders();

  Future<PaymentResult> markReminderRead(String reminderId);

  /// A teacher's Camiva transaction history indicator.
  Future<PaymentResult> fetchTeacherActivity(String teacherId);

  /// "Need help?" — keeps the payment/relationship reference so the Camiva
  /// team can investigate. It promises nothing about the outcome.
  Future<PaymentResult> submitSupportRequest({
    required String message,
    String? paymentId,
    String? relationshipId,
    String? withdrawalId,
  });
}

// ---------------------------------------------------------------------------
// Real implementation backed by Supabase + Edge Functions
// ---------------------------------------------------------------------------

class SupabasePaymentService implements PaymentService {
  SupabasePaymentService(this._client);

  final SupabaseClient _client;

  @override
  Future<PaymentResult> fetchFeeConfig() async {
    try {
      final row = await _client
          .from('platform_fee_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return const FeeConfigSuccess(FeeConfig.unknown);
      return FeeConfigSuccess(FeeConfig.fromMap(row));
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchActivationState(String relationshipId) async {
    try {
      final value = await _client.rpc(
        'relationship_activation_state',
        params: {'p_relationship_id': relationshipId},
      );
      return ActivationStateSuccess(ActivationState.fromString(value as String?));
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchQuote({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
  }) async {
    try {
      final rows = await _client.rpc('payment_quote', params: {
        'p_purpose': purpose.value,
        'p_relationship_id': relationshipId,
        'p_units': units,
      });
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const PaymentFailure(genericPaymentError);
      final row = Map<String, dynamic>.from(list.first as Map);
      return PaymentQuoteSuccess(
        amount: row['amount'] as int,
        currency: (row['currency'] as String?) ?? 'XAF',
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> startPayment({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
    String? sessionId,
    String? payerPhone,
    int? amount,
  }) async {
    if (_client.auth.currentUser == null) {
      return const PaymentFailure('Please sign in again.');
    }
    try {
      // The amount is deliberately absent: the backend computes it.
      final response = await _client.functions.invoke(
        'payments-create',
        body: {
          'purpose': purpose.value,
          if (relationshipId != null) 'relationshipId': relationshipId,
          'units': units,
          // An instalment the parent proposed. The server bounds it by the
          // outstanding balance, so this is a request, not an instruction.
          if (amount != null) 'amount': amount,
          if (sessionId != null) 'sessionId': sessionId,
          if (payerPhone != null && payerPhone.isNotEmpty) 'phone': payerPhone,
        },
      );

      final data = response.data;
      if (data is! Map) return const PaymentFailure(genericPaymentError);
      if (data['error'] != null) {
        return PaymentFailure(_friendlyBackendMessage(data['error'].toString()));
      }

      return PaymentStartSuccess(
        paymentId: data['paymentId'] as String,
        status: PaymentStatus.fromString(data['status'] as String?),
        checkoutUrl: data['checkoutUrl'] as String?,
        method: data['method'] as String?,
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> verifyPayment(String paymentId) async {
    try {
      final response = await _client.functions.invoke(
        'payments-verify',
        body: {'paymentId': paymentId},
      );
      final data = response.data;
      if (data is! Map || data['status'] == null) {
        return const PaymentFailure(genericPaymentError);
      }
      return PaymentStatusSuccess(
        PaymentStatus.fromString(data['status'] as String?),
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchPayment(String paymentId) async {
    try {
      final row = await _client
          .from('payment_history')
          .select()
          .eq('id', paymentId)
          .maybeSingle();
      if (row == null) return const PaymentFailure('Payment not found.');
      return PaymentSuccess(PaymentTransaction.fromMap(row));
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchMyPaymentsAsParent() =>
      _fetchBy(column: 'parent_id');

  @override
  Future<PaymentResult> fetchMyPaymentsAsTeacher() =>
      _fetchBy(column: 'teacher_id');

  Future<PaymentResult> _fetchBy({required String column}) async {
    final user = _client.auth.currentUser;
    if (user == null) return const PaymentFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('payment_history')
          .select()
          .eq(column, user.id)
          .order('created_at', ascending: false);
      return PaymentListSuccess(_parseList(rows));
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchPaymentsForRelationship(
      String relationshipId) async {
    try {
      final rows = await _client
          .from('payment_history')
          .select()
          .eq('relationship_id', relationshipId)
          .order('created_at', ascending: false);
      return PaymentListSuccess(_parseList(rows));
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchRelationshipContact(String relationshipId) async {
    try {
      final rows = await _client.rpc(
        'relationship_contact',
        params: {'p_relationship_id': relationshipId},
      );
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const ContactSuccess(revealed: false);
      final row = Map<String, dynamic>.from(list.first as Map);
      final revealed = (row['revealed'] as bool?) ?? false;
      return ContactSuccess(
        revealed: revealed,
        name: revealed ? row['name'] as String? : null,
        phone: revealed ? row['phone'] as String? : null,
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchBillingSummary(String relationshipId) async {
    try {
      final rows = await _client.rpc(
        'relationship_billing_summary',
        params: {'p_relationship_id': relationshipId},
      );
      final list = (rows as List<dynamic>?) ?? const [];
      // No row means no monthly fee has been set - not an error.
      if (list.isEmpty) return const BillingSummarySuccess(null);
      return BillingSummarySuccess(
        BillingSummary.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchReminders() async {
    final user = _client.auth.currentUser;
    if (user == null) return const PaymentFailure('Please sign in again.');
    try {
      final rows = await _client
          .from('payment_reminders')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      return ReminderListSuccess(
        (rows as List<dynamic>)
            .map((r) => PaymentReminder.fromMap(r as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> markReminderRead(String reminderId) async {
    try {
      await _client.rpc('mark_reminder_read', params: {
        'p_reminder_id': reminderId,
      });
      return const PaymentActionSuccess();
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> fetchTeacherActivity(String teacherId) async {
    try {
      final rows = await _client.rpc(
        'teacher_activity_summary',
        params: {'p_teacher_id': teacherId},
      );
      final list = (rows as List<dynamic>?) ?? const [];
      if (list.isEmpty) return const TeacherActivitySuccess(TeacherActivity.none);
      return TeacherActivitySuccess(
        TeacherActivity.fromMap(Map<String, dynamic>.from(list.first as Map)),
      );
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  @override
  Future<PaymentResult> submitSupportRequest({
    required String message,
    String? paymentId,
    String? relationshipId,
    String? withdrawalId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return const PaymentFailure('Please sign in again.');
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return const PaymentFailure('Please describe what happened.');
    }
    try {
      await _client.from('support_requests').insert({
        'user_id': user.id,
        'message': trimmed,
        if (paymentId != null) 'payment_id': paymentId,
        if (relationshipId != null) 'relationship_id': relationshipId,
        if (withdrawalId != null) 'withdrawal_id': withdrawalId,
      });
      return const PaymentActionSuccess();
    } catch (e) {
      return PaymentFailure(_friendlyError(e));
    }
  }

  List<PaymentTransaction> _parseList(dynamic rows) {
    return (rows as List<dynamic>)
        .map((row) => PaymentTransaction.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Error handling lives in payment_errors.dart so the payment and earnings
  /// services classify failures identically.
  String _friendlyError(Object e) => friendlyPaymentError(e);

  String _friendlyBackendMessage(String raw) => safePaymentMessage(raw);
}

// ---------------------------------------------------------------------------
// Stub used when Supabase credentials are not configured
// ---------------------------------------------------------------------------

class UnconfiguredPaymentService implements PaymentService {
  const UnconfiguredPaymentService();

  static const _message =
      'The app is not connected to a backend. Please contact support.';

  @override
  Future<PaymentResult> fetchFeeConfig() async =>
      const FeeConfigSuccess(FeeConfig.unknown);

  @override
  Future<PaymentResult> fetchActivationState(String relationshipId) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchQuote({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
  }) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> startPayment({
    required PaymentPurpose purpose,
    String? relationshipId,
    int units = 1,
    String? sessionId,
    String? payerPhone,
    int? amount,
  }) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> verifyPayment(String paymentId) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchPayment(String paymentId) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchMyPaymentsAsParent() async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchMyPaymentsAsTeacher() async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchPaymentsForRelationship(
          String relationshipId) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchRelationshipContact(String relationshipId) async =>
      const ContactSuccess(revealed: false);

  @override
  Future<PaymentResult> fetchBillingSummary(String relationshipId) async =>
      const BillingSummarySuccess(null);

  @override
  Future<PaymentResult> fetchReminders() async =>
      const ReminderListSuccess(<PaymentReminder>[]);

  @override
  Future<PaymentResult> markReminderRead(String reminderId) async =>
      const PaymentFailure(_message);

  @override
  Future<PaymentResult> fetchTeacherActivity(String teacherId) async =>
      const TeacherActivitySuccess(TeacherActivity.none);

  @override
  Future<PaymentResult> submitSupportRequest({
    required String message,
    String? paymentId,
    String? relationshipId,
    String? withdrawalId,
  }) async =>
      const PaymentFailure(_message);
}

// ---------------------------------------------------------------------------
// Widget tree injection
// ---------------------------------------------------------------------------

class PaymentServiceScope extends InheritedWidget {
  const PaymentServiceScope({
    super.key,
    required this.paymentService,
    required super.child,
  });

  final PaymentService paymentService;

  static PaymentService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PaymentServiceScope>();
    assert(scope != null, 'No PaymentServiceScope found in widget tree.');
    return scope!.paymentService;
  }

  /// For payment widgets embedded in non-payment screens. Those screens must
  /// still build when no payment service is in scope — the widget then shows
  /// nothing rather than bringing the screen down.
  static PaymentService? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PaymentServiceScope>()
          ?.paymentService;

  @override
  bool updateShouldNotify(PaymentServiceScope oldWidget) =>
      paymentService != oldWidget.paymentService;
}
