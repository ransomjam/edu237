import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/teacher_earnings.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A teacher's Camiva transaction history, shown on their profile.
///
/// The wording is deliberately narrow. It reports what has happened on the
/// platform — payments completed through Camiva, relationships currently
/// active — and claims nothing about teaching quality, results, or any
/// academic certification, because the ledger cannot support such a claim.
///
/// It renders nothing for a teacher with no Camiva activity yet, rather than
/// showing zeroes that read as a bad score.
class TeacherActivityCard extends StatefulWidget {
  const TeacherActivityCard({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<TeacherActivityCard> createState() => _TeacherActivityCardState();
}

class _TeacherActivityCardState extends State<TeacherActivityCard> {
  TeacherActivity _activity = TeacherActivity.none;
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
    final result = await service.fetchTeacherActivity(widget.teacherId);
    if (!mounted) return;
    if (result case TeacherActivitySuccess(:final activity)) {
      setState(() => _activity = activity);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_activity.hasActivity) return const SizedBox.shrink();

    final payments = _activity.completedPayments;
    final relationships = _activity.activeRelationships;

    return Container(
      key: const Key('teacher_activity_card'),
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppColors.grey700),
              const SizedBox(width: AppConstants.space8),
              Text('Camiva activity', style: AppTextStyles.h3),
            ],
          ),
          const SizedBox(height: AppConstants.space8),
          if (payments > 0)
            Text(
              payments == 1
                  ? '1 completed Camiva tutoring payment'
                  : '$payments completed Camiva tutoring payments',
              style: AppTextStyles.body.copyWith(color: AppColors.grey700),
            ),
          if (relationships > 0)
            Text(
              relationships == 1
                  ? '1 active relationship'
                  : '$relationships active relationships',
              style: AppTextStyles.body.copyWith(color: AppColors.grey700),
            ),
        ],
      ),
    );
  }
}
