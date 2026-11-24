import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/assignment.dart';
import '../../core/models/submission.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/assignment_service.dart';
import '../../core/services/student_service.dart';
import '../../core/services/submission_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

class TeacherAssignmentDetailScreen extends StatefulWidget {
  const TeacherAssignmentDetailScreen({super.key, required this.assignment});

  final Assignment assignment;

  @override
  State<TeacherAssignmentDetailScreen> createState() =>
      _TeacherAssignmentDetailScreenState();
}

class _TeacherAssignmentDetailScreenState
    extends State<TeacherAssignmentDetailScreen> {
  late Assignment _assignment;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDeleting = false;

  // recipient student id -> submission (or null if not submitted)
  List<RecipientStatus> _recipientStatuses = [];

  @override
  void initState() {
    super.initState();
    _assignment = widget.assignment;
  }

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final assignmentService = AssignmentServiceScope.of(context);
    final submissionService = SubmissionServiceScope.of(context);
    final studentService = StudentServiceScope.of(context);

    // Fetch recipients
    final recipients = await assignmentService.fetchRecipients(_assignment.id);
    if (!mounted) return;

    // Fetch submissions for this assignment
    final subResult =
        await submissionService.fetchSubmissionsForAssignment(_assignment.id);
    if (!mounted) return;

    final submissions = subResult is SubmissionListSuccess
        ? subResult.submissions
        : <Submission>[];

    // For each recipient, look up student name and match submission
    final statuses = <RecipientStatus>[];
    for (final r in recipients) {
      final sr = await studentService.fetchStudent(r.studentId);
      if (!mounted) return;
      final studentName =
          sr is StudentSuccess ? sr.student.name : 'Unknown student';
      final submission = submissions
          .where((s) => s.studentId == r.studentId)
          .firstOrNull;
      statuses.add(RecipientStatus(
        studentId: r.studentId,
        studentName: studentName,
        submission: submission,
      ));
    }

    setState(() {
      _recipientStatuses = statuses;
      _isLoading = false;
    });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete assignment?'),
        content: const Text(
            'This will delete the assignment and all student submissions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    final result = await AssignmentServiceScope.of(context)
        .deleteAssignment(_assignment.id);
    if (!mounted) return;

    if (result is AssignmentFailure) {
      setState(() => _isDeleting = false);
      final msg = result.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } else {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.error,
            onPressed: _isDeleting ? null : _delete,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Text('Loading...'));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!,
                  style: AppTextStyles.bodyLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppConstants.space16),
              AppButton(label: 'Retry', onPressed: _load),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        Text(_assignment.title, style: AppTextStyles.h1),
        const SizedBox(height: AppConstants.space16),
        if (_assignment.dueAt != null) ...[
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.grey500),
              const SizedBox(width: AppConstants.space8),
              Text(
                'Due ${_assignment.dueAt!.toLocal().toString().split('.')[0]}',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.grey500),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space16),
        ],
        Text('Instructions', style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space8),
        Text(_assignment.instructions, style: AppTextStyles.bodyLarge),
        const SizedBox(height: AppConstants.space32),
        Text('Submissions (${_recipientStatuses.length})',
            style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space12),
        if (_recipientStatuses.isEmpty)
          Text('No submissions yet.',
              style:
                  AppTextStyles.body.copyWith(color: AppColors.grey500))
        else
          ...List.generate(_recipientStatuses.length, (i) {
            final rs = _recipientStatuses[i];
            final submitted = rs.submission != null;
            return AppCard(
              child: ListTile(
                onTap: submitted
                    ? () => context.push(
                          AppRoutes.teacherSubmissionView,
                          extra: rs,
                        )
                    : null,
                leading: CircleAvatar(
                  backgroundColor: submitted
                      ? AppColors.successLight
                      : AppColors.grey100,
                  child: Icon(
                    submitted ? Icons.check : Icons.hourglass_empty,
                    color:
                        submitted ? AppColors.success : AppColors.grey500,
                    size: 20,
                  ),
                ),
                title: Text(rs.studentName, style: AppTextStyles.bodyLarge),
                subtitle: Text(
                  submitted ? 'Submitted' : 'Not submitted',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: submitted ? AppColors.success : AppColors.grey500,
                  ),
                ),
                trailing: submitted
                    ? const Icon(Icons.chevron_right, color: AppColors.grey500)
                    : null,
                contentPadding: EdgeInsets.zero,
              ),
            );
          }),
        const SizedBox(height: AppConstants.space32),
        Text(
          'Created ${_assignment.createdAt.toLocal().toString().split('.')[0]}',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
        ),
      ],
    );
  }
}

class RecipientStatus {
  const RecipientStatus({
    required this.studentId,
    required this.studentName,
    this.submission,
  });
  final String studentId;
  final String studentName;
  final Submission? submission;
}
