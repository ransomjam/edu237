import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../../core/auth/phone_credentials.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations.of(context);
    final authService = AuthServiceScope.of(context);
    final result = await authService.signIn(
      phone: _phoneController.text,
      pin: _pinController.text,
    );

    if (!mounted) return;

    switch (result) {
      case AuthSuccess(:final user):
        AppState.of(context).setUser(user);
        context.go(AppRoutes.home);
      case AuthNeedsEmailConfirmation():
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.errorGeneric;
        });
      case PinResetRequested():
      case PinResetComplete():
        // Recovery results never come from this screen.
        break;
      case AuthFailure(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.pageHorizontalPadding,
            vertical: AppConstants.space32,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppConstants.space32),
                Text(l10n.loginTitle, style: AppTextStyles.display),
                const SizedBox(height: AppConstants.space8),
                Text(l10n.loginSubtitle, style: AppTextStyles.bodyLarge),
                const SizedBox(height: AppConstants.space40),
                AppTextField(
                  key: const Key('login_phone_field'),
                  controller: _phoneController,
                  label: l10n.fieldPhone,
                  hint: '670 00 00 00',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  enabled: !_isLoading,
                  validator: (v) => _validatePhone(v, l10n),
                ),
                const SizedBox(height: AppConstants.space16),
                AppTextField(
                  key: const Key('login_pin_field'),
                  controller: _pinController,
                  label: l10n.fieldPin,
                  keyboardType: TextInputType.number,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  enabled: !_isLoading,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => _validatePin(v, l10n),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.grey500,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppConstants.space16),
                  _ErrorBanner(message: _errorMessage!),
                ],
                const SizedBox(height: AppConstants.space24),
                AppButton(
                  label: l10n.loginButton,
                  onPressed: _submit,
                  isLoading: _isLoading,
                  isFullWidth: true,
                ),
                const SizedBox(height: AppConstants.space8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgot_pin_link'),
                    onPressed: _isLoading
                        ? null
                        : () => context.push(AppRoutes.forgotPin),
                    child: const Text('Forgot PIN?'),
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.loginNoAccount, style: AppTextStyles.body),
                    const SizedBox(width: AppConstants.space4),
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => context.go(AppRoutes.register),
                      child: Text(l10n.loginRegisterLink),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// A number in any form a person types, checked before a request is made.
String? _validatePhone(String? value, AppLocalizations l10n) {
  if ((value ?? '').trim().isEmpty) return l10n.validationRequired;
  return PhoneCredentials.normalisePhone(value!) == null
      ? l10n.validationPhoneInvalid
      : null;
}

String? _validatePin(String? value, AppLocalizations l10n) {
  if ((value ?? '').trim().isEmpty) return l10n.validationRequired;
  return PhoneCredentials.isValidPin(value!.trim())
      ? null
      : l10n.validationPinInvalid;
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppConstants.radius),
      ),
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.error),
      ),
    );
  }
}
