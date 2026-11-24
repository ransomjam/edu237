import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/payment_transaction.dart';
import '../../core/models/student.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/student_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import 'parent_payment_screen.dart';
import 'payment_receipt_screen.dart';

/// One child–teacher arrangement the parent can pay for.
class PayableArrangement {
  const PayableArrangement({
    required this.relationshipId,
    required this.childName,
    required this.teacherName,
    this.subject,
  });

  final String relationshipId;
  final String childName;
  final String teacherName;
  final String? subject;
}

/// Parent-facing "Payments": what can be paid for, and everything already paid.
///
/// This is both the place a parent pays and the record of what they have paid.
/// An empty history is not a dead end — the tutoring arrangements available to
/// pay for are listed above it, so the screen is useful on the first visit.
///
/// Only payments made through Camiva appear in the history, which is exactly
/// what makes the record worth having. Arrangements settled outside the
/// platform are not wrong; they simply are not part of this history.
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<PaymentTransaction> _payments = const [];
  List<PayableArrangement> _arrangements = const [];

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
        await PaymentServiceScope.of(context).fetchMyPaymentsAsParent();
    if (!mounted) return;

    switch (result) {
      case PaymentListSuccess(:final payments):
        _payments = payments;
      case PaymentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
        return;
      default:
        break;
    }

    await _loadArrangements();
    if (mounted) setState(() => _isLoading = false);
  }

  /// The accepted teaching arrangements this parent can pay for, resolved into
  /// the names a person actually recognises: their child and the teacher.
  Future<void> _loadArrangements() async {
    final relResult = await ParentTeacherRelationshipServiceScope.of(context)
        .fetchMyRelationshipsAsParent();
    if (!mounted) return;
    if (relResult is! RelationshipListSuccess) return;

    final accepted = relResult.relationships
        .where((r) => r.status == RelationshipStatus.accepted)
        .toList();
    if (accepted.isEmpty) {
      _arrangements = const [];
      return;
    }

    final studentResult =
        await StudentServiceScope.of(context).fetchMyStudents();
    if (!mounted) return;
    final children = <String, Student>{
      if (studentResult is StudentListSuccess)
        for (final child in studentResult.students) child.id: child,
    };

    final teacherResult =
        await TeacherProfileServiceScope.of(context).fetchTeachers();
    if (!mounted) return;
    final teachers = <String, String>{
      if (teacherResult is TeacherProfileListSuccess)
        for (final profile in teacherResult.profiles)
          profile.userId: profile.fullNameWithTitle,
    };

    _arrangements = [
      for (final relationship in accepted)
        PayableArrangement(
          relationshipId: relationship.id,
          childName: children[relationship.studentId]?.name ?? 'Your child',
          teacherName: teachers[relationship.teacherId] ?? 'Your teacher',
          subject: relationship.subject,
        ),
    ];
  }

  Future<void> _pay(PayableArrangement arrangement) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ParentPaymentScreen(
          args: ParentPaymentArgs(
            relationshipId: arrangement.relationshipId,
            childName: arrangement.childName,
            teacherName: arrangement.teacherName,
            subject: arrangement.subject,
          ),
        ),
      ),
    );
    // Whatever happened, the history is the authority on it.
    if (mounted) _load();
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
        icon: Icons.wifi_off_rounded,
        title: 'Could not load payments',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    // Nothing to pay for and nothing paid: the parent needs a teacher first,
    // so say that instead of showing an empty list.
    if (_payments.isEmpty && _arrangements.isEmpty) {
      return const AppEmptyState(
        key: Key('payments_empty'),
        icon: Icons.receipt_long_outlined,
        title: 'No payments yet',
        message:
            'Once a teacher accepts your request, you can pay for tutoring '
            'here and keep a receipt for every payment.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          if (_arrangements.isNotEmpty) ...[
            const SectionHeader(title: 'Pay for tutoring'),
            TileGroup(
              key: const Key('payable_arrangements'),
              children: [
                for (final arrangement in _arrangements)
                  PersonTile(
                    key: Key('pay_${arrangement.relationshipId}'),
                    name: arrangement.childName,
                    subtitle: [
                      if ((arrangement.subject ?? '').isNotEmpty)
                        arrangement.subject!,
                      arrangement.teacherName,
                    ].join(' · '),
                    kind: AvatarKind.child,
                    onTap: () => _pay(arrangement),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.space24),
          ],
          const SectionHeader(title: 'Payment history'),
          if (_payments.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppConstants.space12),
              child: Text(
                'Payments you make through Camiva appear here with a receipt '
                'you can come back to.',
                key: const Key('payments_history_empty'),
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
            )
          else
            for (final payment in _payments)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: PaymentRow(
                  payment: payment,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentReceiptScreen(payment: payment),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// One line of payment history, used on both the parent and teacher side.
class PaymentRow extends StatelessWidget {
  const PaymentRow({super.key, required this.payment, this.onTap});

  final PaymentTransaction payment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if ((payment.studentName ?? '').isNotEmpty) payment.studentName!,
      if ((payment.teacherName ?? '').isNotEmpty) payment.teacherName!,
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.space12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.purpose.label, style: AppTextStyles.h3),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.space2),
                      Text(subtitle,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.grey500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      formatShortDate(payment.paidAt ?? payment.createdAt),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(payment.formattedAmount, style: AppTextStyles.h3),
                  const SizedBox(height: AppConstants.space4),
                  PaymentStatusChip(status: payment.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The status of a payment, in plain words.
class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      PaymentStatus.pending =>
        ('Processing', AppColors.warningLight, AppColors.warning),
      PaymentStatus.successful =>
        ('Paid', AppColors.successLight, AppColors.success),
      PaymentStatus.failed => ('Failed', AppColors.errorLight, AppColors.error),
      PaymentStatus.cancelled =>
        ('Cancelled', AppColors.grey100, AppColors.grey500),
      PaymentStatus.refunded =>
        ('Refunded', AppColors.grey100, AppColors.grey700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space8,
        vertical: AppConstants.space2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
