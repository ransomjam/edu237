import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/subject_style.dart';
import 'app_avatar.dart';
import 'app_button.dart';
import 'phosphor_icon.dart';

/// A small, quiet section heading used to give screens rhythm without heavy
/// containers. Optionally shows a trailing action (e.g. "See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.grey500,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A subject-coloured chip using the [SubjectStyle] language.
class SubjectChip extends StatelessWidget {
  const SubjectChip({super.key, required this.subject, this.dense = true});

  final String subject;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 12, vertical: dense ? 5 : 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: AppColors.tagBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIcon.iconForSubject(subject),
            size: dense ? 13 : 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            subject,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral pill (e.g. a Form badge).
class FormBadge extends StatelessWidget {
  const FormBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption
            .copyWith(color: AppColors.grey700, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A compact, tappable person row: avatar + title + subtitle + trailing.
///
/// This is the workhorse for lists of people (children, students, teachers).
/// It deliberately avoids a heavy bordered card so lists read as people, not
/// database rows. Group several inside a [TileGroup] for a subtle card.
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.name,
    this.subtitle,
    this.subtitleWidget,
    this.imageUrl,
    this.kind = AvatarKind.person,
    this.trailing,
    this.onTap,
    this.avatarSize = 46,
    this.showChevron = true,
  });

  final String name;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String? imageUrl;
  final AvatarKind kind;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double avatarSize;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space12,
            vertical: AppConstants.space12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(
                  name: name, imageUrl: imageUrl, size: avatarSize, kind: kind),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTextStyles.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: AppConstants.space4),
                      subtitleWidget!,
                    ] else if ((subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: AppConstants.space2),
                      Text(subtitle!,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.grey500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppConstants.space8),
                trailing!,
              ],
              if (showChevron && onTap != null) ...[
                const SizedBox(width: AppConstants.space4),
                const Icon(Icons.chevron_right,
                    color: AppColors.grey300, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A subtle surface that groups related [PersonTile]s (or any children) with a
/// light border and dividers — a lighter alternative to one card per row.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(
            height: 1, thickness: 1, indent: 70, color: AppColors.divider));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// A small coloured status dot + label (Connected, Pending, No teacher yet …).
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.iconName,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? iconName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconName != null)
          PhosphorIcon(iconName!, size: 14, color: color)
        else if (icon != null)
          Icon(icon, size: 14, color: color)
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.caption
                .copyWith(color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A friendly, intentional empty state: icon, title, one line of guidance, and
/// an optional primary action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon,
    this.iconName,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData? icon;
  final String? iconName;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: iconName != null
                        ? PhosphorIcon(iconName!, size: 32, color: AppColors.primary)
                        : Icon(icon ?? Icons.info_outline, size: 34, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.space16),
              Text(title, style: AppTextStyles.h2, textAlign: TextAlign.center),
              const SizedBox(height: AppConstants.space8),
              Text(
                message,
                style:
                    AppTextStyles.bodyLarge.copyWith(color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppConstants.space24),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  isFullWidth: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
