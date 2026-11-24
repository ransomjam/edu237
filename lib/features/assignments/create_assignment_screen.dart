import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/services/assignment_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

class CreateAssignmentScreen extends StatefulWidget {
  const CreateAssignmentScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<CreateAssignmentScreen> createState() => _CreateAssignmentScreenState();
}

class _CreateAssignmentScreenState extends State<CreateAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();
  DateTime? _dueAt;

  bool _isLoadingStudents = true;
  bool _isSaving = false;
  String? _errorMessage;
  List<Student> _compatibleStudents = [];
  final Set<String> _selectedStudentIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoadingStudents) _loadConnectedStudents();
  }

  Future<void> _loadConnectedStudents() async {
    setState(() => _isLoadingStudents = true);

    final relService = ParentTeacherRelationshipServiceScope.of(context);
    final studentService = StudentServiceScope.of(context);

    final relResult = await relService.fetchMyRelationshipsAsTeacher();
    if (!mounted) return;

    if (relResult case RelationshipListSuccess(:final relationships)) {
      final accepted = relationships
          .where((r) => r.status == RelationshipStatus.accepted)
          .toList();

      final compatible = <Student>[];
      for (final rel in accepted) {
        final sr = await studentService.fetchStudent(rel.studentId);
        if (!mounted) return;
        if (sr case StudentSuccess(:final student)) {
          // Only include students whose form matches the lesson form
          // AND who take the lesson subject
          if (student.schoolLevel == widget.lesson.form &&
              student.subjects.contains(widget.lesson.subject)) {
            compatible.add(student);
          }
        }
      }

      setState(() {
        _compatibleStudents = compatible;
        _isLoadingStudents = false;
      });
    } else {
      setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueAt = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentIds.isEmpty) {
      setState(() => _errorMessage = 'Please select at least one student.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await AssignmentServiceScope.of(context).createAssignment(
      lessonId: widget.lesson.id,
      title: _titleController.text.trim(),
      instructions: _instructionsController.text.trim(),
      dueAt: _dueAt,
      studentIds: _selectedStudentIds.toList(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result is AssignmentSuccess) {
      context.pop(result.assignment);
    } else if (result is AssignmentFailure) {
      final msg = result.message;
      setState(() => _errorMessage = msg);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Assignment')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoadingStudents) {
      return const Center(child: Text('Loading students...'));
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          // Lesson context banner
          Container(
            padding: const EdgeInsets.all(AppConstants.space16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppConstants.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book, color: AppColors.primary),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From lesson',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.primary)),
                      Text(widget.lesson.title,
                          style: AppTextStyles.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text('${widget.lesson.form} · ${widget.lesson.subject}',
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space24),
          if (_errorMessage != null) ...[
            Text(_errorMessage!,
                style:
                    AppTextStyles.body.copyWith(color: AppColors.error)),
            const SizedBox(height: AppConstants.space16),
          ],
          AppTextField(
            label: 'Assignment title',
            controller: _titleController,
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: AppConstants.space24),
          AppTextField(
            label: 'Instructions',
            controller: _instructionsController,
            maxLines: 5,
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: AppConstants.space24),
          Text('Due Date (optional)', style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space8),
          GestureDetector(
            onTap: _pickDueDate,
            child: Container(
              padding: const EdgeInsets.all(AppConstants.space16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey300),
                borderRadius: BorderRadius.circular(AppConstants.radius),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.grey500),
                  const SizedBox(width: AppConstants.space12),
                  Text(
                    _dueAt != null
                        ? '${_dueAt!.day} ${_monthName(_dueAt!.month)} ${_dueAt!.year}'
                        : 'No due date',
                    style: AppTextStyles.body.copyWith(
                      color: _dueAt != null
                          ? AppColors.grey900
                          : AppColors.grey500,
                    ),
                  ),
                  const Spacer(),
                  if (_dueAt != null)
                    GestureDetector(
                      onTap: () => setState(() => _dueAt = null),
                      child: const Icon(Icons.close,
                          size: 18, color: AppColors.grey500),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space32),
          Text('Assign to students', style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space8),
          if (_compatibleStudents.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppConstants.space24),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(AppConstants.radius),
              ),
              child: Text(
                'No connected students are enrolled in ${widget.lesson.form} ${widget.lesson.subject}.',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            if (_compatibleStudents.length > 1)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_selectedStudentIds.length ==
                        _compatibleStudents.length) {
                      _selectedStudentIds.clear();
                    } else {
                      _selectedStudentIds.addAll(
                          _compatibleStudents.map((s) => s.id));
                    }
                  });
                },
                icon: Icon(
                    _selectedStudentIds.length == _compatibleStudents.length
                        ? Icons.deselect
                        : Icons.select_all),
                label: Text(
                    _selectedStudentIds.length == _compatibleStudents.length
                        ? 'Deselect all'
                        : 'Select all'),
              ),
            ...List.generate(_compatibleStudents.length, (i) {
              final student = _compatibleStudents[i];
              final selected = _selectedStudentIds.contains(student.id);
              return Card(
                margin: const EdgeInsets.symmetric(
                    vertical: AppConstants.space4),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radius),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.grey300,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: CheckboxListTile(
                  value: selected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedStudentIds.add(student.id);
                      } else {
                        _selectedStudentIds.remove(student.id);
                      }
                    });
                  },
                  title: Text(student.name, style: AppTextStyles.h3),
                  subtitle: Text(
                    '${student.schoolLevel ?? ''} · ${student.subjects.join(', ')}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.grey500),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                ),
              );
            }),
          ],
          const SizedBox(height: AppConstants.space32),
          AppButton(
            label: 'Save Assignment',
            isLoading: _isSaving,
            onPressed: _compatibleStudents.isEmpty ? null : _save,
          ),
          const SizedBox(height: AppConstants.space16),
        ],
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
