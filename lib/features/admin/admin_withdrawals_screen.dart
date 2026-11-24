import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/withdrawal.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/edu_ui.dart';

/// Camiva admin: settle teacher withdrawals by hand.
///
/// Fapshi disburses only through a separate, provider-activated payout service.
/// Until Camiva has one, an admin sends the money themselves — from their own
/// mobile money — and records it here.
///
/// This screen does NOT move money. It records that a named admin did, with
/// their reference, so the ledger never claims more than actually happened.
class AdminWithdrawalsScreen extends StatefulWidget {
  const AdminWithdrawalsScreen({super.key});

  @override
  State<AdminWithdrawalsScreen> createState() => _AdminWithdrawalsScreenState();
}

class _AdminWithdrawalsScreenState extends State<AdminWithdrawalsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<PendingWithdrawal> _pending = const [];
  List<SettledWithdrawal> _recent = const [];
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

    final service = AdminServiceScope.of(context);
    final pending = await service.fetchPendingWithdrawals();
    if (!mounted) return;

    switch (pending) {
      case PendingWithdrawalsSuccess(:final withdrawals):
        _pending = withdrawals;
      case AdminFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
        return;
      default:
        break;
    }

    final recent = await service.fetchRecentWithdrawals();
    if (!mounted) return;
    if (recent case SettledWithdrawalsSuccess(:final withdrawals)) {
      _recent = withdrawals;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _markSent(PendingWithdrawal withdrawal) async {
    final reference = await _prompt(
      title: 'Mark as sent',
      message: 'Send ${formatMoney(withdrawal.amount, withdrawal.currency)} to '
          '${withdrawal.payoutPhone} first, then enter the reference from your '
          'mobile money transfer.',
      label: 'Payment reference',
      actionLabel: 'Confirm sent',
    );
    if (reference == null || !mounted) return;

    setState(() => _working.add(withdrawal.id));
    final result = await AdminServiceScope.of(context).markWithdrawalSent(
      withdrawalId: withdrawal.id,
      reference: reference,
    );
    if (!mounted) return;
    _working.remove(withdrawal.id);
    _afterAction(result, 'Recorded as sent.');
  }

  Future<void> _reject(PendingWithdrawal withdrawal) async {
    final reason = await _prompt(
      title: 'Reject request',
      message: 'The teacher will see this reason, and the amount goes back to '
          'their available earnings.',
      label: 'Reason',
      actionLabel: 'Reject',
      hint: 'Wrong payout number',
    );
    if (reason == null || !mounted) return;

    setState(() => _working.add(withdrawal.id));
    final result = await AdminServiceScope.of(context).rejectWithdrawal(
      withdrawalId: withdrawal.id,
      reason: reason,
    );
    if (!mounted) return;
    _working.remove(withdrawal.id);
    _afterAction(result, 'Request rejected.');
  }

  void _afterAction(AdminResult result, String successMessage) {
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

  Future<String?> _prompt({
    required String title,
    required String message,
    required String label,
    required String actionLabel,
    String? hint,
  }) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        message: message,
        label: label,
        actionLabel: actionLabel,
        hint: hint,
      ),
    );
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawals')),
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
        title: 'Could not load withdrawals',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          const SectionHeader(title: 'Waiting to be sent'),
          if (_pending.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppConstants.space12),
              child: Text(
                'Nothing waiting. Requests appear here as teachers make them.',
                key: const Key('admin_no_pending'),
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
            )
          else
            for (final withdrawal in _pending)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space12),
                child: _PendingCard(
                  withdrawal: withdrawal,
                  isWorking: _working.contains(withdrawal.id),
                  onMarkSent: () => _markSent(withdrawal),
                  onReject: () => _reject(withdrawal),
                ),
              ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space24),
            const SectionHeader(title: 'Already handled'),
            for (final withdrawal in _recent)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: _SettledRow(withdrawal: withdrawal),
              ),
          ],
        ],
      ),
    );
  }
}

/// A one-field dialog that owns its controller.
///
/// The controller lives here rather than in the calling method so it is
/// disposed with the dialog itself - disposing it as soon as showDialog returns
/// tears it down while the exit animation is still painting the field.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.actionLabel,
    this.hint,
  });

  final String title;
  final String message;
  final String label;
  final String actionLabel;
  final String? hint;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: AppTextStyles.body),
          const SizedBox(height: AppConstants.space16),
          AppTextField(
            key: const Key('admin_prompt_field'),
            controller: _controller,
            label: widget.label,
            hint: widget.hint,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('admin_prompt_confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.withdrawal,
    required this.isWorking,
    required this.onMarkSent,
    required this.onReject,
  });

  final PendingWithdrawal withdrawal;
  final bool isWorking;
  final VoidCallback onMarkSent;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('pending_withdrawal_${withdrawal.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(withdrawal.teacherName, style: AppTextStyles.h3),
              ),
              Text(
                formatMoney(withdrawal.amount, withdrawal.currency),
                style: AppTextStyles.h3,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space12),
          // The full number, because sending the money requires it.
          _DetailRow(label: 'Send to', value: withdrawal.payoutPhone),
          _DetailRow(label: 'Method', value: withdrawal.payoutMedium),
          _DetailRow(
            label: 'Requested',
            value: formatShortDate(withdrawal.requestedAt),
          ),
          const SizedBox(height: AppConstants.space16),
          if (isWorking)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    key: Key('mark_sent_${withdrawal.id}'),
                    label: 'Mark as sent',
                    isFullWidth: true,
                    onPressed: onMarkSent,
                  ),
                ),
                const SizedBox(width: AppConstants.space8),
                Expanded(
                  child: AppButton(
                    key: Key('reject_${withdrawal.id}'),
                    label: 'Reject',
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

class _SettledRow extends StatelessWidget {
  const _SettledRow({required this.withdrawal});

  final SettledWithdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final settled = withdrawal.status == WithdrawalStatus.successful;
    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(withdrawal.teacherName, style: AppTextStyles.body),
                if ((withdrawal.reference ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppConstants.space2),
                  Text('Ref ${withdrawal.reference}',
                      style: AppTextStyles.caption),
                ],
                if (withdrawal.completedAt != null) ...[
                  const SizedBox(height: AppConstants.space2),
                  Text(formatShortDate(withdrawal.completedAt!),
                      style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(withdrawal.amount, withdrawal.currency),
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppConstants.space2),
              Text(
                settled ? 'Sent' : withdrawal.status.label,
                style: AppTextStyles.caption.copyWith(
                  color: settled ? AppColors.success : AppColors.grey500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space4),
      child: Row(
        children: [
          Text(label,
              style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
          const Spacer(),
          Text(value,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
