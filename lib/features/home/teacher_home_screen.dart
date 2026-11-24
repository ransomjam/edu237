import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/lesson_session.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teacher_request.dart';
import '../../core/routing/app_router.dart';
import '../payments/payment_reminders_card.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/services/teacher_request_service.dart';
import '../../core/state/app_state.dart';
import '../../core/state/refresh_bus.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/phosphor_icon.dart';
import '../../shared/widgets/geometric_header.dart';
import '../../shared/widgets/edu_ui.dart';
import '../schedule/lesson_followup.dart';
import '../schedule/schedule_format.dart';

// ─── Design Tokens ──────────────────────────────────────────────────────────
const _kBlue = AppColors.primary; // Exact vibrant royal blue
const _kBlueLight = AppColors.iconContainerBg; // Soft blue/cyan icon background
const _kBluePill = AppColors.primaryLight; // Soft ice blue pill
const _kTextDark = AppColors.grey900; // Slate 900
const _kTextSoft = AppColors.grey500; // Slate 500
const _kTextMuted = Color(0xFF94A3B8); // Slate 400
const _kBorder = AppColors.border; // Light card border
const _kDivider = AppColors.divider; // Card inner divider
const _kBackground = AppColors.background; // Page background

/// Teacher Home — pixel-perfect matching of the design mockups for both
/// populated and empty states.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  TeacherProfile? _profile;
  int _requestCount = 0;
  List<Student> _studentPreview = const [];
  Map<String, Student> _studentById = const {};
  List<LessonSession> _sessions = const [];
  RefreshBus? _bus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bus = RefreshBusScope.maybeOf(context);
    if (bus != _bus) {
      _bus?.removeListener(_onBusChanged);
      _bus = bus;
      _bus?.addListener(_onBusChanged);
    }
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  void _onBusChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    _bus?.removeListener(_onBusChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      TeacherProfileServiceScope.of(context).fetchMyProfile(),
      ParentTeacherRelationshipServiceScope.of(context)
          .fetchMyRelationshipsAsTeacher(),
      TeacherRequestServiceScope.of(context).fetchIncomingRequestsAsTeacher(),
      LessonSessionServiceScope.of(context).fetchMyTeacherSessions(),
    ]);
    if (!mounted) return;

    final profileResult = results[0] as TeacherProfileResult;
    final relResult = results[1] as RelationshipResult;
    final reqResult = results[2] as TeacherRequestResult;
    final sessionResult = results[3] as LessonSessionResult;

    if (profileResult is TeacherProfileFailure) {
      setState(() {
        _errorMessage = profileResult.message;
        _isLoading = false;
      });
      return;
    }
    if (profileResult is TeacherProfileSuccess) {
      _profile = profileResult.profile;
    }

    if (sessionResult is LessonSessionListSuccess) {
      _sessions = sessionResult.sessions;
    }

    final acceptedIds = <String>[];
    if (relResult is RelationshipListSuccess) {
      for (final r in relResult.relationships) {
        if (r.status == RelationshipStatus.accepted) {
          acceptedIds.add(r.studentId);
        }
      }
    }
    if (reqResult is TeacherRequestListSuccess) {
      _requestCount = reqResult.requests
          .where((r) => r.status == TeacherRequestStatus.pending)
          .length;
    }

    if (acceptedIds.isNotEmpty) {
      final sr = await StudentServiceScope.of(context)
          .fetchStudentsByIds(acceptedIds.toSet().toList());
      if (!mounted) return;
      if (sr is StudentListSuccess) {
        final all = sr.students;
        _studentById = {for (final s in all) s.id: s};
        _studentPreview = all.take(3).toList();
      }
    } else {
      _studentPreview = const [];
      _studentById = const {};
    }

    setState(() => _isLoading = false);
  }

  Future<void> _editProfile() async {
    final updated = await context
        .push<TeacherProfile>(AppRoutes.teacherProfileEdit, extra: _profile);
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    } else if (mounted) {
      _load();
    }
  }

  Future<void> _followUp(LessonSession s) async {
    final updated = await showLessonFollowUpSheet(context, s);
    if (updated != null && mounted) _load();
  }

  String get _displayName {
    final pn = _profile?.displayName.trim();
    if (pn != null && pn.isNotEmpty) return pn;
    return AppState.of(context).currentUser?.name ?? '';
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _profile == null) {
      return SafeArea(
        child: AppEmptyState(
          iconName: PhosphorIcons.warningCircle,
          title: 'Connection error',
          message: 'Could not load your dashboard. Pull down to retry.',
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }

    if (_profile == null) {
      return SafeArea(
        child: AppEmptyState(
          iconName: PhosphorIcons.shieldCheck,
          title: 'Set up your profile',
          message: 'Create your teacher profile to start accepting students.',
          actionLabel: 'Create profile',
          onAction: _editProfile,
        ),
      );
    }

    final now = DateTime.now();
    final todaySessions = _sessions
        .where((s) =>
            s.status.isScheduled &&
            bucketFor(s.localStart, now) == ScheduleBucket.today)
        .toList()
      ..sort((a, b) => a.localStart.compareTo(b.localStart));

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Header + Primary Actions Stack ──────────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Blue Header Background
                _TeacherHeader(
                  name: _displayName,
                  photoUrl: _profile?.photoUrl,
                  badgeCount: AppState.of(context).totalNotificationCount,
                  onAvatarTap: () => context.go(AppRoutes.profile),
                  onBellTap: () => context.go(AppRoutes.teacherRequests),
                ),

                // 2. Primary Actions Bar (overlapping the bottom of the header)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: -38,
                  child: _PrimaryActionsBar(
                    requestCount: _requestCount,
                    onScheduleTap: () =>
                        context.push(AppRoutes.teacherSchedule),
                    onRequestsTap: () =>
                        context.go(AppRoutes.teacherRequests),
                  ),
                ),
              ],
            ),
          ),

          // Space for the half-overlapped primary actions bar
          const SliverToBoxAdapter(
            child: SizedBox(height: 54),
          ),

          // ── Sections: TODAY, MY STUDENTS ────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Camiva reminders: payments received, service plan, agreement
                // and verification updates. Creating one IS the delivery, so
                // this is where it has to be visible.
                const PaymentRemindersCard(),

                // TODAY
                _HomeSection(
                  label: 'TODAY',
                  trailing: _SeeAllLink(
                    onTap: () => context.push(AppRoutes.teacherSchedule),
                  ),
                  child: _TodayCard(
                    sessions: todaySessions,
                    studentById: _studentById,
                    now: now,
                    onSessionTap: (s) =>
                        s.hasEnded(now) ? () => _followUp(s) : null,
                    onViewSchedule: () =>
                        context.push(AppRoutes.teacherSchedule),
                  ),
                ),

                const SizedBox(height: 24),

                // MY STUDENTS
                _HomeSection(
                  label: 'MY STUDENTS',
                  trailing: _SeeAllLink(
                    onTap: () => context.push(AppRoutes.myStudents),
                  ),
                  child: _studentPreview.isEmpty
                      ? const _StudentsEmptyCard()
                      : _StudentsCard(
                          students: _studentPreview,
                          onStudentTap: (s) => context.push(
                            AppRoutes.scheduleLesson,
                            extra: s,
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. BLUE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherHeader extends StatelessWidget {
  const _TeacherHeader({
    required this.name,
    required this.photoUrl,
    required this.badgeCount,
    required this.onAvatarTap,
    required this.onBellTap,
  });

  final String name;
  final String? photoUrl;
  final int badgeCount;
  final VoidCallback onAvatarTap;
  final VoidCallback onBellTap;

  static String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final greeting = _greeting(DateTime.now().hour);
    final displayName = name.trim().isEmpty ? 'Welcome' : name;

    return GeometricHeader(
      padding: EdgeInsets.fromLTRB(
        16,
        topPadding + 14,
        16,
        64, // generous bottom padding to seat the overlapping cards below subtitle
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Greeting, Name, Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your teaching workspace',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right: Notification Bell & Circular Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Bell with badge
              GestureDetector(
                onTap: onBellTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: PhosphorIcon(
                          PhosphorIcons.bell,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Center(
                            child: Text(
                              '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Circular Teacher Avatar
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: (photoUrl ?? '').isNotEmpty
                          ? Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => AppAvatar(
                                name: name.trim().isEmpty ? '?' : name,
                                size: 52,
                                kind: AvatarKind.teacher,
                              ),
                            )
                          : AppAvatar(
                              name: name.trim().isEmpty ? '?' : name,
                              size: 52,
                              kind: AvatarKind.teacher,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. PRIMARY ACTIONS BAR (Schedule | View requests)
// ─────────────────────────────────────────────────────────────────────────────

class _PrimaryActionsBar extends StatelessWidget {
  const _PrimaryActionsBar({
    required this.requestCount,
    required this.onScheduleTap,
    required this.onRequestsTap,
  });

  final int requestCount;
  final VoidCallback onScheduleTap;
  final VoidCallback onRequestsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PrimaryCard(
            iconName: PhosphorIcons.calendarBlank,
            title: 'Schedule',
            subtitle: 'Plan your\ntutoring sessions',
            badgeCount: 0,
            onTap: onScheduleTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrimaryCard(
            iconName: PhosphorIcons.listBullets,
            title: 'View requests',
            subtitle: 'See teaching\nrequests',
            badgeCount: requestCount,
            onTap: onRequestsTap,
          ),
        ),
      ],
    );
  }
}

class _PrimaryCard extends StatelessWidget {
  const _PrimaryCard({
    required this.iconName,
    required this.title,
    required this.subtitle,
    required this.badgeCount,
    required this.onTap,
  });

  final String iconName;
  final String title;
  final String subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              // Icon Box
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kBlueLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: PhosphorIcon(iconName, color: _kBlue, size: 22)),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: _kBlue,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 10),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kTextSoft,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              const PhosphorIcon(
                PhosphorIcons.caretRight,
                size: 18,
                color: _kTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Wrapper Header
// ─────────────────────────────────────────────────────────────────────────────

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _kTextSoft,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'See all',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kBlue,
            ),
          ),
          SizedBox(width: 2),
          PhosphorIcon(PhosphorIcons.caretRight, size: 14, color: _kBlue),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TODAY CARD (Populated & Empty)
// ─────────────────────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.sessions,
    required this.studentById,
    required this.now,
    required this.onSessionTap,
    required this.onViewSchedule,
  });

  final List<LessonSession> sessions;
  final Map<String, Student> studentById;
  final DateTime now;
  final VoidCallback? Function(LessonSession) onSessionTap;
  final VoidCallback onViewSchedule;

  @override
  Widget build(BuildContext context) {
    // ── Empty State ──────────────────────────────────────────────────────
    if (sessions.isEmpty) {
      return _surfaceCard(
        child: InkWell(
          onTap: onViewSchedule,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: _kBlueLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: PhosphorIcon(
                      PhosphorIcons.calendarBlank,
                      color: _kBlue,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No classes today',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Tap to view your full schedule.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _kTextSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _kTextMuted,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Populated State ──────────────────────────────────────────────────
    return _surfaceCard(
      child: Column(
        children: [
          // Top Summary Banner
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kBlueLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: PhosphorIcon(
                      PhosphorIcons.calendarBlank,
                      color: _kBlue,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sessions.length} '
                        '${sessions.length == 1 ? 'class' : 'classes'} today',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Here's your schedule for today.",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _kTextSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: _kDivider),

          // Session Rows
          ...sessions.asMap().entries.map((e) {
            final idx = e.key;
            final s = e.value;
            return Column(
              children: [
                _SessionRow(
                  session: s,
                  student: studentById[s.studentId],
                  now: now,
                  onTap: onSessionTap(s),
                ),
                if (idx < sessions.length - 1)
                  const Divider(height: 1, color: _kDivider),
              ],
            );
          }),

          const Divider(height: 1, color: _kDivider),

          // Bottom View Full Schedule Link
          InkWell(
            onTap: onViewSchedule,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View full schedule',
                    style: TextStyle(
                      color: _kBlue,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  PhosphorIcon(PhosphorIcons.arrowRight, size: 15, color: _kBlue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.student,
    required this.now,
    this.onTap,
  });

  final LessonSession session;
  final Student? student;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final timeText = clockLabel(session.localStart);
    final levelLabel = student?.qualifiedLevelLabel ?? student?.schoolLevel;
    final meta = [
      session.subject,
      if (levelLabel != null && levelLabel.isNotEmpty) levelLabel,
    ].join('  •  ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Blue vertical bar indicator
            Container(
              width: 3.5,
              height: 28,
              decoration: BoxDecoration(
                color: _kBlue,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            const SizedBox(width: 10),

            // Time
            SizedBox(
              width: 64,
              child: Text(
                timeText,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _kBlue,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Name + Subject • Form
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.childName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // "Upcoming" chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kBluePill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Upcoming',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kBlue,
                ),
              ),
            ),

            const SizedBox(width: 6),
            const PhosphorIcon(PhosphorIcons.caretRight,
                size: 18, color: _kTextMuted),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY STUDENTS CARD (Populated & Empty)
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsCard extends StatelessWidget {
  const _StudentsCard({
    required this.students,
    required this.onStudentTap,
  });

  final List<Student> students;
  final void Function(Student) onStudentTap;

  @override
  Widget build(BuildContext context) {
    return _surfaceCard(
      child: Column(
        children: [
          ...students.asMap().entries.map((e) {
            final idx = e.key;
            final s = e.value;
            return Column(
              children: [
                _StudentRow(
                  student: s,
                  onTap: () => onStudentTap(s),
                ),
                if (idx < students.length - 1)
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: _kDivider,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.onTap});

  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final levelLabel =
        student.qualifiedLevelLabel ?? student.schoolLevel ?? '';
    final subjects = student.subjects.take(2).join('  •  ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Name + Form/Class
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (levelLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      levelLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Subjects (Right-aligned clean text)
            if (subjects.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  subjects,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _kTextSoft,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(width: 6),
            const PhosphorIcon(PhosphorIcons.caretRight,
                size: 18, color: _kTextMuted),
          ],
        ),
      ),
    );
  }
}

class _StudentsEmptyCard extends StatelessWidget {
  const _StudentsEmptyCard();

  @override
  Widget build(BuildContext context) {
    return _surfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: _kBlueLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: PhosphorIcon(
                  PhosphorIcons.users,
                  color: _kBlue,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No students yet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTextDark,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Students you connect with will appear here.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _kTextSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Surface Card Helper
// ─────────────────────────────────────────────────────────────────────────────

Widget _surfaceCard({required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _kBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}
