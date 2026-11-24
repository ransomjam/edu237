import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/lesson_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';

class TeacherLessonDetailScreen extends StatefulWidget {
  const TeacherLessonDetailScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<TeacherLessonDetailScreen> createState() =>
      _TeacherLessonDetailScreenState();
}

class _TeacherLessonDetailScreenState extends State<TeacherLessonDetailScreen> {
  late Lesson _lesson;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _lesson = widget.lesson;
  }

  Future<void> _edit() async {
    final updated = await context.push<Lesson>(
      AppRoutes.editLesson,
      extra: _lesson,
    );
    if (updated != null && mounted) {
      setState(() => _lesson = updated);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lesson?'),
        content: const Text(
            'This will permanently delete the lesson. Students will no longer be able to see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);

    final result =
        await LessonServiceScope.of(context).deleteLesson(_lesson.id);

    if (!mounted) return;

    if (result is LessonFailure) {
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } else {
      context.pop(true); // Return true to signal deletion
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lesson Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.error,
            onPressed: _isDeleting ? null : _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lesson.title, style: AppTextStyles.h1),
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
                      _lesson.form,
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
                      _lesson.subject,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.space24),
              Text('Description', style: AppTextStyles.h3),
              const SizedBox(height: AppConstants.space8),
              Text(_lesson.description, style: AppTextStyles.bodyLarge),
              const SizedBox(height: AppConstants.space32),
              Text(
                'Created ${_lesson.createdAt.toLocal().toString().split('.')[0]}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
              ),
              if (_lesson.updatedAt.isAfter(_lesson.createdAt)) ...[
                const SizedBox(height: AppConstants.space4),
                Text(
                  'Updated ${_lesson.updatedAt.toLocal().toString().split('.')[0]}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
                ),
              ],
              const SizedBox(height: AppConstants.space32),
              const Divider(),
              const SizedBox(height: AppConstants.space24),
              Text('Assignments', style: AppTextStyles.h2),
              const SizedBox(height: AppConstants.space12),
              AppButton(
                label: 'Create Assignment',
                isFullWidth: true,
                onPressed: () => context.push(
                  AppRoutes.createAssignment,
                  extra: _lesson,
                ),
              ),
              const SizedBox(height: AppConstants.space32),
            ],
          ),
        ),
      ),
    );
  }
}
