import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// The signature Camiva geometric faceted header.
///
/// Features the exact royal-blue-to-cyan gradient with translucent geometric
/// polygons / facets as seen in the new UI design.
class GeometricHeader extends StatelessWidget {
  const GeometricHeader({
    super.key,
    required this.child,
    this.padding,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      child: Stack(
        children: [
          // Geometric faceted overlay
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: const _FacetedGeometryPainter(),
              ),
            ),
          ),
          // Content
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Paints subtle translucent faceted triangles / polygons to achieve the
/// exact geometric crystalline aesthetic shown in the reference UI.
class _FacetedGeometryPainter extends CustomPainter {
  const _FacetedGeometryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint1 = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final paint2 = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    final paint3 = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    // Facet 1: Angular sweep from top right
    final path1 = Path()
      ..moveTo(w * 0.45, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.75)
      ..lineTo(w * 0.65, h)
      ..close();
    canvas.drawPath(path1, paint1);

    // Facet 2: Intersecting wedge across center-right
    final path2 = Path()
      ..moveTo(w * 0.25, 0)
      ..lineTo(w * 0.85, 0)
      ..lineTo(w, h * 0.45)
      ..lineTo(w * 0.55, h * 0.85)
      ..close();
    canvas.drawPath(path2, paint2);

    // Facet 3: Lower left subtle facet
    final path3 = Path()
      ..moveTo(0, h * 0.4)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
