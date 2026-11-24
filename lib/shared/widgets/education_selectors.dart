import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/education_catalogue.dart';
import '../../core/models/education_draft.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The one set of education pickers used everywhere in the product:
/// parent children, student profile, teacher onboarding, teacher profile and
/// discovery filters. Nothing else may build its own level or subject list.
///
/// Every selector reads from [EducationCatalogue], so the hierarchy shown to a
/// parent is exactly the hierarchy shown to a teacher.

// ---------------------------------------------------------------------------
// Step 1 — education system
// ---------------------------------------------------------------------------

/// "Which education system?" — English Subsystem / French Subsystem.
class SubsystemSelector extends StatelessWidget {
  const SubsystemSelector({
    super.key,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final EducationSubsystem? selected;
  final ValueChanged<EducationSubsystem> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final subsystem in EducationSubsystem.values) ...[
          EduSelectableRow(
            key: Key('subsystem_${subsystem.code}'),
            label: subsystem.label,
            subtitle: switch (subsystem) {
              EducationSubsystem.english =>
                'Class 1 – Class 6 · Form 1 – Form 5 · Lower & Upper Sixth',
              EducationSubsystem.french =>
                'SIL – CM2 · 6ème – 3ème · Seconde – Terminale',
            },
            selected: selected == subsystem,
            onTap: enabled ? () => onSelect(subsystem) : null,
          ),
          const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — school stage
// ---------------------------------------------------------------------------

/// "Primary or secondary?" in the wording of the chosen subsystem.
class SchoolStageSelector extends StatelessWidget {
  const SchoolStageSelector({
    super.key,
    required this.subsystem,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final EducationSubsystem subsystem;
  final SchoolStage? selected;
  final ValueChanged<SchoolStage> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stage in EducationCatalogue.stagesFor(subsystem)) ...[
          EduSelectableRow(
            key: Key('stage_${stage.code}'),
            label: stage.labelFor(subsystem),
            subtitle: EducationCatalogue.cyclesFor(subsystem, stage)
                .map((c) => c.label)
                .join(' · '),
            selected: selected == stage,
            onTap: enabled ? () => onSelect(stage) : null,
          ),
          const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — cycle
// ---------------------------------------------------------------------------

/// "Which cycle?" — Ordinary/Advanced Level, or First/Second Cycle.
///
/// When a stage has only one cycle (primary), callers normally skip this step
/// and select it automatically.
class CycleSelector extends StatelessWidget {
  const CycleSelector({
    super.key,
    required this.subsystem,
    required this.stage,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final EducationSubsystem subsystem;
  final SchoolStage stage;
  final EducationCycle? selected;
  final ValueChanged<EducationCycle> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cycle
            in EducationCatalogue.cyclesFor(subsystem, stage)) ...[
          EduSelectableRow(
            key: Key('cycle_${cycle.code}'),
            label: cycle.label,
            subtitle: cycle.subtitle,
            selected: selected == cycle,
            onTap: enabled ? () => onSelect(cycle) : null,
          ),
          const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — level
// ---------------------------------------------------------------------------

/// "Which class?" — a single class within a cycle.
class LevelSelector extends StatelessWidget {
  const LevelSelector({
    super.key,
    required this.cycle,
    required this.selectedCode,
    required this.onSelect,
    this.enabled = true,
  });

  final EducationCycle cycle;

  /// Canonical level code, e.g. `en.sec.ol.form4`.
  final String? selectedCode;
  final ValueChanged<String> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final level in EducationCatalogue.levelsForCycle(cycle)) ...[
          EduSelectableRow(
            key: Key('level_${level.code}'),
            label: level.label,
            subtitle: level.alternateLabel,
            selected: selectedCode == level.code,
            onTap: enabled ? () => onSelect(level.code) : null,
          ),
          const SizedBox(height: AppConstants.space12),
        ],
      ],
    );
  }
}

/// Multi-select classes. Used by teachers, who teach several levels at once.
class LevelMultiSelector extends StatelessWidget {
  const LevelMultiSelector({
    super.key,
    required this.cycles,
    required this.selectedCodes,
    required this.onToggle,
    this.enabled = true,
  });

  /// Cycles to offer, in order. Usually the cycles the teacher ticked.
  final List<EducationCycle> cycles;
  final Set<String> selectedCodes;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cycle in cycles) ...[
          Text(
            '${cycle.subsystem.shortLabel} · ${cycle.label}',
            style: AppTextStyles.label.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space8),
          EduChipMultiSelect(
            options: [
              for (final level in EducationCatalogue.levelsForCycle(cycle))
                EduChipOption(value: level.code, label: level.label),
            ],
            selected: selectedCodes,
            onToggle: enabled ? onToggle : null,
          ),
          const SizedBox(height: AppConstants.space20),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5 — series
// ---------------------------------------------------------------------------

/// "Which series?" for upper-secondary learners, grouped Arts / Science /
/// Other so the choice is structured rather than a flat list of codes.
class SeriesSelector extends StatelessWidget {
  const SeriesSelector({
    super.key,
    required this.cycle,
    required this.selectedCode,
    required this.onSelect,
    this.enabled = true,
  });

  final EducationCycle cycle;
  final String? selectedCode;
  final ValueChanged<String> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final grouped = EducationCatalogue.seriesByGroup(cycle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Text(
            entry.key.label,
            style: AppTextStyles.label.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space8),
          EduChipMultiSelect(
            options: [
              for (final series in entry.value)
                EduChipOption(
                  value: series.code,
                  label: series.description == null
                      ? series.label
                      : '${series.label} · ${series.description}',
                ),
            ],
            selected: selectedCode == null ? const {} : {selectedCode!},
            onToggle: enabled ? onSelect : null,
          ),
          const SizedBox(height: AppConstants.space20),
        ],
      ],
    );
  }
}

/// Multi-select series, for teachers who cover several.
class SeriesMultiSelector extends StatelessWidget {
  const SeriesMultiSelector({
    super.key,
    required this.cycles,
    required this.selectedCodes,
    required this.onToggle,
    this.enabled = true,
  });

  final List<EducationCycle> cycles;
  final Set<String> selectedCodes;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final seriesCycles = cycles.where((c) => c.hasSeries).toList();
    if (seriesCycles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cycle in seriesCycles)
          for (final entry in EducationCatalogue.seriesByGroup(cycle).entries) ...[
            Text(
              '${cycle.subsystem.shortLabel} · ${entry.key.label}',
              style: AppTextStyles.label.copyWith(color: AppColors.grey500),
            ),
            const SizedBox(height: AppConstants.space8),
            EduChipMultiSelect(
              options: [
                for (final series in entry.value)
                  EduChipOption(value: series.code, label: series.label),
              ],
              selected: selectedCodes,
              onToggle: enabled ? onToggle : null,
            ),
            const SizedBox(height: AppConstants.space20),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 6 — subjects
// ---------------------------------------------------------------------------

/// Context-aware subject multi-select.
///
/// Only ever shows subjects that belong to [cycle]; when a [series] is given
/// its suggested pool comes first and the rest of the cycle can be revealed.
/// Values are the subsystem-appropriate labels, which is what gets stored.
class SubjectSelector extends StatefulWidget {
  const SubjectSelector({
    super.key,
    required this.cycle,
    required this.selected,
    required this.onToggle,
    this.series,
    this.enabled = true,
  });

  final EducationCycle cycle;
  final EducationSeries? series;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  State<SubjectSelector> createState() => _SubjectSelectorState();
}

class _SubjectSelectorState extends State<SubjectSelector> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final labels = EducationCatalogue.subjectLabelsFor(
      cycle: widget.cycle,
      series: series,
      includeAllForCycle: _showAll,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (series != null) ...[
          Text(
            seriesSuggestionNote,
            style: AppTextStyles.caption.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space12),
        ],
        EduChipMultiSelect(
          options: [
            for (final label in labels)
              EduChipOption(value: label, label: label),
          ],
          selected: widget.selected,
          onToggle: widget.enabled ? widget.onToggle : null,
        ),
        if (series != null && !_showAll) ...[
          const SizedBox(height: AppConstants.space12),
          TextButton.icon(
            key: const Key('subjects_show_all'),
            onPressed: () => setState(() => _showAll = true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Show all subjects for this cycle'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher-side selectors (multi-select across the same hierarchy)
// ---------------------------------------------------------------------------

/// "Which education systems do you teach?" — a teacher may teach both.
class SubsystemMultiSelector extends StatelessWidget {
  const SubsystemMultiSelector({
    super.key,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final Set<EducationSubsystem> selected;
  final ValueChanged<EducationSubsystem> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return EduChipMultiSelect(
      options: [
        for (final subsystem in EducationSubsystem.values)
          EduChipOption(value: subsystem.code, label: subsystem.label),
      ],
      selected: selected.map((s) => s.code).toSet(),
      onToggle: enabled
          ? (code) {
              final subsystem = EducationSubsystem.fromCode(code);
              if (subsystem != null) onToggle(subsystem);
            }
          : null,
    );
  }
}

/// "Which cycles do you teach?" across the chosen subsystems. Cycles carry
/// their own stage, so ticking a cycle answers the stage question too.
class CycleMultiSelector extends StatelessWidget {
  const CycleMultiSelector({
    super.key,
    required this.subsystems,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final Set<EducationSubsystem> subsystems;
  final Set<EducationCycle> selected;
  final ValueChanged<EducationCycle> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (subsystems.isEmpty) return const _ChooseEarlierStep();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final subsystem in EducationSubsystem.values)
          if (subsystems.contains(subsystem))
            for (final stage in EducationCatalogue.stagesFor(subsystem)) ...[
              Text(
                '${subsystem.shortLabel} · ${stage.labelFor(subsystem)}',
                style: AppTextStyles.label.copyWith(color: AppColors.grey500),
              ),
              const SizedBox(height: AppConstants.space8),
              EduChipMultiSelect(
                options: [
                  for (final cycle
                      in EducationCatalogue.cyclesFor(subsystem, stage))
                    EduChipOption(value: cycle.code, label: cycle.label),
                ],
                selected: selected.map((c) => c.code).toSet(),
                onToggle: enabled
                    ? (code) {
                        final cycle = EducationCycle.fromCode(code);
                        if (cycle != null) onToggle(cycle);
                      }
                    : null,
              ),
              const SizedBox(height: AppConstants.space20),
            ],
      ],
    );
  }
}

/// Subjects offered across every cycle a teacher covers, grouped by cycle so
/// the list stays context-aware instead of becoming one giant catalogue dump.
class TeacherSubjectSelector extends StatelessWidget {
  const TeacherSubjectSelector({
    super.key,
    required this.cycles,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final List<EducationCycle> cycles;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (cycles.isEmpty) return const _ChooseEarlierStep();

    // A subject offered by two cycles of the same subsystem has the same
    // label, so show it once per cycle group but never twice in one group.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cycle in cycles) ...[
          Text(
            '${cycle.subsystem.shortLabel} · ${cycle.label}',
            style: AppTextStyles.label.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: AppConstants.space8),
          EduChipMultiSelect(
            options: [
              for (final label
                  in EducationCatalogue.subjectLabelsFor(cycle: cycle))
                EduChipOption(value: label, label: label),
            ],
            selected: selected,
            onToggle: enabled ? onToggle : null,
          ),
          const SizedBox(height: AppConstants.space20),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One step of the shared hierarchy
// ---------------------------------------------------------------------------

/// Renders whichever selector [step] calls for, reading and writing [draft].
///
/// This is the piece that makes the hierarchy reusable: Add Child, Edit Child,
/// student signup and the student profile all drive the same widget, so the
/// question order and wording can never diverge between them.
class EducationStepView extends StatelessWidget {
  const EducationStepView({
    super.key,
    required this.step,
    required this.draft,
    required this.onChanged,
    this.enabled = true,
  });

  final EducationStep step;
  final EducationDraft draft;
  final VoidCallback onChanged;
  final bool enabled;

  void _changed(void Function() mutate) {
    mutate();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case EducationStep.subsystem:
        return SubsystemSelector(
          selected: draft.subsystem,
          enabled: enabled,
          onSelect: (v) => _changed(() => draft.setSubsystem(v)),
        );

      case EducationStep.stage:
        final subsystem = draft.subsystem;
        if (subsystem == null) return const _ChooseEarlierStep();
        return SchoolStageSelector(
          subsystem: subsystem,
          selected: draft.stage,
          enabled: enabled,
          onSelect: (v) => _changed(() => draft.setStage(v)),
        );

      case EducationStep.cycle:
        final subsystem = draft.subsystem;
        final stage = draft.stage;
        if (subsystem == null || stage == null) return const _ChooseEarlierStep();
        return CycleSelector(
          subsystem: subsystem,
          stage: stage,
          selected: draft.cycle,
          enabled: enabled,
          onSelect: (v) => _changed(() => draft.setCycle(v)),
        );

      case EducationStep.level:
        final cycle = draft.cycle;
        if (cycle == null) return const _ChooseEarlierStep();
        return LevelSelector(
          cycle: cycle,
          selectedCode: draft.levelCode,
          enabled: enabled,
          onSelect: (v) => _changed(() => draft.setLevel(v)),
        );

      case EducationStep.series:
        final cycle = draft.cycle;
        if (cycle == null) return const _ChooseEarlierStep();
        return SeriesSelector(
          cycle: cycle,
          selectedCode: draft.seriesCode,
          enabled: enabled,
          onSelect: (v) => _changed(() => draft.setSeries(v)),
        );

      case EducationStep.subjects:
        final cycle = draft.cycle;
        if (cycle == null) return const _ChooseEarlierStep();
        return SubjectSelector(
          cycle: cycle,
          series: draft.series,
          selected: draft.subjects,
          enabled: enabled,
          onToggle: (label) => _changed(() => draft.toggleSubject(label)),
        );
    }
  }
}

class _ChooseEarlierStep extends StatelessWidget {
  const _ChooseEarlierStep();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Please answer the previous question first.',
      style: AppTextStyles.body.copyWith(color: AppColors.grey500),
    );
  }
}

// ---------------------------------------------------------------------------
// Review
// ---------------------------------------------------------------------------

/// The "Review" summary shown before saving an academic profile.
class EducationSummaryCard extends StatelessWidget {
  const EducationSummaryCard({
    super.key,
    required this.name,
    required this.levelCode,
    this.seriesCode,
    this.subjects = const <String>[],
  });

  final String name;
  final String? levelCode;
  final String? seriesCode;
  final List<String> subjects;

  @override
  Widget build(BuildContext context) {
    final level = EducationCatalogue.levelByCode(levelCode);
    final series = EducationCatalogue.seriesByCode(seriesCode);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AppTextStyles.h2),
          if (level != null) ...[
            const SizedBox(height: AppConstants.space8),
            _SummaryLine(text: level.subsystem.label),
            _SummaryLine(
              text: '${level.stage.labelFor(level.subsystem)} · '
                  '${level.cycle.label}',
            ),
            _SummaryLine(text: level.label, emphasised: true),
          ],
          if (series != null) _SummaryLine(text: series.qualifiedLabel),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space8),
            Text(
              subjects.join(' · '),
              style: AppTextStyles.body.copyWith(color: AppColors.grey700),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.text, this.emphasised = false});

  final String text;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: AppTextStyles.body.copyWith(
          color: emphasised ? AppColors.primary : AppColors.grey700,
          fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

/// A large, full-width tappable option with an obvious selected state.
class EduSelectableRow extends StatelessWidget {
  const EduSelectableRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = (subtitle ?? '').trim().isNotEmpty;
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space20,
            vertical: AppConstants.space12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            selected ? AppColors.primary : AppColors.grey900,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.grey500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.space12),
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

/// A value + label pair for [EduChipMultiSelect]. The value is what gets
/// stored (a code or a subject label); the label is what the user reads.
class EduChipOption {
  const EduChipOption({required this.value, required this.label});
  final String value;
  final String label;
}

/// A wrap of large tappable chips with obvious selected/unselected states.
class EduChipMultiSelect extends StatelessWidget {
  const EduChipMultiSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<EduChipOption> options;
  final Set<String> selected;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppConstants.space12,
      runSpacing: AppConstants.space12,
      children: [
        for (final option in options)
          _EduChip(
            label: option.label,
            selected: selected.contains(option.value),
            onTap: onToggle == null ? null : () => onToggle!(option.value),
          ),
      ],
    );
  }
}

class _EduChip extends StatelessWidget {
  const _EduChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space16,
            vertical: AppConstants.space12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check : Icons.add,
                size: 18,
                color: selected ? AppColors.white : AppColors.grey500,
              ),
              const SizedBox(width: AppConstants.space8),
              Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: selected ? AppColors.white : AppColors.grey900,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
