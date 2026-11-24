import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/student.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/phosphor_icon.dart';

class _FeedItem {
  final LearningActivity activity;
  final ActivityRecipient? recipient;

  const _FeedItem({required this.activity, this.recipient});
}

class StudentLearningFeedScreen extends StatefulWidget {
  final Student student;

  const StudentLearningFeedScreen({super.key, required this.student});

  @override
  State<StudentLearningFeedScreen> createState() =>
      _StudentLearningFeedScreenState();
}

class _StudentLearningFeedScreenState extends State<StudentLearningFeedScreen> {
  bool _isLoading = true;
  String? _error;
  List<_FeedItem> _items = [];
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _loadData();
      _isInit = true;
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = LearningActivityServiceScope.of(context);
      final activityRes =
          await service.fetchActivitiesForStudent(widget.student.id);

      if (activityRes is! ActivityListSuccess) {
        if (mounted) {
          setState(() {
            _error = 'Failed to load learning activities';
            _isLoading = false;
          });
        }
        return;
      }

      final activities = activityRes.activities;
      final List<_FeedItem> loadedItems = [];

      for (final activity in activities) {
        final recipientRes =
            await service.fetchRecipientsForActivity(activity.id);
        ActivityRecipient? recipient;

        if (recipientRes is RecipientListSuccess) {
          try {
            recipient = recipientRes.recipients
                .firstWhere((r) => r.studentId == widget.student.id);
          } catch (_) {
            // No recipient found for this student, which shouldn't normally happen
            // since fetchActivitiesForStudent only returns activities relevant to them.
          }
        }

        loadedItems.add(_FeedItem(activity: activity, recipient: recipient));
      }

      if (mounted) {
        setState(() {
          _items = loadedItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'An error occurred while loading activities';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _dateGroupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);
    if (itemDate == today) return 'Today';
    if (itemDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return _formatDate(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.student.name}\'s Learning',
            style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.grey900),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!,
                style: AppTextStyles.body.copyWith(color: AppColors.error)),
            const SizedBox(height: AppConstants.space16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.12),
            AppEmptyState(
              icon: Icons.menu_book_outlined,
              title: l10n.learningEmptyParentTitle,
              message: l10n.learningEmptyParentBody,
            ),
          ],
        ),
      );
    }

    // Group items
    final grouped = <String, List<_FeedItem>>{};
    for (final item in _items) {
      final label = _dateGroupLabel(item.activity.createdAt.toLocal());
      grouped.putIfAbsent(label, () => []).add(item);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.pageHorizontalPadding,
            vertical: AppConstants.space16),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final groupLabel = grouped.keys.elementAt(index);
          final groupItems = grouped[groupLabel]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    bottom: AppConstants.space8, top: AppConstants.space16),
                child: Text(groupLabel, style: AppTextStyles.h3),
              ),
              ...groupItems.map((item) => _buildActivityCard(item)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivityCard(_FeedItem item) {
    final activity = item.activity;
    final recipient = item.recipient;

    Color statusBg = AppColors.grey100;
    Color statusText = AppColors.grey700;
    String statusLabel = '';

    if (recipient != null) {
      statusLabel = recipient.status.label;
      switch (recipient.status) {
        case ActivityStatus.upcoming:
          statusBg = AppColors.warningLight;
          statusText = AppColors.warning;
          break;
        case ActivityStatus.inProgress:
          statusBg = AppColors.primaryLight;
          statusText = AppColors.primary;
          break;
        case ActivityStatus.completed:
          statusBg = AppColors.successLight;
          statusText = AppColors.success;
          break;
        case ActivityStatus.needsAttention:
          statusBg = AppColors.errorLight;
          statusText = AppColors.error;
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.space8,
                      vertical: AppConstants.space4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(color: AppColors.tagBorder, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        activity.activityType.phosphorIcon,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        activity.activityType.label,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                if (recipient != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space8,
                        vertical: AppConstants.space4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTextStyles.label.copyWith(color: statusText),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.space12),
            Text(activity.topic, style: AppTextStyles.h3),
            const SizedBox(height: AppConstants.space4),
            Text(
              '${activity.subject} · ${activity.form}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
            ),
            if (activity.dueDate != null) ...[
              const SizedBox(height: AppConstants.space8),
              Text(
                'Due ${_formatDate(activity.dueDate!)}',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.grey500),
              ),
            ],
            if (recipient?.teacherNote != null &&
                recipient!.teacherNote!.isNotEmpty) ...[
              const SizedBox(height: AppConstants.space12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.space12),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Teacher note',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.grey700),
                    ),
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      recipient.teacherNote!,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
