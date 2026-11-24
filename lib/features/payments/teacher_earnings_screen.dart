import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_reminder.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/models/teacher_earnings.dart';
import '../../core/models/withdrawal.dart';
import '../../core/services/earnings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import 'payment_flow_screen.dart';
import 'payment_history_screen.dart';
import 'payment_receipt_screen.dart';
import 'withdraw_screen.dart';

/// Teacher-facing "Earnings".
///
/// Every figure on this screen is derived from the transaction ledger by the
/// server. Nothing is stored as a balance and nothing is computed here, so what
/// a teacher sees always matches what actually happened.
class TeacherEarningsScreen extends StatefulWidget {
  const TeacherEarningsScreen({super.key});

  @override
  State<TeacherEarningsScreen> createState() => _TeacherEarningsScreenState();
}

class _TeacherEarningsScreenState extends State<TeacherEarningsScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  TeacherEarnings _earnings = TeacherEarnings.empty;
  List<PaymentTransaction> _history = const [];
  List<Withdrawal> _withdrawals = const [];
  PayoutAccount? _account;
  ServiceFeePeriod? _serviceFee;
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

    final service = EarningsServiceScope.of(context);

    final earnings = await service.fetchEarnings();
    if (!mounted) return;
    switch (earnings) {
      case EarningsSuccess(:final earnings):
        _earnings = earnings;
      case EarningsFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
        return;
      default:
        break;
    }

    final history = await service.fetchEarningsHistory();
    if (!mounted) return;
    if (history case EarningsHistorySuccess(:final payments)) {
      _history = payments;
    }

    final withdrawals = await service.fetchWithdrawals();
    if (!mounted) return;
    if (withdrawals case WithdrawalListSuccess(:final withdrawals)) {
      _withdrawals = withdrawals;
    }

    final account = await service.fetchPayoutAccount();
    if (!mounted) return;
    if (account case PayoutAccountSuccess(:final account)) {
      _account = account;
    }

    final fee = await service.fetchServiceFeePeriod();
    if (!mounted) return;
    if (fee case ServiceFeeSuccess(:final period)) {
      _serviceFee = period;
      // The reminder is recorded only now, as it is genuinely being shown.
      if (period != null && period.status == ServiceFeeStatus.due) {
        await service.markServiceFeeReminded(period.id);
      }
    }

    // A withdrawal still in flight is re-checked with the provider, since a
    // webhook can arrive while the teacher is away from the app.
    final inFlight = _withdrawals.where((w) => w.status.isInFlight).toList();
    if (inFlight.isNotEmpty) {
      await service.verifyWithdrawal(inFlight.first.id);
      if (!mounted) return;
      final refreshed = await service.fetchWithdrawals();
      if (!mounted) return;
      if (refreshed case WithdrawalListSuccess(:final withdrawals)) {
        _withdrawals = withdrawals;
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _withdraw() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WithdrawScreen(
          earnings: _earnings,
          account: _account,
        ),
      ),
    );
    if (done == true && mounted) _load();
  }

  Future<void> _payServiceFee(ServiceFeePeriod period) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentFlowScreen(
          title: 'Camiva Teacher Service',
          headline: 'Camiva Teacher Service',
          explanation:
              'Your Teacher Service Plan keeps your account active: managed '
              'payments, records, reminders, earnings history and support. '
              'Camiva takes no commission from your tutoring earnings.',
          details: [
            PaymentDetail(
              'Period',
              '${formatShortDate(period.periodStart)} – ${formatShortDate(period.periodEnd)}',
            ),
          ],
          amount: period.amount,
          currency: period.currency,
          payLabel: 'Pay ${formatMoney(period.amount, period.currency)}',
          successTitle: "You're active",
          successBody: 'Your Camiva Teacher Service Plan is active for this '
              'period. Your tutoring earnings are unaffected.',
          request: const PaymentRequest(
            purpose: PaymentPurpose.teacherServiceFee,
          ),
        ),
      ),
    );
    if (paid == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load earnings',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final serviceFee = _serviceFee;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Available',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.grey500)),
                const SizedBox(height: AppConstants.space4),
                Text(_earnings.formattedAvailable,
                    key: const Key('earnings_available'),
                    style: AppTextStyles.display),
                const SizedBox(height: AppConstants.space12),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Pending',
                        value: _earnings.formattedPending,
                        hint: 'Still settling',
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: 'Earned so far',
                        value: _earnings.formattedLifetime,
                        hint: 'Through Camiva',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.space16),
                AppButton(
                  key: const Key('withdraw_button'),
                  label: 'Withdraw',
                  isFullWidth: true,
                  onPressed: _earnings.available > 0 ? _withdraw : null,
                ),
              ],
            ),
          ),
          if (serviceFee != null && serviceFee.status.isOutstanding) ...[
            const SizedBox(height: AppConstants.space16),
            _ServiceFeeCard(
              period: serviceFee,
              onPay: () => _payServiceFee(serviceFee),
            ),
          ],
          if (_withdrawals.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space24),
            const SectionHeader(title: 'Withdrawals'),
            for (final withdrawal in _withdrawals)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: _WithdrawalRow(withdrawal: withdrawal),
              ),
          ],
          const SizedBox(height: AppConstants.space24),
          const SectionHeader(title: 'Earnings history'),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.space16),
              child: Text(
                'Tutoring payments made through Camiva appear here. Only '
                'Camiva payments are part of this record.',
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
            )
          else
            for (final payment in _history)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: PaymentRow(
                  payment: payment,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentReceiptScreen(payment: payment),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
        const SizedBox(height: AppConstants.space2),
        Text(value, style: AppTextStyles.h3),
        Text(hint, style: AppTextStyles.caption.copyWith(color: AppColors.grey300)),
      ],
    );
  }
}

class _ServiceFeeCard extends StatelessWidget {
  const _ServiceFeeCard({required this.period, required this.onPay});

  final ServiceFeePeriod period;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final overdue = period.status == ServiceFeeStatus.overdue;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overdue ? Icons.warning_amber_rounded : Icons.event_note,
                size: 18,
                color: overdue ? AppColors.error : AppColors.grey500,
              ),
              const SizedBox(width: AppConstants.space8),
              Text('Camiva Teacher Service', style: AppTextStyles.h3),
            ],
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            '${formatMoney(period.amount, period.currency)} · '
            '${formatShortDate(period.periodStart)} – ${formatShortDate(period.periodEnd)}',
            style: AppTextStyles.body.copyWith(color: AppColors.grey700),
          ),
          const SizedBox(height: AppConstants.space12),
          AppButton(
            key: const Key('pay_service_fee_button'),
            label: overdue ? 'Pay now' : 'Pay service fee',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            onPressed: onPay,
          ),
        ],
      ),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.withdrawal});

  final Withdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (withdrawal.status) {
      WithdrawalStatus.successful => (AppColors.successLight, AppColors.success),
      WithdrawalStatus.failed => (AppColors.errorLight, AppColors.error),
      WithdrawalStatus.cancelled => (AppColors.grey100, AppColors.grey500),
      _ => (AppColors.warningLight, AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(withdrawal.formattedAmount, style: AppTextStyles.h3),
                const SizedBox(height: AppConstants.space2),
                Text(
                  '${withdrawal.maskedPhone} · '
                  '${formatShortDate(withdrawal.completedAt ?? withdrawal.createdAt)}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space8,
              vertical: AppConstants.space2,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(withdrawal.status.label,
                style: AppTextStyles.caption
                    .copyWith(color: fg, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
