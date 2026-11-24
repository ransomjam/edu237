import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/tutoring_agreement.dart';
import '../../core/services/tutoring_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/edu_ui.dart';
import 'tutoring_draft.dart';

/// What the teacher is proposing tutoring for.
class SetupTutoringArgs {
  const SetupTutoringArgs({
    required this.relationshipId,
    required this.childName,
    required this.subject,
    this.locationArea,
  });

  final String relationshipId;
  final String childName;
  final String subject;
  final String? locationArea;
}

/// The teacher sets the tutoring terms, in simple choices.
///
/// The student comes from the accepted relationship and is not selectable — a
/// teacher can only propose for the child they were actually asked about.
///
/// Camiva-managed payment is the normal option: it is what produces receipts,
/// payment history, reminders, earnings history and a record support can act
/// on. Paying the teacher directly stays possible, further down, stated plainly
/// and without any warning language.
class SetupTutoringScreen extends StatefulWidget {
  const SetupTutoringScreen({super.key, required this.args});

  final SetupTutoringArgs args;

  @override
  State<SetupTutoringScreen> createState() => _SetupTutoringScreenState();
}

class _SetupTutoringScreenState extends State<SetupTutoringScreen> {
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  LessonFrequency _frequency = LessonFrequency.twiceWeekly;
  int _customLessons = 4;
  int _lessonMinutes = 60;
  PriceUnit _priceUnit = PriceUnit.perLesson;
  TeachingModeChoice _mode = TeachingModeChoice.inPerson;
  AgreementPaymentMethod _paymentMethod = AgreementPaymentMethod.edu237;
  PaymentFrequency _paymentFrequency = PaymentFrequency.perMonth;

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  /// Set once the proposal is away, so leaving the screen does not resurrect a
  /// draft of terms that have already been sent.
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _areaController.text = widget.args.locationArea ?? '';

    // Restore anything typed before the teacher navigated away, so going back
    // to check something does not throw the form away.
    final draft = TutoringDraftStore.read(widget.args.relationshipId);
    if (draft != null) {
      _startDate = draft.startDate;
      _frequency = draft.frequency;
      _customLessons = draft.customLessons;
      _lessonMinutes = draft.lessonMinutes;
      _priceController.text = draft.priceText;
      _priceUnit = draft.priceUnit;
      _mode = draft.mode;
      _areaController.text = draft.area;
      _paymentMethod = draft.paymentMethod;
      _paymentFrequency = draft.paymentFrequency;
    }
  }

  @override
  void deactivate() {
    if (!_sent) _saveDraft();
    super.deactivate();
  }

  void _saveDraft() {
    TutoringDraftStore.save(
      widget.args.relationshipId,
      TutoringDraft(
        startDate: _startDate,
        frequency: _frequency,
        customLessons: _customLessons,
        lessonMinutes: _lessonMinutes,
        priceText: _priceController.text,
        priceUnit: _priceUnit,
        mode: _mode,
        area: _areaController.text,
        paymentMethod: _paymentMethod,
        paymentFrequency: _paymentFrequency,
      ),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  int get _lessonsPerWeek => _frequency == LessonFrequency.custom
      ? _customLessons
      : _frequency.lessonsPerWeek;

  int? get _price {
    final value = int.tryParse(_priceController.text.replaceAll(RegExp(r'\D'), ''));
    return (value == null || value < 100) ? null : value;
  }

  bool get _canSubmit => _price != null && !_isSubmitting;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await TutoringServiceScope.of(context).proposeAgreement(
      relationshipId: widget.args.relationshipId,
      subject: widget.args.subject,
      startDate: _startDate,
      frequency: _frequency,
      lessonsPerWeek: _lessonsPerWeek,
      lessonMinutes: _lessonMinutes,
      price: _price!,
      priceUnit: _priceUnit,
      teachingMode: _mode,
      locationArea: _mode == TeachingModeChoice.inPerson
          ? _areaController.text.trim()
          : null,
      paymentMethod: _paymentMethod,
      paymentFrequency: _paymentFrequency,
    );
    if (!mounted) return;

    setState(() => _isSubmitting = false);
    switch (result) {
      case AgreementSuccess():
        // Sent: the draft has become an agreement and should not linger.
        _sent = true;
        TutoringDraftStore.clear(widget.args.relationshipId);
        Navigator.of(context).pop(true);
      case TutoringFailure(:final message):
        setState(() => _errorMessage = message);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up tutoring')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          children: [
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.args.childName, style: AppTextStyles.h3),
                        const SizedBox(height: AppConstants.space2),
                        Text(widget.args.subject,
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.grey500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'Start date'),
            AppButton(
              key: const Key('pick_start_date'),
              label: formatShortDate(_startDate),
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              leading: const Icon(Icons.event_outlined, size: 18),
              onPressed: _pickDate,
            ),
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'How often'),
            _Choices<LessonFrequency>(
              values: LessonFrequency.values,
              selected: _frequency,
              labelOf: (f) => f.label,
              keyOf: (f) => 'frequency_${f.value}',
              onChanged: (f) => setState(() => _frequency = f),
            ),
            if (_frequency == LessonFrequency.custom) ...[
              const SizedBox(height: AppConstants.space12),
              _Stepper(
                key: const Key('custom_lessons_stepper'),
                label: 'Lessons per week',
                value: _customLessons,
                min: 1,
                max: 14,
                onChanged: (v) => setState(() => _customLessons = v),
              ),
            ],
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'Lesson length'),
            _Choices<int>(
              values: const [30, 45, 60, 90, 120],
              selected: _lessonMinutes,
              labelOf: _durationLabel,
              keyOf: (m) => 'duration_$m',
              onChanged: (m) => setState(() => _lessonMinutes = m),
            ),
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'Agreed price'),
            AppTextField(
              key: const Key('price_field'),
              controller: _priceController,
              label: 'Amount (FCFA)',
              hint: '5000',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppConstants.space12),
            _Choices<PriceUnit>(
              values: PriceUnit.values,
              selected: _priceUnit,
              labelOf: (u) => u.label,
              keyOf: (u) => 'price_unit_${u.value}',
              onChanged: (u) => setState(() => _priceUnit = u),
            ),
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'Where'),
            _Choices<TeachingModeChoice>(
              values: TeachingModeChoice.values,
              selected: _mode,
              labelOf: (m) => m.label,
              keyOf: (m) => 'mode_${m.value}',
              onChanged: (m) => setState(() => _mode = m),
            ),
            if (_mode == TeachingModeChoice.inPerson) ...[
              const SizedBox(height: AppConstants.space12),
              AppTextField(
                key: const Key('area_field'),
                controller: _areaController,
                label: 'Area',
                hint: 'Bastos',
              ),
              const SizedBox(height: AppConstants.space4),
              Text(
                'The area only — never a full home address.',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.grey500),
              ),
            ],
            const SizedBox(height: AppConstants.space24),

            const SectionHeader(title: 'How the parent pays'),
            // Tutoring obtained through Camiva is managed through Camiva -
            // that is the agreement the teacher accepted, so there is nothing
            // to choose here.
            const _CamivaPaymentNote(),
            const SizedBox(height: AppConstants.space12),
            _Choices<PaymentFrequency>(
              values: PaymentFrequency.values,
              selected: _paymentFrequency,
              labelOf: (f) => f.label,
              keyOf: (f) => 'payment_frequency_${f.value}',
              onChanged: (f) => setState(() => _paymentFrequency = f),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: AppConstants.space16),
              Container(
                key: const Key('proposal_error'),
                padding: const EdgeInsets.all(AppConstants.space12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(_errorMessage!,
                    style: AppTextStyles.body.copyWith(color: AppColors.error)),
              ),
            ],

            const SizedBox(height: AppConstants.space24),
            AppButton(
              key: const Key('send_proposal_button'),
              label: 'Send to parent',
              isFullWidth: true,
              isLoading: _isSubmitting,
              onPressed: _canSubmit ? _submit : null,
            ),
            const SizedBox(height: AppConstants.space12),
            Text(
              'The parent reviews these details and confirms before anything '
              'else happens.',
              style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(int minutes) => switch (minutes) {
        30 => '30 min',
        45 => '45 min',
        60 => '1 hour',
        90 => '1.5 hours',
        _ => '2 hours',
      };
}

/// A row of single-choice chips.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.keyOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final String Function(T) keyOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppConstants.space8,
      runSpacing: AppConstants.space8,
      children: [
        for (final value in values)
          ChoiceChip(
            key: Key(keyOf(value)),
            label: Text(labelOf(value)),
            selected: value == selected,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.body)),
        IconButton(
          key: const Key('stepper_minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: AppTextStyles.h3),
        IconButton(
          key: const Key('stepper_plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// Camiva-managed payment, stated rather than chosen.
///
/// The teacher agreed to Camiva-managed payments when they accepted the
/// request, so offering "direct to you" here would contradict the agreement
/// they already made.
class _CamivaPaymentNote extends StatelessWidget {
  const _CamivaPaymentNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('edu237_payment_note'),
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 20, color: AppColors.primary),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Camiva-managed', style: AppTextStyles.h3),
                const SizedBox(height: AppConstants.space4),
                Text(
                  'The parent pays through Camiva. You get payment records, '
                  'reminders and earnings history, and Camiva follows up on '
                  'payment so you do not have to.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.grey700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
