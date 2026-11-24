import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/tutoring_agreement.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../core/services/payment_service.dart';
import 'contract_view.dart';

/// What the parent is being asked to review.
class ReviewAgreementArgs {
  const ReviewAgreementArgs({
    required this.agreement,
    required this.childName,
    required this.teacherName,
  });

  final TutoringAgreement agreement;
  final String childName;
  final String teacherName;
}

/// The parent reads exactly what was proposed and confirms it — or declines.
///
/// Everything that matters is on one screen: what the tutoring is, how often,
/// how long, how much, when payment is due, and how it is paid. No legal text.
///
/// Confirming is what makes the teacher's Platform Charge due. Nothing is
/// charged to the parent here, and no contact details are revealed yet.
class ReviewAgreementScreen extends StatefulWidget {
  const ReviewAgreementScreen({
    super.key,
    required this.agreement,
    required this.childName,
    required this.teacherName,
  });

  final TutoringAgreement agreement;
  final String childName;
  final String teacherName;

  @override
  State<ReviewAgreementScreen> createState() => _ReviewAgreementScreenState();
}

class _ReviewAgreementScreenState extends State<ReviewAgreementScreen> {
  ExpectedPayment? _expected;
  String? _teacherPhone;
  String? _parentName;
  bool _isWorking = false;
  String? _errorMessage;
  late AgreementStatus _status = widget.agreement.status;
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadExpected();
    }
  }

  Future<void> _loadExpected() async {
    final result = await TutoringServiceScope.of(context)
        .fetchExpectedPayment(widget.agreement.id);
    if (!mounted) return;
    if (result case ExpectedPaymentSuccess(:final expected)) {
      setState(() => _expected = expected);
    }

    // The teacher's number, so the parent can talk the details through before
    // agreeing them. The server decides whether it is available; this screen
    // simply shows nothing when it is not.
    final contact = await PaymentServiceScope.of(context)
        .fetchRelationshipContact(widget.agreement.relationshipId);
    if (!mounted) return;
    if (contact case ContactSuccess(:final revealed, :final phone)) {
      if (revealed) setState(() => _teacherPhone = phone);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    final result = await TutoringServiceScope.of(context)
        .confirmAgreement(widget.agreement.id);
    if (!mounted) return;
    setState(() => _isWorking = false);

    switch (result) {
      case AgreementSuccess(:final agreement) when agreement != null:
        setState(() => _status = agreement.status);
      case TutoringFailure(:final message):
        setState(() => _errorMessage = message);
      default:
        break;
    }
  }

  Future<void> _decline() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    final result = await TutoringServiceScope.of(context)
        .declineAgreement(agreementId: widget.agreement.id);
    if (!mounted) return;
    setState(() => _isWorking = false);

    switch (result) {
      case AgreementSuccess(:final agreement) when agreement != null:
        setState(() => _status = agreement.status);
        Navigator.of(context).pop(false);
      case TutoringFailure(:final message):
        setState(() => _errorMessage = message);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Confirmed: the parent is done, and the teacher activates next. There is
    // deliberately nothing more for the parent to do.
    if (_status == AgreementStatus.confirmed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tutoring arrangement')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.space32),
            child: Column(
              key: const Key('awaiting_activation'),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 34, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppConstants.space20),
                Text('Waiting for teacher activation',
                    style: AppTextStyles.h2, textAlign: TextAlign.center),
                const SizedBox(height: AppConstants.space8),
                Text(
                  'Camiva is finalising your tutoring connection.',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.grey700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.space24),
                AppButton(
                  key: const Key('agreement_done_button'),
                  label: 'Done',
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final a = widget.agreement;
    final expected = _expected;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutoring arrangement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          children: [
            Text(widget.childName, style: AppTextStyles.h1),
            const SizedBox(height: AppConstants.space4),
            Text('${a.subject} with ${widget.teacherName}',
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.grey700)),
            const SizedBox(height: AppConstants.space16),

            // Talk it through first. Agreeing the details with the teacher
            // before confirming is the point of this step.
            Container(
              key: const Key('discuss_first_note'),
              padding: const EdgeInsets.all(AppConstants.space12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(
                    child: Text(
                      'Agree these details with your teacher first. Call or '
                      'message them, then confirm.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.grey900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.space12),
            ContactActions(
              phone: _teacherPhone,
              name: widget.teacherName,
              message: 'Hello ${widget.teacherName}, about '
                  "${widget.childName}'s ${a.subject} tutoring on Camiva —",
            ),
            const SizedBox(height: AppConstants.space16),

            ContractView(
              agreement: a,
              childName: widget.childName,
              teacherName: widget.teacherName,
              parentName: _parentName ?? 'You',
            ),
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'Payment'),
            AppCard(
              key: const Key('agreement_payment_card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        a.paymentMethod.isCamiva
                            ? Icons.verified_user_outlined
                            : Icons.handshake_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppConstants.space8),
                      Text(a.paymentMethod.label, style: AppTextStyles.h3),
                    ],
                  ),
                  const SizedBox(height: AppConstants.space8),
                  Text(
                    a.paymentMethod.isCamiva
                        ? 'Pay through the Camiva app. You get a receipt, a '
                            'payment history and reminders, and Camiva can help '
                            'if something goes wrong.'
                        : 'You pay your teacher directly. These payments are '
                            'not recorded in your Camiva payment history and '
                            'are not covered by Camiva reminders or records.',
                    style: AppTextStyles.body.copyWith(color: AppColors.grey700),
                  ),
                  if (expected != null && expected.isCamivaManaged) ...[
                    const SizedBox(height: AppConstants.space16),
                    _Row(
                      label: 'Next payment',
                      value: formatShortDate(expected.dueOn),
                    ),
                    _Row(
                      label: 'Amount',
                      value: expected.formattedAmount,
                      isStrong: true,
                    ),
                  ],
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: AppConstants.space16),
              Container(
                key: const Key('agreement_error'),
                padding: const EdgeInsets.all(AppConstants.space12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(_errorMessage!,
                    style: AppTextStyles.body.copyWith(color: AppColors.error)),
              ),
            ],

            const SizedBox(height: AppConstants.space24),
            AppButton(
              key: const Key('confirm_agreement_button'),
              label: 'Confirm tutoring arrangement',
              isFullWidth: true,
              isLoading: _isWorking,
              onPressed: _isWorking ? null : _confirm,
            ),
            const SizedBox(height: AppConstants.space8),
            AppButton(
              key: const Key('decline_agreement_button'),
              label: 'Decline',
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              onPressed: _isWorking ? null : _decline,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.space4),
      child: Row(
        children: [
          Text(label,
              style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
          const Spacer(),
          Text(
            value,
            style: isStrong
                ? AppTextStyles.h3
                : AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
