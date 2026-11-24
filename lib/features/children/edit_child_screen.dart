import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/education_draft.dart';
import '../../core/models/student.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/education_selectors.dart';
import 'add_child_screen.dart' show EducationErrorBanner;

/// Edit an existing child. A single scrolling screen (not a wizard) so the
/// parent sees everything at once, pre-filled with the current values, using
/// exactly the same education selectors as Add Child.
///
/// Legacy records — rows saved before the structured catalogue, whose class we
/// cannot map to a subsystem — are shown with a clear banner asking the parent
/// to confirm the class. The stored value is preserved and displayed until they
/// do; nothing is guessed on their behalf.
///
/// On success it pops the updated [Student] back to the detail screen.
class EditChildScreen extends StatefulWidget {
  const EditChildScreen({
    super.key,
    this.student,
    this.studentId,
  }) : assert(student != null || studentId != null,
            'Must provide student or studentId');

  final Student? student;
  final String? studentId;

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  Student? _student;
  TextEditingController? _nameController;
  TextEditingController? _notesController;
  EducationDraft _draft = EducationDraft();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    if (_student != null) {
      _initFields(_student!);
    } else {
      _loadStudent();
    }
  }

  void _initFields(Student s) {
    _nameController = TextEditingController(text: s.name);
    _notesController = TextEditingController(text: s.notes ?? '');
    _draft = EducationDraft.fromStudent(s);
  }

  Future<void> _loadStudent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result =
        await StudentServiceScope.of(context).fetchStudent(widget.studentId!);
    if (!mounted) return;
    switch (result) {
      case StudentSuccess(:final student):
        setState(() {
          _student = student;
          _initFields(student);
          _isLoading = false;
        });
      case StudentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      case StudentListSuccess():
      case StudentNotFound():
        setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController?.dispose();
    _notesController?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sName = _nameController?.text ?? '';
    if (sName.trim().isEmpty) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context).validationRequired);
      return;
    }
    if (!_draft.isComplete) {
      setState(() => _errorMessage = _draft.levelCode == null
          ? _draft.validationMessage(EducationStep.level)
          : _draft.validationMessage(EducationStep.series));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await StudentServiceScope.of(context).updateStudent(
      studentId: _student!.id,
      name: sName,
      dateOfBirth: _student!.dateOfBirth,
      levelCode: _draft.levelCode,
      seriesCode: _draft.seriesCode,
      subjects: _draft.subjects.toList(),
      notes: _notesController?.text ?? '',
    );

    if (!mounted) return;

    switch (result) {
      case StudentSuccess(:final student):
        context.pop(student);
      case StudentFailure(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      case StudentListSuccess():
      case StudentNotFound():
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final student = _student;
    if (student == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.editChildTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editChildTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.pageHorizontalPadding,
                  vertical: AppConstants.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (student.needsEducationReview)
                      _LegacyEducationBanner(
                          storedLevel: student.schoolLevel ?? ''),
                    Text(l10n.editChildNameQuestion, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _nameController,
                      label: l10n.addChildNameLabel,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      enabled: !_isLoading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppConstants.space32),

                    // The same hierarchy as Add Child, revealed progressively.
                    for (final step in _draft.steps) ...[
                      Text(step.question, style: AppTextStyles.h3),
                      const SizedBox(height: AppConstants.space12),
                      EducationStepView(
                        step: step,
                        draft: _draft,
                        enabled: !_isLoading,
                        onChanged: () =>
                            setState(() => _errorMessage = null),
                      ),
                      const SizedBox(height: AppConstants.space24),
                    ],

                    const SizedBox(height: AppConstants.space8),
                    _StudentLoginSection(
                      student: student,
                      enabled: !_isLoading,
                      onCodeIssued: (updated) =>
                          setState(() => _student = updated),
                    ),
                    const SizedBox(height: AppConstants.space24),
                    Text(l10n.childDetailNotesLabel, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _notesController,
                      label: l10n.addChildNotesLabel,
                      textInputAction: TextInputAction.done,
                      maxLines: 3,
                      enabled: !_isLoading,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppConstants.space16),
                      EducationErrorBanner(message: _errorMessage!),
                    ],
                    const SizedBox(height: AppConstants.space16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.pageHorizontalPadding,
                AppConstants.space12,
                AppConstants.pageHorizontalPadding,
                AppConstants.space16,
              ),
              child: AppButton(
                label: l10n.editChildSave,
                isFullWidth: true,
                isLoading: _isLoading,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets a parent give their child their own login without creating a second
/// learner record.
///
/// The parent issues a one-time code; the child enters it when they register
/// and their account attaches to THIS row. Nothing here creates or duplicates
/// a student — that is the whole point of the code.
class _StudentLoginSection extends StatefulWidget {
  const _StudentLoginSection({
    required this.student,
    required this.enabled,
    required this.onCodeIssued,
  });

  final Student student;
  final bool enabled;
  final ValueChanged<Student> onCodeIssued;

  @override
  State<_StudentLoginSection> createState() => _StudentLoginSectionState();
}

class _StudentLoginSectionState extends State<_StudentLoginSection> {
  bool _isWorking = false;
  String? _errorMessage;

  Future<void> _createCode() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    final result =
        await StudentServiceScope.of(context).createLinkCode(widget.student.id);
    if (!mounted) return;

    setState(() => _isWorking = false);
    switch (result) {
      case StudentSuccess(:final student):
        widget.onCodeIssued(student);
      case StudentFailure(:final message):
        setState(() => _errorMessage = message);
      case StudentListSuccess():
      case StudentNotFound():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Student login', style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space4),
        if (student.hasAccount)
          Text(
            '${student.name} has their own login and can see their subjects, '
            'teachers and lessons.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey700),
          )
        else ...[
          Text(
            'Give ${student.name} their own login. They register on Camiva '
            'and enter this code, so you both see the same profile — no '
            'second child is created.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey700),
          ),
          const SizedBox(height: AppConstants.space12),
          if (student.hasPendingLinkCode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.space16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Their code',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.grey700)),
                  const SizedBox(height: 4),
                  SelectableText(
                    student.linkCode!,
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppConstants.space12),
          AppButton(
            key: const Key('child_create_link_code'),
            label: student.hasPendingLinkCode
                ? 'Create a new code'
                : 'Create a login code',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            isLoading: _isWorking,
            onPressed: widget.enabled ? _createCode : null,
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: AppConstants.space12),
          EducationErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }
}

/// Shown for a child whose stored class predates the structured catalogue and
/// cannot be mapped to a subsystem. The old value is never overwritten
/// silently — the parent confirms it here.
class _LegacyEducationBanner extends StatelessWidget {
  const _LegacyEducationBanner({required this.storedLevel});

  final String storedLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.space24),
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: AppConstants.space8),
              Expanded(
                child: Text(
                  'Please confirm this class',
                  style: AppTextStyles.label
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            storedLevel.isEmpty
                ? 'Camiva now records the education system as well as the '
                    'class. Choose the system and class below.'
                : 'This child is saved as "$storedLevel". Camiva now records '
                    'the education system too, so please choose the system '
                    'and class below. Nothing has been changed for you.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey700),
          ),
        ],
      ),
    );
  }
}
