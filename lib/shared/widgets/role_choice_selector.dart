import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/user_role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The three-way role chooser shown at registration and onboarding.
///
/// Deliberately worded as a person, not as an enum: "I am a Parent", never
/// `PARENT`. The same widget serves both screens so the wording cannot drift.
class RoleChoiceSelector extends StatelessWidget {
  const RoleChoiceSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  /// Null renders every option unselected — used at registration, where the
  /// user has not chosen yet and no role should look pre-picked.
  final UserRole? selected;
  final ValueChanged<UserRole> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final role in UserRole.values) ...[
          _RoleCard(
            key: Key('role_choice_${role.name}'),
            label: roleChoiceLabel(l10n, role),
            hint: roleChoiceHint(l10n, role),
            icon: _iconFor(role),
            selected: selected == role,
            onTap: enabled ? () => onChanged(role) : null,
          ),
          const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }

  static IconData _iconFor(UserRole role) => switch (role) {
        UserRole.parent => Icons.family_restroom_outlined,
        UserRole.teacher => Icons.school_outlined,
        UserRole.student => Icons.backpack_outlined,
      };
}

/// "I am a Parent" / "I am a Teacher" / "I am a Student".
String roleChoiceLabel(AppLocalizations l10n, UserRole role) => switch (role) {
      UserRole.parent => l10n.roleChoiceParent,
      UserRole.teacher => l10n.roleChoiceTeacher,
      UserRole.student => l10n.roleChoiceStudent,
    };

String roleChoiceHint(AppLocalizations l10n, UserRole role) => switch (role) {
      UserRole.parent => l10n.roleChoiceParentHint,
      UserRole.teacher => l10n.roleChoiceTeacherHint,
      UserRole.student => l10n.roleChoiceStudentHint,
    };

/// The plain noun ("Parent", "Teacher", "Student") for chips and summaries.
String roleNoun(AppLocalizations l10n, UserRole role) => switch (role) {
      UserRole.parent => l10n.roleParent,
      UserRole.teacher => l10n.roleTeacher,
      UserRole.student => l10n.roleStudent,
    };

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space16,
            vertical: AppConstants.space16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.grey500,
              ),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color:
                            selected ? AppColors.primary : AppColors.grey900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.grey300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
