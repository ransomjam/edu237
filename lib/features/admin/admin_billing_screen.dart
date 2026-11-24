import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';

/// Camiva admin: every monthly arrangement, what is outstanding, and a way to
/// remind the parent.
///
/// The figures are the same ones the parent sees — both come from
/// relationship_billing_summary(), derived from the ledger — so an admin can
/// never quote a number the parent's own app disagrees with.
///
/// Reminders report honestly. The in-app reminder always lands; whether a push
/// notification went out depends on this project having push credentials and
/// the parent having a registered device, and the result says which happened.
class AdminBillingScreen extends StatefulWidget {
  const AdminBillingScreen({super.key});

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<AdminBillingRow> _rows = const [];
  final Set<String> _sending = {};

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

    final result = await AdminServiceScope.of(context).fetchBillingOverview();
    if (!mounted) return;

    switch (result) {
      case AdminBillingSuccess(:final rows):
        setState(() {
          _rows = rows;
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

  Future<void> _remind(AdminBillingRow row) async {
    setState(() => _sending.add(row.relationshipId));
    final result = await AdminServiceScope.of(context)
        .sendPaymentReminder(row.relationshipId);
    if (!mounted) return;
    setState(() => _sending.remove(row.relationshipId));

    final message = switch (result) {
      // Carries the provider's reason when push failed, so a rejection can be
      // acted on without opening the server logs.
      ReminderSentSuccess(:final message) => message,
      AdminFailure(:final message) => message,
      _ => 'Reminder sent in the app.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (result is ReminderSentSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly payments')),
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
        title: 'Could not load',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_rows.isEmpty) {
      return const AppEmptyState(
        key: Key('admin_no_billing'),
        icon: Icons.event_note_outlined,
        title: 'No monthly arrangements yet',
        message: 'These appear once a teacher sets a monthly fee for a child.',
      );
    }

    final owing = _rows.where((r) => !r.isSettled).toList();
    final settled = _rows.where((r) => r.isSettled).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          if (owing.isNotEmpty) ...[
            const SectionHeader(title: 'Outstanding this month'),
            for (final row in owing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space12),
                child: _BillingCard(
                  row: row,
                  isSending: _sending.contains(row.relationshipId),
                  onRemind: () => _remind(row),
                ),
              ),
            const SizedBox(height: AppConstants.space16),
          ],
          if (settled.isNotEmpty) ...[
            const SectionHeader(title: 'Fully paid this month'),
            for (final row in settled)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space12),
                child: _BillingCard(
                  row: row,
                  isSending: false,
                  onRemind: null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BillingCard extends StatelessWidget {
  const _BillingCard({
    required this.row,
    required this.isSending,
    required this.onRemind,
  });

  final AdminBillingRow row;
  final bool isSending;
  final VoidCallback? onRemind;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('billing_row_${row.relationshipId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(row.childName, style: AppTextStyles.h3)),
              Text(
                row.isSettled
                    ? 'Paid'
                    : formatMoney(row.balance, row.currency),
                style: AppTextStyles.h3.copyWith(
                  color: row.isSettled ? AppColors.success : AppColors.grey900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space2),
          Text('${row.parentName} → ${row.teacherName}',
              style: AppTextStyles.body.copyWith(color: AppColors.grey700)),
          const SizedBox(height: AppConstants.space12),
          _Line(
            label: 'Monthly fee',
            value: formatMoney(row.monthlyAmount, row.currency),
          ),
          _Line(
            label: 'Paid this month',
            value: formatMoney(row.paidThisPeriod, row.currency),
          ),
          _Line(label: 'Started', value: formatShortDate(row.startedOn)),
          _Line(label: 'Next due', value: formatShortDate(row.nextDueOn)),
          if (row.lastRemindedAt != null)
            _Line(
              label: 'Last reminded',
              value: formatShortDate(row.lastRemindedAt!),
            ),
          if (onRemind != null) ...[
            const SizedBox(height: AppConstants.space12),
            AppButton(
              key: Key('remind_${row.relationshipId}'),
              label: 'Send reminder',
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              isLoading: isSending,
              onPressed: isSending ? null : onRemind,
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space4),
      child: Row(
        children: [
          Text(label,
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
          const Spacer(),
          Text(value,
              style: AppTextStyles.caption
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
