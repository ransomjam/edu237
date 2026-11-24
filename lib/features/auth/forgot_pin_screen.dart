import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/phone_credentials.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

/// Recovering a forgotten PIN.
///
/// This is the only place Camiva sends a code. Normal sign-in stays phone plus
/// PIN with no SMS, because a code on every sign-in is friction people do not
/// need — and a cost the platform does not need either.
///
/// Two steps, on one screen: ask for the code, then enter it with the new PIN.
/// The new PIN is turned into a secret on this device before anything is sent,
/// so the PIN itself never travels.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

enum _Step { enterPhone, enterCode, done }

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.enterPhone;
  bool _isWorking = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final phone = PhoneCredentials.normalisePhone(_phoneController.text);
    if (phone == null) {
      setState(() =>
          _errorMessage = 'Enter a valid number, e.g. 670 00 00 00.');
      return;
    }

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    final result = await AuthServiceScope.of(context).requestPinReset(phone);
    if (!mounted) return;

    setState(() {
      _isWorking = false;
      switch (result) {
        case PinResetRequested():
          // Always moves on, whether or not that number has an account.
          _step = _Step.enterCode;
        case AuthFailure(:final message):
          _errorMessage = message;
        default:
          _step = _Step.enterCode;
      }
    });
  }

  Future<void> _confirm() async {
    if (_pinController.text != _confirmController.text) {
      setState(() => _errorMessage = 'The two PINs do not match.');
      return;
    }

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    final result = await AuthServiceScope.of(context).confirmPinReset(
      phone: _phoneController.text,
      code: _codeController.text,
      newPin: _pinController.text,
    );
    if (!mounted) return;

    setState(() {
      _isWorking = false;
      switch (result) {
        case PinResetComplete():
          _step = _Step.done;
        case AuthFailure(:final message):
          _errorMessage = message;
        default:
          _errorMessage = 'That code is not valid.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          children: [
            switch (_step) {
              _Step.enterPhone => _phoneStep(),
              _Step.enterCode => _codeStep(),
              _Step.done => _doneStep(),
            },
          ],
        ),
      ),
    );
  }

  Widget _phoneStep() {
    return Column(
      key: const Key('forgot_pin_phone_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space16),
        Text('Reset your PIN', style: AppTextStyles.h1),
        const SizedBox(height: AppConstants.space8),
        Text(
          'We will send a code by SMS to your registered number.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
        ),
        const SizedBox(height: AppConstants.space24),
        AppTextField(
          key: const Key('forgot_phone_field'),
          controller: _phoneController,
          label: 'Phone number',
          hint: '670 00 00 00',
          keyboardType: TextInputType.phone,
          autofocus: true,
          enabled: !_isWorking,
        ),
        _error(),
        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('send_code_button'),
          label: 'Send code',
          isFullWidth: true,
          isLoading: _isWorking,
          onPressed: _isWorking ? null : _requestCode,
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      key: const Key('forgot_pin_code_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space16),
        Text('Enter the code', style: AppTextStyles.h1),
        const SizedBox(height: AppConstants.space8),
        Text(
          'If that number has an account, a 6-digit code has been sent to it. '
          'It expires in 10 minutes.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
        ),
        const SizedBox(height: AppConstants.space24),
        AppTextField(
          key: const Key('reset_code_field'),
          controller: _codeController,
          label: 'Code',
          hint: '123456',
          keyboardType: TextInputType.number,
          autofocus: true,
          enabled: !_isWorking,
        ),
        const SizedBox(height: AppConstants.space16),
        AppTextField(
          key: const Key('new_pin_field'),
          controller: _pinController,
          label: 'New PIN',
          hint: 'Choose 4 to 6 digits you will remember.',
          keyboardType: TextInputType.number,
          obscureText: true,
          enabled: !_isWorking,
        ),
        const SizedBox(height: AppConstants.space16),
        AppTextField(
          key: const Key('confirm_new_pin_field'),
          controller: _confirmController,
          label: 'Confirm new PIN',
          keyboardType: TextInputType.number,
          obscureText: true,
          enabled: !_isWorking,
        ),
        _error(),
        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('confirm_reset_button'),
          label: 'Set new PIN',
          isFullWidth: true,
          isLoading: _isWorking,
          onPressed: _isWorking ? null : _confirm,
        ),
        const SizedBox(height: AppConstants.space8),
        AppButton(
          key: const Key('resend_code_button'),
          label: 'Send another code',
          variant: AppButtonVariant.outlined,
          isFullWidth: true,
          onPressed: _isWorking ? null : _requestCode,
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      key: const Key('forgot_pin_done_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.space40),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 34, color: AppColors.success),
          ),
        ),
        const SizedBox(height: AppConstants.space20),
        Text('PIN changed', style: AppTextStyles.h2, textAlign: TextAlign.center),
        const SizedBox(height: AppConstants.space8),
        Text(
          'Sign in with your number and your new PIN.',
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.space24),
        AppButton(
          key: const Key('back_to_login_button'),
          label: 'Sign in',
          isFullWidth: true,
          onPressed: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }

  Widget _error() {
    if (_errorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.space16),
      child: Container(
        key: const Key('forgot_pin_error'),
        padding: const EdgeInsets.all(AppConstants.space12),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(_errorMessage!,
            style: AppTextStyles.body.copyWith(color: AppColors.error)),
      ),
    );
  }
}
