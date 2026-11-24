import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_availability.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teacher_request.dart';
import '../../core/models/teaching_mode.dart';
import '../../core/services/teacher_availability_service.dart';
import '../../core/services/teacher_request_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// Arguments for viewing a teacher from discovery.
///
/// [student] is the child on behalf of whom the parent is looking for a
/// teacher. It is required so the request button can create a real request.
class TeacherProfileArgs {
  const TeacherProfileArgs({required this.teacher, required this.student});
  final TeacherProfile teacher;
  final Student student;

  /// Convenience getter — avoids touching every call site that only needs the
  /// child's name for display.
  String get childName => student.name;
}

/// A teacher's profile as seen by a parent during discovery.
///
/// Loads the current request state on startup and surfaces the correct action:
///   * No active request  → "Request to teach {child}" (primary action)
///   * Pending request    → "Request pending" (disabled) + Cancel option
///   * Accepted request   → "Teacher connected" (disabled, success colour)
///   * Declined/cancelled → "Request to teach {child}" (re-request allowed)
class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({
    super.key,
    required this.teacher,
    required this.student,
  });

  final TeacherProfile teacher;
  final Student student;

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  bool _isActioning = false;
  TeacherRequest? _activeRequest;
  WeeklyAvailability _availability = WeeklyAvailability.empty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadRequestState();
      _loadAvailability();
    }
  }

  Future<void> _loadAvailability() async {
    final result = await TeacherAvailabilityServiceScope.of(context)
        .fetchAvailabilityFor(widget.teacher.userId);
    if (!mounted) return;
    if (result is AvailabilitySuccess) {
      setState(() => _availability = result.availability);
    }
  }

  Future<void> _loadRequestState() async {
    setState(() => _isLoading = true);
    final service = TeacherRequestServiceScope.of(context);
    final hasActive = await service.hasActiveRequest(
      studentId: widget.student.id,
      teacherId: widget.teacher.userId,
    );
    if (!mounted) return;

    if (!hasActive) {
      setState(() {
        _activeRequest = null;
        _isLoading = false;
      });
      return;
    }

    // Fetch the parent's own requests to find this specific one.
    final result = await service.fetchMyRequestsAsParent();
    if (!mounted) return;
    if (result case TeacherRequestListSuccess(:final requests)) {
      final match = requests.where((r) =>
          r.studentId == widget.student.id &&
          r.teacherId == widget.teacher.userId &&
          r.status.isActive).firstOrNull;
      setState(() {
        _activeRequest = match;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _isActioning = true);
    final l10n = AppLocalizations.of(context);
    final result = await TeacherRequestServiceScope.of(context).createRequest(
      studentId: widget.student.id,
      teacherId: widget.teacher.userId,
    );
    if (!mounted) return;
    switch (result) {
      case TeacherRequestSuccess(:final request):
        setState(() {
          _activeRequest = request;
          _isActioning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.requestSent)),
        );
      case TeacherRequestFailure(:final message):
        setState(() => _isActioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        setState(() => _isActioning = false);
    }
  }

  Future<void> _cancelRequest() async {
    final request = _activeRequest;
    if (request == null) return;
    setState(() => _isActioning = true);
    final result = await TeacherRequestServiceScope.of(context)
        .cancelRequest(request.id);
    if (!mounted) return;
    switch (result) {
      case TeacherRequestSuccess():
        setState(() {
          _activeRequest = null;
          _isActioning = false;
        });
      case TeacherRequestFailure(:final message):
        setState(() => _isActioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        setState(() => _isActioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.teacher.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _TeacherProfileBody(
                teacher: widget.teacher,
                student: widget.student,
                availability: _availability,
                isActioning: _isActioning,
                onRequest: _sendRequest,
              ),
            ),
            _RequestFooter(
              l10n: l10n,
              isLoading: _isLoading,
              isActioning: _isActioning,
              activeRequest: _activeRequest,
              childName: widget.student.name,
              onRequest: _sendRequest,
              onCancel: _cancelRequest,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestActionButtons extends StatelessWidget {
  const _RequestActionButtons({
    required this.l10n,
    required this.isLoading,
    required this.isActioning,
    required this.activeRequest,
    required this.childName,
    required this.onRequest,
    required this.onCancel,
  });

  final AppLocalizations l10n;
  final bool isLoading;
  final bool isActioning;
  final TeacherRequest? activeRequest;
  final String childName;
  final VoidCallback onRequest;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final status = activeRequest?.status;
    Widget primaryButton;

    switch (status) {
      case TeacherRequestStatus.pending:
        primaryButton = AppButton(
          key: const Key('request_pending_button_body'),
          label: l10n.requestPending,
          isFullWidth: true,
          leading: const Icon(Icons.hourglass_top_outlined, size: 18),
          onPressed: null,
        );
        break;
      case TeacherRequestStatus.accepted:
        primaryButton = _ConnectedBadge(l10n: l10n);
        break;
      case null:
      case TeacherRequestStatus.declined:
      case TeacherRequestStatus.cancelled:
        primaryButton = AppButton(
          key: const Key('request_send_button_body'),
          label: l10n.teacherRequestButton(childName),
          isFullWidth: true,
          isLoading: isActioning,
          leading: const Icon(Icons.school_outlined, size: 18),
          onPressed: isActioning ? null : onRequest,
        );
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        primaryButton,
        if (status == TeacherRequestStatus.pending) ...[
          const SizedBox(height: AppConstants.space8),
          AppButton(
            label: l10n.requestCancelButton,
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            isLoading: isActioning,
            onPressed: isActioning ? null : onCancel,
          ),
        ],
      ],
    );
  }
}

class _RequestFooter extends StatelessWidget {
  const _RequestFooter({
    required this.l10n,
    required this.isLoading,
    required this.isActioning,
    required this.activeRequest,
    required this.childName,
    required this.onRequest,
    required this.onCancel,
  });

  final AppLocalizations l10n;
  final bool isLoading;
  final bool isActioning;
  final TeacherRequest? activeRequest;
  final String childName;
  final VoidCallback onRequest;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space12,
        AppConstants.pageHorizontalPadding,
        AppConstants.space16,
      ),
      child: _RequestActionButtons(
        l10n: l10n,
        isLoading: isLoading,
        isActioning: isActioning,
        activeRequest: activeRequest,
        childName: childName,
        onRequest: onRequest,
        onCancel: onCancel,
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('teacher_connected_badge'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(AppConstants.radius),
        border: Border.all(color: AppColors.success.withAlpha(80)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 18),
          const SizedBox(width: AppConstants.space8),
          Text(
            l10n.requestAccepted,
            style: AppTextStyles.body.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherProfileBody extends StatelessWidget {
  const _TeacherProfileBody({
    required this.teacher,
    required this.student,
    required this.availability,
    required this.isActioning,
    required this.onRequest,
  });

  final TeacherProfile teacher;
  final Student student;
  final WeeklyAvailability availability;
  final bool isActioning;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 1. Cover Card + Avatar Stack
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Cover Image
            SizedBox(
              width: double.infinity,
              height: 185,
              child: (teacher.coverUrl ?? '').isNotEmpty
                  ? Image.network(
                      teacher.coverUrl!,
                      fit: BoxFit.cover,
                    )
                  : Image.asset(
                      'assets/images/teacher_cover.jpg',
                      fit: BoxFit.cover,
                    ),
            ),
            // Avatar Card
            Positioned(
              left: 16,
              bottom: -36,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 100,
                    height: 104,
                    child: (teacher.photoUrl ?? '').isNotEmpty
                        ? Image.network(
                            teacher.photoUrl!,
                            fit: BoxFit.cover,
                            width: 100,
                            height: 104,
                          )
                        : Container(
                            color: AppColors.iconContainerBg,
                            child: Center(
                              child: Text(
                                teacher.displayName.isNotEmpty
                                    ? teacher.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 2. Name & Action Row (Right aligned next to avatar spacer)
        Padding(
          padding: const EdgeInsets.only(left: 132, top: 4, right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                teacher.fullNameWithTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 21,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const PhosphorIcon(PhosphorIcons.house, size: 16, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Home Tutor',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                        Text(
                          teacher.city ?? 'Yaounde',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        const Text('|', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.person_outline, size: 14, color: Color(0xFF64748B)),
                        const Text(
                          'In person',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: isActioning ? null : onRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.send, size: 12, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Request',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 3. Tile List
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _ProfileTile(
                icon: Icons.person_outline,
                title: 'About',
                child: Text(
                  (teacher.bio ?? '').isNotEmpty ? teacher.bio! : 'No bio yet.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: (teacher.bio ?? '').isNotEmpty ? const Color(0xFF334155) : const Color(0xFF94A3B8),
                  ),
                ),
              ),

              _ProfileTile(
                icon: Icons.menu_book,
                title: 'Subjects',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in teacher.subjects)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.checkCircleFill, color: AppColors.primary, size: 15),
                            const SizedBox(width: 8),
                            Text(
                              s,
                              style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              _ProfileTile(
                icon: Icons.school_outlined,
                title: 'Classes',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < (teacher.forms.length + 1) ~/ 2; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                children: [
                                  const PhosphorIcon(PhosphorIcons.checkCircleFill, color: AppColors.primary, size: 15),
                                  const SizedBox(width: 8),
                                  Text(
                                    teacher.forms[i],
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = (teacher.forms.length + 1) ~/ 2; i < teacher.forms.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                children: [
                                  const PhosphorIcon(PhosphorIcons.checkCircleFill, color: AppColors.primary, size: 15),
                                  const SizedBox(width: 8),
                                  Text(
                                    teacher.forms[i],
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              _ProfileTile(
                icon: Icons.payments_outlined,
                title: 'Cost per session',
                child: Text(
                  '${teacher.hourlyRate} FCFA',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primary,
                  ),
                ),
              ),

              _ProfileTile(
                icon: Icons.location_on_outlined,
                title: 'Teaching Areas',
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      teacher.city ?? 'Yaounde',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    const Text('|', style: TextStyle(color: Color(0xFFE2E8F0))),
                    const SizedBox(width: 8),
                    const Icon(Icons.person_outline, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      teacher.teachingMode == TeachingMode.inPerson ? 'In person' : 'Online',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              _ProfileTile(
                icon: Icons.star_outline,
                title: 'Reviews',
                child: const Text(
                  'No reviews yet.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
        ],
      ),
    );
  }
}
