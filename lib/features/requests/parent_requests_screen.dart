import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/teacher_request.dart';
import '../../core/models/teacher_request_view.dart';
import '../../core/models/payment_reminder.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/services/teacher_request_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// Parent-facing screen showing all of their teacher requests.
///
/// Child identity (name, Form, subjects) comes from the safe snapshot carried
/// on each request; the requested teacher's name is resolved from teacher
/// profiles. Both are joined into a [TeacherRequestView] for display.
class ParentRequestsScreen extends StatefulWidget {
  const ParentRequestsScreen({super.key});

  @override
  State<ParentRequestsScreen> createState() => _ParentRequestsScreenState();
}

class _ParentRequestsScreenState extends State<ParentRequestsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<TeacherRequestView> _views = const [];
  List<PaymentReminder> _reminders = const [];

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
    final teacherService = TeacherProfileServiceScope.of(context);
    final paymentService = PaymentServiceScope.of(context);

    final results = await Future.wait([
      requestService.fetchMyRequestsAsParent(),
      teacherService.fetchTeachers(),
      paymentService.fetchReminders(),
    ]);
    if (!mounted) return;

    final requestResult = results[0] as TeacherRequestResult;
    final teacherResult = results[1] as TeacherProfileResult;
    final remindersResult = results[2] as PaymentResult;

    if (requestResult case TeacherRequestFailure(:final message)) {
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
      return;
    }

    final requests = requestResult is TeacherRequestListSuccess
        ? requestResult.requests
        : <TeacherRequest>[];

    final teacherNames = <String, String>{};
    if (teacherResult case TeacherProfileListSuccess(:final profiles)) {
      for (final t in profiles) {
        teacherNames[t.userId] = t.fullNameWithTitle;
      }
    }

    List<PaymentReminder> reminders = const [];
    if (remindersResult is ReminderListSuccess) {
      reminders = remindersResult.reminders;
    }

    setState(() {
      _views = [
        for (final r in requests)
          TeacherRequestView(
            request: r,
            teacherName: teacherNames[r.teacherId],
          ),
      ];
      _reminders = reminders;
      _isLoading = false;
    });

    // Update global badge notification counts in AppState
    final unreadUpdates = reminders.where((r) => r.isUnread).length;
    final pendingRequests = requests.where((r) => r.status == TeacherRequestStatus.pending).length;
    AppState.of(context).setNotificationCounts(
      unreadUpdates: unreadUpdates,
      pendingRequests: pendingRequests,
    );
  }

  Future<void> _cancel(TeacherRequestView view) async {
    final result =
        await TeacherRequestServiceScope.of(context).cancelRequest(view.id);
    if (!mounted) return;
    if (result case TeacherRequestFailure(:final message)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else {
      _load();
    }
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navRequests)),
      body: SafeArea(child: _buildBody(l10n)),
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

    Widget cardFor(TeacherRequestView view) => Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.space12),
          child: _RequestCard(
            view: view,
            onCancel: view.status == TeacherRequestStatus.pending
                ? () => _cancel(view)
                : null,
          ),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
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
            SectionHeader(title: l10n.requestsPendingSection),
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.view, this.onCancel});

  final TeacherRequestView view;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final teacherName = view.teacherName ?? '—';

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Teacher Avatar + Name + Status & Date
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(name: teacherName, size: 52, kind: AvatarKind.teacher),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherName,
                        style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.grey900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.requestForChild(view.childName),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.grey500,
                          fontSize: 13,
                        ),
                      ),
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
                  _SubjectPill(
                    label: s,
                    icon: Icons.bookmark_border_outlined,
                    bg: const Color(0xFFF1F5F9),
                    fg: AppColors.grey700,
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // Details Row + Mini Map Preview
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
                const _MiniMapWidget(),
              ],
            ),

            // Bottom Actions: Connection badge or Cancel button
            if (view.status == TeacherRequestStatus.accepted) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const PhosphorIcon(PhosphorIcons.checkCircleFill, color: AppColors.success, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    l10n.connectedBadge,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],

            if (onCancel != null) ...[
              const SizedBox(height: 16),
              AppButton(
                key: Key('cancel_request_${view.id}'),
                label: l10n.requestCancelButton,
                variant: AppButtonVariant.outlined,
                isFullWidth: true,
                onPressed: onCancel,
              ),
            ],
          ],
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: AppColors.grey900,
                ),
              ),
              const SizedBox(height: 1.5),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.grey500,
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
  const _MiniMapWidget();

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
              painter: const _MiniMapPainter(),
              child: Stack(
              children: [
                Positioned(
                  right: 14,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4.5),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
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
                      color: AppColors.primary,
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

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter();
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
      ..color = AppColors.primary
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final TeacherRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      TeacherRequestStatus.pending => (
          'Pending',
          AppColors.warningLight,
          AppColors.warning,
        ),
      TeacherRequestStatus.accepted => (
          'Accepted',
          AppColors.successLight,
          AppColors.success,
        ),
      TeacherRequestStatus.declined => (
          'Declined',
          AppColors.errorLight,
          AppColors.error,
        ),
      TeacherRequestStatus.cancelled => (
          'Cancelled',
          AppColors.grey100,
          AppColors.grey500,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space8,
        vertical: AppConstants.space4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(label,
          style: AppTextStyles.bodySmall
              .copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
