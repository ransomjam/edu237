import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import 'support_sheet.dart';

/// The receipt for one payment.
///
/// This is a large part of why staying on-platform is worth something: the
/// parent can come back to it at any time, and it carries the reference the
/// Camiva team needs if anything has to be looked into.
class PaymentReceiptScreen extends StatelessWidget {
  const PaymentReceiptScreen({super.key, required this.payment});

  final PaymentTransaction payment;

  @override
  Widget build(BuildContext context) {
    final succeeded = payment.status.isSuccessful;
    final date = payment.paidAt ?? payment.createdAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppConstants.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: succeeded
                          ? AppColors.successLight
                          : AppColors.grey100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      succeeded ? Icons.check_rounded : Icons.receipt_long,
                      size: 32,
                      color:
                          succeeded ? AppColors.success : AppColors.grey500,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.space16),
                Text(
                  succeeded ? 'Payment successful' : payment.status.message,
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.space4),
                Text(
                  payment.formattedAmount,
                  key: const Key('receipt_amount'),
                  style: AppTextStyles.display,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.space24),
                AppCard(
                  child: Column(
                    children: [
                      _ReceiptRow(label: 'Date', value: formatShortDate(date)),
                      _ReceiptRow(
                          label: 'Purpose', value: payment.purpose.label),
                      if ((payment.studentName ?? '').isNotEmpty)
                        _ReceiptRow(
                            label: 'Child', value: payment.studentName!),
                      if ((payment.teacherName ?? '').isNotEmpty)
                        _ReceiptRow(
                            label: 'Teacher', value: payment.teacherName!),
                      _ReceiptRow(
                        label: 'Reference',
                        value: payment.reference,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.space24),
                AppButton(
                  key: const Key('receipt_support_button'),
                  label: 'Need help?',
                  variant: AppButtonVariant.outlined,
                  isFullWidth: true,
                  onPressed: () => showSupportSheet(
                    context,
                    paymentId: payment.id,
                    relationshipId: payment.relationshipId,
                    reference: payment.reference,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
            ),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              flex: 2,
              child: Text(
                value,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        if (!isLast) const Divider(height: AppConstants.space24),
      ],
    );
  }
}
