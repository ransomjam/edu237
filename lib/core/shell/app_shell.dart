import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../state/app_state.dart';
import '../state/refresh_bus.dart';
import '../services/payment_service.dart';
import '../services/teacher_request_service.dart';
import '../models/teacher_request.dart';
import '../models/payment_reminder.dart';
import '../theme/app_colors.dart';
import '../../shared/widgets/phosphor_icon.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final Set<String> _notifiedReminderIds = {};
  bool _isFetchingCounts = false;
  bool _initialCountsFetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialCountsFetched) {
      _initialCountsFetched = true;
      _fetchCounts();
    }
  }

  Future<void> _fetchCounts() async {
    if (_isFetchingCounts) return;
    final paymentService = PaymentServiceScope.maybeOf(context);
    final requestService = TeacherRequestServiceScope.maybeOf(context);
    if (paymentService == null || requestService == null) return;

    // Use read(context) so AppShell does not depend on AppState changes
    // (the bottom nav subscribes independently in its own build).
    final appState = AppState.read(context);
    if (!appState.isAuthenticated) return;

    // Students have no requests to approve and no payments to chase, so there
    // is nothing to count — and no reason to hit those tables at all.
    if (appState.activeRole.isStudent) return;

    _isFetchingCounts = true;
    try {
      final isTeacher = appState.activeRole.isTeacher;

      // Fetch unread payment reminders count
      int unreadUpdates = 0;
      final remindersResult = await paymentService.fetchReminders();
      if (!mounted) return;
      if (remindersResult is ReminderListSuccess) {
        final unreadList = remindersResult.reminders.where((r) => r.isUnread).toList();
        unreadUpdates = unreadList.length;

        // Show push notification overlay for any newly discovered unread reminders
        final newReminders = unreadList.where((r) => !_notifiedReminderIds.contains(r.id)).toList();
        for (final PaymentReminder r in newReminders) {
          _notifiedReminderIds.add(r.id);
        }
        if (newReminders.isNotEmpty && mounted) {
          final first = newReminders.first;
          PushNotificationOverlay.show(context, title: first.title, body: first.body);
        }
      }

      // Fetch pending requests count
      int pendingRequests = 0;
      if (isTeacher) {
        final reqResult = await requestService.fetchIncomingRequestsAsTeacher();
        if (!mounted) return;
        if (reqResult is TeacherRequestListSuccess) {
          pendingRequests = reqResult.requests.where((r) => r.status == TeacherRequestStatus.pending).length;
        }
      } else {
        final reqResult = await requestService.fetchMyRequestsAsParent();
        if (!mounted) return;
        if (reqResult is TeacherRequestListSuccess) {
          pendingRequests = reqResult.requests.where((r) => r.status == TeacherRequestStatus.pending).length;
        }
      }

      if (mounted) {
        appState.setNotificationCounts(
          unreadUpdates: unreadUpdates,
          pendingRequests: pendingRequests,
        );
      }
    } finally {
      _isFetchingCounts = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: _AppBottomNav(
        currentBranch: widget.navigationShell.currentIndex,
        onTapBranch: _onTapBranch,
        l10n: l10n,
      ),
    );
  }

  /// [branch] is the shell branch index, not the position of the tapped
  /// destination — the two differ for roles that hide a tab.
  void _onTapBranch(int branch) {
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
    if (branch == _Branch.profile) {
      RefreshBusScope.maybeOf(context)?.profileChanged();
    }
    // Re-check counts whenever user navigates/tabs
    _fetchCounts();
  }
}

/// Branch indices of the [StatefulShellRoute] the nav bar drives.
abstract final class _Branch {
  static const int home = 0;

  /// Payments (parent) / Earnings (teacher) / Learning (student).
  static const int secondary = 1;

  /// Updates — parent and teacher only.
  static const int updates = 2;

  static const int profile = 3;
}

/// One bottom-navigation entry, bound to the shell branch it opens.
class _NavItem {
  const _NavItem({
    required this.branch,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final int branch;
  final String icon;
  final String selectedIcon;
  final String label;
  final int badgeCount;
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentBranch,
    required this.onTapBranch,
    required this.l10n,
  });

  final int currentBranch;
  final ValueChanged<int> onTapBranch;
  final AppLocalizations l10n;

  /// The destinations for the signed-in role, each bound to a branch.
  ///
  /// A student's navigation is deliberately minimal — Home, Learning, Profile.
  /// No updates tab, because a student has no requests to manage, and no
  /// payments tab, because a student never handles money.
  List<_NavItem> _itemsFor(BuildContext context) {
    final role = AppState.of(context).activeRole;
    final totalNotifications = AppState.of(context).totalNotificationCount;

    if (role.isStudent) {
      return [
        _NavItem(
          branch: _Branch.home,
          icon: PhosphorIcons.house,
          selectedIcon: PhosphorIcons.houseFill,
          label: l10n.navHome,
        ),
        _NavItem(
          branch: _Branch.secondary,
          icon: PhosphorIcons.bookOpen,
          selectedIcon: PhosphorIcons.bookOpenFill,
          label: l10n.navLearning,
        ),
        _NavItem(
          branch: _Branch.profile,
          icon: PhosphorIcons.user,
          selectedIcon: PhosphorIcons.userFill,
          label: l10n.navProfile,
        ),
      ];
    }

    final isTeacher = role.isTeacher;
    return [
      _NavItem(
        branch: _Branch.home,
        icon: PhosphorIcons.house,
        selectedIcon: PhosphorIcons.houseFill,
        label: l10n.navHome,
      ),
      _NavItem(
        branch: _Branch.secondary,
        icon: PhosphorIcons.wallet,
        selectedIcon: PhosphorIcons.walletFill,
        label: isTeacher ? l10n.navEarnings : l10n.navPayments,
      ),
      _NavItem(
        branch: _Branch.updates,
        icon: PhosphorIcons.bell,
        selectedIcon: PhosphorIcons.bellFill,
        label: l10n.navRequests,
        badgeCount: totalNotifications,
      ),
      if (isTeacher)
        _NavItem(
          branch: _Branch.profile,
          icon: PhosphorIcons.user,
          selectedIcon: PhosphorIcons.userFill,
          label: l10n.navProfile,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFor(context);

    // The active branch may not be in this role's nav (e.g. a parent deep in
    // the profile branch); fall back to Home rather than an invalid index.
    final selectedIndex =
        items.indexWhere((item) => item.branch == currentBranch);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.navPillBg,
        elevation: 0,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) => onTapBranch(items[index].branch),
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: _maybeBadged(
                item.badgeCount,
                PhosphorIcon(item.icon, size: 22, color: AppColors.grey500),
              ),
              selectedIcon: _maybeBadged(
                item.badgeCount,
                PhosphorIcon(item.selectedIcon, size: 22, color: AppColors.primary),
              ),
              label: item.label,
            ),
        ],
      ),
    );
  }

  Widget _maybeBadged(int count, Widget child) {
    if (count <= 0) return child;
    return Badge(
      backgroundColor: AppColors.error,
      label: Text('$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
      child: child,
    );
  }
}

class PushNotificationOverlay {
  static void show(BuildContext context, {required String title, required String body}) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      if (overlayEntry.mounted) {
                        overlayEntry.remove();
                      }
                    },
                    child: const Icon(Icons.close, color: Colors.white60, size: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}
