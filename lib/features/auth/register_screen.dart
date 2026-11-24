import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../../core/auth/phone_credentials.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/models/user_role.dart';
import '../../core/services/auth_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/role_choice_selector.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _infoMessage;

  /// Chosen before the account is created so the very first question Camiva
  /// asks is "who are you?", not "what is your email?".
  UserRole? _selectedRole;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);

    if (_selectedRole == null) {
      setState(() => _errorMessage = l10n.registerRolePrompt);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    // Remembered for onboarding, which is where the profile row is written.
    AppState.of(context).setPendingRole(_selectedRole);

    final authService = AuthServiceScope.of(context);
    final result = await authService.register(
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
          _infoMessage = l10n.registerEmailConfirmation;
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
                Text(l10n.registerTitle, style: AppTextStyles.display),
                const SizedBox(height: AppConstants.space8),
                Text(l10n.registerSubtitle, style: AppTextStyles.bodyLarge),
                const SizedBox(height: AppConstants.space32),
                Text(l10n.registerRoleLabel, style: AppTextStyles.label),
                const SizedBox(height: AppConstants.space12),
                RoleChoiceSelector(
                  selected: _selectedRole,
                  enabled: !_isLoading,
                  onChanged: (role) => setState(() {
                    _selectedRole = role;
                    _errorMessage = null;
                  }),
                ),
                const SizedBox(height: AppConstants.space24),
                AppTextField(
                  key: const Key('register_phone_field'),
                  controller: _phoneController,
                  label: l10n.fieldPhone,
                  hint: '670 00 00 00',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                  validator: (v) => _validatePhone(v, l10n),
                ),
                const SizedBox(height: AppConstants.space16),
                AppTextField(
                  key: const Key('register_pin_field'),
                  controller: _pinController,
                  label: l10n.fieldPin,
                  hint: l10n.pinHelper,
                  keyboardType: TextInputType.number,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                  validator: (v) => _validatePin(v, l10n),
                  suffixIcon: _VisibilityToggle(
                    obscure: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppConstants.space16),
                AppTextField(
                  key: const Key('register_confirm_pin_field'),
                  controller: _confirmPinController,
                  label: l10n.fieldPinConfirm,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  enabled: !_isLoading,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => _validateConfirm(v, l10n),
                  suffixIcon: _VisibilityToggle(
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: AppConstants.space16),
                  _ErrorBanner(message: _errorMessage!),
                ],
                if (_infoMessage != null) ...[
                  const SizedBox(height: AppConstants.space16),
                  _InfoBanner(message: _infoMessage!),
                ],
                const SizedBox(height: AppConstants.space24),
                AppButton(
                  label: l10n.registerButton,
                  onPressed: _submit,
                  isLoading: _isLoading,
                  isFullWidth: true,
                ),
                const SizedBox(height: AppConstants.space24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.registerHaveAccount, style: AppTextStyles.body),
                    const SizedBox(width: AppConstants.space4),
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => context.go(AppRoutes.login),
                      child: Text(l10n.registerLoginLink),
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

  String? _validatePhone(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    // Accepts any form a person types; normalising is what decides validity.
    return PhoneCredentials.normalisePhone(value) == null
        ? l10n.validationPhoneInvalid
        : null;
  }

  String? _validatePin(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.validationRequired;
    return PhoneCredentials.isValidPin(value.trim())
        ? null
        : l10n.validationPinInvalid;
  }

  String? _validateConfirm(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.validationRequired;
    if (value != _pinController.text) return l10n.validationPinMismatch;
    return null;
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscure, required this.onToggle});
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: AppColors.grey500,
      ),
      onPressed: onToggle,
    );
  }
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.radius),
      ),
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.primary),
      ),
    );
  }
}
