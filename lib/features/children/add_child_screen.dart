import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/education_draft.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/education_selectors.dart';

/// Add a child, one question at a time:
///
///   Name → Education system → Primary/Secondary → Cycle → Class → Series →
///   Subjects → Review → Save
///
/// The cycle question is skipped when a stage has only one cycle, and the
/// series question only appears for GCE Advanced Level and the French second
/// cycle, so a parent never sees a question that does not apply.
///
/// Designed for parents with limited smartphone experience: one question per
/// step, large touch targets, minimal typing. A child is a database record, not
/// an account — we never ask for email, phone or password here.
class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

/// Where the wizard currently is. The education phase is driven by
/// [EducationDraft.steps], which is recomputed as answers come in.
enum _Phase { name, education, review }

class _AddChildScreenState extends State<AddChildScreen> {
  final _nameController = TextEditingController();
  final EducationDraft _draft = EducationDraft();

  _Phase _phase = _Phase.name;
  EducationStep _eduStep = EducationStep.subsystem;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<EducationStep> get _eduSteps => _draft.steps;

  /// Index of the current education question, clamped in case an earlier
  /// answer removed the step the user was on (e.g. switching to primary).
  int get _eduIndex {
    final index = _eduSteps.indexOf(_eduStep);
    return index < 0 ? 0 : index;
  }

  int get _totalSteps => _eduSteps.length + 2;

  int get _currentStepNumber => switch (_phase) {
        _Phase.name => 1,
        _Phase.education => _eduIndex + 2,
        _Phase.review => _totalSteps,
      };

  bool get _isLastStep => _phase == _Phase.review;

  void _goBack() {
    if (_isLoading) return;
    if (_phase == _Phase.name) {
      context.pop();
      return;
    }
    setState(() {
      _errorMessage = null;
      if (_phase == _Phase.review) {
        _phase = _Phase.education;
        _eduStep = _eduSteps.last;
      } else if (_eduIndex == 0) {
        _phase = _Phase.name;
      } else {
        _eduStep = _eduSteps[_eduIndex - 1];
      }
    });
  }

  void _goNext() {
    final l10n = AppLocalizations.of(context);
    setState(() => _errorMessage = null);

    switch (_phase) {
      case _Phase.name:
        if (_nameController.text.trim().isEmpty) {
          setState(() => _errorMessage = l10n.validationRequired);
          return;
        }
        setState(() {
          _phase = _Phase.education;
          _eduStep = _eduSteps.first;
        });

      case _Phase.education:
        if (!_draft.isAnswered(_eduStep)) {
          setState(() => _errorMessage = _draft.validationMessage(_eduStep));
          return;
        }
        final steps = _eduSteps;
        final index = steps.indexOf(_eduStep);
        if (index >= 0 && index < steps.length - 1) {
          setState(() => _eduStep = steps[index + 1]);
        } else {
          setState(() => _phase = _Phase.review);
        }

      case _Phase.review:
        _save();
    }
  }

  Future<void> _save() async {
    if (!_draft.isComplete) {
      setState(() {
        _phase = _Phase.education;
        _eduStep = EducationStep.level;
        _errorMessage = _draft.validationMessage(EducationStep.level);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await StudentServiceScope.of(context).createStudent(
      name: _nameController.text,
      levelCode: _draft.levelCode,
      seriesCode: _draft.seriesCode,
      subjects: _draft.subjects.toList(),
    );

    if (!mounted) return;

    switch (result) {
      case StudentSuccess():
        context.pop(true);
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

    return PopScope(
      // While on a later step, the Android back gesture steps back rather than
      // leaving the flow.
      canPop: _phase == _Phase.name,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.addChildTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepHeader(step: _currentStepNumber, total: _totalSteps),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.pageHorizontalPadding,
                  ),
                  child: _buildStep(l10n),
                ),
              ),
              _buildFooter(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(AppLocalizations l10n) {
    switch (_phase) {
      case _Phase.name:
        return _StepBody(
          question: l10n.addChildStepName,
          errorMessage: _errorMessage,
          child: AppTextField(
            controller: _nameController,
            label: l10n.addChildNameLabel,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autofocus: true,
            enabled: !_isLoading,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _goNext(),
          ),
        );

      case _Phase.education:
        return _StepBody(
          question: _eduStep.question,
          errorMessage: _errorMessage,
          child: EducationStepView(
            step: _eduStep,
            draft: _draft,
            enabled: !_isLoading,
            onChanged: () => setState(() => _errorMessage = null),
          ),
        );

      case _Phase.review:
        return _StepBody(
          question: 'Review',
          errorMessage: _errorMessage,
          child: EducationSummaryCard(
            name: _nameController.text.trim(),
            levelCode: _draft.levelCode,
            seriesCode: _draft.seriesCode,
            subjects: _draft.subjects.toList(),
          ),
        );
    }
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space12,
        AppConstants.pageHorizontalPadding,
        AppConstants.space16,
      ),
      child: Row(
        children: [
          if (_phase != _Phase.name) ...[
            Expanded(
              child: AppButton(
                label: l10n.addChildBack,
                variant: AppButtonVariant.outlined,
                onPressed: _isLoading ? null : _goBack,
              ),
            ),
            const SizedBox(width: AppConstants.space12),
          ],
          Expanded(
            flex: 2,
            child: AppButton(
              label:
                  _isLastStep ? l10n.addChildSaveChild : l10n.addChildContinue,
              isFullWidth: true,
              isLoading: _isLoading,
              onPressed: _goNext,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step chrome
// ---------------------------------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space16,
        AppConstants.pageHorizontalPadding,
        AppConstants.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.addChildStepLabel(step, total),
            style: AppTextStyles.label.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: step / total,
              minHeight: 8,
              backgroundColor: AppColors.grey100,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.question,
    required this.child,
    this.errorMessage,
  });

  final String question;
  final Widget child;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppConstants.space24),
        Text(question, style: AppTextStyles.h1),
        const SizedBox(height: AppConstants.space24),
        child,
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: AppConstants.space16),
          EducationErrorBanner(message: errorMessage!),
        ],
        const SizedBox(height: AppConstants.space16),
      ],
    );
  }
}

/// Shared inline error banner for the education flows.
class EducationErrorBanner extends StatelessWidget {
  const EducationErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppConstants.radius),
      ),
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.error),
      ),
    );
  }
}
