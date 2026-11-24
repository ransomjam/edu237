import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/phosphor_icon.dart';

class _RecipientDisplay {
  final ActivityRecipient recipient;
  final String studentName;

  _RecipientDisplay({required this.recipient, required this.studentName});
}

class TeacherActivityDetailScreen extends StatefulWidget {
  final LearningActivity activity;

  const TeacherActivityDetailScreen({
    super.key,
    required this.activity,
  });

  @override
  State<TeacherActivityDetailScreen> createState() => _TeacherActivityDetailScreenState();
}

class _TeacherActivityDetailScreenState extends State<TeacherActivityDetailScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  List<_RecipientDisplay> _recipients = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    
    final result = await LearningActivityServiceScope.of(context).fetchRecipientsForActivity(widget.activity.id);
    if (!mounted) return;
    
    if (result is RecipientListSuccess) {
      final studentService = StudentServiceScope.of(context);
      final futures = result.recipients.map((r) async {
        final studentResult = await studentService.fetchStudent(r.studentId);
        if (studentResult is StudentSuccess) {
          return _RecipientDisplay(recipient: r, studentName: studentResult.student.name);
        }
        return null;
      });
      final displays = (await Future.wait(futures)).whereType<_RecipientDisplay>().toList();
      if (mounted) {
        setState(() {
          _recipients = displays;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Detail'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildActivityInfo(),
                  const SizedBox(height: AppConstants.space24),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: AppConstants.space24),
                  _buildRecipientsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildActivityInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(color: AppColors.tagBorder, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                widget.activity.activityType.phosphorIcon,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.activity.activityType.label,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space16),
        Text(
          '${widget.activity.subject} • Form ${widget.activity.form}',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
        ),
        const SizedBox(height: AppConstants.space8),
        Text(widget.activity.topic, style: AppTextStyles.h2),
        if (widget.activity.dueDate != null) ...[
          const SizedBox(height: AppConstants.space12),
          Row(
            children: [
              const Icon(Icons.event, size: 16, color: AppColors.grey700),
              const SizedBox(width: AppConstants.space8),
              Text(
                'Due ${_formatDate(widget.activity.dueDate!)}',
                style: AppTextStyles.body.copyWith(color: AppColors.grey700),
              ),
            ],
          ),
        ],
        if (widget.activity.note != null && widget.activity.note!.isNotEmpty) ...[
          const SizedBox(height: AppConstants.space16),
          Container(
            padding: const EdgeInsets.all(AppConstants.space16),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(widget.activity.note!, style: AppTextStyles.body),
          ),
        ],
        const SizedBox(height: AppConstants.space16),
        Text(
          'Created ${_formatDate(widget.activity.createdAt)}',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
        ),
      ],
    );
  }

  Widget _buildRecipientsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Students (${_recipients.length})',
          style: AppTextStyles.h3,
        ),
        const SizedBox(height: AppConstants.space16),
        ..._recipients.map((display) => _buildRecipientCard(display)),
      ],
    );
  }

  Widget _buildRecipientCard(_RecipientDisplay display) {
    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (display.recipient.status) {
      case ActivityStatus.upcoming:
        statusColor = AppColors.warning;
        statusBgColor = AppColors.warningLight;
        statusIcon = Icons.hourglass_empty;
        break;
      case ActivityStatus.inProgress:
        statusColor = AppColors.primary;
        statusBgColor = AppColors.primaryLight;
        statusIcon = Icons.play_arrow;
        break;
      case ActivityStatus.completed:
        statusColor = AppColors.success;
        statusBgColor = AppColors.successLight;
        statusIcon = Icons.check;
        break;
      case ActivityStatus.needsAttention:
        statusColor = AppColors.error;
        statusBgColor = AppColors.errorLight;
        statusIcon = Icons.warning;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space12),
      child: AppCard(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: statusBgColor,
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          title: Text(display.studentName, style: AppTextStyles.bodyLarge),
          subtitle: Text(display.recipient.status.label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (display.recipient.status != ActivityStatus.completed)
                TextButton(
                  onPressed: () => _updateStatus(display.recipient.id, ActivityStatus.completed),
                  child: const Text('Mark completed'),
                ),
              PopupMenuButton<ActivityStatus>(
                icon: const Icon(Icons.more_vert),
                onSelected: (status) => _updateStatus(display.recipient.id, status),
                itemBuilder: (context) => [
                  if (display.recipient.status != ActivityStatus.inProgress)
                    const PopupMenuItem(
                      value: ActivityStatus.inProgress,
                      child: Text('Mark in progress'),
                    ),
                  if (display.recipient.status != ActivityStatus.completed)
                    const PopupMenuItem(
                      value: ActivityStatus.completed,
                      child: Text('Mark completed'),
                    ),
                  if (display.recipient.status != ActivityStatus.needsAttention)
                    const PopupMenuItem(
                      value: ActivityStatus.needsAttention,
                      child: Text('Needs attention'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String recipientId, ActivityStatus status) async {
    await LearningActivityServiceScope.of(context).updateRecipientStatus(
      recipientId: recipientId,
      status: status,
    );
    if (mounted) _load();
  }
}
