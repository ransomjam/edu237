import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/admin_user_detail.dart';
import '../../core/models/user_role.dart';
import '../../core/services/admin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/edu_ui.dart';

/// Screen displaying ALL the details of a single user on Camiva.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    this.initialSummary,
  });

  final String userId;
  final AdminUserSummary? initialSummary;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  AdminUserDetail? _user;

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
    final result = await service.fetchUserDetail(widget.userId);
    if (!mounted) return;

    switch (result) {
      case AdminUserDetailSuccess(:final user):
        setState(() {
          _user = user;
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

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _user?.name ?? widget.initialSummary?.name ?? 'User Details';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy User ID',
              onPressed: () => _copyToClipboard(_user!.id, 'User ID'),
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

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.person_off_outlined,
        title: 'Could not load user',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final user = _user;
    if (user == null) {
      return const Center(child: Text('User not found.'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          _buildIdentityCard(user),
          const SizedBox(height: AppConstants.space16),
          if (user.role.isTeacher && user.teacherProfile != null)
            _buildTeacherSection(user, user.teacherProfile!),
          if (user.role.isParent && user.parentProfile != null)
            _buildParentSection(user, user.parentProfile!),
          if (user.role.isStudent && user.studentProfile != null)
            _buildStudentSection(user, user.studentProfile!),
          const SizedBox(height: AppConstants.space24),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(AdminUserDetail user) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                name: user.name,
                size: 64,
                kind: switch (user.role) {
                  UserRole.teacher => AvatarKind.teacher,
                  UserRole.parent => AvatarKind.parent,
                  UserRole.student => AvatarKind.child,
                },
              ),
              const SizedBox(width: AppConstants.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            style: AppTextStyles.h2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppConstants.space8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.space8,
                            vertical: AppConstants.space2,
                          ),
                          decoration: BoxDecoration(
                            color: roleBg,
                            borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      user.email,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.grey700,
                      ),
                    ),
                    if (user.phone != null && user.phone!.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.space2),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 14, color: AppColors.grey500),
                          const SizedBox(width: AppConstants.space4),
                          Text(
                            user.phone!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: AppConstants.space24),
          _buildInfoRow(
            icon: Icons.fingerprint,
            label: 'User ID',
            value: user.id,
            onCopy: () => _copyToClipboard(user.id, 'User ID'),
          ),
          const SizedBox(height: AppConstants.space8),
          _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Member Since',
            value: formatShortDate(user.createdAt),
          ),
          if (user.updatedAt != null) ...[
            const SizedBox(height: AppConstants.space8),
            _buildInfoRow(
              icon: Icons.update,
              label: 'Last Active',
              value: formatShortDate(user.updatedAt!),
            ),
          ],
          const SizedBox(height: AppConstants.space8),
          _buildInfoRow(
            icon: user.profileComplete
                ? Icons.check_circle_outline
                : Icons.pending_outlined,
            label: 'Profile Status',
            value: user.profileComplete ? 'Complete' : 'Incomplete',
            valueColor: user.profileComplete
                ? AppColors.success
                : AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherSection(
      AdminUserDetail user, AdminTeacherDetails teacher) {
    final isVerified = teacher.verificationStatus == 'approved';
    final isPending = teacher.verificationStatus == 'pending';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Teacher Teaching Profile'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Verification Status',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _buildVerificationChip(teacher.verificationStatus),
                ],
              ),
              if (teacher.qualificationTitle != null) ...[
                const SizedBox(height: AppConstants.space8),
                _buildInfoRow(
                  icon: Icons.school_outlined,
                  label: 'Qualification',
                  value: teacher.qualificationTitle!,
                ),
              ],
              if (teacher.identityDocPath != null ||
                  teacher.qualificationDocPath != null) ...[
                const SizedBox(height: AppConstants.space12),
                Wrap(
                  spacing: AppConstants.space8,
                  runSpacing: AppConstants.space8,
                  children: [
                    if (teacher.identityDocPath != null)
                      _buildDocButton(
                        label: 'View Identity Document',
                        path: teacher.identityDocPath!,
                      ),
                    if (teacher.qualificationDocPath != null)
                      _buildDocButton(
                        label: 'View Qualification Document',
                        path: teacher.qualificationDocPath!,
                      ),
                  ],
                ),
              ],
              const Divider(height: AppConstants.space24),
              if (teacher.bio != null && teacher.bio!.isNotEmpty) ...[
                Text(
                  'About / Bio',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.grey500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.space4),
                Text(teacher.bio!, style: AppTextStyles.body),
                const SizedBox(height: AppConstants.space16),
              ],
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: teacher.locationLabel,
              ),
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.payments_outlined,
                label: 'Hourly Rate',
                value: teacher.hourlyRate > 0
                    ? '${formatMoney(teacher.hourlyRate, 'XAF')} / hr'
                    : 'Not specified',
              ),
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.laptop_chromebook_outlined,
                label: 'Teaching Mode',
                value: switch (teacher.teachingMode) {
                  'in_person' => 'In-person tutoring',
                  'online' => 'Online tutoring',
                  'both' => 'In-person & Online',
                  _ => 'Flexible',
                },
              ),
              const SizedBox(height: AppConstants.space16),
              Text(
                'Subjects Taught',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.grey500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppConstants.space8),
              teacher.subjects.isEmpty
                  ? const Text('No subjects listed',
                      style: TextStyle(color: AppColors.grey500))
                  : Wrap(
                      spacing: AppConstants.space8,
                      runSpacing: AppConstants.space8,
                      children: [
                        for (final s in teacher.subjects)
                          Chip(
                            label: Text(s),
                            backgroundColor: AppColors.primaryLight,
                            labelStyle: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
              if (teacher.forms.isNotEmpty) ...[
                const SizedBox(height: AppConstants.space16),
                Text(
                  'Classes & Forms Covered',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.grey500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                Wrap(
                  spacing: AppConstants.space8,
                  runSpacing: AppConstants.space8,
                  children: [
                    for (final f in teacher.forms)
                      Chip(
                        label: Text(f),
                        backgroundColor: AppColors.grey100,
                        labelStyle: AppTextStyles.caption.copyWith(
                          color: AppColors.grey700,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        const SectionHeader(title: 'Earnings & Payout Destination'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lifetime Earnings',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.grey500)),
                        const SizedBox(height: AppConstants.space2),
                        Text(
                          formatMoney(teacher.totalEarnings, 'XAF'),
                          style: AppTextStyles.h2
                              .copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Available Balance',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.grey500)),
                        const SizedBox(height: AppConstants.space2),
                        Text(
                          formatMoney(teacher.availableBalance, 'XAF'),
                          style: AppTextStyles.h2
                              .copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: AppConstants.space24),
              _buildInfoRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Payout Operator',
                value: teacher.payoutMedium ?? 'Not configured',
              ),
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.phone_android_outlined,
                label: 'Payout Phone',
                value: teacher.payoutPhone ?? 'Not configured',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        SectionHeader(
            title: 'Assigned Learners (${teacher.students.length})'),
        if (teacher.students.isEmpty)
          const AppCard(
            child: Text('No learners currently assigned to this teacher.'),
          )
        else
          AppCard(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: teacher.students.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final s = teacher.students[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AppAvatar(name: s.name, kind: AvatarKind.child),
                  title: Text(s.name,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${s.level ?? 'Learner'}${s.subsystem != null ? ' (${s.subsystem})' : ''}'
                    '${s.subjects.isNotEmpty ? ' · ${s.subjects.join(", ")}' : ''}',
                    style: AppTextStyles.caption,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildParentSection(AdminUserDetail user, AdminParentDetails parent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
            title: 'Children / Registered Learners (${parent.children.length})'),
        if (parent.children.isEmpty)
          const AppCard(
            child: Text('No children registered yet.'),
          )
        else
          AppCard(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: parent.children.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final c = parent.children[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AppAvatar(name: c.name, kind: AvatarKind.child),
                  title: Text(c.name,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${c.level ?? 'Learner'}${c.subsystem != null ? ' (${c.subsystem})' : ''}'
                    '${c.subjects.isNotEmpty ? '\nSubjects: ${c.subjects.join(", ")}' : ''}',
                    style: AppTextStyles.caption,
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: AppConstants.space16),
        const SectionHeader(title: 'Parent Commercial Overview'),
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Paid on Camiva',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.grey500)),
                        const SizedBox(height: AppConstants.space2),
                        Text(
                          formatMoney(parent.totalPaid, 'XAF'),
                          style: AppTextStyles.h2
                              .copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Outstanding Balance',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.grey500)),
                        const SizedBox(height: AppConstants.space2),
                        Text(
                          formatMoney(parent.outstandingBalance, 'XAF'),
                          style: AppTextStyles.h2.copyWith(
                            color: parent.outstandingBalance > 0
                                ? AppColors.warning
                                : AppColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: AppConstants.space24),
              _buildInfoRow(
                icon: Icons.person_search_outlined,
                label: 'Tutors Hired',
                value: parent.activeTeachers.isEmpty
                    ? 'None currently'
                    : parent.activeTeachers.join(', '),
              ),
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.handshake_outlined,
                label: 'Active Arrangements',
                value: '${parent.activeAgreementsCount} active arrangements',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentSection(
      AdminUserDetail user, AdminStudentDetails student) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Learner Academic Profile'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                icon: Icons.school_outlined,
                label: 'Subsystem',
                value: student.subsystem ?? 'General Education',
              ),
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.grade_outlined,
                label: 'Class / Level',
                value: student.level ?? 'Unspecified',
              ),
              if (student.series != null) ...[
                const SizedBox(height: AppConstants.space8),
                _buildInfoRow(
                  icon: Icons.category_outlined,
                  label: 'Series / Speciality',
                  value: student.series!,
                ),
              ],
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.account_circle_outlined,
                label: 'Account Mode',
                value: student.isSelfManaged
                    ? 'Self-managed Student account'
                    : 'Managed by Parent (${student.parentName ?? "Parent"})',
              ),
              if (student.parentPhone != null &&
                  student.parentPhone!.isNotEmpty) ...[
                const SizedBox(height: AppConstants.space8),
                _buildInfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Parent Phone',
                  value: student.parentPhone!,
                ),
              ],
              const Divider(height: AppConstants.space24),
              Text(
                'Enrolled Subjects',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.grey500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppConstants.space8),
              student.subjects.isEmpty
                  ? const Text('No subjects listed')
                  : Wrap(
                      spacing: AppConstants.space8,
                      runSpacing: AppConstants.space8,
                      children: [
                        for (final s in student.subjects)
                          Chip(
                            label: Text(s),
                            backgroundColor: AppColors.warningLight,
                            labelStyle: AppTextStyles.caption.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
              if (student.assignedTeachers.isNotEmpty) ...[
                const SizedBox(height: AppConstants.space16),
                _buildInfoRow(
                  icon: Icons.person_outline,
                  label: 'Assigned Teachers',
                  value: student.assignedTeachers.join(', '),
                ),
              ],
              const SizedBox(height: AppConstants.space8),
              _buildInfoRow(
                icon: Icons.book_outlined,
                label: 'Learning Sessions Completed',
                value: '${student.totalSessions} sessions',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationChip(String status) {
    final (label, color, bg) = switch (status) {
      'approved' => ('Verified', AppColors.success, AppColors.successLight),
      'pending' => ('Pending Review', AppColors.warning, AppColors.warningLight),
      'rejected' => ('Rejected', AppColors.error, AppColors.errorLight),
      _ => ('Unverified', AppColors.grey500, AppColors.grey100),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDocButton({required String label, required String path}) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.file_present_outlined, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.tagBorder),
      ),
      onPressed: () async {
        final url =
            await AdminServiceScope.of(context).verificationDocUrl(path);
        if (!mounted) return;
        if (url != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Document link created for $label'),
              action: SnackBarAction(
                label: 'Copy Link',
                onPressed: () => _copyToClipboard(url, 'Document link'),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not generate document link.')),
          );
        }
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    VoidCallback? onCopy,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.grey500),
        const SizedBox(width: AppConstants.space8),
        Text(
          '$label: ',
          style: AppTextStyles.body.copyWith(
            color: AppColors.grey500,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(
              color: valueColor ?? AppColors.grey900,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onCopy != null)
          InkWell(
            onTap: onCopy,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.copy, size: 14, color: AppColors.grey500),
            ),
          ),
      ],
    );
  }
}
