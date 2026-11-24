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
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';
import 'admin_user_detail_screen.dart';

/// Screen listing all users across Camiva (Parents, Teachers, Students), with
/// search, role filtering, and deep detail inspection.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<AdminUserSummary> _users = const [];
  String _selectedRole = 'all'; // 'all', 'teacher', 'parent', 'student'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final service = AdminServiceScope.of(context);
    final result = await service.fetchUsers(
      query: _searchQuery,
      roleFilter: _selectedRole == 'all' ? null : _selectedRole,
    );
    if (!mounted) return;

    switch (result) {
      case AdminUsersSuccess(:final users):
        setState(() {
          _users = users;
          _isLoading = false;
        });
      case AdminFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      default:
        setState(() => _isLoading = false);
    }
  }

  void _onRoleFilterChanged(String role) {
    setState(() {
      _selectedRole = role;
    });
    _load();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
    });
    _load();
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
        title: const Text('Platform Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh users',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchAndFilters(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? AppEmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load users',
                      message: _errorMessage!,
                      actionLabel: 'Try again',
                      onAction: _load,
                    )
                  : _users.isEmpty
                      ? AppEmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'No users found',
                          message: _searchQuery.isNotEmpty
                              ? 'No users match "$_searchQuery".'
                              : 'No users registered under this role yet.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(
                                AppConstants.pageHorizontalPadding),
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppConstants.space8),
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              return _UserCard(
                                key: Key('user_card_${user.id}'),
                                user: user,
                                onTap: () => _openUserDetail(user),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    final teachersCount =
        _users.where((u) => u.role == UserRole.teacher).length;
    final parentsCount = _users.where((u) => u.role == UserRole.parent).length;
    final studentsCount =
        _users.where((u) => u.role == UserRole.student).length;

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pageHorizontalPadding,
        vertical: AppConstants.space12,
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            key: const Key('admin_user_search_field'),
            decoration: InputDecoration(
              hintText: 'Search by name, email, phone, subject...',
              prefixIcon: const Icon(Icons.search, color: AppColors.grey500),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppConstants.space12,
                vertical: AppConstants.space8,
              ),
              filled: true,
              fillColor: AppColors.grey100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: AppConstants.space8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  key: const Key('filter_role_all'),
                  label: 'All (${_users.length})',
                  selected: _selectedRole == 'all',
                  onSelected: () => _onRoleFilterChanged('all'),
                ),
                const SizedBox(width: AppConstants.space8),
                _FilterChip(
                  key: const Key('filter_role_teacher'),
                  label: 'Teachers ($teachersCount)',
                  selected: _selectedRole == 'teacher',
                  color: AppColors.primary,
                  onSelected: () => _onRoleFilterChanged('teacher'),
                ),
                const SizedBox(width: AppConstants.space8),
                _FilterChip(
                  key: const Key('filter_role_parent'),
                  label: 'Parents ($parentsCount)',
                  selected: _selectedRole == 'parent',
                  color: AppColors.success,
                  onSelected: () => _onRoleFilterChanged('parent'),
                ),
                const SizedBox(width: AppConstants.space8),
                _FilterChip(
                  key: const Key('filter_role_student'),
                  label: 'Students ($studentsCount)',
                  selected: _selectedRole == 'student',
                  color: AppColors.warning,
                  onSelected: () => _onRoleFilterChanged('student'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: AppTextStyles.caption.copyWith(
        color: selected ? AppColors.white : AppColors.grey700,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: activeColor,
      backgroundColor: AppColors.grey100,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    super.key,
    required this.user,
    required this.onTap,
  });

  final AdminUserSummary user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roleColor = switch (user.role) {
      UserRole.teacher => AppColors.primary,
      UserRole.parent => AppColors.success,
      UserRole.student => AppColors.warning,
    };
    final roleBg = switch (user.role) {
      UserRole.teacher => AppColors.primaryLight,
      UserRole.parent => AppColors.successLight,
      UserRole.student => AppColors.warningLight,
    };

    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    name: user.name,
                    size: 48,
                    kind: switch (user.role) {
                      UserRole.teacher => AvatarKind.teacher,
                      UserRole.parent => AvatarKind.parent,
                      UserRole.student => AvatarKind.child,
                    },
                  ),
                  const SizedBox(width: AppConstants.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.name,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: roleBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                user.roleLabel,
                                style: AppTextStyles.caption.copyWith(
                                  color: roleColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.space2),
                        Text(
                          user.email,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.grey500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user.phone != null && user.phone!.isNotEmpty) ...[
                          const SizedBox(height: AppConstants.space2),
                          Text(
                            user.phone!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.grey700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.grey300),
                ],
              ),
              const SizedBox(height: AppConstants.space8),
              const Divider(height: 1),
              const SizedBox(height: AppConstants.space8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (user.town != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: AppColors.grey500),
                        const SizedBox(width: 4),
                        Text(
                          user.town!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.grey700,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  if (user.role.isTeacher &&
                      user.teacherVerificationStatus != null)
                    _buildVerificationBadge(user.teacherVerificationStatus!)
                  else if (user.role.isParent && user.childrenCount != null)
                    Text(
                      '${user.childrenCount} children',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.grey500,
                      ),
                    )
                  else
                    Text(
                      'Joined ${formatShortDate(user.createdAt)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.grey500,
                      ),
                    ),
                ],
              ),
              if (user.subjects.isNotEmpty) ...[
                const SizedBox(height: AppConstants.space4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final s in user.subjects.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            color: AppColors.grey700,
                          ),
                        ),
                      ),
                    if (user.subjects.length > 3)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+${user.subjects.length - 3}',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            color: AppColors.grey500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationBadge(String status) {
    final (label, color, bg) = switch (status) {
      'approved' => ('Verified', AppColors.success, AppColors.successLight),
      'pending' => ('Pending', AppColors.warning, AppColors.warningLight),
      'rejected' => ('Rejected', AppColors.error, AppColors.errorLight),
      _ => ('Unverified', AppColors.grey500, AppColors.grey100),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
