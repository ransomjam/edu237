import 'package:flutter/material.dart';
import 'app_colors.dart';

/// A restrained, education-specific colour language for subjects.
///
/// Four semantic families keep the UI legible without turning it into a game:
///   * Maths / ICT / Business  → blue
///   * Sciences                → green
///   * Languages               → purple
///   * Humanities              → amber
///
/// Each subject maps to a soft background + a strong foreground for chips.
class SubjectStyle {
  const SubjectStyle(this.background, this.foreground);
  final Color background;
  final Color foreground;

  static const _blue = SubjectStyle(Color(0xFFDBEAFE), Color(0xFF1D4ED8));
  static const _green = SubjectStyle(Color(0xFFDCFCE7), Color(0xFF15803D));
  static const _purple = SubjectStyle(Color(0xFFEDE9FE), Color(0xFF6D28D9));
  static const _amber = SubjectStyle(Color(0xFFFEF3C7), Color(0xFFB45309));
  static const _neutral = SubjectStyle(AppColors.grey100, AppColors.grey700);

  static const _sciences = {
    'biology',
    'chemistry',
    'physics',
    'human biology',
    'geology',
    'food and nutrition',
  };
  static const _languages = {
    'english language',
    'literature in english',
    'french',
    'special bilingual education french',
  };
  static const _humanities = {
    'geography',
    'history',
    'citizenship education',
    'religious studies',
    'economics',
    'commerce',
    'accounting',
  };
  static const _mathsIct = {
    'mathematics',
    'additional mathematics',
    'computer science',
    'logic',
  };

  static SubjectStyle of(String subject) {
    final s = subject.trim().toLowerCase();
    if (_mathsIct.contains(s)) return _blue;
    if (_sciences.contains(s)) return _green;
    if (_languages.contains(s)) return _purple;
    if (_humanities.contains(s)) return _amber;
    return _neutral;
  }
}
