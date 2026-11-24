import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/assignment.dart';
import '../../core/models/student.dart';
import '../../core/models/submission.dart';
import '../../core/services/submission_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

class SubmitWorkScreen extends StatefulWidget {
  const SubmitWorkScreen({
    super.key,
    required this.assignment,
    required this.student,
    this.existingSubmission,
  });

  final Assignment assignment;
  final Student student;
  final Submission? existingSubmission;

  @override
  State<SubmitWorkScreen> createState() => _SubmitWorkScreenState();
}

class _SubmitWorkScreenState extends State<SubmitWorkScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _answerController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController(
      text: widget.existingSubmission?.content ?? '',
    );
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await SubmissionServiceScope.of(context).submitWork(
      assignmentId: widget.assignment.id,
      studentId: widget.student.id,
      content: _answerController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result is SubmissionSuccess) {
      context.pop(result.submission);
    } else if (result is SubmissionFailure) {
      final msg = result.message;
      setState(() => _errorMessage = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingSubmission != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Submission' : 'Submit Answer'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          // Assignment banner
          Container(
            padding: const EdgeInsets.all(AppConstants.space16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppConstants.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.assignment.title,
                  style: AppTextStyles.h3,
                ),
                const SizedBox(height: AppConstants.space4),
                Text(
                  widget.assignment.instructions,
                  style: AppTextStyles.body.copyWith(color: AppColors.grey500),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space24),
          if (_errorMessage != null) ...[
            Text(_errorMessage!,
                style: AppTextStyles.body.copyWith(color: AppColors.error)),
            const SizedBox(height: AppConstants.space16),
          ],
          Text('Your Answer', style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space12),
          AppTextField(
            label: 'Write your answer here',
            controller: _answerController,
            maxLines: 10,
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Please write your answer' : null,
          ),
          const SizedBox(height: AppConstants.space16),
          Text(
            'Once submitted, you can still edit your answer until the teacher reviews it.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space32),
          AppButton(
            label: widget.existingSubmission != null
                ? 'Update Submission'
                : 'Submit Assignment',
            isLoading: _isSaving,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
