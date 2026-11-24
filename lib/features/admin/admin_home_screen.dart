import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/admin_user_detail.dart';
import '../../core/models/user_role.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import 'admin_user_detail_screen.dart';

/// The Camiva admin home: platform overview, user directory, verifications,
/// and financial ledgers.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  AdminTotals _totals = AdminTotals.empty;
  int _pendingVerifications = 0;
  List<AdminUserSummary> _users = const [];

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

    final service = AdminServiceScope.of(context);
    final totalsResult = await service.fetchTotals();
    if (!mounted) return;

    final verifications = await service.fetchPendingVerifications();
    if (!mounted) return;
    if (verifications case PendingVerificationsSuccess(:final verifications)) {
      _pendingVerifications = verifications.length;
    }

    final usersResult = await service.fetchUsers();
    if (!mounted) return;
    if (usersResult case AdminUsersSuccess(:final users)) {
      _users = users;
    }

    switch (totalsResult) {
      case AdminTotalsSuccess(:final totals):
        setState(() {
          _totals = totals;
          _isLoading = false;
        });
      case AdminFailure(:final message):
        // If users succeeded, don't block the whole screen on totals
        if (_users.isNotEmpty) {
          setState(() => _isLoading = false);
        } else {
          setState(() {
            _errorMessage = message;
            _isLoading = false;
          });
        }
      default:
        setState(() => _isLoading = false);
    }
  }

  void _openUserDetail(AdminUserSummary user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminUserDetailScreen(
          userId: user.id,
          initialSummary: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camiva Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'All Users',
            onPressed: () => context.push(AppRoutes.adminUsers),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _users.isEmpty) {
      return AppEmptyState(
        icon: Icons.lock_outline,
        title: 'Could not load admin dashboard',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final teachersCount =
        _users.where((u) => u.role == UserRole.teacher).length;
    final parentsCount = _users.where((u) => u.role == UserRole.parent).length;
    final studentsCount =
        _users.where((u) => u.role == UserRole.student).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          // Platform Money Overview
          AppCard(
            key: const Key('admin_totals'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collected through Camiva',
                  style: AppTextStyles.body.copyWith(color: AppColors.grey500),
                ),
                const SizedBox(height: AppConstants.space4),
                Text(
                  formatMoney(_totals.collected, _totals.currency),
                  key: const Key('admin_collected'),
                  style: AppTextStyles.h1,
                ),
                const SizedBox(height: AppConstants.space16),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Owed to teachers',
                        value: formatMoney(
                            _totals.owedToTeachers, _totals.currency),
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Payments',
                        value: '${_totals.successfulCount} paid'
                            '${_totals.pendingCount > 0 ? ' · ${_totals.pendingCount} pending' : ''}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space16),

          // Platform Community & Users Metric Card
          AppCard(
            key: const Key('admin_users_metric_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Platform Community',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.grey500),
                    ),
                    InkWell(
                      onTap: () => context.push(AppRoutes.adminUsers),
                      child: Text(
                        'View All',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.space4),
                Text(
                  '${_users.length} Registered Users',
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: AppConstants.space12),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCountChip(
                        label: 'Teachers',
                        count: teachersCount,
                        color: AppColors.primary,
                        bg: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: AppConstants.space8),
                    Expanded(
                      child: _RoleCountChip(
                        label: 'Parents',
                        count: parentsCount,
                        color: AppColors.success,
                        bg: AppColors.successLight,
                      ),
                    ),
                    const SizedBox(width: AppConstants.space8),
                    Expanded(
                      child: _RoleCountChip(
                        label: 'Students',
                        count: studentsCount,
                        color: AppColors.warning,
                        bg: AppColors.warningLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space24),

          // Manage Menu
          const SectionHeader(title: 'Manage'),
          TileGroup(
            children: [
              ListTile(
                key: const Key('admin_open_users'),
                leading: const Icon(Icons.people_alt_outlined,
                    color: AppColors.primary),
                title: const Text('Users & Profiles'),
                subtitle: Text(
                  _users.isEmpty
                      ? 'All user accounts and details'
                      : '${_users.length} users ($teachersCount teachers, $parentsCount parents, $studentsCount students)',
                ),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.grey300),
                onTap: () async {
                  await context.push(AppRoutes.adminUsers);
                  if (mounted) _load();
                },
              ),
              ListTile(
                key: const Key('admin_open_withdrawals'),
                leading: const Icon(Icons.outbox_outlined,
                    color: AppColors.primary),
                title: const Text('Withdrawals'),
                subtitle: Text(
                  _totals.awaitingWithdrawal == 0
                      ? 'Nothing waiting'
                      : '${_totals.awaitingWithdrawal} waiting to be sent',
                ),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.grey300),
                onTap: () async {
                  await context.push(AppRoutes.adminWithdrawals);
                  if (mounted) _load();
                },
              ),
              ListTile(
                key: const Key('admin_open_verifications'),
                leading: const Icon(Icons.verified_outlined,
                    color: AppColors.primary),
                title: const Text('Verifications'),
                subtitle: Text(
                  _pendingVerifications == 0
                      ? 'Nothing waiting'
                      : '$_pendingVerifications waiting to be checked',
                ),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.grey300),
                onTap: () async {
                  await context.push(AppRoutes.adminVerifications);
                  if (mounted) _load();
                },
              ),
              ListTile(
                key: const Key('admin_open_billing'),
                leading: const Icon(Icons.event_note_outlined,
                    color: AppColors.primary),
                title: const Text('Monthly payments'),
                subtitle: const Text('Balances, due dates and reminders'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.grey300),
                onTap: () => context.push(AppRoutes.adminBilling),
              ),
              ListTile(
                key: const Key('admin_open_payments'),
                leading: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.primary),
                title: const Text('Payments'),
                subtitle: const Text('Who paid whom, and for which child'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.grey300),
                onTap: () => context.push(AppRoutes.adminPayments),
              ),
            ],
          ),

          // User details quick list directly on the Admin dashboard
          if (_users.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space24),
            SectionHeader(
              title: 'Platform Users Overview',
              trailing: TextButton(
                key: const Key('admin_see_all_users_btn'),
                onPressed: () => context.push(AppRoutes.adminUsers),
                child: const Text('See All'),
              ),
            ),
            for (final user in _users.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.space8),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AppAvatar(
                      name: user.name,
                      kind: switch (user.role) {
                        UserRole.teacher => AvatarKind.teacher,
                        UserRole.parent => AvatarKind.parent,
                        UserRole.student => AvatarKind.child,
                      },
                    ),
                    title: Text(
                      user.name,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${user.roleLabel} · ${user.email}'
                      '${user.phone != null ? " · ${user.phone}" : ""}',
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.grey300),
                    onTap: () => _openUserDetail(user),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption.copyWith(color: AppColors.grey500)),
        const SizedBox(height: AppConstants.space2),
        Text(value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _RoleCountChip extends StatelessWidget {
  const _RoleCountChip({
    required this.label,
    required this.count,
    required this.color,
    required this.bg,
  });

  final String label;
  final int count;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space8,
        vertical: AppConstants.space8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: AppTextStyles.h2.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
