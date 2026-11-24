import 'package:flutter/material.dart';

import '../../core/models/student.dart';
import '../../core/services/student_service.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/edu_ui.dart';

/// Loads the signed-in student's own learner record and hands it to [builder].
///
/// Every student screen needs the same thing first: the one `students` row
/// their account is linked to. Doing it here keeps the screens themselves
/// small, and keeps the "one learner, one row" rule in a single place — no
/// screen ever creates a record as a side effect of rendering.
class StudentRecordLoader extends StatefulWidget {
  const StudentRecordLoader({
    super.key,
    required this.builder,
    this.onLoaded,
  });

  final Widget Function(BuildContext context, Student student) builder;

  /// Called once whenever a record is (re)loaded, e.g. to refresh a header.
  final ValueChanged<Student>? onLoaded;

  @override
  State<StudentRecordLoader> createState() => StudentRecordLoaderState();
}

class StudentRecordLoaderState extends State<StudentRecordLoader> {
  Student? _student;
  bool _isLoading = true;
  bool _notFound = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _notFound = false;
    });

    final result = await StudentServiceScope.of(context).fetchMyStudentRecord();
    if (!mounted) return;

    switch (result) {
      case StudentSuccess(:final student):
        setState(() {
          _student = student;
          _isLoading = false;
        });
        widget.onLoaded?.call(student);
      case StudentNotFound():
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
      case StudentFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      case StudentListSuccess():
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notFound) {
      return const AppEmptyState(
        icon: Icons.school_outlined,
        title: 'Your student profile is not set up yet',
        message:
            'Finish adding your school details and your subjects, teachers '
            'and lessons will appear here.',
      );
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load your profile',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: reload,
      );
    }
    return widget.builder(context, _student!);
  }
}

/// A small "English · Form 4" style line used across the student screens.
class StudentLevelLine extends StatelessWidget {
  const StudentLevelLine({super.key, required this.student, this.style});

  final Student student;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = student.qualifiedLevelLabel;
    if (label == null) return const SizedBox.shrink();
    return Text(label, style: style ?? AppTextStyles.body);
  }
}
