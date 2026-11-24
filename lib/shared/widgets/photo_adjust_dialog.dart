import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_button.dart';

/// Modal dialog for zooming, panning, and framing a photo before upload.
class PhotoAdjustDialog extends StatefulWidget {
  const PhotoAdjustDialog({
    super.key,
    required this.imageBytes,
    this.aspectRatio = 1.0,
    this.title = 'Adjust Photo',
  });

  final Uint8List imageBytes;
  final double aspectRatio;
  final String title;

  /// Shows the dialog and returns the adjusted/cropped image bytes, or null if cancelled.
  static Future<Uint8List?> show(
    BuildContext context,
    Uint8List imageBytes, {
    double aspectRatio = 1.0,
    String title = 'Adjust Photo',
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PhotoAdjustDialog(
        imageBytes: imageBytes,
        aspectRatio: aspectRatio,
        title: title,
      ),
    );
  }

  @override
  State<PhotoAdjustDialog> createState() => _PhotoAdjustDialogState();
}

class _PhotoAdjustDialogState extends State<PhotoAdjustDialog> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformController =
      TransformationController();
  double _scale = 1.0;
  bool _isProcessing = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _onSliderChanged(double value) {
    setState(() {
      _scale = value;
      _transformController.value = Matrix4.diagonal3Values(value, value, 1.0);
    });
  }

  Future<void> _capture() async {
    setState(() => _isProcessing = true);
    try {
      final boundary =
          _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop(widget.imageBytes);
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) Navigator.of(context).pop(widget.imageBytes);
        return;
      }
      final cropped = byteData.buffer.asUint8List();
      if (mounted) {
        Navigator.of(context).pop(cropped);
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop(widget.imageBytes);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cropWidth = 280.0;
    final double cropHeight = (cropWidth / widget.aspectRatio).clamp(140.0, 280.0);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      insetPadding: const EdgeInsets.all(AppConstants.space16),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title, style: AppTextStyles.h3),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.grey500),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Drag to position and pinch or use the slider to zoom.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space16),

            // --- Crop Viewport ---
            Center(
              child: Container(
                width: cropWidth,
                height: cropHeight,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RepaintBoundary(
                    key: _cropKey,
                    child: SizedBox(
                      width: cropWidth,
                      height: cropHeight,
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 0.5,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(200),
                        onInteractionUpdate: (details) {
                          final currentScale =
                              _transformController.value.getMaxScaleOnAxis();
                          if (currentScale != _scale && mounted) {
                            setState(() {
                              _scale = currentScale.clamp(0.5, 5.0);
                            });
                          }
                        },
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppConstants.space16),

            // --- Zoom Slider ---
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 20, color: AppColors.grey500),
                Expanded(
                  child: Slider(
                    value: _scale.clamp(0.5, 5.0),
                    min: 0.5,
                    max: 5.0,
                    activeColor: AppColors.primary,
                    onChanged: _onSliderChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 20, color: AppColors.grey500),
              ],
            ),

            const SizedBox(height: AppConstants.space16),

            // --- Action Buttons ---
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.outlined,
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: AppButton(
                    label: 'Set Photo',
                    isLoading: _isProcessing,
                    onPressed: _isProcessing ? null : _capture,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
