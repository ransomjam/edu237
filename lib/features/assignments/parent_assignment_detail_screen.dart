import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/assignment.dart';
import '../../core/models/student.dart';
import '../../core/models/submission.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/submission_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';

class ParentAssignmentDetailScreen extends StatefulWidget {
  const ParentAssignmentDetailScreen({
    super.key,
    required this.assignment,
    required this.student,
  });

  final Assignment assignment;
  final Student student;

  @override
  State<ParentAssignmentDetailScreen> createState() =>
      _ParentAssignmentDetailScreenState();
}

class _ParentAssignmentDetailScreenState
    extends State<ParentAssignmentDetailScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  Submission? _submission;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadSubmission();
    }
  }

  Future<void> _loadSubmission() async {
    setState(() => _isLoading = true);

    final result =
        await SubmissionServiceScope.of(context).fetchSubmissionForStudent(
      assignmentId: widget.assignment.id,
      studentId: widget.student.id,
    );
    if (!mounted) return;

    setState(() {
      _submission = result is SubmissionSuccess ? result.submission : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assignment')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final a = widget.assignment;

    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        Text(a.title, style: AppTextStyles.h1),
        const SizedBox(height: AppConstants.space16),
        if (a.dueAt != null) ...[
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.grey500),
              const SizedBox(width: AppConstants.space8),
              Text(
                'Due ${a.dueAt!.toLocal().toString().split('.')[0]}',
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space16),
        ],
        Text('Instructions', style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space8),
        Text(a.instructions, style: AppTextStyles.bodyLarge),
        const SizedBox(height: AppConstants.space32),
        const Divider(),
        const SizedBox(height: AppConstants.space24),
        Text('Your Answer', style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space12),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_submission != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.space16),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(AppConstants.radius),
              border: Border.all(color: AppColors.success),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: AppConstants.space8),
                    Text('Submitted',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppConstants.space12),
                Text(_submission!.content, style: AppTextStyles.bodyLarge),
                const SizedBox(height: AppConstants.space12),
                Text(
                  'Last updated ${_submission!.updatedAt.toLocal().toString().split('.')[0]}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.grey500),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space16),
          Text(
            'Once submitted, you can still edit your answer until the teacher reviews it.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space16),
          AppButton(
            label: 'Edit submission',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            onPressed: () => context.push(
              AppRoutes.submitWork,
              extra: {
                'assignment': a,
                'student': widget.student,
                'submission': _submission,
              },
            ).then((_) => _loadSubmission()),
          ),
        ] else ...[
          Text(
            'You have not submitted an answer yet.',
            style: AppTextStyles.body.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space16),
          AppButton(
            label: 'Submit Answer',
            isFullWidth: true,
            onPressed: () => context.push(
              AppRoutes.submitWork,
              extra: {
                'assignment': a,
                'student': widget.student,
                'submission': null,
              },
            ).then((_) => _loadSubmission()),
          ),
        ],
      ],
    );
  }
}
