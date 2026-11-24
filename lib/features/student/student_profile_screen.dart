import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/education_draft.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/education_selectors.dart';
import 'student_scope.dart';

/// The student's own profile: who they are, what they study, who teaches them.
///
/// A student may correct their own academic details here — that is the whole
/// point of a student account. What they cannot do is manage a family: no
/// add-child, no parent dashboard, no teacher or parent requests, no money.
class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studentProfileTitle)),
      body: SafeArea(
        child: StudentRecordLoader(
          builder: (context, student) => _StudentProfileBody(student: student),
        ),
      ),
    );
  }
}

class _StudentProfileBody extends StatefulWidget {
  const _StudentProfileBody({required this.student});

  final Student student;

  @override
  State<_StudentProfileBody> createState() => _StudentProfileBodyState();
}

class _StudentProfileBodyState extends State<_StudentProfileBody> {
  late Student _student = widget.student;
  List<TeacherProfile> _teachers = const [];
  bool _loadingTeachers = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingTeachers) _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    final relationshipService =
        ParentTeacherRelationshipServiceScope.of(context);
    final teacherProfileService = TeacherProfileServiceScope.of(context);

    final relationships =
        await relationshipService.fetchRelationshipsForStudent(_student.id);
    if (!mounted) return;

    final connectedIds = <String>{};
    if (relationships is RelationshipListSuccess) {
      for (final r in relationships.relationships) {
        if (r.status == RelationshipStatus.accepted) {
          connectedIds.add(r.teacherId);
        }
      }
    }

    final profiles = await teacherProfileService.fetchTeachers();
    if (!mounted) return;

    setState(() {
      _teachers = profiles is TeacherProfileListSuccess
          ? profiles.profiles
              .where((t) => connectedIds.contains(t.userId))
              .toList()
          : const <TeacherProfile>[];
      _loadingTeachers = false;
    });
  }

  Future<void> _editSchoolDetails() async {
    final updated = await showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditSchoolDetailsSheet(student: _student),
    );
    if (updated != null && mounted) {
      setState(() => _student = updated);
    }
  }

  Future<void> _signOut() async {
    final authService = AuthServiceScope.of(context);
    final appState = AppState.of(context);
    final router = GoRouter.of(context);
    await authService.signOut();
    appState.setUser(null);
    router.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final student = _student;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space16,
        AppConstants.pageHorizontalPadding,
        AppConstants.space32,
      ),
      children: [
        Center(
          child: Column(
            children: [
              AppAvatar(name: student.name, size: 84, kind: AvatarKind.child),
              const SizedBox(height: AppConstants.space12),
              Text(student.name, style: AppTextStyles.h1),
              const SizedBox(height: 4),
              StudentLevelLine(
                student: student,
                style: AppTextStyles.body.copyWith(color: AppColors.grey700),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space24),

        const SectionHeader(title: 'School details'),
        _DetailRow(
            label: 'Education system',
            value: student.effectiveSubsystem?.label ?? '—'),
        _DetailRow(
          label: 'School stage',
          value: (student.effectiveStage != null &&
                  student.effectiveSubsystem != null)
              ? student.effectiveStage!.labelFor(student.effectiveSubsystem!)
              : '—',
        ),
        _DetailRow(label: 'Cycle', value: student.effectiveCycle?.label ?? '—'),
        _DetailRow(label: 'Class', value: student.level?.label ?? '—'),
        if (student.series != null)
          _DetailRow(label: 'Series', value: student.series!.qualifiedLabel),
        const SizedBox(height: AppConstants.space12),
        AppButton(
          key: const Key('student_edit_school_details'),
          label: 'Update school details',
          variant: AppButtonVariant.outlined,
          isFullWidth: true,
          onPressed: _editSchoolDetails,
        ),
        const SizedBox(height: AppConstants.space24),

        const SectionHeader(title: 'My subjects'),
        if (student.subjects.isEmpty)
          Text('No subjects yet.',
              style: AppTextStyles.body.copyWith(color: AppColors.grey500))
        else
          Wrap(
            spacing: AppConstants.space8,
            runSpacing: AppConstants.space8,
            children: [
              for (final subject in student.subjects)
                SubjectChip(subject: subject),
            ],
          ),
        const SizedBox(height: AppConstants.space24),

        const SectionHeader(title: 'My teachers'),
        if (_loadingTeachers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.space12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_teachers.isEmpty)
          Text('No teachers connected yet.',
              style: AppTextStyles.body.copyWith(color: AppColors.grey500))
        else
          TileGroup(
            children: [
              for (final teacher in _teachers)
                PersonTile(
                  name: teacher.fullNameWithTitle,
                  subtitle: teacher.subjects.take(3).join(' · '),
                  imageUrl: teacher.photoUrl,
                  kind: AvatarKind.teacher,
                ),
            ],
          ),
        const SizedBox(height: AppConstants.space32),

        AppButton(
          key: const Key('student_sign_out'),
          label: AppLocalizations.of(context).profileLogout,
          variant: AppButtonVariant.outlined,
          isFullWidth: true,
          onPressed: _signOut,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
          ),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the student correct their own class and subjects, using exactly the
/// same selectors the parent and teacher flows use.
class _EditSchoolDetailsSheet extends StatefulWidget {
  const _EditSchoolDetailsSheet({required this.student});

  final Student student;

  @override
  State<_EditSchoolDetailsSheet> createState() =>
      _EditSchoolDetailsSheetState();
}

class _EditSchoolDetailsSheetState extends State<_EditSchoolDetailsSheet> {
  late final EducationDraft _draft =
      EducationDraft.fromStudent(widget.student);

  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _save() async {
    if (!_draft.isComplete) {
      setState(() => _errorMessage = _draft.levelCode == null
          ? _draft.validationMessage(EducationStep.level)
          : _draft.validationMessage(EducationStep.series));
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result =
        await StudentServiceScope.of(context).updateMyStudentRecord(
      name: widget.student.name,
      levelCode: _draft.levelCode!,
      seriesCode: _draft.seriesCode,
      subjects: _draft.subjects.toList(),
    );

    if (!mounted) return;

    switch (result) {
      case StudentSuccess(:final student):
        Navigator.of(context).pop(student);
      case StudentFailure(:final message):
        setState(() {
          _isSaving = false;
          _errorMessage = message;
        });
      case StudentNotFound():
        setState(() {
          _isSaving = false;
          _errorMessage = 'Your student profile could not be found.';
        });
      case StudentListSuccess():
        setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.pageHorizontalPadding,
                  AppConstants.space24,
                  AppConstants.pageHorizontalPadding,
                  AppConstants.space16,
                ),
                children: [
                  Text('Update school details', style: AppTextStyles.h1),
                  const SizedBox(height: AppConstants.space16),
                  for (final step in _draft.steps) ...[
                    Text(step.question, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    EducationStepView(
                      step: step,
                      draft: _draft,
                      enabled: !_isSaving,
                      onChanged: () => setState(() => _errorMessage = null),
                    ),
                    const SizedBox(height: AppConstants.space24),
                  ],
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppConstants.space12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radius),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.pageHorizontalPadding,
                AppConstants.space8,
                AppConstants.pageHorizontalPadding,
                AppConstants.space16,
              ),
              child: AppButton(
                label: 'Save',
                isFullWidth: true,
                isLoading: _isSaving,
                onPressed: _save,
              ),
            ),
          ],
        );
      },
    );
  }
}
