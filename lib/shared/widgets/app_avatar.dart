import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Visual role of the person an [AppAvatar] represents. Only used to pick a
/// subtle accent (a small corner glyph) so the same component can visually
/// distinguish a child, teacher, or parent while staying one design system.
enum AvatarKind { person, child, teacher, parent }

/// A reusable, initials-based avatar.
///
/// Every person in Camiva gets a consistent visual identity. When no photo is
/// available we render tasteful initials on a colour deterministically derived
/// from the name, so the same person always looks the same. If [imageUrl] is
/// provided it is shown instead (initials remain the fallback while loading /
/// on error). We never imply a generated avatar is a real photograph.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.kind = AvatarKind.person,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final AvatarKind kind;

  /// A calm, warm palette — friendly and appropriate, never garish.
  static const List<_AvatarColor> _palette = [
    _AvatarColor(Color(0xFFDBEAFE), Color(0xFF1D4ED8)), // blue
    _AvatarColor(Color(0xFFDCFCE7), Color(0xFF15803D)), // green
    _AvatarColor(Color(0xFFFEF3C7), Color(0xFFB45309)), // amber
    _AvatarColor(Color(0xFFEDE9FE), Color(0xFF6D28D9)), // violet
    _AvatarColor(Color(0xFFFFE4E6), Color(0xFFBE123C)), // rose
    _AvatarColor(Color(0xFFCFFAFE), Color(0xFF0E7490)), // cyan
    _AvatarColor(Color(0xFFFFEDD5), Color(0xFFC2410C)), // orange
    _AvatarColor(Color(0xFFD1FAE5), Color(0xFF047857)), // teal
  ];

  static String initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.characters.take(p.length >= 2 ? 2 : 1).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  _AvatarColor get _color {
    final key = name.trim().toLowerCase();
    final hash = key.isEmpty ? 0 : key.codeUnits.fold<int>(0, (a, c) => a + c);
    return _palette[hash % _palette.length];
  }

  IconData _iconForKind(AvatarKind kind) {
    return switch (kind) {
      AvatarKind.child => Icons.face_6_rounded,
      AvatarKind.parent => Icons.person_rounded,
      AvatarKind.teacher => Icons.school_rounded,
      AvatarKind.person => Icons.person_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final hasPhoto = (imageUrl ?? '').isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.background,
        shape: BoxShape.circle,
        image: hasPhoto
            ? DecorationImage(
                image: ResizeImage(
                  NetworkImage(imageUrl!),
                  width: (size * 2).clamp(64, 256).round(),
                  height: (size * 2).clamp(64, 256).round(),
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Icon(
              _iconForKind(kind),
              color: color.foreground,
              size: size * 0.55,
            ),
    );
  }
}

class _AvatarColor {
  const _AvatarColor(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

/// A small badge used for forms, subjects, and lightweight tags. Belongs to the
/// same family as [StatusBadge] but is neutral / brand-tinted.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.icon,
  });

  /// A brand-tinted badge (used for forms).
  const AppBadge.form(String label, {Key? key})
      : this(key: key, label: label, background: AppColors.primaryLight, foreground: AppColors.primary);

  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? AppColors.grey100;
    final fg = foreground ?? AppColors.grey700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tone for a [StatusBadge].
enum StatusTone { neutral, info, success, warning, danger }

/// A coloured status pill (pending, connected, declined, …) with a leading dot.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusTone.neutral => (AppColors.grey100, AppColors.grey700),
      StatusTone.info => (AppColors.primaryLight, AppColors.primary),
      StatusTone.success => (AppColors.successLight, AppColors.success),
      StatusTone.warning => (AppColors.warningLight, AppColors.warning),
      StatusTone.danger => (AppColors.errorLight, AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
