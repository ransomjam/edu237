import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/teacher_earnings.dart';
import '../../core/models/withdrawal.dart';
import '../../core/services/earnings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import 'payout_account_screen.dart';

/// Teacher-facing withdrawal request.
///
/// The amount check here is only to keep the form honest — the server checks it
/// again against the ledger, takes a lock so two taps cannot both pass, and
/// refuses a second withdrawal while one is in flight.
///
/// A request never ends as "successful" on this screen. It ends as requested or
/// processing, because only a confirmed payout from the provider settles it.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({
    super.key,
    required this.earnings,
    required this.account,
  });

  final TeacherEarnings earnings;

  /// Null when no payout destination is set yet.
  final PayoutAccount? account;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final TextEditingController _amountController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  WithdrawalStatus? _result;
  PayoutAccount? _account;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _amountController.text =
        widget.earnings.available > 0 ? '${widget.earnings.available}' : '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_amountController.text.trim());

  String? get _amountProblem {
    final amount = _amount;
    if (amount == null || amount <= 0) return null;
    if (amount > widget.earnings.available) {
      return 'That is more than your available earnings.';
    }
    return null;
  }

  bool get _canSubmit =>
      _account != null &&
      _amount != null &&
      _amount! > 0 &&
      _amountProblem == null;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result =
        await EarningsServiceScope.of(context).requestWithdrawal(_amount!);
    if (!mounted) return;

    switch (result) {
      case WithdrawalStatusSuccess(:final status):
        setState(() {
          _result = status;
          _isSubmitting = false;
        });
      case EarningsFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isSubmitting = false;
        });
      default:
        setState(() => _isSubmitting = false);
    }
  }

  Future<void> _setUpAccount() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PayoutAccountScreen()),
    );
    if (saved != true || !mounted) return;
    final result = await EarningsServiceScope.of(context).fetchPayoutAccount();
    if (!mounted) return;
    if (result case PayoutAccountSuccess(:final account)) {
      setState(() => _account = account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppConstants.maxContentWidth),
            child: _result != null ? _buildResult() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final account = _account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.grey500)),
              const SizedBox(height: AppConstants.space4),
              Text(widget.earnings.formattedAvailable,
                  key: const Key('withdraw_available'),
                  style: AppTextStyles.h1),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Send to',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.grey500)),
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      account == null
                          ? 'No number yet'
                          : '${account.medium == 'orange money' ? 'Orange Money' : 'MTN MoMo'} · ${account.maskedPhone}',
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              AppButton(
                key: const Key('change_payout_button'),
                label: account == null ? 'Add' : 'Change',
                variant: AppButtonVariant.text,
                onPressed: _setUpAccount,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        AppTextField(
          key: const Key('withdraw_amount_field'),
          controller: _amountController,
          label: 'Amount to withdraw',
          keyboardType: TextInputType.number,
          errorText: _amountProblem,
          onChanged: (_) => setState(() {}),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppConstants.space12),
          Text(_errorMessage!,
              key: const Key('withdraw_error'),
              style: AppTextStyles.body.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('request_withdrawal_button'),
          label: 'Request withdrawal',
          isFullWidth: true,
          isLoading: _isSubmitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: AppConstants.space12),
        Text(
          'Withdrawals are sent to your number once confirmed. '
          '${formatMoney(widget.earnings.pending, widget.earnings.currency)} '
          'is still settling and cannot be withdrawn yet.',
          style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final status = _result!;
    final failed = status == WithdrawalStatus.failed ||
        status == WithdrawalStatus.cancelled;

    return Column(
      key: Key('withdrawal_result_${status.value}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space32),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: failed ? AppColors.errorLight : AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              failed ? Icons.close_rounded : Icons.schedule_rounded,
              size: 34,
              color: failed ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.space20),
        Text(status.message,
            style: AppTextStyles.h2, textAlign: TextAlign.center),
        const SizedBox(height: AppConstants.space8),
        Text(
          failed
              ? 'Nothing left your account.'
              : 'We will update this as soon as it is confirmed. You can '
                  'follow it in your earnings.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.space24),
        AppButton(
          label: 'Done',
          isFullWidth: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
