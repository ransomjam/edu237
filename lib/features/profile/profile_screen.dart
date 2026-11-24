import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../../core/auth/phone_credentials.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/admin_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/services/teacher_availability_service.dart';
import '../../core/state/app_state.dart';
import '../../core/state/refresh_bus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/models/app_user.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teacher_availability.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// What to show under someone's name: their phone number, or the raw value if
/// this account predates phone sign-in.
String _accountLabel(String email) {
  final phone = PhoneCredentials.phoneFromEmail(email);
  return phone == null ? email : PhoneCredentials.format(phone);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  TeacherProfile? _profile;
  WeeklyAvailability? _availability;
  String? _error;
  String? _lastLoadedUserId;
  String? _adminCheckedUserId;
  RefreshBus? _bus;

  /// Whether this account also holds Camiva admin capability. Hiding the entry
  /// is a convenience only - every admin action is re-checked server-side, so a
  /// non-admin who reaches the screen anyway is still refused.
  bool _isAdmin = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bus = RefreshBusScope.maybeOf(context);
    if (bus != _bus) {
      _bus?.removeListener(_onBusChanged);
      _bus = bus;
      _bus?.addListener(_onBusChanged);
    }

    final appState = AppState.of(context);
    final user = appState.currentUser;

    // Admin is an extra capability on a normal account, so this runs for
    // parents and teachers alike.
    if (user != null && user.id != _adminCheckedUserId) {
      _adminCheckedUserId = user.id;
      _checkAdmin();
    }

    if (user != null && appState.activeRole.isTeacher) {
      if (user.id != _lastLoadedUserId || _profile == null) {
        _lastLoadedUserId = user.id;
        _loadData();
      }
    } else {
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onBusChanged() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    _bus?.removeListener(_onBusChanged);
    super.dispose();
  }

  Future<void> _editProfile(TeacherProfile? current) async {
    final updated = await context.push<TeacherProfile>(
      AppRoutes.teacherProfileEdit,
      extra: current,
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
      _loadData();
    }
  }

  Future<void> _checkAdmin() async {
    final service = AdminServiceScope.maybeOf(context);
    if (service == null) return;
    final result = await service.checkAdminAccess();
    if (!mounted) return;
    if (result case AdminAccessSuccess(:final isAdmin)) {
      if (isAdmin != _isAdmin) setState(() => _isAdmin = isAdmin);
    }
  }

  Widget _adminEntry(BuildContext context) {
    if (!_isAdmin) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space16),
      child: AppButton(
        key: const Key('open_admin_button'),
        label: 'Camiva admin',
        variant: AppButtonVariant.outlined,
        isFullWidth: true,
        leading: const PhosphorIcon(PhosphorIcons.shieldCheck, size: 18, color: AppColors.primary),
        onPressed: () => context.push(AppRoutes.adminHome),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profileResult = await TeacherProfileServiceScope.of(
        context,
      ).fetchMyProfile();
      final availabilityResult = await TeacherAvailabilityServiceScope.of(
        context,
      ).fetchMyAvailability();

      if (!mounted) return;

      setState(() {
        if (profileResult is TeacherProfileSuccess) {
          _profile = profileResult.profile;
        } else if (profileResult is TeacherProfileFailure) {
          _error = profileResult.message;
        }
        if (availabilityResult is AvailabilitySuccess) {
          _availability = availabilityResult.availability;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appState = AppState.of(context);
    final user = appState.currentUser;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(l10n.profileTitle),
      ),
      body: user.activeRole.isTeacher
          ? _buildTeacherProfile(l10n, user.name)
          : _buildParentProfile(l10n, user),
    );
  }

  Widget _buildParentProfile(AppLocalizations l10n, AppUser user) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        const SizedBox(height: AppConstants.space24),
        Center(
          child: AppAvatar(
            name: user.name,
            imageUrl: null,
            size: 80,
            kind: AvatarKind.parent,
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        Center(child: Text(user.name, style: AppTextStyles.h2)),
        // The account is a phone number now; the stored address is synthetic
        // and means nothing to the person reading it.
        Center(
          child: Text(
            _accountLabel(user.email),
            style: AppTextStyles.body,
          ),
        ),
        const SizedBox(height: AppConstants.space8),
        Center(
          child: Chip(
            label: Text(l10n.roleParent),
            backgroundColor: AppColors.primaryLight,
            labelStyle: const TextStyle(color: AppColors.primary),
          ),
        ),
        const SizedBox(height: AppConstants.space32),
        AppButton(
          key: const Key('open_payments_button'),
          label: 'Payments',
          variant: AppButtonVariant.outlined,
          isFullWidth: true,
          leading: const PhosphorIcon(PhosphorIcons.receipt, size: 18, color: AppColors.primary),
          onPressed: () => context.push(AppRoutes.paymentHistory),
        ),
        const SizedBox(height: AppConstants.space40),
        _adminEntry(context),
        _LogoutButton(l10n: l10n),
      ],
    );
  }

  Widget _buildTeacherProfile(AppLocalizations l10n, String userName) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppConstants.space16),
            Text(l10n.childrenLoading),
          ],
        ),
      );
    }

    if (_error != null) {
      return AppEmptyState(
        iconName: PhosphorIcons.warningCircle,
        title: l10n.errorGenericTitle,
        message: _error!,
        actionLabel: l10n.retryButton,
        onAction: _loadData,
      );
    }

    if (_profile == null) {
      return AppEmptyState(
        iconName: PhosphorIcons.user,
        title: l10n.teacherNoProfileTitle,
        message: l10n.teacherNoProfileBody,
        actionLabel: l10n.teacherCreateProfile,
        onAction: () => _editProfile(null),
      );
    }

    final p = _profile!;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 1. Cover Card + Avatar Stack
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Cover Image with Camera Edit Overlay
              GestureDetector(
                onTap: () => _editProfile(p),
                child: SizedBox(
                  width: double.infinity,
                  height: 185,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      (p.coverUrl ?? '').isNotEmpty
                          ? Image.network(
                              p.coverUrl!,
                              fit: BoxFit.cover,
                            )
                          : Image.asset(
                              'assets/images/teacher_cover.jpg',
                              fit: BoxFit.cover,
                            ),
                      // Top-right edit badge
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white54,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              PhosphorIcon(PhosphorIcons.camera, size: 14, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'Edit Cover',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Avatar Card with Camera Badge
              Positioned(
                left: 16,
                bottom: -36,
                child: GestureDetector(
                  onTap: () => _editProfile(p),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
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
                            child: (p.photoUrl ?? '').isNotEmpty
                                ? Image.network(
                                    p.photoUrl!,
                                    fit: BoxFit.cover,
                                    width: 100,
                                    height: 104,
                                  )
                                : Container(
                                    color: AppColors.iconContainerBg,
                                    child: Center(
                                      child: Text(
                                        p.displayName.isNotEmpty
                                            ? p.displayName[0].toUpperCase()
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
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const PhosphorIcon(
                            PhosphorIcons.camera,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
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
                  p.fullNameWithTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 21,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.roleTeacher,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editProfile(p),
                        icon: const PhosphorIcon(PhosphorIcons.pencilSimple, size: 14, color: AppColors.primary),
                        label: const Text('Edit profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.push(AppRoutes.teacherEarnings),
                        icon: const PhosphorIcon(PhosphorIcons.wallet, size: 14, color: Colors.white),
                        label: const Text('Earnings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 3. Details Card List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _TeacherProfileCard(
                  title: 'About',
                  child: Text(
                    p.bio?.isNotEmpty == true ? p.bio! : l10n.teacherProfileNoBio,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: p.bio?.isNotEmpty == true ? const Color(0xFF334155) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),

                _TeacherProfileCard(
                  title: 'Subjects',
                  child: Text(
                    p.subjects.isNotEmpty ? p.subjects.join('   |   ') : '—',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                _TeacherProfileCard(
                  title: 'Classes',
                  child: Text(
                    p.levels.isNotEmpty
                        ? p.qualifiedLevelLabels.join('   |   ')
                        : '—',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                if (p.city != null && p.city!.isNotEmpty)
                  _TeacherProfileCard(
                    title: 'Location',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.mapPin, size: 18, color: AppColors.grey500),
                            const SizedBox(width: 8),
                            Text(
                              '${p.area ?? ''}${p.area != null && p.area!.isNotEmpty ? ', ' : ''}${p.city}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Teaching area — not a home address.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),

                _TeacherProfileCard(
                  title: 'Availability',
                  headerTrailing: GestureDetector(
                    onTap: () async {
                      await context.push(AppRoutes.teacherAvailability);
                      _loadData();
                    },
                    child: const Text(
                      'Edit availability',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  child: () {
                    var daysText = 'Not specified';
                    var timeText = 'Not specified';
                    if (_availability != null && _availability!.isNotEmpty) {
                      final summaryLines = availabilitySummaryLines(_availability!);
                      if (summaryLines.isNotEmpty) {
                        final parts = summaryLines.first.split(' · ');
                        if (parts.length >= 2) {
                          daysText = parts[0];
                          timeText = parts[1];
                        } else {
                          daysText = summaryLines.first;
                        }
                      }
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.calendarBlank, size: 16, color: AppColors.grey500),
                            const SizedBox(width: 8),
                            Text(
                              daysText,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.clock, size: 16, color: AppColors.grey500),
                            const SizedBox(width: 8),
                            Text(
                              timeText,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    );
                  }(),
                ),

                _TeacherProfileCard(
                  title: 'Account',
                  child: Column(
                    children: [
                      _adminEntry(context),
                      _LogoutButton(l10n: l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TeacherProfileCard extends StatelessWidget {
  const _TeacherProfileCard({
    required this.title,
    this.headerTrailing,
    required this.child,
  });

  final String title;
  final Widget? headerTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.l10n});
  final AppLocalizations l10n;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _isLoading = false;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.profileLogoutConfirmTitle),
        content: Text(widget.l10n.profileLogoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.l10n.profileLogoutCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(widget.l10n.profileLogoutConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    final authService = AuthServiceScope.of(context);
    await authService.signOut();

    if (!mounted) return;

    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _logout,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.error,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PhosphorIcon(PhosphorIcons.signOut, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(widget.l10n.profileLogout),
                ],
              ),
      ),
    );
  }
}
