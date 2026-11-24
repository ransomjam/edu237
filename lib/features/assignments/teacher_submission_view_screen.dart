import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'teacher_assignment_detail_screen.dart';

class TeacherSubmissionViewScreen extends StatelessWidget {
  const TeacherSubmissionViewScreen({super.key, required this.recipientStatus});

  final RecipientStatus recipientStatus;

  @override
  Widget build(BuildContext context) {
    final submission = recipientStatus.submission!;
    return Scaffold(
      appBar: AppBar(
        title: Text(recipientStatus.studentName),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submission', style: AppTextStyles.h2),
              const SizedBox(height: AppConstants.space8),
              Text(
                'By ${recipientStatus.studentName}',
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
              const SizedBox(height: AppConstants.space4),
              Text(
                'Submitted ${submission.updatedAt.toLocal().toString().split('.')[0]}',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
              ),
              const SizedBox(height: AppConstants.space32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.space24),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(AppConstants.radius),
                  border: Border.all(color: AppColors.grey300),
                ),
                child: Text(
                  submission.content,
                  style: AppTextStyles.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
