import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/topic_catalogue.dart';
import '../../core/models/learning_activity.dart';
import '../../core/models/parent_teacher_relationship.dart';
import '../../core/models/student.dart';
import '../../core/services/learning_activity_service.dart';
import '../../core/services/parent_teacher_relationship_service.dart';
import '../../core/services/student_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/phosphor_icon.dart';

class CreateActivityScreen extends StatefulWidget {
  final Student? preselectedStudent;

  const CreateActivityScreen({
    super.key,
    this.preselectedStudent,
  });

  @override
  State<CreateActivityScreen> createState() => _CreateActivityScreenState();
}

class _CreateActivityScreenState extends State<CreateActivityScreen> {
  // Loading states
  bool _isLoadingProfile = true;
  String? _profileError;
  List<String> _teacherSubjects = [];
  List<String> _teacherForms = [];

  bool _isLoadingStudents = false;
  String? _studentsError;
  List<Student> _availableStudents = [];

  bool _isPublishing = false;
  String? _publishError;

  // Selections
  String? _selectedSubject;
  String? _selectedForm;
  ActivityType? _selectedType;
  
  String? _selectedTopic;
  bool _isOtherTopic = false;
  final TextEditingController _otherTopicController = TextEditingController();
  
  final Set<String> _selectedStudentIds = {};
  
  DateTime? _selectedDueDate;
  String? _selectedDueDateLabel;
  
  final TextEditingController _noteController = TextEditingController();
  bool _initialProfileLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedStudent != null) {
      _selectedStudentIds.add(widget.preselectedStudent!.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialProfileLoaded) {
      _initialProfileLoaded = true;
      _loadTeacherProfile();
    }
  }

  @override
  void dispose() {
    _otherTopicController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadTeacherProfile() async {
    final result = await TeacherProfileServiceScope.of(context).fetchMyProfile();
    
    if (!mounted) return;
    
    if (result is TeacherProfileSuccess) {
      setState(() {
        _teacherSubjects = result.profile?.subjects ?? [];
        _teacherForms = result.profile?.forms ?? [];
        _isLoadingProfile = false;
        
        // Auto-select if only one option exists
        if (_teacherSubjects.length == 1) {
          _selectedSubject = _teacherSubjects.first;
        }
        if (_teacherForms.length == 1) {
          _selectedForm = _teacherForms.first;
        }
        
        if (_selectedSubject != null && _selectedForm != null) {
          _loadEligibleStudents();
        }
      });
    } else if (result is TeacherProfileFailure) {
      setState(() {
        _profileError = result.message;
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _loadEligibleStudents() async {
    if (_selectedForm == null || _selectedSubject == null) return;
    
    setState(() {
      _isLoadingStudents = true;
      _studentsError = null;
    });

    final relResult = await ParentTeacherRelationshipServiceScope.of(context).fetchMyRelationshipsAsTeacher();
    
    if (!mounted) return;
    
    if (relResult is RelationshipListSuccess) {
      final acceptedRels = relResult.relationships.where((r) => r.status == RelationshipStatus.accepted).toList();
      
      List<Student> students = [];
      for (final rel in acceptedRels) {
        final studentResult = await StudentServiceScope.of(context).fetchStudent(rel.studentId);
        if (studentResult is StudentSuccess) {
          final student = studentResult.student;
          if (student.schoolLevel == _selectedForm && student.subjects.contains(_selectedSubject)) {
            students.add(student);
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _availableStudents = students;
          _isLoadingStudents = false;
          
          // Pre-select if needed
          if (widget.preselectedStudent != null && 
              students.any((s) => s.id == widget.preselectedStudent!.id)) {
            _selectedStudentIds.add(widget.preselectedStudent!.id);
          } else {
            // Select all by default
            _selectedStudentIds.addAll(students.map((s) => s.id));
          }
        });
      }
    } else if (relResult is RelationshipFailure) {
      if (mounted) {
        setState(() {
          _studentsError = relResult.message;
          _isLoadingStudents = false;
        });
      }
    }
  }

  void _onSubjectSelected(String subject) {
    setState(() {
      _selectedSubject = subject;
      _checkStudentEligibility();
    });
  }

  void _onFormSelected(String form) {
    setState(() {
      _selectedForm = form;
      _selectedTopic = null; // Reset topic when form changes
      _checkStudentEligibility();
    });
  }
  
  void _checkStudentEligibility() {
    if (_selectedForm != null && _selectedSubject != null) {
      _loadEligibleStudents();
    } else {
      setState(() {
        _availableStudents = [];
        _selectedStudentIds.clear();
      });
    }
  }

  Future<void> _publishActivity() async {
    final topic = _isOtherTopic ? _otherTopicController.text.trim() : _selectedTopic;
    if (topic == null || topic.isEmpty) return;
    
    setState(() {
      _isPublishing = true;
      _publishError = null;
    });

    final note = _noteController.text.trim();
    
    final result = await LearningActivityServiceScope.of(context).createActivity(
      subject: _selectedSubject!,
      form: _selectedForm!,
      topic: topic,
      activityType: _selectedType!,
      note: note.isEmpty ? null : note,
      dueDate: _selectedDueDate,
      studentIds: _selectedStudentIds.toList(),
    );
    
    if (!mounted) return;
    
    if (result is ActivitySuccess) {
      context.pop(result.activity);
    } else if (result is ActivityFailure) {
      setState(() {
        _isPublishing = false;
        _publishError = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profileError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load profile', style: AppTextStyles.h2),
              const SizedBox(height: AppConstants.space8),
              Text(_profileError!, style: AppTextStyles.body),
              const SizedBox(height: AppConstants.space16),
              AppButton(
                label: 'Retry',
                onPressed: _loadTeacherProfile,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Create learning activity', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.grey900),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progressive disclosure: each step is revealed only once the
              // previous choice is made — no grey disabled sections up front.
              _buildSectionHeader('What subject?'),
              _buildSubjectSelection(),

              if (_selectedSubject != null) ...[
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('Which class?'),
                _buildFormSelection(),
              ],

              if (_selectedForm != null) ...[
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('What are you doing?'),
                _buildActivityTypeSelection(),
              ],

              if (_selectedType != null) ...[
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('Topic'),
                _buildTopicSelection(),
              ],

              if (_selectedTopic != null || _isOtherTopic) ...[
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('Who are you teaching?'),
                _buildStudentSelection(),
              ],

              if (_selectedStudentIds.isNotEmpty) ...[
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('When?'),
                _buildDueDateSelection(),
                const SizedBox(height: AppConstants.space24),
                _buildSectionHeader('Add a note (optional)'),
                _buildNoteSelection(),
                const SizedBox(height: AppConstants.space32),
                _buildConfirmationSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space12),
      child: Text(title, style: AppTextStyles.h3),
    );
  }

  Widget _buildSubjectSelection() {
    return Wrap(
      spacing: AppConstants.space8,
      runSpacing: AppConstants.space8,
      children: _teacherSubjects.map((subject) {
        final isSelected = _selectedSubject == subject;
        return _buildChip(
          label: subject,
          isSelected: isSelected,
          onTap: () => _onSubjectSelected(subject),
        );
      }).toList(),
    );
  }

  Widget _buildFormSelection() {
    final enabled = _selectedSubject != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Wrap(
        spacing: AppConstants.space8,
        runSpacing: AppConstants.space8,
        children: _teacherForms.map((form) {
          final isSelected = _selectedForm == form;
          return _buildChip(
            label: form,
            isSelected: isSelected,
            onTap: enabled ? () => _onFormSelected(form) : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivityTypeSelection() {
    final enabled = _selectedForm != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppConstants.space12,
        mainAxisSpacing: AppConstants.space12,
        childAspectRatio: 1.5,
        children: [
          _buildTypeCard(ActivityType.lesson, PhosphorIcons.bookOpen, 'Lesson', enabled),
          _buildTypeCard(ActivityType.practice, PhosphorIcons.pencilSimple, 'Practice', enabled),
          _buildTypeCard(ActivityType.homework, PhosphorIcons.fileText, 'Homework', enabled),
          _buildTypeCard(ActivityType.revision, PhosphorIcons.arrowClockwise, 'Revision', enabled),
        ],
      ),
    );
  }

  Widget _buildTypeCard(ActivityType type, String iconName, String label, bool enabled) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: enabled ? () => setState(() => _selectedType = type) : null,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.05 : 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.white : AppColors.iconContainerBg,
                shape: BoxShape.circle,
              ),
              child: PhosphorIcon(
                iconName,
                size: 22,
                color: isSelected ? AppColors.primary : AppColors.grey700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isSelected ? AppColors.primary : AppColors.grey900,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicSelection() {
    final enabled = _selectedType != null;
    if (!enabled) {
      return Opacity(
        opacity: 0.5,
        child: Text('Select an activity type first', style: AppTextStyles.body),
      );
    }

    final topics = TopicCatalogue.topicsFor(_selectedForm!, _selectedSubject!);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topics.isNotEmpty)
          Wrap(
            spacing: AppConstants.space8,
            runSpacing: AppConstants.space8,
            children: topics.map((topic) {
              final isSelected = _selectedTopic == topic && !_isOtherTopic;
              return _buildChip(
                label: topic,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedTopic = topic;
                    _isOtherTopic = false;
                  });
                },
              );
            }).toList(),
          ),
        if (topics.isNotEmpty) const SizedBox(height: AppConstants.space12),
        
        _buildChip(
          label: 'Other topic...',
          isSelected: _isOtherTopic,
          onTap: () {
            setState(() {
              _isOtherTopic = true;
              _selectedTopic = null;
            });
          },
        ),
        
        if (_isOtherTopic) ...[
          const SizedBox(height: AppConstants.space12),
          AppTextField(
            controller: _otherTopicController,
            label: 'Enter custom topic',
            onChanged: (val) => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _buildStudentSelection() {
    final enabled = (_selectedTopic != null || _isOtherTopic);
    if (!enabled) {
      return Opacity(
        opacity: 0.5,
        child: Text('Complete previous steps to see students', style: AppTextStyles.body),
      );
    }

    if (_isLoadingStudents) {
      return const Padding(
        padding: EdgeInsets.all(AppConstants.space16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_studentsError != null) {
      return Text('Something went wrong loading your students. Please try again.',
          style: AppTextStyles.body.copyWith(color: AppColors.error));
    }

    if (_availableStudents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.space16),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          'None of your connected students take $_selectedSubject in '
          '${_selectedForm ?? ''}. You can create the activity for a student '
          'once they are connected to you for this subject.',
          style: AppTextStyles.body.copyWith(color: AppColors.grey700),
        ),
      );
    }

    final allSelected = _selectedStudentIds.length == _availableStudents.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            title: Text('Select all', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
            value: allSelected,
            activeColor: AppColors.primary,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedStudentIds.addAll(_availableStudents.map((s) => s.id));
                } else {
                  _selectedStudentIds.clear();
                }
              });
            },
          ),
          const Divider(height: 1),
          ..._availableStudents.map((student) {
            final isSelected = _selectedStudentIds.contains(student.id);
            return CheckboxListTile(
              title: Text(student.name, style: AppTextStyles.body),
              value: isSelected,
              activeColor: AppColors.primary,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedStudentIds.add(student.id);
                  } else {
                    _selectedStudentIds.remove(student.id);
                  }
                });
              },
            );
          }),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildDueDateSelection() {
    final enabled = _selectedStudentIds.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Wrap(
        spacing: AppConstants.space8,
        runSpacing: AppConstants.space8,
        children: [
          _buildDateChip(
            label: 'Today',
            date: DateTime.now(),
            enabled: enabled,
          ),
          _buildDateChip(
            label: 'Tomorrow',
            date: DateTime.now().add(const Duration(days: 1)),
            enabled: enabled,
          ),
          _buildDateChip(
            label: 'This week',
            date: _getEndOfWeek(),
            enabled: enabled,
          ),
          _buildChip(
            label: 'No due date',
            isSelected: _selectedDueDate == null && _selectedDueDateLabel == 'No due date',
            onTap: enabled ? () {
              setState(() {
                _selectedDueDate = null;
                _selectedDueDateLabel = 'No due date';
              });
            } : null,
          ),
        ],
      ),
    );
  }

  DateTime _getEndOfWeek() {
    final now = DateTime.now();
    final daysUntilSunday = DateTime.sunday - now.weekday;
    return now.add(Duration(days: daysUntilSunday));
  }

  Widget _buildDateChip({required String label, required DateTime date, required bool enabled}) {
    final isSelected = _selectedDueDateLabel == label;
    final dateStr = '${_getMonthName(date.month)} ${date.day}';
    
    return _buildChip(
      label: '$label ($dateStr)',
      isSelected: isSelected,
      onTap: enabled ? () {
        setState(() {
          _selectedDueDate = date;
          _selectedDueDateLabel = label;
        });
      } : null,
    );
  }

  Widget _buildNoteSelection() {
    final enabled = _selectedStudentIds.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: AppTextField(
        controller: _noteController,
        label: 'Optional note for students',
        maxLines: 2,
        enabled: enabled,
      ),
    );
  }

  Widget _buildConfirmationSection() {
    final isComplete = _selectedSubject != null &&
        _selectedForm != null &&
        _selectedType != null &&
        (_selectedTopic != null || (_isOtherTopic && _otherTopicController.text.trim().isNotEmpty)) &&
        _selectedStudentIds.isNotEmpty;

    if (!isComplete) return const SizedBox.shrink();

    final topic = _isOtherTopic ? _otherTopicController.text.trim() : _selectedTopic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_publishError != null)
          Container(
            padding: const EdgeInsets.all(AppConstants.space12),
            margin: const EdgeInsets.only(bottom: AppConstants.space16),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppConstants.radius),
            ),
            child: Text(
              _publishError!,
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
          ),
          
        Container(
          padding: const EdgeInsets.all(AppConstants.space16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.primaryLight, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summary', style: AppTextStyles.h3),
              const SizedBox(height: AppConstants.space12),
              _buildSummaryRow('Subject · Form', '$_selectedSubject · $_selectedForm'),
              _buildSummaryRow('Type', _selectedType!.name.toUpperCase()),
              _buildSummaryRow('Topic', topic!),
              _buildSummaryRow('Students', '${_selectedStudentIds.length} selected'),
              if (_selectedDueDateLabel != null)
                _buildSummaryRow('Due', _selectedDueDateLabel!),
              if (_noteController.text.trim().isNotEmpty)
                _buildSummaryRow('Note', _noteController.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.space24),
        AppButton(
          label: 'Publish activity',
          isFullWidth: true,
          isLoading: _isPublishing,
          onPressed: _publishActivity,
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey300,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: isSelected ? AppColors.white : AppColors.grey900,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
