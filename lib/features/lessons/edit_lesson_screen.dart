import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/lesson.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/services/lesson_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';

class EditLessonScreen extends StatefulWidget {
  const EditLessonScreen({super.key, this.existing});

  final Lesson? existing;

  @override
  State<EditLessonScreen> createState() => _EditLessonScreenState();
}

class _EditLessonScreenState extends State<EditLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String? _selectedSubject;
  String? _selectedForm;
  
  bool _isLoadingProfile = true;
  bool _isSaving = false;
  String? _errorMessage;
  TeacherProfile? _profile;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleController.text = widget.existing!.title;
      _descriptionController.text = widget.existing!.description;
      _selectedSubject = widget.existing!.subject;
      _selectedForm = widget.existing!.form;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoadingProfile) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final result = await TeacherProfileServiceScope.of(context).fetchMyProfile();
    if (!mounted) return;
    
    if (result is TeacherProfileSuccess) {
      setState(() {
        _profile = result.profile;
        _isLoadingProfile = false;
        
        // Auto-select if there's only one option and we're creating
        if (widget.existing == null) {
          if (_profile!.subjects.length == 1) {
            _selectedSubject = _profile!.subjects.first;
          }
          if (_profile!.forms.length == 1) {
            _selectedForm = _profile!.forms.first;
          }
        }
      });
    } else {
      setState(() {
        _errorMessage = 'Could not load your teacher profile. You need a profile with subjects and forms to create a lesson.';
        _isLoadingProfile = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubject == null || _selectedForm == null) {
      setState(() => _errorMessage = 'Please select a subject and a form.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final service = LessonServiceScope.of(context);
    final LessonResult result;

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subject: _selectedSubject,
        form: _selectedForm,
      );
      result = await service.updateLesson(updated);
    } else {
      result = await service.createLesson(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subject: _selectedSubject!,
        form: _selectedForm!,
      );
    }

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result is LessonSuccess) {
      context.pop(result.lesson); // Return the lesson to refresh or navigate
    } else if (result is LessonFailure) {
      final msg = result.message;
      setState(() => _errorMessage = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Create Lesson' : 'Edit Lesson'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoadingProfile) {
      return const Center(child: Text('Loading profile...'));
    }

    if (_profile == null || _profile!.subjects.isEmpty || _profile!.forms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ?? 'You must complete your teacher profile (subjects and forms) before creating lessons.',
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.space16),
              AppButton(label: 'Go back', onPressed: () => context.pop()),
            ],
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
        children: [
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: AppTextStyles.body.copyWith(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: AppConstants.space16),
          ],
          AppTextField(
            label: 'Lesson title',
            controller: _titleController,
            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: AppConstants.space24),
          Text('Subject', style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space8),
          DropdownButtonFormField<String>(
            initialValue: _selectedSubject,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: AppConstants.space16, vertical: AppConstants.space12),
            ),
            items: _profile!.subjects.map((subject) {
              return DropdownMenuItem(value: subject, child: Text(subject));
            }).toList(),
            onChanged: (val) => setState(() => _selectedSubject = val),
            validator: (val) => val == null ? 'Please select a subject' : null,
          ),
          const SizedBox(height: AppConstants.space24),
          Text('Form / Class', style: AppTextStyles.h3),
          const SizedBox(height: AppConstants.space8),
          DropdownButtonFormField<String>(
            initialValue: _selectedForm,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: AppConstants.space16, vertical: AppConstants.space12),
            ),
            items: _profile!.forms.map((form) {
              return DropdownMenuItem(value: form, child: Text(form));
            }).toList(),
            onChanged: (val) => setState(() => _selectedForm = val),
            validator: (val) => val == null ? 'Please select a form' : null,
          ),
          const SizedBox(height: AppConstants.space24),
          AppTextField(
            label: 'Description',
            controller: _descriptionController,
            maxLines: 6,
            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: AppConstants.space32),
          AppButton(
            label: widget.existing == null ? 'Save Lesson' : 'Update Lesson',
            isLoading: _isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
