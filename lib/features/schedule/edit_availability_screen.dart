import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/teacher_availability.dart';
import '../../core/services/teacher_availability_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';

/// Editable per-day state: whether the teacher is available and, if so, the
/// single daily window.
class _DayState {
  _DayState({required this.available, required this.start, required this.end});
  bool available;
  TimeOfDay start;
  TimeOfDay end;
}

/// Set the teacher's recurring weekly availability with a very simple
/// interaction: for each day, toggle Available, then tap Start / End time
/// pickers. No typing.
class EditAvailabilityScreen extends StatefulWidget {
  const EditAvailabilityScreen({super.key});

  @override
  State<EditAvailabilityScreen> createState() => _EditAvailabilityScreenState();
}

class _EditAvailabilityScreenState extends State<EditAvailabilityScreen> {
  static const _defaultStart = TimeOfDay(hour: 16, minute: 0);
  static const _defaultEnd = TimeOfDay(hour: 20, minute: 0);

  final Map<int, _DayState> _days = {
    for (final d in WeeklyAvailability.weekdayOrder)
      d: _DayState(available: false, start: _defaultStart, end: _defaultEnd),
  };

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    final result =
        await TeacherAvailabilityServiceScope.of(context).fetchMyAvailability();
    if (!mounted) return;
    if (result is AvailabilitySuccess) {
      for (final slot in result.availability.slots) {
        final s = _days[slot.weekday];
        if (s != null) {
          s.available = true;
          s.start = slot.start;
          s.end = slot.end;
        }
      }
    }
    setState(() => _isLoading = false);
  }

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(int weekday, {required bool isStart}) async {
    final day = _days[weekday]!;
    final initial = isStart ? day.start : day.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart
          ? 'Start time · ${kWeekdayLong[weekday]}'
          : 'End time · ${kWeekdayLong[weekday]}',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        day.start = picked;
        // Keep end after start for a sensible default.
        if (_minutes(day.end) <= _minutes(picked)) {
          final endM = (_minutes(picked) + 60).clamp(0, 1439);
          day.end = TimeOfDay(hour: endM ~/ 60, minute: endM % 60);
        }
      } else {
        day.end = picked;
      }
    });
  }

  Future<void> _save() async {
    // Validate every enabled day has end after start.
    for (final entry in _days.entries) {
      final d = entry.value;
      if (d.available && _minutes(d.end) <= _minutes(d.start)) {
        setState(() => _error =
            '${kWeekdayLong[entry.key]}: end time must be after start time.');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final slots = <AvailabilitySlot>[
      for (final d in WeeklyAvailability.weekdayOrder)
        if (_days[d]!.available)
          AvailabilitySlot(
            weekday: d,
            startMinute: _minutes(_days[d]!.start),
            endMinute: _minutes(_days[d]!.end),
          ),
    ];

    final result =
        await TeacherAvailabilityServiceScope.of(context).saveMyAvailability(slots);
    if (!mounted) return;

    if (result is AvailabilitySuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability saved.')),
      );
      context.pop(true);
    } else if (result is AvailabilityFailure) {
      setState(() {
        _isSaving = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding:
                          const EdgeInsets.all(AppConstants.pageHorizontalPadding),
                      children: [
                        Text(
                          'Set the days and times you normally teach. Parents see this on your profile, and lessons can only be scheduled inside these hours.',
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.grey500),
                        ),
                        const SizedBox(height: AppConstants.space16),
                        for (final d in WeeklyAvailability.weekdayOrder)
                          _DayRow(
                            weekday: d,
                            state: _days[d]!,
                            onToggle: (v) =>
                                setState(() => _days[d]!.available = v),
                            onPickStart: () => _pickTime(d, isStart: true),
                            onPickEnd: () => _pickTime(d, isStart: false),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: AppConstants.space12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppConstants.space12),
                            decoration: BoxDecoration(
                              color: AppColors.errorLight,
                              borderRadius:
                                  BorderRadius.circular(AppConstants.radius),
                            ),
                            child: Text(_error!,
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.error)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.pageHorizontalPadding,
                      AppConstants.space12,
                      AppConstants.pageHorizontalPadding,
                      AppConstants.space16,
                    ),
                    child: AppButton(
                      label: 'Save availability',
                      isFullWidth: true,
                      isLoading: _isSaving,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.weekday,
    required this.state,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final int weekday;
  final _DayState state;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.space12),
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: state.available ? AppColors.primary : AppColors.border,
          width: state.available ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kWeekdayLong[weekday], style: AppTextStyles.h3),
              ),
              Text(
                state.available ? 'Available' : 'Unavailable',
                style: AppTextStyles.caption.copyWith(
                  color:
                      state.available ? AppColors.primary : AppColors.grey500,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Switch(value: state.available, onChanged: onToggle),
            ],
          ),
          if (state.available) ...[
            const SizedBox(height: AppConstants.space8),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Start',
                    value: formatTimeOfDay(state.start),
                    onTap: onPickStart,
                  ),
                ),
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: AppConstants.space12),
                  child: Text('–'),
                ),
                Expanded(
                  child: _TimeButton(
                    label: 'End',
                    value: formatTimeOfDay(state.end),
                    onTap: onPickEnd,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.grey100,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space12, vertical: AppConstants.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 15),
                  const SizedBox(width: 6),
                  Text(value, style: AppTextStyles.labelLarge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
