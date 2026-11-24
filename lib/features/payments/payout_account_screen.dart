import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/withdrawal.dart';
import '../../core/services/earnings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

/// Where a teacher's withdrawals are sent.
///
/// Two things matter here. The number is validated before it is stored, because
/// a wrong payout number means money going to a stranger. And a teacher can
/// only ever write their own destination — the row is keyed by their own user
/// id and row-level security refuses anything else, so no one can redirect
/// another teacher's earnings.
///
/// The saved number is never shown in full again; only the last two digits.
class PayoutAccountScreen extends StatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen> {
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _medium = 'mobile money';
  String? _errorMessage;
  PayoutAccount? _existing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await EarningsServiceScope.of(context).fetchPayoutAccount();
    if (!mounted) return;
    if (result case PayoutAccountSuccess(:final account)) {
      setState(() {
        _existing = account;
        if (account != null) _medium = account.medium;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await EarningsServiceScope.of(context).savePayoutAccount(
      phone: _phoneController.text,
      medium: _medium,
    );
    if (!mounted) return;

    switch (result) {
      case PayoutAccountSuccess():
        Navigator.of(context).pop(true);
      case EarningsFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isSaving = false;
        });
      default:
        setState(() => _isSaving = false);
    }
  }

  bool get _isValid => PayoutAccount.isValidPhone(_phoneController.text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payout number')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.all(AppConstants.pageHorizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Where should we send your money?',
                        style: AppTextStyles.h2),
                    const SizedBox(height: AppConstants.space8),
                    Text(
                      'Withdrawals always go to this number. Only you can see '
                      'or change it.',
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.grey700),
                    ),
                    if (_existing != null) ...[
                      const SizedBox(height: AppConstants.space16),
                      Text('Current number: ${_existing!.maskedPhone}',
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.grey500)),
                    ],
                    const SizedBox(height: AppConstants.space24),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'mobile money', label: Text('MTN MoMo')),
                        ButtonSegment(
                            value: 'orange money', label: Text('Orange Money')),
                      ],
                      selected: {_medium},
                      onSelectionChanged: (selection) =>
                          setState(() => _medium = selection.first),
                    ),
                    const SizedBox(height: AppConstants.space16),
                    AppTextField(
                      key: const Key('payout_number_field'),
                      controller: _phoneController,
                      label: 'Mobile money number',
                      hint: '670000000',
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppConstants.space12),
                      Text(_errorMessage!,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.error)),
                    ],
                    const SizedBox(height: AppConstants.space24),
                    AppButton(
                      key: const Key('save_payout_button'),
                      label: 'Save number',
                      isFullWidth: true,
                      isLoading: _isSaving,
                      onPressed: _isValid ? _save : null,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
