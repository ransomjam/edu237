import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

/// "Need help?" — the simple support path from a payment or a relationship.
///
/// It is not a dispute system and promises nothing: it records the message
/// together with the exact transaction/relationship reference so the Camiva
/// team can look into it. No refund, timeline or outcome is implied, because no
/// policy exists yet to back one.
Future<void> showSupportSheet(
  BuildContext context, {
  String? paymentId,
  String? relationshipId,
  String? withdrawalId,
  String? reference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _SupportSheet(
        paymentId: paymentId,
        relationshipId: relationshipId,
        withdrawalId: withdrawalId,
        reference: reference,
      ),
    ),
  );
}

class _SupportSheet extends StatefulWidget {
  const _SupportSheet({
    this.paymentId,
    this.relationshipId,
    this.withdrawalId,
    this.reference,
  });

  final String? paymentId;
  final String? relationshipId;
  final String? withdrawalId;
  final String? reference;

  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  bool _isSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final result = await PaymentServiceScope.of(context).submitSupportRequest(
      message: _controller.text,
      paymentId: widget.paymentId,
      relationshipId: widget.relationshipId,
      withdrawalId: widget.withdrawalId,
    );
    if (!mounted) return;

    switch (result) {
      case PaymentActionSuccess():
        setState(() {
          _isSent = true;
          _isSending = false;
        });
      case PaymentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isSending = false;
        });
      default:
        setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _isSent
              ? [
                  Text('Message sent', style: AppTextStyles.h2),
                  const SizedBox(height: AppConstants.space8),
                  Text(
                    'The Camiva team has your message and the reference for '
                    'this payment. Someone will look into it.',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.grey700),
                  ),
                  const SizedBox(height: AppConstants.space20),
                  AppButton(
                    label: 'Close',
                    isFullWidth: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]
              : [
                  Text('Contact Camiva', style: AppTextStyles.h2),
                  const SizedBox(height: AppConstants.space8),
                  Text(
                    'Tell us what happened. We keep the reference for this '
                    'payment with your message.',
                    style: AppTextStyles.body.copyWith(color: AppColors.grey700),
                  ),
                  if ((widget.reference ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppConstants.space8),
                    Text('Reference: ${widget.reference}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.grey500)),
                  ],
                  const SizedBox(height: AppConstants.space16),
                  AppTextField(
                    key: const Key('support_message_field'),
                    controller: _controller,
                    label: 'What happened?',
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppConstants.space12),
                    Text(_errorMessage!,
                        style:
                            AppTextStyles.body.copyWith(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppConstants.space20),
                  AppButton(
                    key: const Key('support_send_button'),
                    label: 'Send to Camiva',
                    isFullWidth: true,
                    isLoading: _isSending,
                    onPressed:
                        _controller.text.trim().isEmpty ? null : _send,
                  ),
                ],
        ),
      ),
    );
  }
}
