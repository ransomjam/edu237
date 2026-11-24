import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/edu_ui.dart';

/// Camiva admin: check a teacher's identity and qualification documents.
///
/// This is the only place a teacher becomes verified. Submitting documents
/// moves them to "pending" and no further — the decision is made here, by a
/// person, and recorded against the admin who made it.
///
/// The documents live in a private bucket. They are opened through a
/// short-lived signed link created at the moment an admin looks, so an identity
/// document is never sitting behind a URL that keeps working.
class AdminVerificationsScreen extends StatefulWidget {
  const AdminVerificationsScreen({super.key});

  @override
  State<AdminVerificationsScreen> createState() =>
      _AdminVerificationsScreenState();
}

class _AdminVerificationsScreenState extends State<AdminVerificationsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<PendingVerification> _pending = const [];
  final Set<String> _working = {};

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

    final result =
        await AdminServiceScope.of(context).fetchPendingVerifications();
    if (!mounted) return;

    switch (result) {
      case PendingVerificationsSuccess(:final verifications):
        setState(() {
          _pending = verifications;
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

  Future<void> _openDoc(String path) async {
    final url = await AdminServiceScope.of(context).verificationDocUrl(path);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that document.')),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _approve(PendingVerification verification) async {
    setState(() => _working.add(verification.teacherId));
    final result = await AdminServiceScope.of(context).reviewVerification(
      teacherId: verification.teacherId,
      approve: true,
    );
    if (!mounted) return;
    _working.remove(verification.teacherId);
    _after(result, '${verification.teacherName} is verified.');
  }

  Future<void> _reject(PendingVerification verification) async {
    final reason = await _askReason(verification.teacherName);
    if (reason == null || !mounted) return;

    setState(() => _working.add(verification.teacherId));
    final result = await AdminServiceScope.of(context).reviewVerification(
      teacherId: verification.teacherId,
      approve: false,
      reason: reason,
    );
    if (!mounted) return;
    _working.remove(verification.teacherId);
    _after(result, 'Sent back for correction.');
  }

  void _after(AdminResult result, String successMessage) {
    if (result case AdminFailure(:final message)) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successMessage)));
    _load();
  }

  Future<String?> _askReason(String teacherName) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifications')),
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
        title: 'Could not load verifications',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_pending.isEmpty) {
      return const AppEmptyState(
        key: Key('admin_no_verifications'),
        icon: Icons.verified_outlined,
        title: 'Nothing waiting',
        message: 'Teachers appear here when they send their documents.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        itemCount: _pending.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppConstants.space12),
        itemBuilder: (context, index) {
          final verification = _pending[index];
          return _VerificationCard(
            verification: verification,
            isWorking: _working.contains(verification.teacherId),
            onOpenDoc: _openDoc,
            onApprove: () => _approve(verification),
            onReject: () => _reject(verification),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.verification,
    required this.isWorking,
    required this.onOpenDoc,
    required this.onApprove,
    required this.onReject,
  });

  final PendingVerification verification;
  final bool isWorking;
  final ValueChanged<String> onOpenDoc;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('verification_${verification.teacherId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(verification.teacherName, style: AppTextStyles.h3),
          if (verification.submittedAt != null) ...[
            const SizedBox(height: AppConstants.space2),
            Text('Sent ${formatShortDate(verification.submittedAt!)}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.grey500)),
          ],
          const SizedBox(height: AppConstants.space12),

          AppButton(
            key: Key('view_id_${verification.teacherId}'),
            label: verification.identityDocType?.label ?? 'Identity document',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            leading: const Icon(Icons.badge_outlined, size: 18),
            onPressed: () => onOpenDoc(verification.identityDocPath),
          ),
          const SizedBox(height: AppConstants.space8),
          AppButton(
            key: Key('view_qualification_${verification.teacherId}'),
            label: (verification.qualificationTitle ?? '').trim().isEmpty
                ? 'Qualification document'
                : verification.qualificationTitle!,
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            leading: const Icon(Icons.school_outlined, size: 18),
            onPressed: () => onOpenDoc(verification.qualificationDocPath),
          ),

          const SizedBox(height: AppConstants.space16),
          if (isWorking)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    key: Key('approve_${verification.teacherId}'),
                    label: 'Verify',
                    isFullWidth: true,
                    onPressed: onApprove,
                  ),
                ),
                const SizedBox(width: AppConstants.space8),
                Expanded(
                  child: AppButton(
                    key: Key('reject_verification_${verification.teacherId}'),
                    label: 'Ask for a fix',
                    variant: AppButtonVariant.outlined,
                    isFullWidth: true,
                    onPressed: onReject,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Asks what needs correcting. The teacher sees this text, so it is required —
/// sending documents back without saying why helps nobody.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask for a fix'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The teacher sees this, so say what to change.',
              style: AppTextStyles.body),
          const SizedBox(height: AppConstants.space16),
          AppTextField(
            key: const Key('verification_reason_field'),
            controller: _controller,
            label: 'What needs correcting',
            hint: 'The ID photo is blurred',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('verification_reason_confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Send back'),
        ),
      ],
    );
  }
}
