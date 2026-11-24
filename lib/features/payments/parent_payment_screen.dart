import 'package:flutter/material.dart';

import '../../core/models/payment_transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/money.dart';
import '../../core/models/billing_summary.dart';
import '../../core/services/payment_service.dart';
import '../../shared/widgets/edu_ui.dart';
import 'payment_flow_screen.dart';

/// Arguments for the parent's tutoring payment, passed through the router.
class ParentPaymentArgs {
  const ParentPaymentArgs({
    required this.relationshipId,
    required this.childName,
    required this.teacherName,
    this.subject,
    this.sessionId,
  });

  final String relationshipId;
  final String childName;
  final String teacherName;
  final String? subject;

  /// Set when the payment is for one specific scheduled lesson.
  final String? sessionId;
}

/// Parent-facing: pay for tutoring.
///
/// The amount is asked of the server before anything is shown, so the parent
/// approves exactly what will be charged. The provider is never mentioned —
/// this is simply "Pay with Mobile Money".
class ParentPaymentScreen extends StatefulWidget {
  const ParentPaymentScreen({super.key, required this.args});

  final ParentPaymentArgs args;

  @override
  State<ParentPaymentScreen> createState() => _ParentPaymentScreenState();
}

class _ParentPaymentScreenState extends State<ParentPaymentScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  int? _amount;
  String _currency = 'XAF';
  BillingSummary? _billing;

  /// What the parent has chosen to pay now. Defaults to the whole balance;
  /// they may pay less as an instalment, never more.
  int? _installment;
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final service = PaymentServiceScope.of(context);
    final billingResult =
        await service.fetchBillingSummary(widget.args.relationshipId);
    if (!mounted) return;
    if (billingResult case BillingSummarySuccess(:final summary)) {
      _billing = summary;
    }

    final result = await service.fetchQuote(
      purpose: PaymentPurpose.tutoringPayment,
      relationshipId: widget.args.relationshipId,
    );
    if (!mounted) return;

    switch (result) {
      case PaymentQuoteSuccess(:final amount, :final currency):
        setState(() {
          _amount = amount;
          _currency = currency;
          _installment = amount;
          _isLoading = false;
        });
      case PaymentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      default:
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final amount = _amount;
    if (amount == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pay for tutoring')),
        body: AppEmptyState(
          icon: Icons.error_outline,
          title: 'Payment not available',
          message: _errorMessage ??
              'This tutoring arrangement is not ready for payment yet.',
          actionLabel: 'Try again',
          onAction: _load,
        ),
      );
    }

    final subject = (widget.args.subject ?? '').trim();
    final billing = _billing;
    final payable = _installment ?? amount;

    return PaymentFlowScreen(
      title: 'Pay for tutoring',
      headline: "${widget.args.childName}'s tutoring",
      explanation:
          'Paying here gives you a receipt, a payment history and Camiva '
          'support for this arrangement.',
      details: [
        PaymentDetail('Child', widget.args.childName),
        if (subject.isNotEmpty) PaymentDetail('Subject', subject),
        PaymentDetail('Teacher', widget.args.teacherName),
        if (billing != null)
          PaymentDetail('This month', billing.formattedMonthly),
        if (billing != null && billing.paidThisPeriod > 0)
          PaymentDetail('Already paid', billing.formattedPaid),
      ],
      // An instalment is allowed: pay part now, the rest later in the month.
      // The server still bounds whatever is sent by the outstanding balance.
      belowAmount: billing == null
          ? null
          : _InstallmentChooser(
              balance: billing.balance,
              currency: _currency,
              selected: payable,
              onChanged: (value) => setState(() => _installment = value),
            ),
      amount: payable,
      currency: _currency,
      payLabel: 'Pay with Mobile Money',
      successTitle: 'Payment successful',
      successBody:
          'Your receipt is saved in Payments, and the teacher has been notified.',
      request: PaymentRequest(
        purpose: PaymentPurpose.tutoringPayment,
        relationshipId: widget.args.relationshipId,
        sessionId: widget.args.sessionId,
        amount: billing == null ? null : payable,
      ),
    );
  }
}

/// Lets a parent pay all of this month's balance, or part of it.
///
/// Instalments are how tutoring is actually paid for in many families: a little
/// now, the rest later in the month. The choices are bounded by the balance —
/// and the server refuses anything above it regardless of what this sends.
class _InstallmentChooser extends StatelessWidget {
  const _InstallmentChooser({
    required this.balance,
    required this.currency,
    required this.selected,
    required this.onChanged,
  });

  final int balance;
  final String currency;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Whole-amount, half and quarter, rounded to something a person would hand
  /// over. Options at or below zero, or equal to the full balance, are dropped.
  List<int> get _options {
    final half = _round(balance ~/ 2);
    final quarter = _round(balance ~/ 4);
    final options = <int>{balance};
    for (final value in [half, quarter]) {
      if (value >= 100 && value < balance) options.add(value);
    }
    final list = options.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  static int _round(int value) => (value ~/ 100) * 100;

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (options.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.space16),
      child: Column(
        key: const Key('installment_chooser'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pay now',
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
          const SizedBox(height: AppConstants.space8),
          Wrap(
            spacing: AppConstants.space8,
            children: [
              for (final option in options)
                ChoiceChip(
                  key: Key('installment_$option'),
                  label: Text(
                    option == balance
                        ? 'All ${formatMoney(option, currency)}'
                        : formatMoney(option, currency),
                  ),
                  selected: option == selected,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
          if (selected < balance) ...[
            const SizedBox(height: AppConstants.space8),
            Text(
              '${formatMoney(balance - selected, currency)} will still be left '
              'for this month.',
              key: const Key('installment_remainder'),
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
            ),
          ],
        ],
      ),
    );
  }
}
