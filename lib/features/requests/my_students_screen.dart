import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/state/refresh_bus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/edu_ui.dart';

/// Teacher-facing screen listing their connected students.
///
/// Only shows students linked via an accepted [ParentTeacherRelationship].
/// The teacher RLS policy on students allows reading these rows.
class MyStudentsScreen extends StatefulWidget {
  const MyStudentsScreen({super.key});

  @override
  State<MyStudentsScreen> createState() => _MyStudentsScreenState();
}

class _MyStudentsScreenState extends State<MyStudentsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  // Students joined with their relationships for display.
  List<_StudentWithRelationship> _entries = const [];
  String _selectedFormFilter = 'All';
  RefreshBus? _refreshBus;
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload whenever a relationship changes elsewhere (e.g. a request was
    // accepted on the Requests tab while this kept-alive tab was idle).
    final bus = RefreshBusScope.maybeOf(context);
    if (bus != _refreshBus) {
      _refreshBus?.removeListener(_onRelationshipsChanged);
      _refreshBus = bus;
      _refreshBus?.addListener(_onRelationshipsChanged);
    }
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  @override
  void dispose() {
    _refreshBus?.removeListener(_onRelationshipsChanged);
    super.dispose();
  }

  void _onRelationshipsChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final relService = ParentTeacherRelationshipServiceScope.of(context);
    final studentService = StudentServiceScope.of(context);

    final result = await relService.fetchMyRelationshipsAsTeacher();
    if (!mounted) return;

    switch (result) {
      case RelationshipListSuccess(:final relationships):
        // Keep only accepted relationships, most recent first.
        final accepted = relationships
            .where((r) => r.status == RelationshipStatus.accepted)
            .toList();

        // Batch-read the connected students in ONE query, scoped by RLS (a
        // teacher may read students they are connected to). We deliberately do
        // NOT use fetchStudent(), which is parent-scoped and would return
        // nothing for a teacher.
        final ids = accepted.map((r) => r.studentId).toSet().toList();
        final studentResult = await studentService.fetchStudentsByIds(ids);
        if (!mounted) return;

        final byId = <String, Student>{};
        if (studentResult case StudentListSuccess(:final students)) {
          for (final s in students) {
            byId[s.id] = s;
          }
        }

        final entries = <_StudentWithRelationship>[];
        for (final rel in accepted) {
          final student = byId[rel.studentId];
          if (student != null) {
            entries.add(_StudentWithRelationship(
              student: student,
              relationship: rel,
            ));
          }
        }
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      case RelationshipFailure(:final message):
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myStudentsTitle)),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return Center(child: Text(l10n.childrenLoading));
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.errorGenericTitle,
        message: l10n.errorGenericBody,
        actionLabel: l10n.retryButton,
        onAction: _load,
      );
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.12),
            AppEmptyState(
              icon: Icons.groups_outlined,
              title: l10n.myStudentsEmptyTitle,
              message: l10n.myStudentsEmptyBody,
            ),
          ],
        ),
      );
    }

    // Filter on the qualified label so an English Form 4 and a French 4eme
    // are never collapsed into one chip.
    final availableForms = _entries
        .map((e) => e.student.qualifiedLevelLabel)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    final filteredEntries = _selectedFormFilter == 'All'
        ? _entries
        : _entries
            .where((e) => e.student.qualifiedLevelLabel == _selectedFormFilter)
            .toList();

    return Column(
      children: [
        if (availableForms.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.pageHorizontalPadding,
              vertical: AppConstants.space12,
            ),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _selectedFormFilter == 'All',
                  onTap: () => setState(() => _selectedFormFilter = 'All'),
                ),
                for (final form in availableForms) ...[
                  const SizedBox(width: AppConstants.space8),
                  _FilterChip(
                    label: form,
                    isSelected: _selectedFormFilter == form,
                    onTap: () => setState(() => _selectedFormFilter = form),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
            padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
            itemCount: filteredEntries.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppConstants.space12),
            itemBuilder: (context, index) {
              final entry = filteredEntries[index];
              return _StudentCard(
                student: entry.student,
                relationship: entry.relationship,
                onTap: () => context.push(
                  AppRoutes.scheduleLesson,
                  extra: entry.student,
                ),
              );
            },
          ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.white,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey300,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? AppColors.white : AppColors.grey500,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _StudentWithRelationship {
  const _StudentWithRelationship({
    required this.student,
    required this.relationship,
  });
  final Student student;
  final ParentTeacherRelationship relationship;
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.relationship,
    required this.onTap,
  });

  final Student student;
  final ParentTeacherRelationship relationship;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = student.qualifiedLevelLabel ?? '—';
    final subjects = student.subjects;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name, style: AppTextStyles.h3),
                          const SizedBox(height: AppConstants.space2),
                          Text(form,
                              style: AppTextStyles.body
                                  .copyWith(color: AppColors.grey500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusFull),
                      ),
                      child: Text(l10n.connectedBadge,
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: AppConstants.space4),
                    const Icon(Icons.chevron_right,
                        color: AppColors.grey300, size: 22),
                  ],
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.space12),
                  Padding(
                    padding: const EdgeInsets.only(left: 58),
                    child: Wrap(
                      spacing: AppConstants.space8,
                      runSpacing: AppConstants.space8,
                      children: [
                        for (final subject in subjects)
                          SubjectChip(subject: subject),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
