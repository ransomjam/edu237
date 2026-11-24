import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/tutoring_agreement.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_format.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

/// The agreed terms, laid out as a contract both sides can read back at any
/// time — and copy out of the app if they want their own record.
///
/// This is a plain, readable summary of the structured agreement, not a
/// separate document: the agreement in the database stays the source of truth,
/// so what is shown here can never drift from what was actually agreed.
class ContractView extends StatelessWidget {
  const ContractView({
    super.key,
    required this.agreement,
    required this.childName,
    required this.teacherName,
    required this.parentName,
  });

  final TutoringAgreement agreement;
  final String childName;
  final String teacherName;
  final String parentName;

  /// The contract as text, for copying or sharing outside the app.
  String get asText {
    final a = agreement;
    return [
      'EDU237 TUTORING ARRANGEMENT',
      '',
      'Student: $childName',
      'Subject: ${a.subject}',
      'Teacher: $teacherName',
      'Parent: $parentName',
      '',
      'Starts: ${formatShortDate(a.startDate)}',
      'How often: ${a.frequencyLabel}',
      'Each lesson: ${a.durationLabel}',
      'Price: ${a.formattedPrice}',
      'Where: ${a.modeLabel}',
      '',
      'Payment: ${a.paymentMethod.label}',
      'Billed: ${a.paymentFrequency.label}',
      '',
      'Proposed: ${formatShortDate(a.proposedAt)}',
      if (a.parentConfirmedAt != null)
        'Confirmed by parent: ${formatShortDate(a.parentConfirmedAt!)}',
      if (a.teacherActivatedAt != null)
        'Activated: ${formatShortDate(a.teacherActivatedAt!)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final a = agreement;
    return AppCard(
      key: const Key('contract_view'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppConstants.space8),
              Text('Tutoring arrangement', style: AppTextStyles.h3),
              const Spacer(),
              _StatusPill(status: a.status),
            ],
          ),
          const SizedBox(height: AppConstants.space12),
          _Line(label: 'Student', value: childName),
          _Line(label: 'Subject', value: a.subject),
          _Line(label: 'Teacher', value: teacherName),
          const Divider(height: AppConstants.space24),
          _Line(label: 'Starts', value: formatShortDate(a.startDate)),
          _Line(label: 'How often', value: a.frequencyLabel),
          _Line(label: 'Each lesson', value: a.durationLabel),
          _Line(label: 'Price', value: a.formattedPrice),
          _Line(label: 'Where', value: a.modeLabel),
          const Divider(height: AppConstants.space24),
          _Line(label: 'Payment', value: a.paymentMethod.label),
          _Line(label: 'Billed', value: a.paymentFrequency.label),
          const SizedBox(height: AppConstants.space16),
          AppButton(
            key: const Key('copy_contract_button'),
            label: 'Copy details',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            leading: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: asText));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Arrangement copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Call and WhatsApp, for talking the details through before agreeing them.
///
/// Shown only where the other person's number is actually available under the
/// existing rules — this widget renders nothing without one, so it can never be
/// used to work around who is allowed to see whose contact details.
class ContactActions extends StatelessWidget {
  const ContactActions({
    super.key,
    required this.phone,
    required this.name,
    this.message,
  });

  /// The counterpart's number, or null when it is not available yet.
  final String? phone;
  final String name;

  /// Prefilled WhatsApp text, e.g. the tutoring details to discuss.
  final String? message;

  /// Cameroon numbers are stored as 9 digits; both links need the country code.
  String get _international => '237${phone!.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _call() async {
    await launchUrl(Uri.parse('tel:+$_international'));
  }

  Future<void> _whatsapp() async {
    final text = (message ?? '').isEmpty
        ? ''
        : '?text=${Uri.encodeComponent(message!)}';
    await launchUrl(
      Uri.parse('https://wa.me/$_international$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((phone ?? '').isEmpty) return const SizedBox.shrink();

    return Row(
      key: const Key('contact_actions'),
      children: [
        Expanded(
          child: AppButton(
            key: const Key('call_button'),
            label: 'Call',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            leading: const Icon(Icons.call_outlined, size: 18),
            onPressed: _call,
          ),
        ),
        const SizedBox(width: AppConstants.space8),
        Expanded(
          child: AppButton(
            key: const Key('whatsapp_button'),
            label: 'WhatsApp',
            variant: AppButtonVariant.outlined,
            isFullWidth: true,
            leading: const Icon(Icons.chat_outlined, size: 18),
            onPressed: _whatsapp,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final AgreementStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      AgreementStatus.proposed =>
        ('To agree', AppColors.warningLight, AppColors.warning),
      AgreementStatus.confirmed =>
        ('Agreed', AppColors.primaryLight, AppColors.primary),
      AgreementStatus.active =>
        ('Active', AppColors.successLight, AppColors.success),
      AgreementStatus.declined =>
        ('Declined', AppColors.grey100, AppColors.grey700),
      AgreementStatus.cancelled =>
        ('Cancelled', AppColors.grey100, AppColors.grey700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.body.copyWith(color: AppColors.grey500)),
          const SizedBox(width: AppConstants.space16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
