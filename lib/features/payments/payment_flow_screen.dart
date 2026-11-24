import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';

/// One labelled line on a payment screen ("Child · Daniel").
class PaymentDetail {
  const PaymentDetail(this.label, this.value);
  final String label;
  final String value;
}

/// What is being paid for. The amount is NOT part of this: it is shown from the
/// server-provided figure and recomputed server-side when the payment starts.
class PaymentRequest {
  const PaymentRequest({
    required this.purpose,
    this.relationshipId,
    this.units = 1,
    this.sessionId,
    this.amount,
  });

  final PaymentPurpose purpose;
  final String? relationshipId;
  final int units;
  final String? sessionId;

  /// An instalment the payer chose. Sent as a proposal only - the server
  /// refuses anything above the outstanding balance, so this can never be used
  /// to pay a price of the payer's own choosing.
  final int? amount;
}

/// The one screen every Camiva payment goes through.
///
/// It is deliberately small: what you are paying for, how much, one button. The
/// provider is never named or explained to the user.
///
/// The important behaviour is what it does NOT do. Starting a payment only ever
/// produces a *pending* transaction; the screen then asks the backend to
/// re-check with the provider until a confirmed status arrives. A successful
/// HTTP response never turns into "Payment successful" on its own.
class PaymentFlowScreen extends StatefulWidget {
  const PaymentFlowScreen({
    super.key,
    required this.title,
    required this.headline,
    required this.explanation,
    required this.details,
    required this.amount,
    this.belowAmount,
    required this.currency,
    required this.payLabel,
    required this.successTitle,
    required this.successBody,
    required this.request,
    this.initialPhone,
  });

  final String title;
  final String headline;
  final String explanation;
  final List<PaymentDetail> details;
  final int amount;

  /// Optional content shown directly under the amount, before the number
  /// field - used by the parent flow to offer an instalment.
  final Widget? belowAmount;
  final String currency;
  final String payLabel;
  final String successTitle;
  final String successBody;
  final PaymentRequest request;

  /// Prefilled mobile money number, when we already know one.
  final String? initialPhone;

  @override
  State<PaymentFlowScreen> createState() => _PaymentFlowScreenState();
}

enum _Stage { intro, starting, processing, done }

class _PaymentFlowScreenState extends State<PaymentFlowScreen> {
  static const _pollInterval = Duration(seconds: 8);

  /// Fapshi rate-limits status checks per transaction, so the screen checks
  /// steadily rather than aggressively and then hands control back to the user.
  static const _maxPolls = 20;

  final TextEditingController _phoneController = TextEditingController();

  _Stage _stage = _Stage.intro;
  PaymentStatus? _status;
  String? _paymentId;
  String? _checkoutUrl;
  String? _errorMessage;
  Timer? _poller;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.initialPhone ?? '';
  }

  @override
  void dispose() {
    _poller?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _phoneLooksValid =>
      RegExp(r'^6\d{8}$').hasMatch(_phoneController.text.trim());

  Future<void> _pay() async {
    setState(() {
      _stage = _Stage.starting;
      _errorMessage = null;
    });

    final result = await PaymentServiceScope.of(context).startPayment(
      purpose: widget.request.purpose,
      relationshipId: widget.request.relationshipId,
      units: widget.request.units,
      sessionId: widget.request.sessionId,
      amount: widget.request.amount,
      payerPhone: _phoneLooksValid ? _phoneController.text.trim() : null,
    );
    if (!mounted) return;

    switch (result) {
      case PaymentStartSuccess(:final paymentId, :final status, :final checkoutUrl):
        setState(() {
          _paymentId = paymentId;
          _status = status;
          _checkoutUrl = checkoutUrl;
          _stage = status.isTerminal ? _Stage.done : _Stage.processing;
        });
        if (!status.isTerminal) _startPolling();
      case PaymentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _stage = _Stage.intro;
        });
      default:
        setState(() {
          _errorMessage = 'Something went wrong. Please try again.';
          _stage = _Stage.intro;
        });
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _polls = 0;
    _poller = Timer.periodic(_pollInterval, (_) => _check());
  }

  /// Asks the BACKEND to re-check with the provider. The answer is whatever the
  /// provider says — this screen cannot decide a payment succeeded.
  Future<void> _check() async {
    final paymentId = _paymentId;
    if (paymentId == null) return;

    _polls++;
    if (_polls > _maxPolls) {
      _poller?.cancel();
      if (mounted) setState(() {});
      return;
    }

    final result = await PaymentServiceScope.of(context).verifyPayment(paymentId);
    if (!mounted) return;

    if (result case PaymentStatusSuccess(:final status)) {
      if (status.isTerminal) {
        _poller?.cancel();
        setState(() {
          _status = status;
          _stage = _Stage.done;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _stage = _Stage.intro;
      _status = null;
      _paymentId = null;
      _checkoutUrl = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppConstants.maxContentWidth),
            child: switch (_stage) {
              _Stage.intro || _Stage.starting => _buildIntro(),
              _Stage.processing => _buildProcessing(),
              _Stage.done => _buildDone(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.headline, style: AppTextStyles.h2),
        const SizedBox(height: AppConstants.space8),
        Text(
          widget.explanation,
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
        ),
        const SizedBox(height: AppConstants.space20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final detail in widget.details) ...[
                _DetailRow(detail: detail),
                const SizedBox(height: AppConstants.space8),
              ],
              const Divider(height: AppConstants.space24),
              Text('Amount',
                  style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
              const SizedBox(height: AppConstants.space4),
              Text(
                formatMoney(widget.amount, widget.currency),
                key: const Key('payment_amount'),
                style: AppTextStyles.h1,
              ),
            ],
          ),
        ),
        if (widget.belowAmount != null) widget.belowAmount!,
        const SizedBox(height: AppConstants.space20),
        AppTextField(
          key: const Key('momo_number_field'),
          controller: _phoneController,
          label: 'Mobile money number',
          hint: '670000000',
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppConstants.space8),
        Text(
          'You will get a prompt on this number to approve the payment.',
          style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppConstants.space16),
          _Banner(
            key: const Key('payment_error'),
            icon: Icons.error_outline,
            color: AppColors.error,
            background: AppColors.errorLight,
            message: _errorMessage!,
          ),
        ],
        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('pay_button'),
          label: widget.payLabel,
          isFullWidth: true,
          isLoading: _stage == _Stage.starting,
          onPressed: _phoneLooksValid ? _pay : null,
        ),
      ],
    );
  }

  Widget _buildProcessing() {
    final stalled = _polls > _maxPolls;
    return Column(
      key: const Key('payment_processing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space32),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: AppConstants.space24),
        Text('Payment processing…',
            style: AppTextStyles.h2, textAlign: TextAlign.center),
        const SizedBox(height: AppConstants.space8),
        Text(
          _checkoutUrl == null
              ? 'Approve the prompt on your phone. This screen updates by itself.'
              : 'Open the payment page below to finish, then come back here.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
          textAlign: TextAlign.center,
        ),
        if (_checkoutUrl != null) ...[
          const SizedBox(height: AppConstants.space20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(_checkoutUrl!, style: AppTextStyles.bodySmall),
                const SizedBox(height: AppConstants.space8),
                AppButton(
                  label: 'Copy payment link',
                  variant: AppButtonVariant.outlined,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _checkoutUrl!));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        if (stalled) ...[
          const SizedBox(height: AppConstants.space24),
          Text(
            'This is taking longer than usual. Your payment is still being '
            'checked — you can look again in a moment.',
            style: AppTextStyles.body.copyWith(color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.space12),
          AppButton(
            key: const Key('check_again_button'),
            label: 'Check again',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            onPressed: () {
              _polls = 0;
              _startPolling();
              _check();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDone() {
    final status = _status ?? PaymentStatus.pending;
    final succeeded = status.isSuccessful;

    return Column(
      key: Key('payment_result_${status.value}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space32),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: succeeded ? AppColors.successLight : AppColors.errorLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              succeeded ? Icons.check_rounded : Icons.close_rounded,
              size: 36,
              color: succeeded ? AppColors.success : AppColors.error,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.space20),
        Text(
          succeeded ? widget.successTitle : status.message,
          style: AppTextStyles.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.space8),
        Text(
          succeeded
              ? widget.successBody
              : 'Nothing was charged. You can try again.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.space24),
        if (succeeded)
          AppButton(
            key: const Key('payment_done_button'),
            label: 'Done',
            isFullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
          )
        else ...[
          AppButton(
            key: const Key('payment_retry_button'),
            label: 'Try again',
            isFullWidth: true,
            onPressed: _retry,
          ),
          const SizedBox(height: AppConstants.space8),
          AppButton(
            label: 'Not now',
            variant: AppButtonVariant.text,
            isFullWidth: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});
  final PaymentDetail detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(detail.label,
              style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
        ),
        const SizedBox(width: AppConstants.space12),
        Expanded(
          flex: 2,
          child: Text(
            detail.value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppConstants.space8),
          Expanded(
            child: Text(message,
                style: AppTextStyles.body.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
