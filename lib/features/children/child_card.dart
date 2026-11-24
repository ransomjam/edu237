import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/student.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// A single child, shown on the parent Home and Children screens.
///
/// The whole card is the entry point to the child's detail screen — tapping it
/// opens [onTap]. Shows the child's identity (avatar, name, class), a subject
/// summary, and teacher-connection status.
class ChildCard extends StatelessWidget {
  const ChildCard({
    super.key,
    required this.child,
    this.onTap,
    this.onFindTeacher,
    this.isConnected = false,
  });

  final Student child;
  final VoidCallback? onTap;
  final VoidCallback? onFindTeacher;

  /// Whether the child has at least one accepted teacher relationship.
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Qualified by subsystem — "English · Form 4", never a bare "Form 4".
    final levelLabel = child.qualifiedLevelLabel;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(name: child.name, size: 48, kind: AvatarKind.child),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name, style: AppTextStyles.h3),
                    if (levelLabel != null) ...[
                      const SizedBox(height: AppConstants.space2),
                      Text(
                        levelLabel,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.grey500),
                      ),
                    ],
                  ],
                ),
              ),
              const PhosphorIcon(PhosphorIcons.caretRight, color: AppColors.grey500, size: 16),
            ],
          ),
          const SizedBox(height: AppConstants.space12),
          // Subjects preview as small badges (capped), then an overflow count.
          if (child.subjects.isNotEmpty) ...[
            _SubjectPreview(subjects: child.subjects),
            const SizedBox(height: AppConstants.space4),
            Text(
              l10n.childSubjectCount(child.subjects.length),
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppConstants.space12),
          ],
          // Connection status + action.
          if (isConnected)
            _StatusPill(
              label: l10n.childTeacherConnected,
              color: AppColors.success,
              bg: AppColors.successLight,
              iconName: PhosphorIcons.shieldCheckFill,
            )
          else ...[
            _StatusPill(
              label: l10n.childNoTeacher,
              color: AppColors.grey500,
              bg: AppColors.grey100,
              iconName: PhosphorIcons.magnifyingGlass,
            ),
            const SizedBox(height: AppConstants.space12),
            AppButton(
              label: l10n.findTeacherButton,
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              onPressed: onFindTeacher ??
                  () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.findTeacherComingSoon)),
                      ),
              leading: const PhosphorIcon(PhosphorIcons.magnifyingGlass, size: 16, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectPreview extends StatelessWidget {
  const _SubjectPreview({required this.subjects});
  final List<String> subjects;

  @override
  Widget build(BuildContext context) {
    final shown = subjects.take(3).toList();
    return Wrap(
      spacing: AppConstants.space8,
      runSpacing: AppConstants.space8,
      children: [
        for (final s in shown)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              border: Border.all(color: AppColors.tagBorder, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIcon.iconForSubject(s),
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  s,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.bg,
    required this.iconName,
  });

  final String label;
  final Color color;
  final Color bg;
  final String iconName;

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
          PhosphorIcon(iconName, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption
                .copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
