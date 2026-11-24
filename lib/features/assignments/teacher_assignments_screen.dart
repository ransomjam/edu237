import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/assignment.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/assignment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';

class TeacherAssignmentsScreen extends StatefulWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  State<TeacherAssignmentsScreen> createState() =>
      _TeacherAssignmentsScreenState();
}

class _TeacherAssignmentsScreenState extends State<TeacherAssignmentsScreen> {
  bool _isLoading = true;
  bool _initialLoadDone = false;
  String? _errorMessage;
  List<Assignment> _assignments = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result =
        await AssignmentServiceScope.of(context).fetchTeacherAssignments();
    if (!mounted) return;

    switch (result) {
      case AssignmentListSuccess(:final assignments):
        setState(() {
          _assignments = assignments;
          _isLoading = false;
        });
      case AssignmentEmpty():
        setState(() {
          _assignments = const [];
          _isLoading = false;
        });
      case AssignmentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      default:
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Assignments')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Text('Loading assignments...'));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!,
                  style: AppTextStyles.bodyLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppConstants.space16),
              AppButton(label: 'Retry', onPressed: _load),
            ],
          ),
        ),
      );
    }
    if (_assignments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No assignments yet', style: AppTextStyles.h2,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppConstants.space12),
              Text(
                'Create an assignment from one of your lessons.',
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      itemCount: _assignments.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppConstants.space12),
      itemBuilder: (context, index) {
        final a = _assignments[index];
        return _AssignmentCard(
          assignment: a,
          onTap: () => context.push(AppRoutes.teacherAssignmentDetail, extra: a),
        );
      },
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.assignment, required this.onTap});
  final Assignment assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(assignment.title, style: AppTextStyles.h3),
            const SizedBox(height: AppConstants.space8),
            if (assignment.dueAt != null)
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: AppColors.grey500),
                  const SizedBox(width: AppConstants.space4),
                  Text(
                    'Due ${assignment.dueAt!.day} ${_monthName(assignment.dueAt!.month)}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.grey500),
                  ),
                ],
              ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Created ${assignment.createdAt.toLocal().toString().split(' ')[0]}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}
