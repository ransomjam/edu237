import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/tutoring_agreement.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import '../payments/activate_relationship_screen.dart';
import 'contract_view.dart';
import 'setup_tutoring_screen.dart';

/// What the teacher is looking at.
class TeacherAgreementArgs {
  const TeacherAgreementArgs({
    required this.relationshipId,
    required this.childName,
    required this.subject,
    this.parentName = 'The parent',
  });

  final String relationshipId;
  final String childName;
  final String subject;
  final String parentName;
}

/// The teacher's view of one tutoring arrangement: the contract they sent, where
/// it stands, and what to do next.
///
/// This is the screen the teacher comes back to. Before it existed, sending a
/// proposal was a one-way door — there was no way to read back what had been
/// agreed.
class TeacherAgreementScreen extends StatefulWidget {
  const TeacherAgreementScreen({super.key, required this.args});

  final TeacherAgreementArgs args;

  @override
  State<TeacherAgreementScreen> createState() => _TeacherAgreementScreenState();
}

class _TeacherAgreementScreenState extends State<TeacherAgreementScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  TutoringAgreement? _agreement;
  String? _parentPhone;

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

    final result = await TutoringServiceScope.of(context)
        .fetchAgreement(widget.args.relationshipId);
    if (!mounted) return;

    switch (result) {
      case AgreementSuccess(:final agreement):
        _agreement = agreement;
      case TutoringFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
        return;
      default:
        break;
    }

    // The parent's number, if the relationship has reached the point where it
    // is available. The server decides; this screen shows nothing otherwise.
    final contact = await PaymentServiceScope.of(context)
        .fetchRelationshipContact(widget.args.relationshipId);
    if (!mounted) return;
    if (contact case ContactSuccess(:final revealed, :final phone)) {
      if (revealed) _parentPhone = phone;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _propose() async {
    // Verification comes first. Opening the form for an unverified teacher
    // wastes their time: the server refuses the proposal at the end of it.
    final verification =
        await TutoringServiceScope.of(context).fetchMyVerification();
    if (!mounted) return;
    if (verification case VerificationSuccess(:final verification)
        when !verification.status.isVerified) {
      await context.push<bool>(AppRoutes.teacherVerification);
      if (!mounted) return;
      final recheck =
          await TutoringServiceScope.of(context).fetchMyVerification();
      if (!mounted) return;
      if (recheck is VerificationSuccess &&
          !recheck.verification.status.isVerified) {
        _load();
        return;
      }
    }

    await context.push<bool>(
      AppRoutes.setupTutoring,
      extra: SetupTutoringArgs(
        relationshipId: widget.args.relationshipId,
        childName: widget.args.childName,
        subject: widget.args.subject,
      ),
    );
    if (mounted) _load();
  }

  Future<void> _activate() async {
    await context.push<bool>(
      AppRoutes.activateRelationship,
      extra: ActivateRelationshipArgs(
        relationshipId: widget.args.relationshipId,
        childName: widget.args.childName,
        subject: widget.args.subject,
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutoring arrangement')),
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
        title: 'Could not load this',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final agreement = _agreement;

    // Nothing sent yet.
    if (agreement == null) {
      return Padding(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        child: Column(
          key: const Key('no_agreement_yet'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppEmptyState(
              icon: Icons.description_outlined,
              title: 'No arrangement yet',
              message: 'Set out the tutoring details and send them to '
                  '${widget.args.parentName} to agree.',
            ),
            const SizedBox(height: AppConstants.space16),
            AppButton(
              key: const Key('propose_from_agreement_screen'),
              label: 'Set up tutoring',
              isFullWidth: true,
              onPressed: _propose,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        _NextStep(
          status: agreement.status,
          parentName: widget.args.parentName,
          hasPhone: (_parentPhone ?? '').isNotEmpty,
        ),
        const SizedBox(height: AppConstants.space16),
        ContactActions(
          phone: _parentPhone,
          name: widget.args.parentName,
          message: 'Hello, about ${widget.args.childName}\'s '
              '${widget.args.subject} tutoring on Camiva —',
        ),
        const SizedBox(height: AppConstants.space16),
        ContractView(
          agreement: agreement,
          childName: widget.args.childName,
          teacherName: 'You',
          parentName: widget.args.parentName,
        ),
        if (agreement.status.awaitingActivation) ...[
          const SizedBox(height: AppConstants.space24),
          AppButton(
            key: const Key('activate_from_agreement_screen'),
            label: 'Pay & activate',
            isFullWidth: true,
            onPressed: _activate,
          ),
        ],
        if (agreement.status == AgreementStatus.declined) ...[
          const SizedBox(height: AppConstants.space24),
          AppButton(
            key: const Key('repropose_button'),
            label: 'Propose new terms',
            isFullWidth: true,
            onPressed: _propose,
          ),
        ],
      ],
    );
  }
}

/// One line telling the teacher exactly what happens next.
class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.status,
    required this.parentName,
    required this.hasPhone,
  });

  final AgreementStatus status;
  final String parentName;
  final bool hasPhone;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      AgreementStatus.proposed => hasPhone
          ? 'Talk the details through with $parentName, then wait for them to '
              'confirm in the app.'
          : 'Sent to $parentName. They will talk it through with you and '
              'confirm in the app.',
      AgreementStatus.confirmed =>
        '$parentName confirmed. Activate the relationship to finish.',
      AgreementStatus.active =>
        'Active. You can schedule lessons and record payments.',
      AgreementStatus.declined =>
        '$parentName declined these terms. You can propose new ones.',
      AgreementStatus.cancelled => 'This arrangement was cancelled.',
    };

    return Container(
      key: const Key('agreement_next_step'),
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: AppConstants.space8),
          Expanded(
            child: Text(message,
                style: AppTextStyles.body.copyWith(color: AppColors.grey900)),
          ),
        ],
      ),
    );
  }
}
