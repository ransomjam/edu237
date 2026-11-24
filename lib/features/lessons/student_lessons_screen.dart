import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/lesson_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

class StudentLessonsScreen extends StatefulWidget {
  const StudentLessonsScreen({super.key, required this.student});

  final Student student;

  @override
  State<StudentLessonsScreen> createState() => _StudentLessonsScreenState();
}

class _StudentLessonsScreenState extends State<StudentLessonsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<Lesson> _lessons = [];

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

    final result = await LessonServiceScope.of(context)
        .fetchStudentLessons(widget.student.id);
    if (!mounted) return;

    switch (result) {
      case LessonListSuccess(:final lessons):
        setState(() {
          _lessons = lessons;
          _isLoading = false;
        });
      case LessonEmpty():
        setState(() {
          _lessons = const [];
          _isLoading = false;
        });
      case LessonFailure(:final message):
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.student.name}\'s Learning'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Text('Loading lessons...'));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!,
                  style: AppTextStyles.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppConstants.space16),
              AppButton(label: 'Retry', onPressed: _load),
            ],
          ),
        ),
      );
    }
    if (_lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No lessons yet',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.space12),
              Text(
                'Lessons from teachers will appear here.',
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      itemCount: _lessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppConstants.space12),
      itemBuilder: (context, index) {
        final lesson = _lessons[index];
        return _LessonCard(
          lesson: lesson,
          onTap: () => context.push(
            AppRoutes.parentLessonDetail,
            extra: lesson,
          ),
        );
      },
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson, required this.onTap});

  final Lesson lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lesson.title, style: AppTextStyles.h3),
            const SizedBox(height: AppConstants.space8),
            Row(
              children: [
                _Badge(label: lesson.form, color: AppColors.primary),
                const SizedBox(width: AppConstants.space8),
                _Badge(label: lesson.subject, color: AppColors.success),
              ],
            ),
            const SizedBox(height: AppConstants.space12),
            Text(
              lesson.description,
              style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppConstants.space12),
            Text(
              'Posted ${lesson.createdAt.toLocal().toString().split(' ')[0]}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space8,
        vertical: AppConstants.space4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
