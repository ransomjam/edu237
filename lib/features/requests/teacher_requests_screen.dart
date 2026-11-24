import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/tutoring_service.dart';
import '../tutoring/setup_tutoring_screen.dart';
import '../tutoring/teacher_agreement_screen.dart';
import '../tutoring/teacher_terms_sheet.dart';
import '../../core/models/service_plan.dart';
import '../../core/utils/money.dart';
import '../../core/models/teacher_request.dart';
import '../../core/models/teacher_request_view.dart';
import '../../core/models/payment_reminder.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/services/teacher_request_service.dart';
import '../../core/state/app_state.dart';
import '../../core/state/refresh_bus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// Teacher-facing screen for incoming teaching requests.
class TeacherRequestsScreen extends StatefulWidget {
  const TeacherRequestsScreen({super.key});

  @override
  State<TeacherRequestsScreen> createState() => _TeacherRequestsScreenState();
}

class _TeacherRequestsScreenState extends State<TeacherRequestsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<TeacherRequestView> _views = const [];
  List<PaymentReminder> _reminders = const [];
  List<String> _mySubjects = const [];
  final Set<String> _actioning = {};

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

    final requestService = TeacherRequestServiceScope.of(context);
    final profileService = TeacherProfileServiceScope.of(context);
    final paymentService = PaymentServiceScope.of(context);

    // The teacher's own subjects are used to highlight matching subjects.
    final profileResult = await profileService.fetchMyProfile();
    if (!mounted) return;
    if (profileResult is TeacherProfileSuccess) {
      _mySubjects = profileResult.profile?.subjects ?? const [];
    }

    final results = await Future.wait([
      requestService.fetchIncomingRequestsAsTeacher(),
      paymentService.fetchReminders(),
    ]);
    if (!mounted) return;

    final requestResult = results[0] as TeacherRequestResult;
    final remindersResult = results[1] as PaymentResult;

    List<TeacherRequestView> views = const [];
    String? error;

    switch (requestResult) {
      case TeacherRequestListSuccess(:final requests):
        views = [
          for (final r in requests) TeacherRequestView(request: r),
        ];
      case TeacherRequestFailure(:final message):
        error = message;
      default:
        break;
    }

    List<PaymentReminder> reminders = const [];
    if (remindersResult is ReminderListSuccess) {
      reminders = remindersResult.reminders;
    }

    setState(() {
      _views = views;
      _reminders = reminders;
      _errorMessage = error;
      _isLoading = false;
    });

    // Update global badge notification counts in AppState
    final unreadUpdates = reminders.where((r) => r.isUnread).length;
    final pendingRequests = views.where((r) => r.status == TeacherRequestStatus.pending).length;
    AppState.of(context).setNotificationCounts(
      unreadUpdates: unreadUpdates,
      pendingRequests: pendingRequests,
    );
  }

  Future<void> _dismissUpdate(PaymentReminder reminder) async {
    await PaymentServiceScope.of(context).markReminderRead(reminder.id);
    if (!mounted) return;
    setState(() {
      _reminders = _reminders.where((r) => r.id != reminder.id).toList();
    });
    // Update global badge notification counts
    final unreadUpdates = _reminders.where((r) => r.isUnread).length;
    AppState.of(context).setNotificationCounts(unreadUpdates: unreadUpdates);
  }

  Future<void> _accept(TeacherRequestView view) async {
    // The commercial agreement is made here, before acceptance, and recorded.
    // Nothing is charged: the teacher earns from the tutoring first.
    final tutoring = TutoringServiceScope.maybeOf(context);
    String planAmount = '3,000 FCFA';
    if (tutoring != null) {
      final planResult = await tutoring.fetchServicePlan();
      if (!mounted) return;
      if (planResult case ServicePlanSuccess(:final plan) when plan.amount != null) {
        planAmount = formatMoney(plan.amount!, plan.currency);
      }

      final agreed = await showTeacherTermsSheet(
        context,
        childName: view.childName,
        planAmount: planAmount,
      );
      if (!mounted || agreed != true) return;

      await tutoring.acceptTerms(
        termsText: TeacherTerms.text(planAmount),
        requestId: view.id,
      );
      if (!mounted) return;
    }

    setState(() => _actioning.add(view.id));
    final result =
        await TeacherRequestServiceScope.of(context).acceptRequest(view.id);
    if (!mounted) return;
    _actioning.remove(view.id);
    if (result case TeacherRequestFailure(:final message)) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    RefreshBusScope.maybeOf(context)?.relationshipsChanged();

    // Accepting is the start of the flow, not the end of it:
    //   accept -> verify -> propose -> parent confirms -> Platform Charge
    // The teacher is walked straight into the next step that applies.
    if (result case TeacherRequestAcceptSuccess(:final relationship)) {
      await _continueActivation(relationship.id, view);
      if (!mounted) return;
    }

    _load();
  }

  /// Walks the teacher through whatever comes next for this relationship:
  /// verification, then the tutoring arrangement. No payment is involved at
  /// any point here.
  Future<void> _continueActivation(
    String relationshipId,
    TeacherRequestView view,
  ) async {
    final subject =
        view.childSubjects.isEmpty ? '' : view.childSubjects.first;

    // 1. Verification.
    final tutoring = TutoringServiceScope.maybeOf(context);
    if (tutoring != null) {
      final verification = await tutoring.fetchMyVerification();
      if (!mounted) return;
      if (verification case VerificationSuccess(:final verification)) {
        if (!verification.status.isVerified) {
          await context.push<bool>(AppRoutes.teacherVerification);
          if (!mounted) return;
          final recheck = await tutoring.fetchMyVerification();
          if (!mounted) return;
          final stillUnverified = recheck is VerificationSuccess &&
              !recheck.verification.status.isVerified;
          // Not verified yet: stop here rather than asking for terms or money.
          if (stillUnverified) return;
        }
      }

      // 2. The tutoring proposal, unless one already exists.
      final existing = await tutoring.fetchAgreement(relationshipId);
      if (!mounted) return;
      final hasAgreement =
          existing is AgreementSuccess && existing.agreement != null;
      if (!hasAgreement) {
        final ready = await _explainNextStep(view);
        if (!mounted || ready != true) return;
        await context.push<bool>(
          AppRoutes.setupTutoring,
          extra: SetupTutoringArgs(
            relationshipId: relationshipId,
            childName: view.childName,
            subject: subject,
          ),
        );
        if (!mounted) return;
      }
    }

    // There is no third step: Camiva does not charge to start a tutoring
    // relationship. The teacher teaches, earns, and the Teacher Service Plan
    // begins after their first month.
  }

  /// Sets expectations before the teacher fills in the tutoring form: these
  /// are terms to be agreed with the parent, not a form to guess at.
  Future<bool?> _explainNextStep(TeacherRequestView view) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('next_step_dialog'),
        title: const Text('Agree the details first'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next you will set out the tutoring arrangement for '
              '${view.childName}: when it starts, how often, how long, the '
              'price and how the parent pays.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppConstants.space12),
            const Text(
              'Talk these through with the parent so you both agree before '
              'they confirm. You can reopen the arrangement any time from '
              'this request.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          TextButton(
            key: const Key('next_step_continue'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Set up tutoring'),
          ),
        ],
      ),
    );
  }

  /// Reopens the arrangement for an accepted request, so the contract is never
  /// a one-way door.
  Future<void> _openArrangement(TeacherRequestView view) async {
    // The request does not carry the relationship it produced, so it is looked
    // up by the child it was about.
    final result = await ParentTeacherRelationshipServiceScope.of(context)
        .fetchMyRelationshipsAsTeacher();
    if (!mounted) return;
    if (result is! RelationshipListSuccess) return;

    final match = result.relationships.where(
      (r) =>
          r.studentId == view.request.studentId &&
          r.status == RelationshipStatus.accepted,
    );
    if (match.isEmpty) return;
    final relationshipId = match.first.id;
    await context.push<bool>(
      AppRoutes.teacherAgreement,
      extra: TeacherAgreementArgs(
        relationshipId: relationshipId,
        childName: view.childName,
        subject: view.childSubjects.isEmpty ? '' : view.childSubjects.first,
        parentName: view.parentLabel,
      ),
    );
    if (mounted) _load();
  }

  Future<void> _decline(TeacherRequestView view) async {
    setState(() => _actioning.add(view.id));
    final result =
        await TeacherRequestServiceScope.of(context).declineRequest(view.id);
    if (!mounted) return;
    _actioning.remove(view.id);
    if (result case TeacherRequestFailure(:final message)) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else {
      _load();
    }
  }

  void _showDetail(TeacherRequestView view) {
    final matchedSubjects = view.matchedSubjectsFor(_mySubjects);
    final isActioning = _actioning.contains(view.id);
    final actionable =
        view.status == TeacherRequestStatus.pending && !isActioning;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppAvatar(name: view.childName, size: 56, kind: AvatarKind.child),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.childName,
                          style: AppTextStyles.h1.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          view.parentLabel,
                          style: AppTextStyles.body.copyWith(color: AppColors.grey500),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: view.status),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text('Requested Subjects & Form', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (view.childForm.isNotEmpty)
                    _SubjectPill(
                      label: view.childForm,
                      icon: Icons.school_outlined,
                      bg: AppColors.iconContainerBg,
                      fg: AppColors.primary,
                    ),
                  for (final s in view.childSubjects)
                    _SubjectPillFor(
                        label: s, matched: matchedSubjects.map((e) => e.toLowerCase()).contains(s.toLowerCase())),
                ],
              ),
              const SizedBox(height: 20),
              Text('Location & Schedule', style: AppTextStyles.h3),
              const SizedBox(height: 12),
              _InfoDetailRow(
                icon: Icons.location_on_outlined,
                iconColor: AppColors.primary,
                title: 'Bastos, Yaoundé',
                subtitle: 'Near Santa Lucia • 1.8 km away',
              ),
              const SizedBox(height: 12),
              _InfoDetailRow(
                icon: Icons.access_time_outlined,
                iconColor: AppColors.primary,
                title: 'Mon – Sat',
                subtitle: 'After 4:00 PM',
              ),
              const SizedBox(height: 24),
              if (actionable) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _accept(view);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Accept Request',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _decline(view);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.grey700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Decline',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ] else if (view.status == TeacherRequestStatus.accepted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Request Accepted • Connected',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // The contract is not a one-way door: it can be reopened,
                // read back and copied at any time.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: Key('open_arrangement_${view.id}'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Tutoring arrangement'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openArrangement(view);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        );
      },
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
      return Center(child: Text(l10n.childrenLoading));
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

    final unreadReminders = _reminders.where((r) => r.isUnread).toList();

    if (_views.isEmpty && unreadReminders.isEmpty) {
      return const AppEmptyState(
        iconName: PhosphorIcons.bell,
        title: 'No updates yet',
        message: 'You are all caught up!',
      );
    }

    final pending = _views
        .where((v) => v.status == TeacherRequestStatus.pending)
        .toList();
    final connected = _views
        .where((v) => v.status == TeacherRequestStatus.accepted)
        .toList();
    final earlier = _views
        .where((v) =>
            v.status == TeacherRequestStatus.declined ||
            v.status == TeacherRequestStatus.cancelled)
        .toList();

    Widget cardFor(TeacherRequestView view) {
      final isActioning = _actioning.contains(view.id);
      return Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.space16),
        child: _IncomingRequestCard(
          view: view,
          matchedSubjects: view.matchedSubjectsFor(_mySubjects),
          isActioning: isActioning,
          onViewDetails: () => _showDetail(view),
          onAccept: () => _accept(view),
          onDecline: () => _decline(view),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Blue Header Banner matching mockup
          _HeaderBanner(
            totalCount: _views.length + unreadReminders.length,
            pendingCount: pending.length,
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unreadReminders.isNotEmpty) ...[
                  const SectionHeader(title: 'Updates'),
                  for (final reminder in unreadReminders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppConstants.space8),
                      child: _ReminderTile(
                        reminder: reminder,
                        onTap: () => _showReminderDetails(context, reminder, () => _dismissUpdate(reminder)),
                        onDismiss: () => _dismissUpdate(reminder),
                      ),
                    ),
                  const SizedBox(height: AppConstants.space16),
                ],
                if (pending.isNotEmpty) ...[
                  const SectionHeader(title: 'Pending Requests'),
                  ...pending.map(cardFor),
                  const SizedBox(height: AppConstants.space12),
                ],
                if (connected.isNotEmpty) ...[
                  SectionHeader(title: l10n.requestsConnectedSection),
                  ...connected.map(cardFor),
                  const SizedBox(height: AppConstants.space12),
                ],
                if (earlier.isNotEmpty) ...[
                  SectionHeader(title: l10n.requestsHistorySection),
                  ...earlier.map(cardFor),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onTap,
    required this.onDismiss,
  });

  final PaymentReminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (reminder.kind) {
      ReminderKind.paymentReceived => (Icons.check_circle, AppColors.success),
      ReminderKind.relationshipActivated =>
        (Icons.handshake_outlined, AppColors.success),
      ReminderKind.paymentFailed => (Icons.error_outline, AppColors.error),
      ReminderKind.serviceFeeOverdue =>
        (Icons.warning_amber_rounded, AppColors.error),
      ReminderKind.serviceFeeDue => (Icons.event_note, AppColors.warning),
      ReminderKind.withdrawalUpdate =>
        (Icons.account_balance_wallet_outlined, AppColors.primary),
      ReminderKind.paymentDue => (Icons.event_note, AppColors.warning),
      ReminderKind.agreementUpdate =>
        (Icons.description_outlined, AppColors.primary),
      ReminderKind.verificationUpdate =>
        (Icons.verified_outlined, AppColors.primary),
      ReminderKind.requestReceived =>
        (Icons.person_add_alt_1_outlined, AppColors.primary),
      ReminderKind.requestAnswered =>
        (Icons.mark_email_read_outlined, AppColors.primary),
      ReminderKind.lessonScheduled =>
        (Icons.event_available_outlined, AppColors.primary),
      ReminderKind.other => (Icons.notifications_none, AppColors.grey700),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.title, style: AppTextStyles.h3),
                  const SizedBox(height: AppConstants.space2),
                  Text(reminder.body,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.grey700)),
                ],
              ),
            ),
            IconButton(
              key: Key('dismiss_reminder_${reminder.id}'),
              icon: const PhosphorIcon(PhosphorIcons.x, size: 18, color: AppColors.grey500),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}

void _showReminderDetails(BuildContext context, PaymentReminder reminder, VoidCallback onDismiss) {
  onDismiss();

  showDialog<void>(
    context: context,
    builder: (context) {
      final (icon, color) = switch (reminder.kind) {
        ReminderKind.paymentReceived => (Icons.check_circle, AppColors.success),
        ReminderKind.relationshipActivated =>
          (Icons.handshake_outlined, AppColors.success),
        ReminderKind.paymentFailed => (Icons.error_outline, AppColors.error),
        ReminderKind.serviceFeeOverdue =>
          (Icons.warning_amber_rounded, AppColors.error),
        ReminderKind.serviceFeeDue => (Icons.event_note, AppColors.warning),
        ReminderKind.withdrawalUpdate =>
          (Icons.account_balance_wallet_outlined, AppColors.primary),
        ReminderKind.paymentDue => (Icons.event_note, AppColors.warning),
        ReminderKind.agreementUpdate =>
          (Icons.description_outlined, AppColors.primary),
        ReminderKind.verificationUpdate =>
          (Icons.verified_outlined, AppColors.primary),
        ReminderKind.requestReceived =>
          (Icons.person_add_alt_1_outlined, AppColors.primary),
        ReminderKind.requestAnswered =>
          (Icons.mark_email_read_outlined, AppColors.primary),
        ReminderKind.lessonScheduled =>
          (Icons.event_available_outlined, AppColors.primary),
        ReminderKind.other => (Icons.notifications_none, AppColors.grey700),
      };

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Notification Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.grey500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                reminder.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.grey900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reminder.body,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: AppColors.grey700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.totalCount,
    required this.pendingCount,
  });

  final int totalCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryAzure, AppColors.primaryCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button row
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: PhosphorIcon(PhosphorIcons.arrowLeft, color: Colors.white, size: 20),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Updates',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all ($totalCount)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const PhosphorIcon(PhosphorIcons.caretRight, color: Colors.white, size: 14),
                    ],
                  ),
                ),
            ],
          ),
          if (pendingCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'NEEDS YOUR RESPONSE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.view,
    required this.matchedSubjects,
    required this.isActioning,
    required this.onViewDetails,
    required this.onAccept,
    required this.onDecline,
  });

  final TeacherRequestView view;
  final List<String> matchedSubjects;
  final bool isActioning;
  final VoidCallback onViewDetails;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final matchedSet = matchedSubjects.map((e) => e.toLowerCase()).toSet();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onViewDetails,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar + Name/Parent + Status & Date
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(name: view.childName, size: 52, kind: AvatarKind.child),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.hasChildContext
                                ? view.childName
                                : l10n.requestChildUnavailable,
                            style: AppTextStyles.h2.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.grey900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.requestParentOf(view.childName),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.grey500,
                              fontSize: 13,
                            ),
                          ),
                          if (view.status == TeacherRequestStatus.pending) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.iconContainerBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  PhosphorIcon(PhosphorIcons.sparkle, size: 12, color: AppColors.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'New request',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusChip(status: view.status),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PhosphorIcon(PhosphorIcons.calendarBlank, size: 13, color: AppColors.grey500),
                            const SizedBox(width: 4),
                            Text(
                              'Requested ${formatShortDate(view.createdAt)}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.grey500,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 14),

                // Subject & Form Chips Row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (view.childForm.isNotEmpty)
                      _SubjectPill(
                        label: view.childForm,
                        icon: Icons.school_outlined,
                        bg: AppColors.iconContainerBg,
                        fg: AppColors.primary,
                      ),
                    for (final s in view.childSubjects)
                      _SubjectPillFor(
                          label: s, matched: matchedSet.contains(s.toLowerCase())),
                  ],
                ),

                const SizedBox(height: 14),

                // Details Grid + Mini Map Preview
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _InfoDetailRow(
                            icon: Icons.location_on_outlined,
                            iconColor: AppColors.primary,
                            title: 'Bastos, Yaoundé',
                            subtitle: 'Near Santa Lucia',
                          ),
                          SizedBox(height: 14),
                          _InfoDetailRow(
                            icon: Icons.access_time_outlined,
                            iconColor: AppColors.primary,
                            title: 'Mon – Sat',
                            subtitle: 'After 4:00 PM',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _MiniMapWidget(distanceLabel: '1.8 km away'),
                  ],
                ),

                const SizedBox(height: 16),

                // Bottom Action Bar: Matches Profile Container + View Request Button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFDCFCE7)),
                            ),
                            child: Row(
                              children: [
                                const PhosphorIcon(PhosphorIcons.checkCircleFill, size: 18, color: Color(0xFF16A34A)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    matchedSubjects.isNotEmpty
                                        ? l10n.requestMatchesYourSubjects
                                        : 'Matches your teaching profile',
                                    style: const TextStyle(
                                      color: Color(0xFF166534),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (view.status != TeacherRequestStatus.pending) ...[
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: onViewDetails,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'View Request',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  PhosphorIcon(PhosphorIcons.caretRight, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (view.status == TeacherRequestStatus.pending) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onDecline,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.grey700,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Decline',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              key: Key('accept_request_${view.id}'),
                              onPressed: onAccept,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Accept',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipVisual {
  const _ChipVisual(this.bg, this.fg, this.icon);
  final Color bg;
  final Color fg;
  final IconData icon;

  static _ChipVisual forSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('chem') || s.contains('bio') || s.contains('sci')) {
      return const _ChipVisual(Color(0xFFECFDF5), Color(0xFF059669), Icons.science_outlined);
    }
    if (s.contains('math') || s.contains('phys') || s.contains('acc')) {
      return const _ChipVisual(Color(0xFFF3E8FF), Color(0xFF7C3AED), Icons.calculate_outlined);
    }
    if (s.contains('form') || s.contains('class') || s.contains('level')) {
      return const _ChipVisual(Color(0xFFEFF6FF), AppColors.primary, Icons.school_outlined);
    }
    return const _ChipVisual(Color(0xFFEFF6FF), AppColors.primary, Icons.menu_book_outlined);
  }
}

class _SubjectPill extends StatelessWidget {
  const _SubjectPill({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectPillFor extends StatelessWidget {
  const _SubjectPillFor({required this.label, required this.matched});
  final String label;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final v = _ChipVisual.forSubject(label);
    final bg = matched ? v.bg : AppColors.grey100;
    final fg = matched ? v.fg : AppColors.grey700;
    return _SubjectPill(label: label, icon: v.icon, bg: bg, fg: fg);
  }
}

class _InfoDetailRow extends StatelessWidget {
  const _InfoDetailRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.grey900,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.grey500,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniMapWidget extends StatelessWidget {
  const _MiniMapWidget({this.distanceLabel = '1.8 km away'});

  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      height: 115,
      child: Stack(
        children: [
          // Fading Gradient Map Canvas (No borders)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    colors: [Colors.transparent, Colors.black, Colors.black],
                    stops: [0.0, 0.25, 1.0],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: Container(
                  color: const Color(0xFFE0F2FE),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: const _MiniMapPainter(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Destination Pin
          Positioned(
            right: 18,
            top: 14,
            child: Container(
              padding: const EdgeInsets.all(5.5),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x331D4ED8),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.home_rounded,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
          // Start Location Dot
          Positioned(
            left: 14,
            bottom: 16,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          // Distance Badge on the Map itself
          Positioned(
            left: 6,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PhosphorIcon(PhosphorIcons.navigationArrow, size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        distanceLabel,
                        style: const TextStyle(
                          color: AppColors.grey900,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'from your location',
                        style: TextStyle(
                          color: AppColors.grey500,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    // Green park block
    final parkPaint = Paint()..color = const Color(0xFFDCFCE7);
    canvas.drawRRect(
      RRect.fromLTRBR(
        size.width * 0.55,
        size.height * 0.45,
        size.width * 0.85,
        size.height * 0.75,
        const Radius.circular(6),
      ),
      parkPaint,
    );

    // Road Grid lines
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final path1 = Path()
      ..moveTo(0, size.height * 0.3)
      ..lineTo(size.width, size.height * 0.7);
    canvas.drawPath(path1, roadPaint);

    final path2 = Path()
      ..moveTo(size.width * 0.4, 0)
      ..lineTo(size.width * 0.2, size.height);
    canvas.drawPath(path2, roadPaint);

    final path3 = Path()
      ..moveTo(size.width * 0.75, 0)
      ..lineTo(size.width * 0.55, size.height);
    canvas.drawPath(path3, roadPaint);

    // Dashed Route Line
    final routePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final routePath = Path()
      ..moveTo(25, size.height - 25)
      ..cubicTo(
        size.width * 0.4,
        size.height * 0.5,
        size.width * 0.5,
        size.height * 0.6,
        size.width - 25,
        20,
      );

    final metrics = routePath.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extract = metric.extractPath(distance, distance + 4);
        canvas.drawPath(extract, routePaint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final TeacherRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, bg, fg) = switch (status) {
      TeacherRequestStatus.pending => (
          'Pending',
          Icons.access_time_rounded,
          AppColors.iconContainerBg,
          AppColors.primary,
        ),
      TeacherRequestStatus.accepted => (
          'Accepted',
          Icons.check_circle_rounded,
          AppColors.successLight,
          AppColors.success,
        ),
      TeacherRequestStatus.declined => (
          'Declined',
          Icons.cancel_rounded,
          AppColors.errorLight,
          AppColors.error,
        ),
      TeacherRequestStatus.cancelled => (
          'Cancelled',
          Icons.remove_circle_outline_rounded,
          AppColors.grey100,
          AppColors.grey500,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
