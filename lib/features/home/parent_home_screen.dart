import 'package:flutter/material.dart';
import '../../shared/widgets/phosphor_icon.dart';
import '../../shared/widgets/geometric_header.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../../core/services/auth_service.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson_reminder.dart';
import '../../core/models/lesson_session.dart';
import '../../core/models/billing_summary.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/models/tutoring_agreement.dart';
import '../payments/payment_reminders_card.dart';
import '../tutoring/review_agreement_screen.dart';
import '../../core/utils/date_format.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/services/student_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../payments/parent_payment_screen.dart';
import '../teacher/teacher_discovery_screen.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import '../schedule/session_widgets.dart';

/// The parent's Home — an at-a-glance overview: greeting, what needs attention,
/// a compact overview of the children, recent learning, and a couple of quick
/// actions. Distinct from the Children tab, which is for management.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Student> _children = const [];
  Map<String, ParentSummary> _summaries = const {};
  Set<String> _connected = const {};
  List<LessonSession> _sessions = const [];
  List<ParentTeacherRelationship> _relationships = const [];
  Map<String, String> _teacherNames = const {};
  Map<String, BillingSummary> _billing = const {};

  /// Live tutoring arrangements per relationship. A 'proposed' one is waiting
  /// for this parent to review it; a 'confirmed' one is waiting on the teacher.
  Map<String, TutoringAgreement> _agreements = const {};
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

    final studentService = StudentServiceScope.of(context);
    final activityService = LearningActivityServiceScope.of(context);
    final relationshipService = ParentTeacherRelationshipServiceScope.of(context);
    final teacherProfileService = TeacherProfileServiceScope.of(context);
    final sessionService = LessonSessionServiceScope.of(context);
    final paymentService = PaymentServiceScope.of(context);
    final tutoring = TutoringServiceScope.maybeOf(context);

    // Batch 1: Fetch students, relationships, teachers, and sessions in parallel
    final batch1 = await Future.wait([
      studentService.fetchMyStudents(),
      relationshipService.fetchMyRelationshipsAsParent(),
      teacherProfileService.fetchTeachers(),
      sessionService.fetchMyParentSessions(),
    ]);
    if (!mounted) return;

    final result = batch1[0] as StudentResult;
    final relResult = batch1[1] as RelationshipResult;
    final teacherResult = batch1[2] as TeacherProfileResult;
    final sessionResult = batch1[3] as LessonSessionResult;

    switch (result) {
      case StudentListSuccess(:final students):
        final connected = <String>{};
        List<ParentTeacherRelationship> relationships = const [];
        if (relResult is RelationshipListSuccess) {
          relationships = relResult.relationships;
          for (final r in relResult.relationships) {
            if (r.status == RelationshipStatus.accepted) {
              connected.add(r.studentId);
            }
          }
        }

        // Fetch teachers to get display names
        final teacherNames = <String, String>{};
        if (teacherResult is TeacherProfileListSuccess) {
          for (final p in teacherResult.profiles) {
            teacherNames[p.userId] = p.displayName;
          }
        }

        var sessions = const <LessonSession>[];
        if (sessionResult is LessonSessionListSuccess) {
          sessions = sessionResult.sessions;
        }

        final acceptedRels = relationships
            .where((r) => r.status == RelationshipStatus.accepted)
            .toList();

        // Batch 2: Parallel fetch child summaries, billing, and agreements
        final summaryFutures = students.map((child) async {
          final summary = await activityService.fetchParentSummary(child.id);
          return MapEntry(child.id, summary);
        });

        final billingFutures = acceptedRels.map((r) async {
          final res = await paymentService.fetchBillingSummary(r.id);
          return MapEntry(r.id, res);
        });

        final agreementFutures = tutoring != null
            ? acceptedRels.map((r) async {
                final res = await tutoring.fetchAgreement(r.id);
                return MapEntry(r.id, res);
              })
            : <Future<MapEntry<String, TutoringResult>>>[];

        final summariesEntries = await Future.wait(summaryFutures);
        final billingEntries = await Future.wait(billingFutures);
        final agreementEntries = await Future.wait(agreementFutures);
        if (!mounted) return;

        final summaries = Map.fromEntries(summariesEntries);
        final billing = <String, BillingSummary>{};
        for (final entry in billingEntries) {
          if (entry.value case BillingSummarySuccess(:final summary)
              when summary != null) {
            billing[entry.key] = summary;
          }
        }

        final agreements = <String, TutoringAgreement>{};
        for (final entry in agreementEntries) {
          if (entry.value case AgreementSuccess(:final agreement)
              when agreement != null) {
            agreements[entry.key] = agreement;
          }
        }

        setState(() {
          _children = students;
          _summaries = summaries;
          _connected = connected;
          _sessions = sessions;
          _relationships = relationships;
          _teacherNames = teacherNames;
          _billing = billing;
          _agreements = agreements;
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

  Future<void> _logout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileLogoutConfirmTitle),
        content: Text(l10n.profileLogoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.profileLogoutCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.profileLogoutConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final authService = AuthServiceScope.of(context);
    await authService.signOut();

    if (!context.mounted) return;
    context.go(AppRoutes.login);
  }

  /// Opens the proposal the teacher sent. Confirming there is what makes the
  /// teacher's Platform Charge due - nothing is charged to the parent.
  Future<void> _reviewAgreement(
    TutoringAgreement agreement,
    Student child,
  ) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewAgreementScreen(
          agreement: agreement,
          childName: child.name,
          teacherName: _teacherNames[agreement.teacherId] ?? 'Your teacher',
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openChild(Student child) async {
    final updated = await context.push<Student>(
      AppRoutes.childDetailPath(child.id),
      extra: child,
    );
    if (updated != null && mounted) {
      _load();
    }
  }

  Future<void> _editChild(Student child) async {
    final updated = await context.push<Student>(
      AppRoutes.childEditPath(child.id),
      extra: child,
    );
    if (updated != null && mounted) {
      _load();
    }
  }

  void _findTeacherForSubject(Student child, String? subject) {
    context.push(
      AppRoutes.childTeachersPath(child.id),
      extra: TeacherDiscoveryArgs(child: child, initialSubject: subject),
    );
  }

  void _openLearning(Student child) {
    context.push(AppRoutes.studentLearningFeed, extra: child);
  }

  void _payForTutoring(ParentTeacherRelationship r, Student child) {
    final teacherName = _teacherNames[r.teacherId] ?? 'Your teacher';
    context.push(
      AppRoutes.payForTutoring,
      extra: ParentPaymentArgs(
        relationshipId: r.id,
        childName: child.name,
        teacherName: teacherName,
        subject: r.subject,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const _HomeSkeleton();
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.errorGenericTitle,
        message: _errorMessage!,
        actionLabel: l10n.retryButton,
        onAction: _load,
      );
    }
    if (_children.isEmpty) {
      return AppEmptyState(
        icon: Icons.family_restroom_outlined,
        title: l10n.parentHomeWelcome,
        message: l10n.parentHomeEmptyBody,
        actionLabel: l10n.addChildButton,
        onAction: _addChild,
      );
    }

    final learningChildren =
        _children.where((c) => (_summaries[c.id]?.totalCount ?? 0) > 0).toList();
    final firstUnconnected =
        _children.where((c) => !_connected.contains(c.id)).firstOrNull;

    final now = DateTime.now();
    final reminders = LessonReminderPlanner.due(
      _sessions,
      audience: ReminderAudience.parent,
      now: now,
    );
    final nextByChild = <Student, LessonSession>{};
    for (final child in _children) {
      final next = _sessions
          .where((s) =>
              s.studentId == child.id &&
              s.status.isScheduled &&
              s.localStart.isAfter(now))
          .toList()
        ..sort((a, b) => a.localStart.compareTo(b.localStart));
      if (next.isNotEmpty) nextByChild[child] = next.first;
    }

    final topPad = MediaQuery.of(context).padding.top;
    final parentName = AppState.of(context).currentUser?.name ?? 'Parent';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Blue Banner Header matching mockup
          Stack(
            clipBehavior: Clip.none,
            children: [
              GeometricHeader(
                padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 52),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Home',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Good evening',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          parentName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          onTap: () => _logout(context),
                          borderRadius: BorderRadius.circular(24),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                            child: const PhosphorIcon(PhosphorIcons.user, color: Colors.white, size: 24),
                          ),
                        ),
                        Positioned(
                          top: -2,
                          right: -2,
                          child: InkWell(
                            onTap: () => _logout(context),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: const PhosphorIcon(
                                PhosphorIcons.signOut,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Overlapping Actions Row
              Positioned(
                bottom: -28,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        iconName: PhosphorIcons.plusBold,
                        title: 'Add your child',
                        subtitle: 'Register a new child',
                        onTap: _addChild,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        iconName: PhosphorIcons.magnifyingGlass,
                        title: 'Find a teacher',
                        subtitle: 'Find the right teacher',
                        onTap: () =>
                            _findTeacherForSubject(firstUnconnected ?? _children.first, null),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 44), // spacer for overlap

          // Main body contents
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reminders.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ReminderBanner(reminder: reminders.first),
                ],

                // Payment reminders from Camiva: due amounts, confirmations,
                // arrangement updates. Creating one IS the delivery, so this is
                // where it has to be visible.
                const PaymentRemindersCard(),

                if (nextByChild.isNotEmpty) ...[
                  const SectionHeader(title: 'Next lesson'),
                  for (final entry in nextByChild.entries) ...[
                    NextLessonCard(
                      title: "${entry.key.name}'s next lesson",
                      session: entry.value,
                      onTap: () => _openLearning(entry.key),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],

                if (_children.isNotEmpty) ...[
                  const SectionHeader(title: 'Your children'),
                  for (final child in _children)
                    _ChildOverviewCard(
                      child: child,
                      relationships: _relationships,
                      teacherNames: _teacherNames,
                      billing: _billing,
                      agreements: _agreements,
                      onReviewAgreement: _reviewAgreement,
                      onEdit: () => _editChild(child),
                      onOpen: () => _openChild(child),
                      onFindTeacher: (subject) => _findTeacherForSubject(child, subject),
                      onViewLearning: () => _openLearning(child),
                      onPay: (r) => _payForTutoring(r, child),
                    ),
                ],

                if (learningChildren.isNotEmpty) ...[
                  const SectionHeader(title: 'Recent learning'),
                  TileGroup(
                    children: [
                      for (final child in learningChildren)
                        _LearningSummaryTile(
                          child: child,
                          summary: _summaries[child.id]!,
                          onTap: () => _openLearning(child),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.iconName,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconName;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.iconContainerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PhosphorIcon(iconName, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.grey900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.grey500,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const PhosphorIcon(PhosphorIcons.caretRight, color: AppColors.grey900, size: 13),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _ChildOverviewCard extends StatelessWidget {
  const _ChildOverviewCard({
    required this.child,
    required this.relationships,
    required this.teacherNames,
    required this.onEdit,
    required this.onOpen,
    required this.onFindTeacher,
    required this.onViewLearning,
    required this.onPay,
    this.billing = const {},
    this.agreements = const {},
    this.onReviewAgreement,
  });

  final Student child;
  final List<ParentTeacherRelationship> relationships;
  final Map<String, String> teacherNames;

  /// Monthly picture per relationship id. Absent when the teacher has not set a
  /// monthly fee, in which case the card says nothing about dues.
  final Map<String, BillingSummary> billing;

  /// Live tutoring arrangements, keyed by relationship id.
  final Map<String, TutoringAgreement> agreements;

  final void Function(TutoringAgreement, Student)? onReviewAgreement;
  final VoidCallback onEdit;

  /// Opens the child's own screen. The pencil goes straight to editing, so
  /// without this the card had no way through to the child at all.
  final VoidCallback onOpen;
  final ValueChanged<String?> onFindTeacher;
  final VoidCallback onViewLearning;
  final ValueChanged<ParentTeacherRelationship> onPay;

  String _getFindTeacherLabel() {
    final childRels = relationships
        .where((r) => r.studentId == child.id && r.status == RelationshipStatus.accepted)
        .toList();
    if (childRels.isEmpty) {
      return 'Find a teacher';
    }
    final connectedSubjects = childRels.map((r) => r.subject.trim().toLowerCase()).toSet();
    final unconnectedSubjects = child.subjects
        .where((s) => !connectedSubjects.contains(s.trim().toLowerCase()))
        .toList();

    if (unconnectedSubjects.isEmpty) {
      return 'Find another teacher';
    } else {
      return 'Find teacher for ${unconnectedSubjects.first}';
    }
  }

  String? _getFindTeacherSubject() {
    final childRels = relationships
        .where((r) => r.studentId == child.id && r.status == RelationshipStatus.accepted)
        .toList();
    final connectedSubjects = childRels.map((r) => r.subject.trim().toLowerCase()).toSet();
    final unconnectedSubjects = child.subjects
        .where((s) => !connectedSubjects.contains(s.trim().toLowerCase()))
        .toList();
    return unconnectedSubjects.isNotEmpty ? unconnectedSubjects.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final level = child.qualifiedLevelLabel ?? '';
    final childRels = relationships
        .where((r) => r.studentId == child.id && r.status == RelationshipStatus.accepted)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: AppColors.grey900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (level.isNotEmpty)
                        Text(
                          level,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.grey500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const PhosphorIcon(PhosphorIcons.pencilSimple, size: 18, color: AppColors.grey500),
                  tooltip: 'Edit child',
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (child.subjects.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: child.subjects.map((s) => _SubjectPill(label: s)).toList(),
              ),
              const SizedBox(height: 14),
            ],

            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 14),

            Text(
              'Teacher',
              style: AppTextStyles.label.copyWith(
                color: AppColors.grey900,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (childRels.isNotEmpty) ...[
              ...childRels.map((r) {
                final teacherName = teacherNames[r.teacherId] ?? 'Your teacher';
                final subjectsList = childRels.map((cr) => cr.subject).join(', ');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        children: [
                          AppAvatar(
                            name: teacherName,
                            size: 28,
                            kind: AvatarKind.teacher,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$teacherName ($subjectsList)',
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.grey900,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Connected',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _AgreementState(
                      agreement: agreements[r.id],
                      onReview: onReviewAgreement == null
                          ? null
                          : () => onReviewAgreement!(agreements[r.id]!, child),
                    ),
                    if (agreements[r.id]?.status.isLive ?? true)
                      _BillingLines(summary: billing[r.id]),
                  ],
                );
              }),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'No teacher connected yet.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.grey500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const _CardMiniMapWidget(),
                ],
              ),
            ],

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    onPressed: onViewLearning,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        PhosphorIcon(PhosphorIcons.bookOpen, size: 16, color: AppColors.grey900),
                        SizedBox(width: 8),
                        Text(
                          'View learning',
                          style: TextStyle(
                            color: AppColors.grey900,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: childRels.isEmpty
                      ? ElevatedButton(
                          key: const Key('find_teacher_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => onFindTeacher(_getFindTeacherSubject()),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const PhosphorIcon(PhosphorIcons.calendarBlank, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _getFindTeacherLabel(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ElevatedButton(
                          key: Key('pay_button_${child.id}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => onPay(childRels.first),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              PhosphorIcon(PhosphorIcons.wallet, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Payment',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Where the tutoring arrangement stands, on the parent's card.
///
/// A proposal waiting to be read is the one thing the parent must act on, so it
/// gets a button. A confirmed one is waiting on the teacher's activation and
/// says exactly that, with nothing for the parent to do.
class _AgreementState extends StatelessWidget {
  const _AgreementState({required this.agreement, this.onReview});

  final TutoringAgreement? agreement;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final a = agreement;
    if (a == null || a.status.isLive) return const SizedBox.shrink();

    if (a.status == AgreementStatus.proposed) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          key: const Key('agreement_to_review'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your teacher sent the tutoring details.',
              style: AppTextStyles.caption.copyWith(color: AppColors.grey700),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: Key('review_agreement_${a.id}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onReview,
              child: const Text(
                'Review tutoring details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Confirmed, waiting on the teacher to activate.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        key: const Key('agreement_awaiting_teacher'),
        children: [
          const Icon(Icons.hourglass_top_rounded,
              size: 14, color: AppColors.grey500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Waiting for teacher activation',
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
            ),
          ),
        ],
      ),
    );
  }
}

/// The money picture for one arrangement: when it started, what is left this
/// month, and when the next month falls due.
///
/// Renders nothing at all when the teacher has not set a monthly fee, rather
/// than showing a zero that would look like "nothing to pay".
class _BillingLines extends StatelessWidget {
  const _BillingLines({required this.summary});

  final BillingSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();

    final balanceColour = s.isSettled ? AppColors.success : AppColors.grey900;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        key: const Key('billing_lines'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BillingLine(
            icon: Icons.play_circle_outline,
            label: 'Started',
            value: formatShortDate(s.startedOn),
          ),
          const SizedBox(height: 4),
          _BillingLine(
            icon: Icons.event_outlined,
            label: 'Next payment',
            value: formatShortDate(s.nextDueOn),
          ),
          const SizedBox(height: 4),
          _BillingLine(
            icon: Icons.account_balance_wallet_outlined,
            label: s.isSettled ? 'This month' : 'Left this month',
            value: s.isSettled ? 'Fully paid' : s.formattedBalance,
            valueColour: balanceColour,
          ),
          if (s.isPartlyPaid) ...[
            const SizedBox(height: 4),
            Text(
              '${s.formattedPaid} of ${s.formattedMonthly} paid',
              key: const Key('billing_part_paid'),
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingLine extends StatelessWidget {
  const _BillingLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColour,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.grey500),
        const SizedBox(width: 6),
        Text(label,
            style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
        const Spacer(),
        Text(
          value,
          style: AppTextStyles.caption.copyWith(
            color: valueColour ?? AppColors.grey900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CardMiniMapWidget extends StatelessWidget {
  const _CardMiniMapWidget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 70,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: const Color(0xFFE0F2FE),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: const _CardMiniMapPainter(),
              child: Stack(
              children: [
                Positioned(
                  right: 14,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4.5),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1D4ED8),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x331D4ED8),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const PhosphorIcon(PhosphorIcons.graduationCap, color: Colors.white, size: 12),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class _CardMiniMapPainter extends CustomPainter {
  const _CardMiniMapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final y in [0.25, 0.55, 0.8]) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * y),
        roadPaint,
      );
    }
    for (final x in [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * x, 0),
        Offset(size.width * x, size.height),
        roadPaint,
      );
    }

    final parkPaint = Paint()..color = const Color(0xFFDCFCE7);
    canvas.drawRRect(
      RRect.fromLTRBR(
        size.width * 0.52,
        size.height * 0.35,
        size.width * 0.72,
        size.height * 0.65,
        const Radius.circular(4),
      ),
      parkPaint,
    );

    final dashPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.82)
      ..cubicTo(
        size.width * 0.3, size.height * 0.6,
        size.width * 0.55, size.height * 0.55,
        size.width * 0.78, size.height * 0.22,
      );

    _drawDashedPath(canvas, path, dashPaint, dashLength: 4, gapLength: 3);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        if (draw) {
          final extracted = metric.extractPath(distance, distance + len);
          canvas.drawPath(extracted, paint);
        }
        distance += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SubjectPill extends StatelessWidget {
  const _SubjectPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tagBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIcon.iconForSubject(label),
            size: 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}


class _LearningSummaryTile extends StatelessWidget {
  const _LearningSummaryTile({
    required this.child,
    required this.summary,
    required this.onTap,
  });

  final Student child;
  final ParentSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PersonTile(
      name: child.name,
      kind: AvatarKind.child,
      avatarSize: 40,
      onTap: onTap,
      subtitle: '${summary.totalCount} learning activities',
      showChevron: summary.needsAttentionCount == 0,
      trailing: summary.needsAttentionCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text('${summary.needsAttentionCount} to review',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning, fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: AppConstants.space12),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(AppConstants.radius),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        bar(160, 26),
        bar(double.infinity, 90),
        const SizedBox(height: AppConstants.space16),
        bar(double.infinity, 140),
      ],
    );
  }
}
