import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edu237/l10n/app_localizations.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/education_catalogue.dart';
import '../../core/models/student.dart';
import '../../core/models/teacher_profile.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/geo.dart';
import '../../core/services/teacher_discovery.dart';
import '../../core/services/teacher_profile_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/edu_ui.dart';
import '../../shared/widgets/phosphor_icon.dart';
import 'discovery_map.dart';
import 'discovery_widgets.dart';
import 'teacher_profile_screen.dart';

/// How the results are presented.
enum _ViewMode { list, map }

class TeacherDiscoveryArgs {
  const TeacherDiscoveryArgs({required this.child, this.initialSubject});
  final Student child;
  final String? initialSubject;
}

/// Teacher discovery for a specific child: a beautiful, parent-first experience
/// that ranks real teacher profiles by relevance to the child (form + subject),
/// shows an approximate location on a map, and lets the parent switch between a
/// Map and a List. Location is optional — everything works without it.
class TeacherDiscoveryScreen extends StatefulWidget {
  const TeacherDiscoveryScreen({
    super.key,
    required this.child,
    this.initialSubject,
  });

  final Student child;
  final String? initialSubject;

  @override
  State<TeacherDiscoveryScreen> createState() => _TeacherDiscoveryScreenState();
}

class _TeacherDiscoveryScreenState extends State<TeacherDiscoveryScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<TeacherProfile> _profiles = const [];

  _ViewMode _view = _ViewMode.list;
  DiscoveryFilters _filters = const DiscoveryFilters();
  GeoPoint? _parentLocation;
  String? _selectedTeacherId;

  @override
  void initState() {
    super.initState();
    _filters = DiscoveryFilters(subject: widget.initialSubject);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppState.of(context);
    if (_parentLocation == null && appState.parentLocation != null) {
      _parentLocation = appState.parentLocation;
    }
    if (_isLoading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await TeacherProfileServiceScope.of(context).fetchTeachers();
    if (!mounted) return;

    switch (result) {
      case TeacherProfileListSuccess(:final profiles):
        setState(() {
          _profiles = profiles;
          _isLoading = false;
        });
      case TeacherProfileFailure(:final message):
        setState(() {
          _errorMessage = message;
          _isLoading = false;
        });
      case TeacherProfileSuccess():
        setState(() => _isLoading = false);
    }
  }

  List<DiscoveryTeacher> get _results => buildDiscovery(
        child: widget.child,
        teachers: _profiles,
        parentLocation: _parentLocation,
        filters: _filters,
      );

  List<DiscoveryTeacher> get _similarMatches {
    final currentIds = _results.map((r) => r.teacher.id).toSet();
    final parentCity = AppState.of(context).parentCity;
    
    // Get other teachers who are not in the current search results
    var others = _profiles.where((t) => !currentIds.contains(t.id)).toList();
    
    // Prioritize teachers in the same city as the parent
    if (parentCity != null && parentCity.trim().isNotEmpty) {
      final inCity = others.where((t) => t.city?.toLowerCase() == parentCity.trim().toLowerCase()).toList();
      if (inCity.isNotEmpty) {
        others = inCity;
      }
    }
    
    // Wrap them as DiscoveryTeacher items
    return others.map((t) {
      final location = effectiveLocationFor(t);
      final distanceKm = (_parentLocation != null && location != null)
          ? Geo.distanceKm(_parentLocation!, location)
          : null;
      
      final childSubjects = widget.child.subjects.toSet();
      final matchedSubjects = t.subjects.where(childSubjects.contains).toList();
      // Same subsystem-aware rule as ranking: an exact level match means the
      // teacher teaches this class in the learner's own subsystem.
      final formMatches = t.teachesLevel(widget.child.level?.code);

      return DiscoveryTeacher(
        teacher: t,
        score: matchedSubjects.length * 10 + (formMatches ? 8 : 0),
        matchedSubjects: matchedSubjects,
        formMatches: formMatches,
        location: location,
        distanceKm: distanceKm,
      );
    }).toList();
  }

  void _openTeacher(TeacherProfile teacher) {
    context.push(
      AppRoutes.teacherProfile,
      extra: TeacherProfileArgs(teacher: teacher, student: widget.child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.discoveryHeaderTitle(widget.child.name)),
      ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return AppEmptyState(
        iconName: PhosphorIcons.warningCircle,
        title: l10n.errorGenericTitle,
        message: _errorMessage!,
        actionLabel: l10n.retryButton,
        onAction: _load,
      );
    }

    final results = _results;

    return Column(
      children: [
        _FilterBar(
          child: widget.child,
          filters: _filters,
          view: _view,
          onSubject: (s) => setState(
              () => _filters = _filters.copyWith(subject: s)),
          onLevel: (code) =>
              setState(() => _filters = _filters.copyWith(levelCode: code)),
          onViewChanged: (v) => setState(() {
            _view = v;
            if (v == _ViewMode.map && _selectedTeacherId == null) {
              final located =
                  results.where((t) => t.hasLocation).toList();
              if (located.isNotEmpty) {
                _selectedTeacherId = located.first.teacher.userId;
              }
            }
          }),
        ),
        _ResultCountHeader(resultCount: results.length),
        Expanded(
          child: results.isEmpty
              ? _buildEmpty(l10n)
              : (_view == _ViewMode.list
                  ? _buildList(results)
                  : _buildMap(l10n, results)),
        ),
      ],
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    final filtered = _filters.hasAny;
    final similar = _similarMatches;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pageHorizontalPadding,
        vertical: AppConstants.space12,
      ),
      children: [
        // Custom Empty State card matching the screenshot style but inside Container
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(
                PhosphorIcons.magnifyingGlass,
                size: 48,
                color: AppColors.grey500,
              ),
              const SizedBox(height: 12),
              Text(
                filtered
                    ? l10n.discoveryEmptyNearbyTitle
                    : l10n.discoveryEmptyTitle,
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                filtered
                    ? l10n.discoveryEmptyNearbyBody
                    : l10n.discoveryEmptyBody(widget.child.name),
                style: const TextStyle(color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
              if (filtered) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _filters = const DiscoveryFilters()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(l10n.discoveryViewAll),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // WhatsApp & Call Contact Info
        const ContactUsSection(isForEmptyState: true),
        if (similar.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Other Teachers in your Area',
            style: AppTextStyles.h2.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...similar.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TeacherDiscoveryCard(
              item: item,
              childForm: widget.child.level?.label ?? widget.child.schoolLevel,
              onTap: () => _openTeacher(item.teacher),
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildList(List<DiscoveryTeacher> results) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space12,
        AppConstants.pageHorizontalPadding,
        AppConstants.space24,
      ),
      itemCount: results.length + 1, // Results plus the contact section at the end
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Padding(
            padding: EdgeInsets.only(top: AppConstants.space16),
            child: ContactUsSection(isForEmptyState: false),
          );
        }
        final item = results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.space12),
          child: TeacherDiscoveryCard(
            item: item,
            childForm: widget.child.level?.label ?? widget.child.schoolLevel,
            onTap: () => _openTeacher(item.teacher),
          ),
        );
      },
    );
  }

  Widget _buildMap(AppLocalizations l10n, List<DiscoveryTeacher> results) {
    final located = results.where((t) => t.hasLocation).toList();
    final selected = results
        .where((t) => t.teacher.userId == _selectedTeacherId)
        .cast<DiscoveryTeacher?>()
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space4,
        AppConstants.pageHorizontalPadding,
        AppConstants.space8,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DiscoveryMap(
              teachers: results,
              parentLocation: _parentLocation,
              selectedTeacherId: _selectedTeacherId,
              onSelect: (id) => setState(() => _selectedTeacherId = id),
            ),
          ),
          if (located.isEmpty)
            Positioned(
              left: AppConstants.space12,
              right: AppConstants.space12,
              top: AppConstants.space12,
              child: _InfoBanner(
                text: l10n.discoveryNoMapForTeacher,
              ),
            ),
          // Selected teacher card floats above the map.
          if (selected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppConstants.space12,
              child: TeacherDiscoveryCard(
                item: selected,
                childForm: widget.child.level?.label ?? widget.child.schoolLevel,
                selected: true,
                compact: true,
                onTap: () => _openTeacher(selected.teacher),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.child,
    required this.filters,
    required this.view,
    required this.onSubject,
    required this.onLevel,
    required this.onViewChanged,
  });

  final Student child;
  final DiscoveryFilters filters;
  final _ViewMode view;
  final ValueChanged<String?> onSubject;
  final ValueChanged<String?> onLevel;
  final ValueChanged<_ViewMode> onViewChanged;

  /// The classes offered by the filter: every class in the learner's
  /// subsystem, or the whole catalogue when the subsystem is not yet known.
  List<EducationLevel> get _levelOptions {
    final subsystem = child.effectiveSubsystem;
    if (subsystem == null) return EducationCatalogue.allLevels;
    return EducationCatalogue.levelsForSubsystem(subsystem);
  }

  String _levelFilterLabel(AppLocalizations l10n) {
    final selected = EducationCatalogue.levelByCode(filters.levelCode);
    return selected?.label ?? l10n.discoveryFilterAllForms;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subjectOptions = <String>[...child.subjects];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        8,
        AppConstants.pageHorizontalPadding,
        AppConstants.space4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _MenuFilter(
              label: filters.subject ?? l10n.discoveryFilterAllSubjects,
              active: filters.subject != null,
              options: [l10n.discoveryFilterAllSubjects, ...subjectOptions],
              onSelected: (value) =>
                  onSubject(value == l10n.discoveryFilterAllSubjects ? null : value),
            ),
            const SizedBox(width: 6),
            _MenuFilter(
              label: _levelFilterLabel(l10n),
              active: filters.levelCode != null,
              options: [
                l10n.discoveryFilterAllForms,
                // Only the learner's own subsystem: offering "Form 4" to a
                // French-subsystem learner would be meaningless.
                for (final level in _levelOptions) level.label,
              ],
              onSelected: (value) {
                if (value == l10n.discoveryFilterAllForms) {
                  onLevel(null);
                  return;
                }
                onLevel(EducationCatalogue.levelByLabel(value)?.code);
              },
            ),
            const SizedBox(width: 6),
            _ViewToggleInline(
              view: view,
              onChanged: onViewChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuFilter extends StatelessWidget {
  const _MenuFilter({
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final o in options)
          PopupMenuItem<String>(value: o, child: Text(o)),
      ],
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: active ? AppColors.primary : AppColors.grey700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: active ? AppColors.primary : AppColors.grey500,
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggleInline extends StatelessWidget {
  const _ViewToggleInline({
    required this.view,
    required this.onChanged,
  });

  final _ViewMode view;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewSegment(
            key: const Key('discovery_view_list'),
            label: l10n.discoveryViewList,
            iconName: PhosphorIcons.listBullets,
            active: view == _ViewMode.list,
            onTap: () => onChanged(_ViewMode.list),
          ),
          _ViewSegment(
            key: const Key('discovery_view_map'),
            label: l10n.discoveryViewMap,
            iconName: PhosphorIcons.mapTrifold,
            active: view == _ViewMode.map,
            onTap: () => onChanged(_ViewMode.map),
          ),
        ],
      ),
    );
  }
}

class _ResultCountHeader extends StatelessWidget {
  const _ResultCountHeader({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pageHorizontalPadding,
        AppConstants.space4,
        AppConstants.pageHorizontalPadding,
        AppConstants.space4,
      ),
      child: Row(
        children: [
          Text(
            l10n.discoveryResultCount(resultCount),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.grey500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewSegment extends StatelessWidget {
  const _ViewSegment({
    super.key,
    required this.label,
    required this.iconName,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String iconName;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(iconName,
                  size: 13.5,
                  color: active ? AppColors.primary : AppColors.grey500),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: active ? AppColors.primary : AppColors.grey500,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space12, vertical: AppConstants.space8),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(PhosphorIcons.info, size: 15, color: AppColors.grey500),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: AppTextStyles.caption)),
        ],
      ),
    );
  }
}

class ContactUsSection extends StatelessWidget {
  const ContactUsSection({super.key, this.isForEmptyState = false});
  final bool isForEmptyState;

  Future<void> _launchWhatsApp() async {
    final url = Uri.parse('https://wa.me/237671308991');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchCall() async {
    final url = Uri.parse('tel:+237671308991');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.iconContainerBg,
              shape: BoxShape.circle,
            ),
            child: const PhosphorIcon(
              PhosphorIcons.phoneCall,
              size: 26,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isForEmptyState
                ? 'Contact us directly to allocate a teacher for your specific needs'
                : 'Need a teacher for other subjects or specific needs?',
            style: AppTextStyles.h3.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'We can match you manually with a qualified tutor.',
            style: TextStyle(color: AppColors.grey500, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _launchWhatsApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const PhosphorIcon(PhosphorIcons.whatsappLogo, size: 18, color: Colors.white),
                  label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _launchCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const PhosphorIcon(PhosphorIcons.phone, size: 18, color: Colors.white),
                  label: const Text('Call Us', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
