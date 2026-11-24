import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/student.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/phosphor_icon.dart';

class TeacherActivityListScreen extends StatefulWidget {
  final Student student;

  const TeacherActivityListScreen({
    super.key,
    required this.student,
  });

  @override
  State<TeacherActivityListScreen> createState() => _TeacherActivityListScreenState();
}

class _TeacherActivityListScreenState extends State<TeacherActivityListScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  List<LearningActivity> _activities = [];

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
    final result = await LearningActivityServiceScope.of(context).fetchActivitiesForStudent(widget.student.id);
    
    if (result is ActivityListSuccess) {
      if (mounted) {
        setState(() {
          _activities = result.activities;
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
        title: Text('${widget.student.name}\'s Learning'),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? _buildEmptyState()
              : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.createActivity, extra: widget.student);
          _load();
        },
        label: const Text('Add learning activity'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No learning activities yet.\nAdd one for this student.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.grey500),
            ),
            const SizedBox(height: AppConstants.space24),
            AppButton(
              label: 'Add learning activity',
              onPressed: () async {
                await context.push(AppRoutes.createActivity, extra: widget.student);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding).copyWith(bottom: 80),
      itemCount: _activities.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppConstants.space12),
      itemBuilder: (context, index) {
        final activity = _activities[index];
        return AppCard(
          onTap: () async {
            await context.push(AppRoutes.teacherActivityDetail, extra: activity);
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.space16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: PhosphorIcon(
                    activity.activityType.phosphorIcon,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppConstants.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activity.topic, style: AppTextStyles.h3),
                      const SizedBox(height: AppConstants.space4),
                      Text(
                        '${activity.subject} • Form ${activity.form}',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
                      ),
                      if (activity.dueDate != null) ...[
                        const SizedBox(height: AppConstants.space4),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 14, color: AppColors.primary),
                            const SizedBox(width: AppConstants.space4),
                            Text(
                              'Due ${_formatDate(activity.dueDate!)}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
