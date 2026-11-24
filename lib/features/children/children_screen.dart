import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// The Children tab — a compact management list of a parent's children.
/// Distinct from Home: this is where the parent inspects and manages each
/// child (class, subjects, teacher connection) and adds new ones.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<Student> _children = const [];
  Set<String> _connected = const {};

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

    final result = await StudentServiceScope.of(context).fetchMyStudents();
    if (!mounted) return;

    switch (result) {
      case StudentListSuccess(:final students):
        final connected = <String>{};
        final rel = await ParentTeacherRelationshipServiceScope.of(context)
            .fetchMyRelationshipsAsParent();
        if (!mounted) return;
        if (rel is RelationshipListSuccess) {
          for (final r in rel.relationships) {
            if (r.status == RelationshipStatus.accepted) {
              connected.add(r.studentId);
            }
          }
        }
        setState(() {
          _children = students;
          _connected = connected;
          _isLoading = false;
        });
      case StudentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      case StudentSuccess():
      case StudentNotFound():
        setState(() => _isLoading = false);
    }
  }

  Future<void> _addChild() async {
    final saved = await context.push<bool>(AppRoutes.addChild);
    if (saved == true && mounted) _load();
  }

  Future<void> _openChild(Student child) async {
    await context.push(AppRoutes.childDetailPath(child.id), extra: child);
    if (mounted) _load();
  }

  void _findTeacher(Student child) {
    context.push(AppRoutes.childTeachersPath(child.id), extra: child);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.childrenTitle)),
      floatingActionButton: _children.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addChild,
              icon: const PhosphorIcon(PhosphorIcons.plusBold, size: 18, color: Colors.white),
              label: Text(l10n.addChildButton),
            ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const _ListSkeleton();
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        iconName: PhosphorIcons.warningCircle,
        title: l10n.errorGenericTitle,
        message: l10n.errorGenericBody,
        actionLabel: l10n.retryButton,
        onAction: _load,
      );
    }
    if (_children.isEmpty) {
      return AppEmptyState(
        iconName: PhosphorIcons.student,
        title: l10n.childrenEmptyTitle,
        message: l10n.childrenEmptyBody,
        actionLabel: l10n.addChildButton,
        onAction: _addChild,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pageHorizontalPadding,
          AppConstants.space16,
          AppConstants.pageHorizontalPadding,
          AppConstants.space64 + AppConstants.space32,
        ),
        children: [
          for (final child in _children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.space12),
              child: _ChildRow(
                child: child,
                isConnected: _connected.contains(child.id),
                onTap: () => _openChild(child),
                onFindTeacher: () => _findTeacher(child),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow({
    required this.child,
    required this.isConnected,
    required this.onTap,
    required this.onFindTeacher,
  });

  final Student child;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onFindTeacher;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final level = child.qualifiedLevelLabel ?? '';
    final subjects = child.subjects.take(3).join(' · ');
    final subtitle = [
      if (level.isNotEmpty) level,
      if (subjects.isNotEmpty) subjects,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.space12),
                child: Row(
                  children: [
                    AppAvatar(
                        name: child.name, size: 48, kind: AvatarKind.child),
                    const SizedBox(width: AppConstants.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(child.name, style: AppTextStyles.h3),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: AppConstants.space2),
                            Text(subtitle,
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.grey500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: AppConstants.space8),
                          if (isConnected)
                            StatusLine(
                              label: l10n.childTeacherConnected,
                              color: AppColors.success,
                              iconName: PhosphorIcons.shieldCheckFill,
                            )
                          else
                            StatusLine(
                              label: l10n.childNoTeacher,
                              color: AppColors.grey500,
                              iconName: PhosphorIcons.magnifyingGlass,
                            ),
                        ],
                      ),
                    ),
                    const PhosphorIcon(PhosphorIcons.caretRight,
                        color: AppColors.grey500, size: 16),
                  ],
                ),
              ),
            ),
          ),
          if (!isConnected)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space12,
                0,
                AppConstants.space12,
                AppConstants.space12,
              ),
              child: AppButton(
                label: l10n.findTeacherButton,
                variant: AppButtonVariant.outlined,
                isFullWidth: true,
                leading: const PhosphorIcon(PhosphorIcons.magnifyingGlass, size: 16, color: AppColors.primary),
                onPressed: onFindTeacher,
              ),
            ),
        ],
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.space12),
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
          ),
      ],
    );
  }
}
