import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/edu_ui.dart';
import '../payments/payment_history_screen.dart' show PaymentStatusChip;

/// Camiva admin: every payment on the platform, stated plainly — which parent
/// paid which teacher, for which child.
///
/// Read-only by design. There is no admin action that alters a payment: whether
/// money arrived is Fapshi's answer, recorded through the webhook, and an admin
/// can no more mark a payment successful than a client can.
///
/// Names, amounts and references only. No phone numbers or emails appear here —
/// reconciling money needs identity, not contact details.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<AdminPayment> _payments = const [];

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

    final result = await AdminServiceScope.of(context).fetchRecentPayments();
    if (!mounted) return;

    switch (result) {
      case AdminPaymentsSuccess(:final payments):
        setState(() {
          _payments = payments;
          _isLoading = false;
        });
      case AdminFailure(:final message):
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
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.lock_outline,
        title: 'Could not load payments',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_payments.isEmpty) {
      return const AppEmptyState(
        key: Key('admin_no_payments'),
        icon: Icons.receipt_long_outlined,
        title: 'No payments yet',
        message: 'Payments made through Camiva appear here as they happen.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        itemCount: _payments.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppConstants.space8),
        itemBuilder: (context, index) =>
            _AdminPaymentRow(payment: _payments[index]),
      ),
    );
  }
}

class _AdminPaymentRow extends StatelessWidget {
  const _AdminPaymentRow({required this.payment});

  final AdminPayment payment;

  @override
  Widget build(BuildContext context) {
    // A tutoring payment moves money from a parent to a teacher; the platform
    // fees are paid by the teacher to Camiva. Say which, rather than showing a
    // direction that is only true half the time.
    final flow = switch (payment.purpose) {
      PaymentPurpose.tutoringPayment =>
        '${payment.payerLabel} → ${payment.payeeLabel}',
      PaymentPurpose.matchActivation =>
        '${payment.payeeLabel} → Camiva',
      PaymentPurpose.teacherServiceFee => '${payment.payeeLabel} → Camiva',
    };

    return Container(
      key: Key('admin_payment_${payment.id}'),
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(payment.purpose.label, style: AppTextStyles.h3),
              ),
              Text(formatMoney(payment.amount, payment.currency),
                  style: AppTextStyles.h3),
            ],
          ),
          const SizedBox(height: AppConstants.space4),
          Text(flow,
              style: AppTextStyles.body.copyWith(color: AppColors.grey700)),
          if ((payment.childName ?? '').isNotEmpty) ...[
            const SizedBox(height: AppConstants.space2),
            Text('For ${payment.childName}',
                style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
          ],
          const SizedBox(height: AppConstants.space8),
          Row(
            children: [
              PaymentStatusChip(status: payment.status),
              const SizedBox(width: AppConstants.space8),
              Expanded(
                child: Text(
                  formatShortDate(payment.paidAt ?? payment.createdAt),
                  style: AppTextStyles.caption,
                ),
              ),
              if ((payment.providerTransId ?? '').isNotEmpty)
                Text(payment.providerTransId!,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.grey500)),
            ],
          ),
          if ((payment.failureReason ?? '').isNotEmpty) ...[
            const SizedBox(height: AppConstants.space4),
            Text(payment.failureReason!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}
