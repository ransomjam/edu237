import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/models/service_plan.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import '../payments/payment_flow_screen.dart';

/// The Camiva Teacher Service Plan.
///
/// A flat monthly charge that begins after the teacher's first month of
/// tutoring earnings. It is not a commission — the teacher keeps 100% of their
/// tutoring money — and it is not a fee to receive students or see contacts.
///
/// The wording never says the first month is "free": the parent pays in full
/// and the teacher earns in full. Camiva simply does not charge the plan yet.
class ServicePlanScreen extends StatefulWidget {
  const ServicePlanScreen({super.key});

  @override
  State<ServicePlanScreen> createState() => _ServicePlanScreenState();
}

class _ServicePlanScreenState extends State<ServicePlanScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  TeacherServicePlan _plan = TeacherServicePlan.none;

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

    final result = await TutoringServiceScope.of(context).fetchServicePlan();
    if (!mounted) return;

    switch (result) {
      case ServicePlanSuccess(:final plan):
        setState(() {
          _plan = plan;
          _isLoading = false;
        });
      case TutoringFailure(:final message):
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camiva Teacher Service')),
        body: AppEmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load your plan',
          message: _errorMessage!,
          actionLabel: 'Try again',
          onAction: _load,
        ),
      );
    }

    final plan = _plan;

    // Payable: the first month is behind them and the plan is owed.
    if (plan.state.isPayable && plan.amount != null) {
      return PaymentFlowScreen(
        title: 'Camiva Teacher Service',
        headline: 'Camiva Teacher Service',
        explanation:
            'Your first month of tutoring is complete. To remain an active '
            "teacher on Camiva and keep using the platform's tutoring "
            'services, maintain your Teacher Service Plan.',
        details: const [
          PaymentDetail('Plan', 'Monthly'),
          PaymentDetail('Includes',
              'Payments, records, reminders, earnings history, support'),
        ],
        amount: plan.amount!,
        currency: plan.currency,
        payLabel: 'Pay ${plan.formattedAmount}',
        successTitle: "You're active",
        successBody: 'Your Camiva Teacher Service Plan is active. Your '
            'tutoring earnings are unaffected — Camiva takes no commission.',
        request: const PaymentRequest(purpose: PaymentPurpose.teacherServiceFee),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Camiva Teacher Service')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
            children: [
              AppCard(
                key: Key('service_plan_${plan.state.value}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Camiva Teacher Service',
                              style: AppTextStyles.h3),
                        ),
                        _StatePill(state: plan.state),
                      ],
                    ),
                    const SizedBox(height: AppConstants.space8),
                    Text(
                      plan.amount == null
                          ? 'No plan is configured'
                          : '${plan.formattedAmount} / month',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppConstants.space8),
                    Text(plan.message,
                        style: AppTextStyles.bodyLarge
                            .copyWith(color: AppColors.grey700)),
                    if (plan.dueOn != null) ...[
                      const SizedBox(height: AppConstants.space16),
                      _Line(
                        label: plan.state == ServicePlanState.active
                            ? 'Next due'
                            : 'Due',
                        value: formatShortDate(plan.dueOn!),
                      ),
                    ],
                    if (plan.firstEarnedAt != null)
                      _Line(
                        label: 'First earned',
                        value: formatShortDate(plan.firstEarnedAt!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.space24),
              const SectionHeader(title: 'What the plan covers'),
              const _Includes(),
              const SizedBox(height: AppConstants.space16),
              Text(
                'Camiva takes no commission from your tutoring earnings. You '
                'keep 100% of what the parent pays for tutoring.',
                key: const Key('no_commission_note'),
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.grey500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Includes extends StatelessWidget {
  const _Includes();

  static const _items = [
    'Camiva-managed tutoring payments',
    'Payment records and receipts',
    'Payment reminders, so you do not have to chase parents',
    'Your earnings history',
    'Scheduling and coordination',
    'Support when a payment goes wrong',
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.space8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(child: Text(item, style: AppTextStyles.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final ServicePlanState state;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (state) {
      ServicePlanState.active => (AppColors.successLight, AppColors.success),
      ServicePlanState.suspended => (AppColors.errorLight, AppColors.error),
      ServicePlanState.overdue ||
      ServicePlanState.due =>
        (AppColors.warningLight, AppColors.warning),
      _ => (AppColors.grey100, AppColors.grey700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(state.label,
          style: AppTextStyles.caption
              .copyWith(color: fg, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.only(top: AppConstants.space4),
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
