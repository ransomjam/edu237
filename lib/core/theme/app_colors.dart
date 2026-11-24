import 'package:flutter/material.dart';

/// Camiva exact UI colour palette.
///
/// Features the signature geometric royal-blue-to-cyan header gradient,
/// soft ice-blue pill accents, crisp white cards, and modern slate typography.
abstract final class AppColors {
  // --- Brand & Gradients ---
  static const Color primary = Color(0xFF1051D1); // Vibrant royal blue
  static const Color primaryDark = Color(0xFF0A3BA3);
  static const Color primaryLight = Color(0xFFE9F1FF); // Soft ice blue (tags/pills)
  static const Color primaryAzure = Color(0xFF0E9DDF); // Mid gradient blue
  static const Color primaryCyan = Color(0xFF04C7D9); // Turquoise / cyan gradient end

  /// Signature header gradient: royal blue → azure → cyan
  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF1051D1), Color(0xFF0E9DDF), Color(0xFF04C7D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Primary button vibrant gradient
  static const LinearGradient buttonGradient = LinearGradient(
    colors: [Color(0xFF1051D1), Color(0xFF044ED5)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // --- UI Containers ---
  static const Color iconContainerBg = Color(0xFFE8F4FD); // Light cyan/blue container
  static const Color navPillBg = Color(0xFFEBF2FF); // Active bottom nav indicator pill
  static const Color tagBorder = Color(0xFFBFDBFE); // Soft border for subject pills

  // --- Neutrals & Typography ---
  static const Color grey900 = Color(0xFF0F172A); // Dark slate navy
  static const Color grey700 = Color(0xFF334155); // Slate body
  static const Color grey500 = Color(0xFF64748B); // Slate muted
  static const Color grey300 = Color(0xFFCBD5E1); // Slate border
  static const Color grey100 = Color(0xFFF1F5F9); // Light container fill
  static const Color white = Color(0xFFFFFFFF);

  // --- Semantic ---
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444); // Badge & error red
  static const Color errorLight = Color(0xFFFEE2E2);

  // --- Surface & Scaffolding ---
  static const Color surface = white;
  static const Color background = Color(0xFFF0F7FD); // Soft sky tint
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);
}
