import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_avatar.dart';

/// A warm, personal home header: a time-of-day greeting, the person's name, and
/// their avatar. Shared by the parent and teacher home dashboards.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.name,
    this.subtitle,
    this.kind = AvatarKind.person,
  });

  final String name;
  final String? subtitle;
  final AvatarKind kind;

  static String greetingForHour(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final greeting = greetingForHour(DateTime.now().hour);
    final firstName =
        name.trim().isEmpty ? '' : name.trim().split(RegExp(r'\s+')).first;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: AppTextStyles.body.copyWith(color: AppColors.grey500),
              ),
              const SizedBox(height: AppConstants.space2),
              Text(
                firstName.isEmpty ? 'Welcome' : firstName,
                style: AppTextStyles.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if ((subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: AppConstants.space2),
                Text(
                  subtitle!,
                  style: AppTextStyles.body.copyWith(color: AppColors.grey500),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppConstants.space12),
        AppAvatar(name: name.isEmpty ? '?' : name, size: 52, kind: kind),
      ],
    );
  }
}
