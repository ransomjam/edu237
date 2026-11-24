import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ParentLessonDetailScreen extends StatelessWidget {
  const ParentLessonDetailScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lesson'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lesson.title, style: AppTextStyles.h1),
              const SizedBox(height: AppConstants.space16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space12, vertical: AppConstants.space4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      lesson.form,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space12, vertical: AppConstants.space4),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      lesson.subject,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.space24),
              Text('Description', style: AppTextStyles.h3),
              const SizedBox(height: AppConstants.space8),
              Text(lesson.description, style: AppTextStyles.bodyLarge),
              const SizedBox(height: AppConstants.space32),
              Text(
                'Posted ${lesson.createdAt.toLocal().toString().split('.')[0]}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
