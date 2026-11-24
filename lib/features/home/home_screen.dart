import 'package:flutter/material.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/state/app_state.dart';
import '../student/student_home_screen.dart';
import 'parent_home_screen.dart';
import 'teacher_home_screen.dart';

/// Routes the Home tab to the correct experience for the authenticated role.
///
/// Parents see their children; teachers see their teaching space; students see
/// their own lightweight learning home — never a parent dashboard.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = AppState.of(context).activeRole;
    if (role.isTeacher) {
      return const TeacherHomeScreen();
    }
    if (role.isStudent) {
      return const StudentHomeScreen();
    }
    return const ParentHomeScreen();
  }
}

/// Kept for backwards references; Home now delegates by role above.
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeTitle)),
      body: Center(child: Text(l10n.placeholderHome)),
    );
  }
}
