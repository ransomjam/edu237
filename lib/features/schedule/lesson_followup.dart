import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson_session.dart';
import '../../core/services/lesson_session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_text_field.dart';
import 'schedule_format.dart';

/// The lightweight "How did the class go?" follow-up. After a lesson's end time
/// the teacher records the outcome with one big tap; a short note is optional.
///
/// Returns the updated [LessonSession] if the status was recorded, else null.
Future<LessonSession?> showLessonFollowUpSheet(
  BuildContext context,
  LessonSession session,
) {
  return showModalBottomSheet<LessonSession>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _FollowUpSheet(session: session),
  );
}

class _FollowUpSheet extends StatefulWidget {
  const _FollowUpSheet({required this.session});
  final LessonSession session;

  @override
  State<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<_FollowUpSheet> {
  final TextEditingController _note = TextEditingController();
  SessionStatus? _busyFor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note.text = widget.session.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _record(SessionStatus status) async {
    setState(() {
      _busyFor = status;
      _error = null;
    });
    final result =
        await LessonSessionServiceScope.of(context).updateSessionStatus(
      sessionId: widget.session.id,
      status: status,
      note: _note.text,
    );
    if (!mounted) return;
    if (result is LessonSessionSuccess) {
      Navigator.of(context).pop(result.session);
    } else if (result is LessonSessionFailure) {
      setState(() {
        _busyFor = null;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space16,
        AppConstants.pageHorizontalPadding,
        AppConstants.space16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space16),
          Text('How did the class go?', style: AppTextStyles.h2),
          const SizedBox(height: AppConstants.space4),
          Text(
            '${s.childName} · ${s.subject} · ${dayTimeLabel(s.localStart, DateTime.now())}',
            style: AppTextStyles.body.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space20),
          _OutcomeButton(
            label: 'Completed',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            loading: _busyFor == SessionStatus.completed,
            onTap: () => _record(SessionStatus.completed),
          ),
          const SizedBox(height: AppConstants.space12),
          _OutcomeButton(
            label: 'Missed',
            icon: Icons.error_outline,
            color: AppColors.warning,
            loading: _busyFor == SessionStatus.missed,
            onTap: () => _record(SessionStatus.missed),
          ),
          const SizedBox(height: AppConstants.space12),
          _OutcomeButton(
            label: 'Cancelled',
            icon: Icons.cancel_outlined,
            color: AppColors.grey500,
            loading: _busyFor == SessionStatus.cancelled,
            onTap: () => _record(SessionStatus.cancelled),
          ),
          const SizedBox(height: AppConstants.space20),
          Text('Add a short note (optional)', style: AppTextStyles.label),
          const SizedBox(height: AppConstants.space8),
          AppTextField(
            controller: _note,
            label: 'e.g. Great progress on quadratics',
            maxLines: 2,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppConstants.space12),
            Text(_error!,
                style: AppTextStyles.body.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppConstants.space8),
        ],
      ),
    );
  }
}

class _OutcomeButton extends StatelessWidget {
  const _OutcomeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16, vertical: AppConstants.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppConstants.space12),
              Text(label,
                  style: AppTextStyles.h3.copyWith(color: color)),
              const Spacer(),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
