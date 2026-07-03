import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the structured-exam add/edit form (FED-4.8). Pass [exam] (and its
/// [findings]) to edit an existing one.
Future<bool?> showExamSheet(
  BuildContext context, {
  required String caseId,
  required String animalId,
  Exam? exam,
  List<ExamFinding> findings = const [],
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => ExamSheet(
      caseId: caseId,
      animalId: animalId,
      exam: exam,
      findings: findings,
    ),
  );
}

/// Form for a structured physical exam: top-line vitals (always visible) over a
/// collapsed by-system findings checklist, then free notes. Nothing is required
/// — an empty exam is valid, and only the systems actually assessed are stored.
class ExamSheet extends ConsumerStatefulWidget {
  const ExamSheet({
    required this.caseId,
    required this.animalId,
    this.exam,
    this.findings = const [],
    super.key,
  });

  final String caseId;
  final String animalId;
  final Exam? exam;
  final List<ExamFinding> findings;

  @override
  ConsumerState<ExamSheet> createState() => _ExamSheetState();
}

class _ExamSheetState extends ConsumerState<ExamSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _notes;
  late final TextEditingController _weight;
  late final TextEditingController _temperature;
  late final Map<BodySystem, TextEditingController> _findingNotes;
  late DateTime _examinedAt;
  int? _bodyCondition;
  Hydration? _hydration;
  Mentation? _mentation;
  MmColor? _mmColor;
  MmTexture? _mmTexture;
  final Map<BodySystem, FindingStatus> _findingStatus = {};

  bool get _isEditing => widget.exam != null;

  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    _notes = TextEditingController(text: e?.notes ?? '');
    _weight = TextEditingController();
    _temperature = TextEditingController(
      text: e?.temperature == null ? '' : '${e!.temperature}',
    );
    _examinedAt = e?.examinedAt?.toLocal() ?? DateTime.now();
    _bodyCondition = e?.bodyCondition;
    _hydration = e?.hydration;
    _mentation = e?.mentation;
    _mmColor = e?.mmColor;
    _mmTexture = e?.mmTexture;
    _findingNotes = {
      for (final s in BodySystem.values) s: TextEditingController(),
    };
    for (final f in widget.findings) {
      final system = f.system;
      final status = f.status;
      if (system == null || status == null) continue;
      _findingStatus[system] = status;
      _findingNotes[system]!.text = f.note ?? '';
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _weight.dispose();
    _temperature.dispose();
    for (final c in _findingNotes.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseNumber(String raw) =>
      double.tryParse(raw.trim().replaceFirst(',', '.'));

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initial: _examinedAt,
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) {
      setState(() => _examinedAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    final ok = await runSave(() async {
      await requireUserOrg();
      final exams = await ref.read(examsRepositoryProvider.future);

      // One atomic call (federfall-lov0): the hook route persists the exam,
      // replaces the findings set and creates the optional exam weight in a
      // single server-side transaction — a mid-save network drop can no
      // longer lose the previous findings or duplicate the exam on retry.
      // A weight taken at the exam becomes a real Weight entry (single source
      // of truth + trend), not a field on the exam. Create-path only so
      // editing the exam can't silently duplicate it.
      final existing = widget.exam;
      final weight = existing == null ? _parseNumber(_weight.text) : null;
      await exams.saveWithFindings({
        'id': ?existing?.id,
        if (existing == null) ...{
          'case': widget.caseId,
          'animal': widget.animalId,
        },
        'exam': {
          'examined_at': _examinedAt.toUtc().toIso8601String(),
          'body_condition': ?_bodyCondition,
          'hydration': ?_hydration?.wire,
          'mentation': ?_mentation?.wire,
          'temperature': ?_parseNumber(_temperature.text),
          'mm_color': ?_mmColor?.wire,
          'mm_texture': ?_mmTexture?.wire,
          'notes': _notes.text.trim(),
        },
        'findings': [
          for (final entry in _findingStatus.entries)
            {
              'system': entry.key.wire,
              'status': entry.value.wire,
              'note': _findingNotes[entry.key]!.text.trim(),
            },
        ],
        if (weight != null && weight > 0) 'weight_g': weight,
      });
      // One bundle refetch covers the exam, its findings and the exam weight.
      ref.invalidate(caseBundleProvider(widget.caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.examEditTitle : l10n.examNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.examDateLabel,
            value: _examinedAt,
            enabled: !isBusy,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Zone 1 — vitals, always visible (the fast path).
          Text(l10n.examGeneralSection, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Weight becomes a Weight entry on save; only on a new
              // exam, so editing can't duplicate it. Hidden when editing.
              if (!_isEditing) ...[
                Expanded(
                  child: AppTextField(
                    controller: _weight,
                    label: l10n.examWeightLabel,
                    prefixIcon: Icons.scale_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: AppTextField(
                  controller: _temperature,
                  label: l10n.examTemperatureLabel,
                  prefixIcon: Icons.thermostat_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  enabled: !isBusy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.examBodyConditionLabel, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<int>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (var i = 1; i <= 5; i++)
                ButtonSegment(value: i, label: Text('$i')),
            ],
            selected: {?_bodyCondition},
            onSelectionChanged: isBusy
                ? null
                : (s) {
                    setState(() => _bodyCondition = s.isEmpty ? null : s.first);
                    markDirty();
                  },
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.examBodyConditionHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipRow<Hydration>(
            label: l10n.examHydrationLabel,
            values: Hydration.values,
            selected: _hydration,
            enabled: !isBusy,
            labelOf: (v) => hydrationLabel(l10n, v),
            onChanged: (v) {
              setState(() => _hydration = v);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipRow<Mentation>(
            label: l10n.examMentationLabel,
            values: Mentation.values,
            selected: _mentation,
            enabled: !isBusy,
            labelOf: (v) => mentationLabel(l10n, v),
            onChanged: (v) {
              setState(() => _mentation = v);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipRow<MmColor>(
            label: l10n.examMmColorLabel,
            values: MmColor.values,
            selected: _mmColor,
            enabled: !isBusy,
            labelOf: (v) => mmColorLabel(l10n, v),
            onChanged: (v) {
              setState(() => _mmColor = v);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipRow<MmTexture>(
            label: l10n.examMmTextureLabel,
            values: MmTexture.values,
            selected: _mmTexture,
            enabled: !isBusy,
            labelOf: (v) => mmTextureLabel(l10n, v),
            onChanged: (v) {
              setState(() => _mmTexture = v);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Zone 2 — by-system findings, collapsed by default.
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              title: Text(
                l10n.examFindingsSection,
                style: theme.textTheme.titleSmall,
              ),
              children: [
                for (final system in BodySystem.values)
                  _FindingRow(
                    label: bodySystemLabel(l10n, system),
                    status: _findingStatus[system],
                    noteController: _findingNotes[system]!,
                    enabled: !isBusy,
                    onStatusChanged: (status) {
                      setState(() {
                        if (status == null) {
                          _findingStatus.remove(system);
                        } else {
                          _findingStatus[system] = status;
                        }
                      });
                      markDirty();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Zone 3 — free notes.
          AppTextField(
            controller: _notes,
            label: l10n.examNotesLabel,
            enabled: !isBusy,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

/// A labelled single-select chip row over an enum, with a clearable selection
/// (tap the selected chip to go back to "not assessed").
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.enabled,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final bool enabled;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: selected == v,
                onSelected: enabled ? (sel) => onChanged(sel ? v : null) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// One body-system row: a tri-state normal/abnormal selector (empty = not
/// assessed) with a note field that appears only once marked abnormal.
class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.label,
    required this.status,
    required this.noteController,
    required this.enabled,
    required this.onStatusChanged,
  });

  final String label;
  final FindingStatus? status;
  final TextEditingController noteController;
  final bool enabled;
  final ValueChanged<FindingStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              SegmentedButton<FindingStatus>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: FindingStatus.normal,
                    label: Text(findingStatusLabel(l10n, FindingStatus.normal)),
                  ),
                  ButtonSegment(
                    value: FindingStatus.abnormal,
                    label: Text(
                      findingStatusLabel(l10n, FindingStatus.abnormal),
                    ),
                  ),
                ],
                selected: {?status},
                onSelectionChanged: enabled
                    ? (s) => onStatusChanged(s.isEmpty ? null : s.first)
                    : null,
              ),
            ],
          ),
          if (status == FindingStatus.abnormal)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: AppTextField(
                controller: noteController,
                label: l10n.examFindingNoteLabel,
                enabled: enabled,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
        ],
      ),
    );
  }
}
