import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

/// The counterpart's contact details for a relationship — or the locked state.
///
/// The card never holds private details it is not allowed to show: the server
/// returns nothing at all until the relationship's activation condition is
/// satisfied, so there is no hidden value in the widget tree to leak. A failed
/// or pending payment therefore leaves this locked, by construction.
class RelationshipContactCard extends StatefulWidget {
  const RelationshipContactCard({
    super.key,
    required this.relationshipId,
    this.lockedTitle = 'Contact details',
    this.lockedMessage =
        'The family\'s contact details appear here once this relationship is '
            'activated.',
    this.onActivate,
  });

  final String relationshipId;
  final String lockedTitle;
  final String lockedMessage;

  /// Shown as an action when the relationship still needs activating.
  final VoidCallback? onActivate;

  @override
  State<RelationshipContactCard> createState() =>
      _RelationshipContactCardState();
}

class _RelationshipContactCardState extends State<RelationshipContactCard> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  bool _revealed = false;
  String? _name;
  String? _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    final service = PaymentServiceScope.maybeOf(context);
    if (service == null) {
      setState(() => _isLoading = false);
      return;
    }
    final result = await service.fetchRelationshipContact(widget.relationshipId);
    if (!mounted) return;

    if (result case ContactSuccess(:final revealed, :final name, :final phone)) {
      setState(() {
        _revealed = revealed;
        _name = name;
        _phone = phone;
        _isLoading = false;
      });
    } else {
      setState(() {
        _revealed = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppConstants.space12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (!_revealed) {
      return AppCard(
        key: const Key('contact_locked'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 18, color: AppColors.grey500),
                const SizedBox(width: AppConstants.space8),
                Text(widget.lockedTitle, style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: AppConstants.space8),
            Text(widget.lockedMessage,
                style: AppTextStyles.body.copyWith(color: AppColors.grey700)),
            if (widget.onActivate != null) ...[
              const SizedBox(height: AppConstants.space12),
              AppButton(
                key: const Key('activate_relationship_button'),
                label: 'Activate relationship',
                isFullWidth: true,
                onPressed: widget.onActivate,
              ),
            ],
          ],
        ),
      );
    }

    return AppCard(
      key: const Key('contact_revealed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.lockedTitle, style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space8),
          if ((_name ?? '').isNotEmpty)
            Text(_name!,
                style: AppTextStyles.bodyLarge
                    .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppConstants.space4),
          Text(
            (_phone ?? '').isEmpty ? 'No phone number added yet' : _phone!,
            key: const Key('contact_phone'),
            style: AppTextStyles.body.copyWith(color: AppColors.grey700),
          ),
        ],
      ),
    );
  }
}
