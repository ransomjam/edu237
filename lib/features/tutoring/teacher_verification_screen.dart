import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/teacher_verification.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/edu_ui.dart';

/// Camiva's trust check: an identity document and a qualification document,
/// reviewed remotely.
///
/// This is a trust gate, not a revenue gate — nothing is charged here. It comes
/// before the Platform Charge because Camiva should not take money to activate a
/// teacher it has not checked.
///
/// Submitting moves the teacher to "pending" and no further. Only Camiva can
/// mark someone verified, so nothing on this screen ever says "verified" on the
/// strength of an upload.
class TeacherVerificationScreen extends StatefulWidget {
  const TeacherVerificationScreen({super.key, this.onVerified});

  /// Called when the screen closes with the teacher already verified, so the
  /// caller can continue the flow.
  final VoidCallback? onVerified;

  @override
  State<TeacherVerificationScreen> createState() =>
      _TeacherVerificationScreenState();
}

class _TeacherVerificationScreenState extends State<TeacherVerificationScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  TeacherVerification _verification = TeacherVerification.none;

  IdentityDocType _idType = IdentityDocType.nationalId;
  final TextEditingController _qualificationController =
      TextEditingController();

  XFile? _idFile;
  XFile? _qualificationFile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  @override
  void dispose() {
    _qualificationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await TutoringServiceScope.of(context).fetchMyVerification();
    if (!mounted) return;
    switch (result) {
      case VerificationSuccess(:final verification):
        setState(() {
          _verification = verification;
          _isLoading = false;
        });
      case TutoringFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      default:
        setState(() => _isLoading = false);
    }
  }

  Future<void> _pick(bool isIdentity) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() {
      if (isIdentity) {
        _idFile = file;
      } else {
        _qualificationFile = file;
      }
    });
  }

  bool get _canSubmit =>
      _idFile != null && _qualificationFile != null && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final service = TutoringServiceScope.of(context);
    final idPath = await service.uploadVerificationDoc(
      fileName: _idFile!.name,
      bytes: await _idFile!.readAsBytes(),
      contentType: _idFile!.mimeType ?? 'image/jpeg',
    );
    final qualificationPath = await service.uploadVerificationDoc(
      fileName: _qualificationFile!.name,
      bytes: await _qualificationFile!.readAsBytes(),
      contentType: _qualificationFile!.mimeType ?? 'image/jpeg',
    );
    if (!mounted) return;

    if (idPath == null || qualificationPath == null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not upload your documents. Please try again.';
      });
      return;
    }

    final result = await service.submitVerification(
      identityDocPath: idPath,
      identityDocType: _idType,
      qualificationDocPath: qualificationPath,
      qualificationTitle: _qualificationController.text.trim(),
    );
    if (!mounted) return;

    setState(() => _isSubmitting = false);
    switch (result) {
      case VerificationSuccess(:final verification):
        setState(() => _verification = verification);
      case TutoringFailure(:final message):
        setState(() => _errorMessage = message);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = _verification.status;

    // Submitted and waiting, or already verified: there is nothing to fill in.
    if (status == VerificationStatus.pending ||
        status == VerificationStatus.verified) {
      return _StatusView(
        key: Key('verification_${status.value}'),
        status: status,
        onDone: status.isVerified
            ? () {
                widget.onVerified?.call();
                Navigator.of(context).pop(true);
              }
            : null,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      children: [
        Text(status.label, style: AppTextStyles.h2),
        const SizedBox(height: AppConstants.space8),
        Text(status.message,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700)),
        if (status == VerificationStatus.rejected &&
            (_verification.rejectionReason ?? '').isNotEmpty) ...[
          const SizedBox(height: AppConstants.space16),
          _Banner(
            key: const Key('verification_rejection'),
            message: _verification.rejectionReason!,
          ),
        ],
        const SizedBox(height: AppConstants.space24),

        const SectionHeader(title: 'Identity'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppConstants.space8,
                children: [
                  for (final type in IdentityDocType.values)
                    ChoiceChip(
                      key: Key('id_type_${type.value}'),
                      label: Text(type.label),
                      selected: _idType == type,
                      onSelected: (_) => setState(() => _idType = type),
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.space12),
              _DocPicker(
                key: const Key('pick_identity_doc'),
                label: 'Photo of your ID',
                fileName: _idFile?.name,
                onPick: () => _pick(true),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space24),

        const SectionHeader(title: 'Qualification'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                key: const Key('qualification_title_field'),
                controller: _qualificationController,
                label: 'Qualification (optional)',
                hint: 'BSc Mathematics',
              ),
              const SizedBox(height: AppConstants.space12),
              _DocPicker(
                key: const Key('pick_qualification_doc'),
                label: 'Photo of your certificate',
                fileName: _qualificationFile?.name,
                onPick: () => _pick(false),
              ),
            ],
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: AppConstants.space16),
          _Banner(key: const Key('verification_error'), message: _errorMessage!),
        ],

        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('submit_verification_button'),
          label: 'Send for verification',
          isFullWidth: true,
          isLoading: _isSubmitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: AppConstants.space12),
        Text(
          'Your documents are private. Only Camiva can see them.',
          style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({super.key, required this.status, this.onDone});

  final VerificationStatus status;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final verified = status.isVerified;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: verified ? AppColors.successLight : AppColors.warningLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                verified ? Icons.verified_outlined : Icons.hourglass_top_rounded,
                size: 34,
                color: verified ? AppColors.success : AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space20),
          Text(status.label,
              style: AppTextStyles.h2, textAlign: TextAlign.center),
          const SizedBox(height: AppConstants.space8),
          Text(
            status.message,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
            textAlign: TextAlign.center,
          ),
          if (onDone != null) ...[
            const SizedBox(height: AppConstants.space24),
            AppButton(
              key: const Key('verification_continue_button'),
              label: 'Continue',
              isFullWidth: true,
              onPressed: onDone,
            ),
          ],
        ],
      ),
    );
  }
}

class _DocPicker extends StatelessWidget {
  const _DocPicker({
    super.key,
    required this.label,
    required this.fileName,
    required this.onPick,
  });

  final String label;
  final String? fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final chosen = (fileName ?? '').isNotEmpty;
    return AppButton(
      label: chosen ? 'Change document' : label,
      variant: AppButtonVariant.outlined,
      isFullWidth: true,
      leading: Icon(chosen ? Icons.check_circle_outline : Icons.upload_outlined,
          size: 18),
      onPressed: onPick,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppConstants.space8),
          Expanded(
            child: Text(message,
                style: AppTextStyles.body.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
