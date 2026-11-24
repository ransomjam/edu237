import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/cameroon_locations.dart';
import '../../core/constants/education_catalogue.dart';
import '../../core/models/teacher_availability.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/models/teaching_mode.dart';
import '../../core/services/location_service.dart';
import '../../core/services/teacher_availability_service.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/state/refresh_bus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/education_selectors.dart';
import '../../shared/widgets/photo_adjust_dialog.dart';
import 'discovery_widgets.dart';

class _DayState {
  _DayState({required this.available, required this.start, required this.end});
  bool available;
  TimeOfDay start;
  TimeOfDay end;
}

/// Create or edit the signed-in teacher's own profile. A single simple screen,
/// reusing the same subject/class pickers as the parent flow.
///
/// On success it pops the saved [TeacherProfile].
class EditTeacherProfileScreen extends StatefulWidget {
  const EditTeacherProfileScreen({super.key, this.existing});

  final TeacherProfile? existing;

  @override
  State<EditTeacherProfileScreen> createState() =>
      _EditTeacherProfileScreenState();
}

class _EditTeacherProfileScreenState extends State<EditTeacherProfileScreen> {
  static const _defaultStart = TimeOfDay(hour: 16, minute: 0);
  static const _defaultEnd = TimeOfDay(hour: 20, minute: 0);

  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;
  late final TextEditingController _areaController;
  late final TextEditingController _rateController;
  late final Set<String> _subjects;

  // Structured teaching profile, from the shared education catalogue.
  final Set<EducationSubsystem> _subsystems = <EducationSubsystem>{};
  final Set<EducationCycle> _cycles = <EducationCycle>{};
  final Set<String> _levelCodes = <String>{};
  final Set<String> _seriesCodes = <String>{};

  late TeachingMode _teachingMode;
  String? _title;
  double? _latitude;
  double? _longitude;
  String? _photoUrl;
  String? _coverUrl;

  final Map<int, _DayState> _days = {
    for (final d in WeeklyAvailability.weekdayOrder)
      d: _DayState(available: false, start: _defaultStart, end: _defaultEnd),
  };
  bool _loadedAvailability = false;

  bool _isLoading = false;
  bool _pinning = false;
  bool _uploadingPhoto = false;
  bool _uploadingCover = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.displayName ?? '');
    _bioController = TextEditingController(text: e?.bio ?? '');
    _cityController = TextEditingController(text: e?.city ?? '');
    _areaController = TextEditingController(text: e?.area ?? '');
    _rateController = TextEditingController(text: (e?.hourlyRate ?? 5000).toString());
    _subjects = (e?.subjects ?? const <String>[]).toSet();

    // `levels` resolves the stored codes, falling back to interpreting legacy
    // "Form 4"-style labels, so an older profile opens fully structured.
    for (final level in e?.levels ?? const <EducationLevel>[]) {
      _subsystems.add(level.subsystem);
      _cycles.add(level.cycle);
      _levelCodes.add(level.code);
    }
    _seriesCodes.addAll(e?.seriesCodes ?? const <String>[]);

    _teachingMode = e?.teachingMode ?? TeachingMode.inPerson;
    _title = e?.title;
    _latitude = e?.latitude;
    _longitude = e?.longitude;
    _photoUrl = e?.photoUrl;
    _coverUrl = e?.coverUrl;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedAvailability) {
      _loadedAvailability = true;
      _loadAvailability();
    }
  }

  Future<void> _loadAvailability() async {
    final result =
        await TeacherAvailabilityServiceScope.of(context).fetchMyAvailability();
    if (!mounted) return;
    if (result is AvailabilitySuccess) {
      setState(() {
        for (final slot in result.availability.slots) {
          final s = _days[slot.weekday];
          if (s != null) {
            s.available = true;
            s.start = slot.start;
            s.end = slot.end;
          }
        }
      });
    }
  }

  /// The teacher's cycles in catalogue order, so the pickers below always read
  /// the same way regardless of the order they were ticked.
  List<EducationCycle> get _orderedCycles => EducationCycle.values
      .where(_cycles.contains)
      .toList(growable: false);

  /// Dropping a subsystem drops everything selected underneath it, so a
  /// profile can never keep a French cycle after switching to English only.
  void _toggleSubsystem(EducationSubsystem subsystem) {
    setState(() {
      if (_subsystems.remove(subsystem)) {
        _cycles.removeWhere((c) => c.subsystem == subsystem);
        _pruneBelowCycles();
      } else {
        _subsystems.add(subsystem);
      }
    });
  }

  void _toggleCycle(EducationCycle cycle) {
    setState(() {
      if (!_cycles.remove(cycle)) {
        _cycles.add(cycle);
      }
      _pruneBelowCycles();
    });
  }

  /// Drops levels, series and subjects that no longer belong to a selected
  /// cycle. Subjects shared with a still-selected cycle are kept.
  void _pruneBelowCycles() {
    final cycles = _orderedCycles;
    final allowedLevels = <String>{
      for (final cycle in cycles)
        for (final level in EducationCatalogue.levelsForCycle(cycle))
          level.code,
    };
    final allowedSeries = <String>{
      for (final cycle in cycles)
        for (final series in EducationCatalogue.seriesForCycle(cycle))
          series.code,
    };
    final allowedSubjects = <String>{
      for (final cycle in cycles)
        ...EducationCatalogue.subjectLabelsFor(cycle: cycle),
    };
    _levelCodes.removeWhere((c) => !allowedLevels.contains(c));
    _seriesCodes.removeWhere((c) => !allowedSeries.contains(c));
    _subjects.removeWhere((s) => !allowedSubjects.contains(s));
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
        if (_minutes(day.end) <= _minutes(picked)) {
          final endM = (_minutes(picked) + 60).clamp(0, 1439);
          day.end = TimeOfDay(hour: endM ~/ 60, minute: endM % 60);
        }
      } else {
        day.end = picked;
      }
    });
  }

  /// Captures a deliberately coarse location for the teaching area: we round to
  /// 2 decimal places (~1 km) so a precise home is never stored or shown.
  Future<void> _pinCurrentArea() async {
    setState(() => _pinning = true);
    final l10n = AppLocalizations.of(context);
    final result = await LocationServiceScope.of(context).currentPosition();
    if (!mounted) return;
    setState(() => _pinning = false);

    if (result.isSuccess) {
      final p = result.point!;
      setState(() {
        _latitude = double.parse(p.latitude.toStringAsFixed(2));
        _longitude = double.parse(p.longitude.toStringAsFixed(2));
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teacherPinAreaDenied)),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null || !mounted) return;

    final rawBytes = await picked.readAsBytes();
    if (rawBytes.lengthInBytes > 10 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover image must be under 10 MB.')),
      );
      return;
    }

    final adjustedBytes = await PhotoAdjustDialog.show(
      context,
      rawBytes,
      aspectRatio: 16 / 9,
      title: 'Adjust Cover Photo',
    );
    if (adjustedBytes == null || !mounted) return;

    setState(() => _uploadingCover = true);
    final result = await TeacherProfileServiceScope.of(context)
        .uploadCoverPhoto(bytes: adjustedBytes, fileExtension: 'png');
    if (!mounted) return;
    setState(() => _uploadingCover = false);

    switch (result) {
      case TeacherProfileSuccess(:final profile):
        setState(() => _coverUrl = profile?.coverUrl);
        RefreshBusScope.maybeOf(context)?.profileChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover photo updated successfully.')),
        );
      case TeacherProfileFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        break;
    }
  }

  Future<void> _removeCoverPhoto() async {
    setState(() => _uploadingCover = true);
    final result =
        await TeacherProfileServiceScope.of(context).deleteCoverPhoto();
    if (!mounted) return;
    setState(() => _uploadingCover = false);

    switch (result) {
      case TeacherProfileSuccess():
        setState(() => _coverUrl = null);
        RefreshBusScope.maybeOf(context)?.profileChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover photo reset to default.')),
        );
      case TeacherProfileFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        break;
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;

    final rawBytes = await picked.readAsBytes();
    if (rawBytes.lengthInBytes > 10 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image must be under 10 MB.')),
      );
      return;
    }

    // Allow user to pan, zoom, and frame their photo in full square
    final adjustedBytes = await PhotoAdjustDialog.show(
      context,
      rawBytes,
      aspectRatio: 1.0,
      title: 'Adjust Profile Photo',
    );
    if (adjustedBytes == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    final result = await TeacherProfileServiceScope.of(context)
        .uploadProfilePhoto(bytes: adjustedBytes, fileExtension: 'png');
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);

    switch (result) {
      case TeacherProfileSuccess(:final profile):
        setState(() => _photoUrl = profile?.photoUrl);
        RefreshBusScope.maybeOf(context)?.profileChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).profilePhotoUpdated)),
        );
      case TeacherProfileFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        break;
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _uploadingPhoto = true);
    final result = await TeacherProfileServiceScope.of(context).deleteProfilePhoto();
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);

    switch (result) {
      case TeacherProfileSuccess():
        setState(() => _photoUrl = null);
        RefreshBusScope.maybeOf(context)?.profileChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).profilePhotoRemoved)),
        );
      case TeacherProfileFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      default:
        break;
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context).validationRequired);
      return;
    }

    // Validate availability times if enabled
    for (final entry in _days.entries) {
      final d = entry.value;
      if (d.available && _minutes(d.end) <= _minutes(d.start)) {
        setState(() => _errorMessage =
            '${kWeekdayLong[entry.key]}: end time must be after start time.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result =
        await TeacherProfileServiceScope.of(context).upsertMyProfile(
      displayName: _nameController.text,
      title: _title,
      subjects: _subjects.toList(),
      // `forms` is the denormalised label mirror of `levelCodes`; the model
      // re-derives it on write so the two can never drift.
      forms: _levelCodes
          .map(EducationCatalogue.levelByCode)
          .whereType<EducationLevel>()
          .map((l) => l.label)
          .toList(),
      levelCodes: _levelCodes.toList(),
      seriesCodes: _seriesCodes.toList(),
      bio: _bioController.text,
      city: _cityController.text,
      area: _areaController.text,
      latitude: _latitude,
      longitude: _longitude,
      teachingMode: _teachingMode,
      photoUrl: _photoUrl,
      coverUrl: _coverUrl,
      hourlyRate: int.tryParse(_rateController.text) ?? 5000,
    );

    if (!mounted) return;

    switch (result) {
      case TeacherProfileSuccess(:final profile):
        // Also save availability slots
        final slots = <AvailabilitySlot>[
          for (final d in WeeklyAvailability.weekdayOrder)
            if (_days[d]!.available)
              AvailabilitySlot(
                weekday: d,
                startMinute: _minutes(_days[d]!.start),
                endMinute: _minutes(_days[d]!.end),
              ),
        ];
        try {
          await TeacherAvailabilityServiceScope.of(context)
              .saveMyAvailability(slots);
        } catch (_) {}

        if (mounted) {
          RefreshBusScope.maybeOf(context)?.profileChanged();
          context.pop(profile);
        }
      case TeacherProfileFailure(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      case TeacherProfileListSuccess():
        setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.teacherEditTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.pageHorizontalPadding,
                  vertical: AppConstants.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Cover & Profile Photos Editor ---
                    _ProfilePhotosEditor(
                      name: _nameController.text,
                      photoUrl: _photoUrl,
                      coverUrl: _coverUrl,
                      isUploadingPhoto: _uploadingPhoto,
                      isUploadingCover: _uploadingCover,
                      onPickPhoto: _pickPhoto,
                      onRemovePhoto: _photoUrl != null ? _removePhoto : null,
                      onPickCover: _pickCoverPhoto,
                      onRemoveCover: _coverUrl != null ? _removeCoverPhoto : null,
                    ),
                    const SizedBox(height: AppConstants.space32),
                    Text('Title', style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Mr', 'Mrs', 'Ms', 'Dr', 'Prof', 'Engr'].map((t) {
                        final isSelected = _title == t;
                        return ChoiceChip(
                          label: Text(t),
                          selected: isSelected,
                          selectedColor: AppColors.primaryLight,
                          labelStyle: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.grey700,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            setState(() => _title = selected ? t : null);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppConstants.space24),
                    Text(l10n.teacherNameSection, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _nameController,
                      label: l10n.teacherNameLabel,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      enabled: !_isLoading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppConstants.space24),
                    Text('Lesson Fee (FCFA)', style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _rateController,
                      label: 'Price per lesson in FCFA (e.g. 5000)',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      enabled: !_isLoading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppConstants.space32),
                    Text('What do you teach?', style: AppTextStyles.h2),
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      'The same structure parents and students use, so you '
                      'appear in the right searches.',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: AppConstants.space24),
                    Text('Education system', style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    SubsystemMultiSelector(
                      selected: _subsystems,
                      enabled: !_isLoading,
                      onToggle: _toggleSubsystem,
                    ),
                    const SizedBox(height: AppConstants.space32),
                    Text('School stage and cycle', style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    CycleMultiSelector(
                      subsystems: _subsystems,
                      selected: _cycles,
                      enabled: !_isLoading,
                      onToggle: _toggleCycle,
                    ),
                    const SizedBox(height: AppConstants.space16),
                    Text(l10n.teacherFormsQuestion, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    if (_orderedCycles.isEmpty)
                      Text(
                        'Choose a cycle first.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.grey500),
                      )
                    else
                      LevelMultiSelector(
                        cycles: _orderedCycles,
                        selectedCodes: _levelCodes,
                        enabled: !_isLoading,
                        onToggle: (code) => setState(() {
                          if (!_levelCodes.remove(code)) _levelCodes.add(code);
                        }),
                      ),
                    if (_orderedCycles.any((c) => c.hasSeries)) ...[
                      const SizedBox(height: AppConstants.space16),
                      Text('Which series do you teach?',
                          style: AppTextStyles.h3),
                      const SizedBox(height: AppConstants.space12),
                      SeriesMultiSelector(
                        cycles: _orderedCycles,
                        selectedCodes: _seriesCodes,
                        enabled: !_isLoading,
                        onToggle: (code) => setState(() {
                          if (!_seriesCodes.remove(code)) {
                            _seriesCodes.add(code);
                          }
                        }),
                      ),
                    ],
                    const SizedBox(height: AppConstants.space16),
                    Text(l10n.teacherSubjectsQuestion, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    TeacherSubjectSelector(
                      cycles: _orderedCycles,
                      selected: _subjects,
                      enabled: !_isLoading,
                      onToggle: (s) => setState(() {
                        if (!_subjects.remove(s)) _subjects.add(s);
                      }),
                    ),
                    const SizedBox(height: AppConstants.space16),
                    Text(l10n.teacherLocationSection, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      l10n.teacherLocationHint,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: AppConstants.space12),
                    _LocationDropdowns(
                      cityController: _cityController,
                      areaController: _areaController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: AppConstants.space24),
                    _PinAreaSection(
                      hasPin: _latitude != null && _longitude != null,
                      pinning: _pinning,
                      enabled: !_isLoading,
                      onPin: _pinCurrentArea,
                      onClear: () => setState(() {
                        _latitude = null;
                        _longitude = null;
                      }),
                    ),
                    const SizedBox(height: AppConstants.space32),
                    Text(l10n.teacherModeQuestion, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space4),
                    const SizedBox(height: AppConstants.space12),
                    _TeachingModeSelector(
                      selected: _teachingMode,
                      onSelect: (m) => setState(() => _teachingMode = m),
                    ),
                    const SizedBox(height: AppConstants.space32),
                    Text(l10n.availabilitySection, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      'Select the days and hours you are available for lessons.',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: AppConstants.space12),
                    for (final d in WeeklyAvailability.weekdayOrder)
                      _DayRow(
                        weekday: d,
                        state: _days[d]!,
                        onToggle: (v) => setState(() => _days[d]!.available = v),
                        onPickStart: () => _pickTime(d, isStart: true),
                        onPickEnd: () => _pickTime(d, isStart: false),
                      ),
                    const SizedBox(height: AppConstants.space32),
                    Text(l10n.teacherBioSection, style: AppTextStyles.h3),
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _bioController,
                      label: l10n.teacherBioLabel,
                      textInputAction: TextInputAction.done,
                      maxLines: 3,
                      enabled: !_isLoading,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppConstants.space16),
                      _ErrorBanner(message: _errorMessage!),
                    ],
                    const SizedBox(height: AppConstants.space16),
                  ],
                ),
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
                label: l10n.teacherSaveProfile,
                isFullWidth: true,
                isLoading: _isLoading,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three large, tappable teaching-mode options.
class _TeachingModeSelector extends StatelessWidget {
  const _TeachingModeSelector({required this.selected, required this.onSelect});

  final TeachingMode selected;
  final ValueChanged<TeachingMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final mode in TeachingMode.values) ...[
          _ModeRow(
            mode: mode,
            selected: selected == mode,
            onTap: () => onSelect(mode),
          ),
          if (mode != TeachingMode.values.last)
            const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final TeachingMode mode;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (mode) {
        TeachingMode.online => Icons.videocam_outlined,
        TeachingMode.inPerson => Icons.handshake_outlined,
        TeachingMode.both => Icons.sync_alt,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16, vertical: AppConstants.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(_icon,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.grey500),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Text(
                  teachingModeLabel(l10n, mode),
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : AppColors.grey900,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.grey300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Optional coarse-coordinate pinning for the map. Requests location only on
/// tap, explains why first, and rounds the result so it's an area, not a home.
class _PinAreaSection extends StatelessWidget {
  const _PinAreaSection({
    required this.hasPin,
    required this.pinning,
    required this.enabled,
    required this.onPin,
    required this.onClear,
  });

  final bool hasPin;
  final bool pinning;
  final bool enabled;
  final VoidCallback onPin;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.teacherPinAreaTitle, style: AppTextStyles.label),
          const SizedBox(height: AppConstants.space4),
          Text(l10n.teacherPinAreaHint, style: AppTextStyles.bodySmall),
          const SizedBox(height: AppConstants.space12),
          if (hasPin)
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.success),
                const SizedBox(width: AppConstants.space8),
                Expanded(
                  child: Text(l10n.teacherPinAreaSet,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.success)),
                ),
                TextButton(
                  onPressed: enabled ? onClear : null,
                  child: Text(l10n.teacherPinAreaClear),
                ),
              ],
            )
          else
            AppButton(
              label: l10n.teacherPinAreaButton,
              variant: AppButtonVariant.outlined,
              isFullWidth: true,
              isLoading: pinning,
              leading: const Icon(Icons.my_location, size: 18),
              onPressed: enabled ? onPin : null,
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppConstants.radius),
      ),
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.error),
      ),
    );
  }
}

/// Visual editor showing the cover photo banner and square profile photo
class _ProfilePhotosEditor extends StatelessWidget {
  const _ProfilePhotosEditor({
    required this.name,
    required this.photoUrl,
    required this.coverUrl,
    required this.isUploadingPhoto,
    required this.isUploadingCover,
    required this.onPickPhoto,
    this.onRemovePhoto,
    required this.onPickCover,
    this.onRemoveCover,
  });

  final String name;
  final String? photoUrl;
  final String? coverUrl;
  final bool isUploadingPhoto;
  final bool isUploadingCover;
  final VoidCallback onPickPhoto;
  final VoidCallback? onRemovePhoto;
  final VoidCallback onPickCover;
  final VoidCallback? onRemoveCover;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile & Cover Photo', style: AppTextStyles.h3),
        const SizedBox(height: AppConstants.space4),
        Text(
          'Tap the cover banner or square photo below to change them.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey500),
        ),
        const SizedBox(height: AppConstants.space16),

        // --- Cover Banner with Overlapping Square Avatar ---
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Cover Image Stack
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((coverUrl ?? '').isNotEmpty)
                        Image.network(coverUrl!, fit: BoxFit.cover)
                      else
                        Image.asset(
                          'assets/images/teacher_cover.jpg',
                          fit: BoxFit.cover,
                        ),
                      if (isUploadingCover)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      else
                        // Change Cover Button overlay
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onPickCover,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white38,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.camera_alt,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      coverUrl != null
                                          ? 'Change Cover'
                                          : 'Add Cover',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Sub-bar with Avatar & Actions
                Padding(
                  padding: const EdgeInsets.all(AppConstants.space12),
                  child: Row(
                    children: [
                      // Square Avatar with camera trigger
                      GestureDetector(
                        onTap: isUploadingPhoto ? null : onPickPhoto,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: (photoUrl ?? '').isNotEmpty
                                    ? Image.network(photoUrl!, fit: BoxFit.cover)
                                    : const Center(
                                        child: Icon(
                                          Icons.school,
                                          size: 32,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                      ),
                              ),
                            ),
                            if (isUploadingPhoto)
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Positioned(
                                bottom: -4,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppConstants.space16),

                      // Buttons
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isUploadingPhoto ? null : onPickPhoto,
                                  icon: const Icon(Icons.photo, size: 14),
                                  label: Text(
                                    photoUrl != null
                                        ? l10n.profilePhotoChange
                                        : l10n.profilePhotoUpload,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                                if (onRemovePhoto != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                    tooltip: l10n.profilePhotoRemove,
                                    onPressed: isUploadingPhoto ? null : onRemovePhoto,
                                  ),
                                ],
                              ],
                            ),
                            if (onRemoveCover != null)
                              TextButton.icon(
                                onPressed: isUploadingCover ? null : onRemoveCover,
                                icon: const Icon(Icons.restore, size: 13),
                                label: const Text(
                                  'Reset cover to default',
                                  style: TextStyle(fontSize: 11),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.grey500,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationDropdowns extends StatefulWidget {
  const _LocationDropdowns({
    required this.cityController,
    required this.areaController,
    required this.enabled,
  });

  final TextEditingController cityController;
  final TextEditingController areaController;
  final bool enabled;

  @override
  State<_LocationDropdowns> createState() => _LocationDropdownsState();
}

class _LocationDropdownsState extends State<_LocationDropdowns> {
  String? _selectedCity;
  String? _selectedArea;
  bool _customCity = false;
  bool _customArea = false;

  @override
  void initState() {
    super.initState();
    _initFromControllers();
  }

  void _initFromControllers() {
    final currentCity = widget.cityController.text.trim();
    final currentArea = widget.areaController.text.trim();

    if (currentCity.isNotEmpty) {
      if (CameroonLocations.cities.contains(currentCity)) {
        _selectedCity = currentCity;
        _customCity = false;
      } else {
        _selectedCity = '__other__';
        _customCity = true;
      }
    } else {
      _selectedCity = 'Yaoundé';
      widget.cityController.text = 'Yaoundé';
    }

    final neighbourhoods = CameroonLocations.getNeighbourhoods(_selectedCity);
    if (currentArea.isNotEmpty) {
      if (neighbourhoods.contains(currentArea)) {
        _selectedArea = currentArea;
        _customArea = false;
      } else {
        _selectedArea = '__other__';
        _customArea = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final neighbourhoods = CameroonLocations.getNeighbourhoods(_selectedCity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- City Dropdown ---
        DropdownButtonFormField<String>(
          value: _selectedCity,
          decoration: InputDecoration(
            labelText: l10n.teacherCityLabel,
            prefixIcon: const Icon(Icons.location_city_outlined, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radius),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radius),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radius),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          items: [
            ...CameroonLocations.cities.map((city) {
              return DropdownMenuItem<String>(
                value: city,
                child: Text(
                  city == 'Yaoundé' ? 'Yaoundé (Centre)' : city,
                  style: city == 'Yaoundé'
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              );
            }),
            const DropdownMenuItem<String>(
              value: '__other__',
              child: Text('Other city...'),
            ),
          ],
          onChanged: widget.enabled
              ? (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedCity = value;
                    if (value == '__other__') {
                      _customCity = true;
                      widget.cityController.clear();
                      _selectedArea = '__other__';
                      _customArea = true;
                    } else {
                      _customCity = false;
                      widget.cityController.text = value;
                      _selectedArea = null;
                      _customArea = false;
                      widget.areaController.clear();
                    }
                  });
                }
              : null,
        ),

        if (_customCity) ...[
          const SizedBox(height: AppConstants.space12),
          AppTextField(
            controller: widget.cityController,
            label: 'Enter city name',
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
          ),
        ],

        const SizedBox(height: AppConstants.space16),

        // --- Neighbourhood / Area Dropdown ---
        if (!_customCity && neighbourhoods.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: _selectedArea,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.teacherAreaLabel,
              prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radius),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            items: [
              ...neighbourhoods.map((area) {
                return DropdownMenuItem<String>(
                  value: area,
                  child: Text(area),
                );
              }),
              const DropdownMenuItem<String>(
                value: '__other__',
                child: Text('Other neighbourhood...'),
              ),
            ],
            onChanged: widget.enabled
                ? (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedArea = value;
                      if (value == '__other__') {
                        _customArea = true;
                        widget.areaController.clear();
                      } else {
                        _customArea = false;
                        widget.areaController.text = value;
                      }
                    });
                  }
                : null,
          ),
        ],

        if (_customArea || neighbourhoods.isEmpty || _customCity) ...[
          if (!_customCity && neighbourhoods.isNotEmpty)
            const SizedBox(height: AppConstants.space12),
          AppTextField(
            controller: widget.areaController,
            label: 'Neighbourhood / Quarter (e.g. Bastos, Omnisports)',
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
          ),
        ],
      ],
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
