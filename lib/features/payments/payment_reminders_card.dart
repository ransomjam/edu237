import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_reminder.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/edu_ui.dart';

/// The unread payment reminders for the signed-in user.
///
/// Each row exists because something actually happened — a payment confirmed, a
/// payout settled, a fee period opened. Nothing is generated speculatively and
/// nothing claims to have been pushed to the device: these are in-app
/// reminders, shown here, and marked read when the user has seen them.
///
/// It renders nothing at all when there is nothing to say. No spam.
class PaymentRemindersCard extends StatefulWidget {
  const PaymentRemindersCard({super.key, this.maxItems = 3});

  final int maxItems;

  @override
  State<PaymentRemindersCard> createState() => _PaymentRemindersCardState();
}

class _PaymentRemindersCardState extends State<PaymentRemindersCard> {
  List<PaymentReminder> _unread = const [];
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
    final service = PaymentServiceScope.maybeOf(context);
    if (service == null) return;
    final result = await service.fetchReminders();
    if (!mounted) return;
    if (result case ReminderListSuccess(:final reminders)) {
      setState(() {
        _unread = reminders
            .where((r) => r.isUnread)
            .take(widget.maxItems)
            .toList(growable: false);
      });
    }
  }

  Future<void> _dismiss(PaymentReminder reminder) async {
    await PaymentServiceScope.of(context).markReminderRead(reminder.id);
    if (!mounted) return;
    setState(() {
      _unread = _unread.where((r) => r.id != reminder.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unread.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('payment_reminders'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Updates'),
        for (final reminder in _unread)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.space8),
            child: _ReminderTile(
              reminder: reminder,
              onDismiss: () => _dismiss(reminder),
            ),
          ),
        const SizedBox(height: AppConstants.space12),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.onDismiss});

  final PaymentReminder reminder;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (reminder.kind) {
      ReminderKind.paymentReceived => (Icons.check_circle, AppColors.success),
      ReminderKind.relationshipActivated =>
        (Icons.handshake_outlined, AppColors.success),
      ReminderKind.paymentFailed => (Icons.error_outline, AppColors.error),
      ReminderKind.serviceFeeOverdue =>
        (Icons.warning_amber_rounded, AppColors.error),
      ReminderKind.serviceFeeDue => (Icons.event_note, AppColors.warning),
      ReminderKind.withdrawalUpdate =>
        (Icons.account_balance_wallet_outlined, AppColors.primary),
      ReminderKind.paymentDue => (Icons.event_note, AppColors.warning),
      ReminderKind.agreementUpdate =>
        (Icons.description_outlined, AppColors.primary),
      ReminderKind.verificationUpdate =>
        (Icons.verified_outlined, AppColors.primary),
      ReminderKind.requestReceived =>
        (Icons.person_add_alt_1_outlined, AppColors.primary),
      ReminderKind.requestAnswered =>
        (Icons.mark_email_read_outlined, AppColors.primary),
      ReminderKind.lessonScheduled =>
        (Icons.event_available_outlined, AppColors.primary),
      ReminderKind.other => (Icons.notifications_none, AppColors.grey700),
    };

    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.title, style: AppTextStyles.h3),
                const SizedBox(height: AppConstants.space2),
                Text(reminder.body,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.grey700)),
              ],
            ),
          ),
          IconButton(
            key: Key('dismiss_reminder_${reminder.id}'),
            icon: const Icon(Icons.close, size: 18, color: AppColors.grey500),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
