import 'package:flutter/material.dart';

/// Reusable Phosphor icon widget that renders monochrome Phosphor PNG assets
/// with custom sizing and color tinting via [BlendMode.srcIn].
class PhosphorIcon extends StatelessWidget {
  const PhosphorIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
  });

  /// The name of the Phosphor icon (without the .png extension).
  final String name;

  /// The size (width and height) of the icon in logical pixels.
  final double size;

  /// Optional color to tint the icon with. If null, renders with current icon theme or default color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color;
    final cleanName = name.replaceAll('.png', '');
    final cacheDim = (size * 2).clamp(32, 96).round();

    return RepaintBoundary(
      child: Image.asset(
        'assets/icons/phosphor/$cleanName.png',
        width: size,
        height: size,
        cacheWidth: cacheDim,
        cacheHeight: cacheDim,
        filterQuality: FilterQuality.low,
        color: effectiveColor,
        colorBlendMode: effectiveColor != null ? BlendMode.srcIn : null,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.circle,
            size: size * 0.4,
            color: effectiveColor?.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  /// Resolves an appropriate Phosphor icon for a school subject (no emojis).
  static String iconForSubject(String subject) {
    final s = subject.trim().toLowerCase();
    if (s.contains('physic')) return PhosphorIcons.atom;
    if (s.contains('chem')) return PhosphorIcons.flask;
    if (s.contains('math') || s.contains('arith')) return PhosphorIcons.calculator;
    if (s.contains('bio') || s.contains('life') || s.contains('scien')) return PhosphorIcons.dna;
    if (s.contains('eng') || s.contains('fren') || s.contains('lang') || s.contains('litt')) {
      return PhosphorIcons.bookOpen;
    }
    if (s.contains('geo')) return PhosphorIcons.globe;
    if (s.contains('hist')) return PhosphorIcons.books;
    if (s.contains('econ') || s.contains('comm') || s.contains('acc')) return PhosphorIcons.chartBar;
    if (s.contains('comp') || s.contains('ict') || s.contains('tech')) return PhosphorIcons.code;
    return PhosphorIcons.graduationCap;
  }
}

/// Constant names for the Phosphor icons used across Camiva.
abstract final class PhosphorIcons {
  // Navigation & Shell
  static const house = 'house';
  static const houseFill = 'house-fill';
  static const wallet = 'wallet';
  static const walletFill = 'wallet-fill';
  static const bell = 'bell';
  static const bellFill = 'bell-fill';
  static const user = 'user';
  static const userFill = 'user-fill';
  static const users = 'users';
  static const bookOpen = 'book-open';
  static const bookOpenFill = 'book-open-fill';
  static const graduationCap = 'graduation-cap';
  static const graduationCapFill = 'graduation-cap-fill';
  static const student = 'student';
  static const studentFill = 'student-fill';
  static const chalkboardTeacher = 'chalkboard-teacher';

  // Actions & Controls
  static const plus = 'plus';
  static const plusBold = 'plus-bold';
  static const plusCircle = 'plus-circle';
  static const magnifyingGlass = 'magnifying-glass';
  static const pencilSimple = 'pencil-simple';
  static const pencil = 'pencil';
  static const notePencil = 'note-pencil';
  static const trash = 'trash';
  static const check = 'check';
  static const checkCircle = 'check-circle';
  static const checkCircleFill = 'check-circle-fill';
  static const checkBold = 'check-bold';
  static const x = 'x';
  static const xCircle = 'x-circle';
  static const gear = 'gear';
  static const gearFill = 'gear-fill';
  static const signOut = 'sign-out';
  static const copy = 'copy';
  static const sparkle = 'sparkle';

  // Chevrons & Arrows
  static const caretRight = 'caret-right';
  static const caretLeft = 'caret-left';
  static const caretDown = 'caret-down';
  static const caretUp = 'caret-up';
  static const arrowRight = 'arrow-right';
  static const arrowLeft = 'arrow-left';
  static const arrowUp = 'arrow-up';
  static const arrowDown = 'arrow-down';
  static const arrowClockwise = 'arrow-clockwise';
  static const arrowCounterClockwise = 'arrow-counter-clockwise';

  // Scheduling & Dates
  static const calendar = 'calendar';
  static const calendarBlank = 'calendar-blank';
  static const calendarCheck = 'calendar-check';
  static const clock = 'clock';
  static const timer = 'timer';

  // Location & Map
  static const mapPin = 'map-pin';
  static const mapPinFill = 'map-pin-fill';
  static const mapTrifold = 'map-trifold';
  static const navigationArrow = 'navigation-arrow';

  // Devices & Media
  static const videoCamera = 'video-camera';
  static const video = 'video';
  static const camera = 'camera';
  static const desktop = 'desktop';
  static const laptop = 'laptop';
  static const receipt = 'receipt';

  // Communication
  static const phone = 'phone';
  static const phoneCall = 'phone-call';
  static const chatCircle = 'chat-circle';
  static const chatCircleDots = 'chat-circle-dots';
  static const whatsappLogo = 'whatsapp-logo';

  // Subjects & Education
  static const flask = 'flask';
  static const atom = 'atom';
  static const calculator = 'calculator';
  static const dna = 'dna';
  static const globe = 'globe';
  static const books = 'books';
  static const chartBar = 'chart-bar';
  static const fileText = 'file-text';
  static const listBullets = 'list-bullets';
  static const code = 'code';

  // Finance & Badges
  static const coins = 'coins';
  static const creditCard = 'credit-card';
  static const currencyCircleDollar = 'currency-circle-dollar';
  static const star = 'star';
  static const starFill = 'star-fill';
  static const shield = 'shield';
  static const shieldCheck = 'shield-check';
  static const shieldCheckFill = 'shield-check-fill';
  static const lock = 'lock';
  static const lockKey = 'lock-key';

  // Status & Alerts
  static const warning = 'warning';
  static const warningCircle = 'warning-circle';
  static const info = 'info';
  static const eye = 'eye';
  static const eyeSlash = 'eye-slash';
  static const funnel = 'funnel';
  static const shareNetwork = 'share-network';
  static const downloadSimple = 'download-simple';
  static const uploadSimple = 'upload-simple';
}
