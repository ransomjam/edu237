import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:edu237/l10n/app_localizations.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/education_draft.dart';
import '../../core/models/user_role.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/profile_service.dart';
import '../../core/services/student_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/education_selectors.dart';
import '../../shared/widgets/role_choice_selector.dart';

import '../../core/constants/cameroon_locations.dart';
import '../../core/services/geo.dart';
import '../../core/services/location_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _customAreaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  UserRole _selectedRole = UserRole.parent;

  /// Student signup asks for the minimum: name, sign-in details (already
  /// collected) and the school details below. No address, no date of birth,
  /// no parent information.
  final EducationDraft _studentEducation = EducationDraft();

  /// True when the student says their parent already added them to Camiva.
  /// They then enter a one-time code instead of re-entering their school
  /// details, and their account attaches to the record that already exists.
  bool _hasParentCode = false;
  final _linkCodeController = TextEditingController();

  String _selectedCity = 'Yaoundé';
  String? _selectedArea = 'Bastos';
  GeoPoint? _gpsPoint;
  bool _isLocating = false;
  bool _isLoading = false;
  bool _hasPrefilled = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasPrefilled) return;
    _hasPrefilled = true;

    final appState = AppState.of(context);

    // Pre-fill name from the auth user if already known.
    final user = appState.currentUser;
    if (user != null && user.name.isNotEmpty) {
      _nameController.text = user.name;
    }

    // Carry over the role chosen at registration when this is the same
    // session. Otherwise the user simply answers again.
    final pending = appState.pendingRole;
    if (pending != null) _selectedRole = pending;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customAreaController.dispose();
    _linkCodeController.dispose();
    super.dispose();
  }

  Future<void> _fetchGpsLocation() async {
    final locationService = LocationServiceScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLocating = true);
    final result = await locationService.currentPosition();
    if (!mounted) return;
    setState(() => _isLocating = false);

    if (result.isSuccess && result.point != null) {
      setState(() {
        _gpsPoint = result.point;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('GPS location detected successfully!'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not access GPS. Please select your city/neighbourhood below.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final appState = AppState.of(context);
    final profileService = ProfileServiceScope.of(context);
    final user = appState.currentUser!;

    // A student must be able to end up attached to exactly one learner
    // record: either an existing one via a code, or a new one they describe.
    if (_selectedRole == UserRole.student) {
      if (_hasParentCode) {
        if (_linkCodeController.text.trim().isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please enter the code from your parent.';
          });
          return;
        }
      } else if (!_studentEducation.isComplete) {
        setState(() {
          _isLoading = false;
          _errorMessage = _studentEducation.levelCode == null
              ? _studentEducation.validationMessage(EducationStep.level)
              : _studentEducation.validationMessage(EducationStep.series);
        });
        return;
      }
    }

    final studentService = StudentServiceScope.of(context);
    final result = await profileService.completeOnboarding(
      userId: user.id,
      email: user.email,
      name: _nameController.text.trim(),
      activeRole: _selectedRole,
    );

    if (!mounted) return;

    switch (result) {
      case ProfileSuccess(:final user):
        if (_selectedRole == UserRole.parent) {
          final area = _selectedArea == 'Other / Custom'
              ? _customAreaController.text.trim()
              : _selectedArea;
          appState.setParentLocation(
            point: _gpsPoint,
            city: _selectedCity,
            area: area,
          );
        }

        if (_selectedRole == UserRole.student) {
          // Attach the account to a learner record. With a parent's code we
          // claim the record that already exists; without one we create the
          // student's own. Either way the account ends up on exactly one row,
          // and createMyStudentRecord returns the existing row if the account
          // is somehow already linked.
          final linked = _hasParentCode
              ? await studentService
                  .linkMyAccountWithCode(_linkCodeController.text)
              : await studentService.createMyStudentRecord(
                  name: _nameController.text.trim(),
                  levelCode: _studentEducation.levelCode!,
                  seriesCode: _studentEducation.seriesCode,
                  subjects: _studentEducation.subjects.toList(),
                );
          if (!mounted) return;
          if (linked is StudentFailure) {
            setState(() {
              _isLoading = false;
              _errorMessage = linked.message;
            });
            return;
          }
        }

        appState.setPendingRole(null);
        appState.setUser(user);
        context.go(AppRoutes.home);
      case ProfileFailure(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final knownNeighbourhoods =
        CameroonLocations.neighbourhoodsByCity[_selectedCity] ?? const [];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.pageHorizontalPadding,
            vertical: AppConstants.space32,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppConstants.space16),
                Text(l10n.onboardingTitle, style: AppTextStyles.display),
                const SizedBox(height: AppConstants.space8),
                Text(l10n.onboardingSubtitle, style: AppTextStyles.bodyLarge),
                const SizedBox(height: AppConstants.space32),
                AppTextField(
                  controller: _nameController,
                  label: l10n.onboardingNameLabel,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  enabled: !_isLoading,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.validationRequired
                      : null,
                ),
                const SizedBox(height: AppConstants.space24),
                Text(l10n.onboardingRoleLabel, style: AppTextStyles.label),
                const SizedBox(height: AppConstants.space12),
                RoleChoiceSelector(
                  selected: _selectedRole,
                  enabled: !_isLoading,
                  onChanged: (role) => setState(() {
                    _selectedRole = role;
                    _errorMessage = null;
                  }),
                ),

                // Student school details - the only extra thing a student is
                // asked for at signup.
                if (_selectedRole == UserRole.student) ...[
                  const SizedBox(height: AppConstants.space24),
                  Text(l10n.studentSetupTitle, style: AppTextStyles.h3),
                  const SizedBox(height: AppConstants.space8),

                  // Offered first, because taking the code keeps a child who
                  // already exists from being added to Camiva twice.
                  CheckboxListTile(
                    key: const Key('student_has_parent_code'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _hasParentCode,
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(() {
                              _hasParentCode = value ?? false;
                              _errorMessage = null;
                            }),
                    title: Text(
                      'My parent already added me to Camiva',
                      style: AppTextStyles.body,
                    ),
                    subtitle: Text(
                      'Enter the code they gave you and we will use the '
                      'profile they already made.',
                      style: AppTextStyles.caption,
                    ),
                  ),

                  if (_hasParentCode) ...[
                    const SizedBox(height: AppConstants.space12),
                    AppTextField(
                      controller: _linkCodeController,
                      label: 'Code from your parent',
                      textCapitalization: TextCapitalization.characters,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: AppConstants.space12),
                  ],

                  if (!_hasParentCode)
                    for (final step in _studentEducation.steps) ...[
                    Text(step.question, style: AppTextStyles.label),
                    const SizedBox(height: AppConstants.space8),
                    EducationStepView(
                      step: step,
                      draft: _studentEducation,
                      enabled: !_isLoading,
                      onChanged: () => setState(() => _errorMessage = null),
                    ),
                    const SizedBox(height: AppConstants.space20),
                  ],
                ],

                // Location selector for Parents
                if (_selectedRole == UserRole.parent) ...[
                  const SizedBox(height: AppConstants.space24),
                  Container(
                    padding: const EdgeInsets.all(AppConstants.space16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppConstants.radius),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Your Location in Cameroon',
                              style: AppTextStyles.h3.copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Camiva uses this to find home tutors near your residence and calculate travel distance.',
                          style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
                        ),
                        const SizedBox(height: 14),

                        // GPS button
                        OutlinedButton.icon(
                          onPressed: (_isLoading || _isLocating) ? null : _fetchGpsLocation,
                          icon: _isLocating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  _gpsPoint != null
                                      ? Icons.check_circle_rounded
                                      : Icons.my_location,
                                  size: 16,
                                  color: _gpsPoint != null
                                      ? AppColors.success
                                      : AppColors.primary,
                                ),
                          label: Text(
                            _gpsPoint != null
                                ? 'GPS Location Enabled'
                                : 'Use Device GPS Location',
                            style: AppTextStyles.label.copyWith(
                              color: _gpsPoint != null
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _gpsPoint != null
                                  ? AppColors.success
                                  : AppColors.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radius),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // City dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCity,
                          decoration: InputDecoration(
                            labelText: 'City / Town',
                            labelStyle: AppTextStyles.label,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radius),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            for (final c in CameroonLocations.cities)
                              DropdownMenuItem(
                                value: c,
                                child: Text(c, style: AppTextStyles.body),
                              ),
                          ],
                          onChanged: _isLoading
                              ? null
                              : (city) {
                                  if (city != null) {
                                    final hoods = CameroonLocations.neighbourhoodsByCity[city];
                                    setState(() {
                                      _selectedCity = city;
                                      _selectedArea = (hoods != null && hoods.isNotEmpty)
                                          ? hoods.first
                                          : null;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),

                        // Neighbourhood dropdown
                        DropdownButtonFormField<String>(
                          initialValue: knownNeighbourhoods.contains(_selectedArea)
                              ? _selectedArea
                              : (knownNeighbourhoods.isNotEmpty ? knownNeighbourhoods.first : 'Other / Custom'),
                          decoration: InputDecoration(
                            labelText: 'Neighbourhood / Quarter',
                            labelStyle: AppTextStyles.label,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radius),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            for (final n in knownNeighbourhoods)
                              DropdownMenuItem(
                                value: n,
                                child: Text(n, style: AppTextStyles.body),
                              ),
                            const DropdownMenuItem(
                              value: 'Other / Custom',
                              child: Text('Other / Custom...', style: AppTextStyles.body),
                            ),
                          ],
                          onChanged: _isLoading
                              ? null
                              : (area) {
                                  setState(() => _selectedArea = area);
                                },
                        ),
                        if (_selectedArea == 'Other / Custom') ...[
                          const SizedBox(height: 10),
                          AppTextField(
                            controller: _customAreaController,
                            label: 'Enter Quarter / Neighbourhood',
                            enabled: !_isLoading,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: AppConstants.space16),
                  _ErrorBanner(message: _errorMessage!),
                ],
                const SizedBox(height: AppConstants.space32),
                AppButton(
                  label: l10n.onboardingButton,
                  onPressed: _submit,
                  isLoading: _isLoading,
                  isFullWidth: true,
                ),
              ],
            ),
          ),
        ),
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
