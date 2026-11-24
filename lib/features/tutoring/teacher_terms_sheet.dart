import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/service_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';

/// The Camiva teacher terms, shown at the point of accepting a request.
///
/// This is where the commercial agreement is made, so it is deliberately not
/// hidden in a Terms and Conditions page: the teacher reads the five points and
/// ticks the box in the same breath as accepting.
///
/// Nothing is charged here. The teacher gets the relationship, earns from the
/// first month, and only then does the service plan begin.
///
/// Returns true when the teacher agreed and wants to accept.
Future<bool?> showTeacherTermsSheet(
  BuildContext context, {
  required String childName,
  required String planAmount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TeacherTermsSheet(
      childName: childName,
      planAmount: planAmount,
    ),
  );
}

class _TeacherTermsSheet extends StatefulWidget {
  const _TeacherTermsSheet({required this.childName, required this.planAmount});

  final String childName;
  final String planAmount;

  @override
  State<_TeacherTermsSheet> createState() => _TeacherTermsSheetState();
}

class _TeacherTermsSheetState extends State<_TeacherTermsSheet> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space20),
        child: Column(
          key: const Key('teacher_terms_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camiva Teacher Terms', style: AppTextStyles.h2),
            const SizedBox(height: AppConstants.space4),
            Text(
              'By accepting ${widget.childName}\'s tutoring request:',
              style: AppTextStyles.body.copyWith(color: AppColors.grey700),
            ),
            const SizedBox(height: AppConstants.space16),

            for (final point in TeacherTerms.points(widget.planAmount))
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: AppConstants.space8),
                    Expanded(child: Text(point, style: AppTextStyles.body)),
                  ],
                ),
              ),

            const SizedBox(height: AppConstants.space8),
            // The thing teachers most want to know: nothing is owed today.
            Container(
              padding: const EdgeInsets.all(AppConstants.space12),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(
                    child: Text(
                      'You pay nothing to accept. You earn from your tutoring '
                      'first.',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.grey900),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.space12),
            CheckboxListTile(
              key: const Key('agree_terms_checkbox'),
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I agree to these terms'),
            ),
            const SizedBox(height: AppConstants.space8),

            AppButton(
              key: const Key('accept_with_terms_button'),
              label: 'Accept request',
              isFullWidth: true,
              onPressed:
                  _agreed ? () => Navigator.of(context).pop(true) : null,
            ),
            const SizedBox(height: AppConstants.space8),
            AppButton(
              key: const Key('terms_cancel_button'),
              label: 'Not now',
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
