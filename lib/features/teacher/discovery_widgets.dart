import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/education_catalogue.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teaching_mode.dart';
import '../../core/services/geo.dart';
import '../../core/services/teacher_discovery.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/phosphor_icon.dart';

/// Visual accent for a [TeachingMode] — a small, restrained icon + colour used
/// on badges. Not full-card colour (per the design language).
class _ModeVisual {
  const _ModeVisual(this.icon, this.color, this.bg);
  final String icon;
  final Color color;
  final Color bg;

  static _ModeVisual of(TeachingMode mode) => switch (mode) {
        TeachingMode.online => const _ModeVisual(
            PhosphorIcons.videoCamera, AppColors.primary, AppColors.primaryLight),
        TeachingMode.inPerson => const _ModeVisual(
            PhosphorIcons.users, Color(0xFF15803D), Color(0xFFDCFCE7)),
        TeachingMode.both => const _ModeVisual(
            PhosphorIcons.arrowClockwise, Color(0xFF6D28D9), Color(0xFFEDE9FE)),
      };
}

String teachingModeLabel(AppLocalizations l10n, TeachingMode mode) =>
    switch (mode) {
      TeachingMode.online => l10n.teacherTeachingModeOnline,
      TeachingMode.inPerson => l10n.teacherTeachingModeInPerson,
      TeachingMode.both => l10n.teacherTeachingModeBoth,
    };

/// A compact badge stating how a teacher teaches (Online / In person / both).
class TeachingModeBadge extends StatelessWidget {
  const TeachingModeBadge({super.key, required this.mode, this.dense = true});

  final TeachingMode mode;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final v = _ModeVisual.of(mode);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 12, vertical: dense ? 5 : 7),
      decoration: BoxDecoration(
        color: v.bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(v.icon, size: dense ? 13 : 15, color: v.color),
          const SizedBox(width: 5),
          Text(
            teachingModeLabel(l10n, mode),
            style: (dense ? AppTextStyles.caption : AppTextStyles.label)
                .copyWith(color: v.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A small "✓ Form 4" / "✓ Mathematics" relevance indicator.
class RelevanceCheck extends StatelessWidget {
  const RelevanceCheck({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(PhosphorIcons.check, size: 12, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The prominent "Best match" pill.
class BestMatchBadge extends StatelessWidget {
  const BestMatchBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(PhosphorIcons.starFill, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            l10n.discoveryBestMatch,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A subtle distance chip ("1.8 km away").
class DistanceChip extends StatelessWidget {
  const DistanceChip({super.key, required this.distanceKm});

  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    final label = Geo.formatDistance(distanceKm);
    if (label == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PhosphorIcon(PhosphorIcons.navigationArrow, size: 13, color: AppColors.grey500),
        const SizedBox(width: 3),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// Builds the ordered relevance labels for a discovery item: the matched form
/// first, then each matched subject.
List<String> relevanceLabels(DiscoveryTeacher d, {String? childForm}) {
  final labels = <String>[];
  if (d.formMatches && (childForm ?? '').trim().isNotEmpty) {
    labels.add(childForm!.trim());
  }
  labels.addAll(d.matchedSubjects);
  return labels;
}


/// The full teacher card used in List view (and as the selected-teacher sheet
/// on the map). Warm, rounded, restrained colour — subjects use the subject
/// colour language, everything else stays neutral.
class TeacherDiscoveryCard extends StatelessWidget {
  const TeacherDiscoveryCard({
    super.key,
    required this.item,
    required this.childForm,
    required this.onTap,
    this.selected = false,
    this.compact = false,
  });

  final DiscoveryTeacher item;
  final String? childForm;
  final VoidCallback onTap;

  /// Highlights the card (map selection).
  final bool selected;

  /// A tighter layout for the map bottom sheet.
  final bool compact;

  /// The cycles this teacher covers, read from the education catalogue and
  /// qualified by subsystem — e.g. "English · Ordinary Level". Falls back to
  /// the stored labels for a profile we cannot resolve.
  List<String> _cycleLabels(TeacherProfile teacher) {
    final cycles = teacher.cycles.toList()
      ..sort((a, b) => EducationCycle.values
          .indexOf(a)
          .compareTo(EducationCycle.values.indexOf(b)));
    if (cycles.isEmpty) return teacher.forms;
    return [
      for (final cycle in cycles)
        '${cycle.subsystem.shortLabel} · ${cycle.label}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final teacher = item.teacher;
    final reasons = relevanceLabels(item, childForm: childForm);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.08 : 0.03),
            blurRadius: selected ? 12 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Identity Row (Avatar + Name & Location + Badges)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 48 : 56,
                      height: compact ? 48 : 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDBEAFE),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: (teacher.photoUrl ?? '').isNotEmpty
                            ? Image.network(
                                teacher.photoUrl!,
                                fit: BoxFit.cover,
                                width: compact ? 48 : 56,
                                height: compact ? 48 : 56,
                              )
                            : Center(
                                child: Text(
                                  teacher.displayName.isNotEmpty
                                      ? teacher.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: compact ? 20 : 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teacher.fullNameWithTitle,
                            style: AppTextStyles.h2.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: AppColors.grey900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Role & City
                          Row(
                            children: [
                              const PhosphorIcon(PhosphorIcons.mapPin,
                                  size: 14, color: AppColors.grey500),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  '${l10n.homeTutorLabel}    ${teacher.city ?? 'Yaoundé'}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.grey700,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Classes
                          if (teacher.forms.isNotEmpty)
                            Text.rich(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Classes: ',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.grey500,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: _cycleLabels(teacher).join(', '),
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.grey700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Badges on the right
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (item.isBestMatch) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.tagBorder, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PhosphorIcon(PhosphorIcons.starFill,
                                    size: 12, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Top Match',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // distance now shown on the mini map
                      ],
                    ),
                  ],
                ),

                // Clean matches info (no highlight/container)
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const PhosphorIcon(PhosphorIcons.checkCircleFill,
                          size: 15, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Matches: ',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.grey900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              TextSpan(
                                text: reasons.join(', '),
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.grey700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Info rows + Mini Map
                if (!compact) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left: subjects / location / schedule
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CardInfoRow(
                              icon: PhosphorIcons.graduationCap,
                              iconColor: AppColors.primary,
                              title: teacher.subjects.take(3).join(' • '),
                              subtitle: _cycleLabels(teacher).join(', '),
                            ),
                            const SizedBox(height: 12),
                            _CardInfoRow(
                              icon: PhosphorIcons.mapPin,
                              iconColor: AppColors.primary,
                              title: teacher.city ?? 'Yaoundé',
                              subtitle: 'Near Santa Lucia',
                            ),
                            const SizedBox(height: 12),
                            _CardInfoRow(
                              icon: PhosphorIcons.clock,
                              iconColor: AppColors.primary,
                              title: 'Mon – Sat',
                              subtitle: 'After 4:00 PM',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: fading mini map with distance badge
                      _CardMiniMapWidget(
                        distanceLabel: item.distanceKm != null
                            ? (Geo.formatDistance(item.distanceKm!) ?? '—')
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 12),
                  // Rate & Availability
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.coins,
                                size: 22, color: Color(0xFF16A34A)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${teacher.hourlyRate.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} FCFA',
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.grey900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'per lesson',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.grey500,
                                      fontSize: 11.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 28, color: AppColors.divider),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const PhosphorIcon(PhosphorIcons.calendarBlank,
                                size: 22, color: Color(0xFF16A34A)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Available: ',
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.grey900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'Mon – Sat',
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.grey700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // Action Button (LinkedIn / Facebook card style)
                if (!compact) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'View Profile & Connect',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              letterSpacing: 0.1,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          PhosphorIcon(PhosphorIcons.arrowRight, size: 16, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// A rounded avatar marker for the map, with a selected-state halo. Kept small
/// and clean — no giant pins.
class TeacherMapMarker extends StatelessWidget {
  const TeacherMapMarker({
    super.key,
    required this.name,
    this.imageUrl,
    this.selected = false,
    this.isBest = false,
  });

  final String name;
  final String? imageUrl;
  final bool selected;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final ring = selected
        ? AppColors.primary
        : (isBest ? AppColors.primary : AppColors.white);
    final size = selected ? 46.0 : 38.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: selected ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      builder: (context, t, _) {
        return SizedBox(
          width: 64,
          height: 64,
          child: Center(
            child: Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(selected ? 3 : 2.5),
              decoration: BoxDecoration(
                color: ring,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary
                        .withValues(alpha: 0.35 * t),
                    blurRadius: 12 * t,
                    spreadRadius: 3 * t,
                  ),
                  BoxShadow(
                    color: AppColors.grey900.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AppAvatar(
                name: name,
                imageUrl: imageUrl,
                size: size - (selected ? 6 : 5),
                kind: AvatarKind.teacher,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Card Info Row ───────────────────────────────────────────────────────────

class _CardInfoRow extends StatelessWidget {
  const _CardInfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.iconContainerBg,
            shape: BoxShape.circle,
          ),
          child: PhosphorIcon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.grey900,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.grey500,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Card Mini Map Widget ─────────────────────────────────────────────────────

class _CardMiniMapWidget extends StatelessWidget {
  const _CardMiniMapWidget({this.distanceLabel});

  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      height: 130,
      child: Stack(
        children: [
          // Fading Gradient Map Canvas — no border
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    colors: [Colors.transparent, Colors.black, Colors.black],
                    stops: [0.0, 0.25, 1.0],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: Container(
                  color: const Color(0xFFE0F2FE),
                  child: RepaintBoundary(
                    child: CustomPaint(painter: const _CardMiniMapPainter()),
                  ),
                ),
              ),
            ),
          ),
          // Destination Pin
          Positioned(
            right: 18,
            top: 16,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x331051D1),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const PhosphorIcon(PhosphorIcons.graduationCap, color: Colors.white, size: 14),
            ),
          ),
          // Start dot
          Positioned(
            left: 14,
            bottom: 18,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
            ),
          ),
          // Distance badge overlay
          if (distanceLabel != null)
            Positioned(
              left: 6,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.93),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: 0.785,
                      child: const PhosphorIcon(PhosphorIcons.navigationArrow,
                          size: 13, color: AppColors.primary),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      distanceLabel!,
                      style: const TextStyle(
                        color: AppColors.grey900,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardMiniMapPainter extends CustomPainter {
  const _CardMiniMapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF1F5F9),
    );

    // Road grid
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Horizontal roads
    for (final y in [0.3, 0.55, 0.78]) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * y),
        roadPaint,
      );
    }
    // Vertical roads
    for (final x in [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * x, 0),
        Offset(size.width * x, size.height),
        roadPaint,
      );
    }

    // Green park block
    final parkPaint = Paint()..color = const Color(0xFFDCFCE7);
    canvas.drawRRect(
      RRect.fromLTRBR(
        size.width * 0.52,
        size.height * 0.38,
        size.width * 0.73,
        size.height * 0.65,
        const Radius.circular(6),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        size.width * 0.52,
        size.height * 0.38,
        size.width * 0.73,
        size.height * 0.65,
        const Radius.circular(6),
      ),
      Paint()
        ..color = const Color(0xFF86EFAC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Dashed route line
    final dashPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.82)
      ..cubicTo(
        size.width * 0.3, size.height * 0.6,
        size.width * 0.55, size.height * 0.55,
        size.width * 0.78, size.height * 0.22,
      );

    _drawDashedPath(canvas, path, dashPaint, dashLength: 6, gapLength: 5);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        if (draw) {
          final extracted = metric.extractPath(distance, distance + len);
          canvas.drawPath(extracted, paint);
        }
        distance += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
