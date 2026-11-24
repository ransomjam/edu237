import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/fee_config.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import 'payment_flow_screen.dart';

/// Arguments for the activation screen, passed through the router.
class ActivateRelationshipArgs {
  const ActivateRelationshipArgs({
    required this.relationshipId,
    required this.childName,
    this.subject,
  });

  final String relationshipId;
  final String childName;
  final String? subject;
}

/// Teacher-facing: activate a newly accepted teaching relationship.
///
/// This is the moment the teacher pays the one-time relationship charge, when
/// one is configured. It explains what Camiva does for the relationship and
/// shows the exact fee — it is never framed as unlocking or buying a contact.
///
/// The screen reads the fee and the activation state from the server. If no
/// charge is configured, or the relationship is already active, there is
/// nothing to pay and it says so instead of inventing a price.
class ActivateRelationshipScreen extends StatefulWidget {
  const ActivateRelationshipScreen({super.key, required this.args});

  final ActivateRelationshipArgs args;

  @override
  State<ActivateRelationshipScreen> createState() =>
      _ActivateRelationshipScreenState();
}

class _ActivateRelationshipScreenState
    extends State<ActivateRelationshipScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  FeeConfig _config = FeeConfig.unknown;
  ActivationState _state = ActivationState.notRequired;
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
    final configResult = await service.fetchFeeConfig();
    if (!mounted) return;
    if (configResult case FeeConfigSuccess(:final config)) {
      _config = config;
    }

    final stateResult =
        await service.fetchActivationState(widget.args.relationshipId);
    if (!mounted) return;

    switch (stateResult) {
      case ActivationStateSuccess(:final state):
        setState(() {
          _state = state;
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camiva Platform Charge')),
        body: AppEmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load this',
          message: _errorMessage!,
          actionLabel: 'Try again',
          onAction: _load,
        ),
      );
    }

    // The parent has not confirmed the arrangement yet, so nothing is owed.
    // This is the business rule made visible: no teacher payment before parent
    // confirmation.
    if (_state.awaitingParent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camiva Platform Charge')),
        body: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            key: const Key('awaiting_parent_confirmation'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppEmptyState(
                icon: Icons.hourglass_top_rounded,
                title: 'Waiting for the parent',
                message:
                    'You will be asked to activate once the parent confirms '
                    'the tutoring arrangement you sent. Nothing is charged '
                    'until then.',
              ),
              const SizedBox(height: AppConstants.space16),
              AppButton(
                label: 'Done',
                isFullWidth: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    }

    // Nothing to pay: either the charge is switched off, no amount is
    // configured, or it is already paid for.
    final fee = _config.matchActivationFeeAmount;
    if (!_state.needsPayment || !_config.chargesForActivation || fee == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camiva Platform Charge')),
        body: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppEmptyState(
                icon: _state == ActivationState.pending
                    ? Icons.hourglass_bottom_rounded
                    : Icons.check_circle_outline,
                title: _state == ActivationState.pending
                    ? 'Payment processing…'
                    : "You're connected to this family",
                message: _state == ActivationState.pending
                    ? 'We are still confirming your last payment. This screen '
                        'will be up to date once it is confirmed.'
                    : 'This teaching relationship is active. You can start '
                        'scheduling lessons.',
              ),
              const SizedBox(height: AppConstants.space16),
              AppButton(
                label: 'Done',
                isFullWidth: true,
                onPressed: () => Navigator.of(context)
                    .pop(_state == ActivationState.active ||
                        _state == ActivationState.notRequired),
              ),
            ],
          ),
        ),
      );
    }

    final subject = (widget.args.subject ?? '').trim();

    return PaymentFlowScreen(
      title: 'Camiva Platform Charge',
      headline: 'Activate your Camiva tutoring relationship',
      explanation:
          "Camiva has received the parent's confirmation. A small platform "
          'charge activates this tutoring relationship and enables Camiva '
          "coordination: reminders, payment records and support.",
      details: [
        PaymentDetail('Student', widget.args.childName),
        if (subject.isNotEmpty) PaymentDetail('Subject', subject),
        const PaymentDetail('Charge', 'One-time'),
      ],
      amount: fee,
      currency: _config.currency,
      payLabel: 'Pay & activate',
      successTitle: "You're connected",
      successBody: "You're connected to this family. You can start scheduling "
          'lessons.',
      request: PaymentRequest(
        purpose: PaymentPurpose.matchActivation,
        relationshipId: widget.args.relationshipId,
      ),
    );
  }
}

/// A small "what happens next" line used where the teacher is waiting for an
/// activation payment to confirm.
class ActivationPendingNote extends StatelessWidget {
  const ActivationPendingNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'We are confirming your payment. The family\'s contact details appear '
      'here as soon as it is confirmed.',
      style: AppTextStyles.body,
    );
  }
}
