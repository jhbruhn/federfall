import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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

class _ExamSheetState extends ConsumerState<ExamSheet> {
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
  bool _busy = false;
  String? _error;

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
    final picked = await showDatePicker(
      context: context,
      initialDate: _examinedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _examinedAt = picked);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final user = await ref.read(currentUserProvider.future);
      final org = user?.org;
      if (user == null || org == null) {
        throw const RepositoryException('no org for current user');
      }
      final exams = await ref.read(examsRepositoryProvider.future);
      final findingsRepo =
          await ref.read(examFindingsRepositoryProvider.future);

      final body = <String, dynamic>{
        'examined_at': _examinedAt.toUtc().toIso8601String(),
        'body_condition': ?_bodyCondition,
        'hydration': ?_hydration?.wire,
        'mentation': ?_mentation?.wire,
        'temperature': ?_parseNumber(_temperature.text),
        'mm_color': ?_mmColor?.wire,
        'mm_texture': ?_mmTexture?.wire,
        'notes': _notes.text.trim(),
      };

      final String examId;
      final existing = widget.exam;
      if (existing == null) {
        examId = (await exams.create({
          ...body,
          'case': widget.caseId,
          'animal': widget.animalId,
          'examiner': user.id,
          'org': org,
        })).id;
        // A weight taken at the exam becomes a real Weight entry (single
        // source of truth + trend), not a field on the exam. Create-path only
        // so editing the exam can't silently duplicate it.
        final w = _parseNumber(_weight.text);
        if (w != null && w > 0) {
          final weights = await ref.read(weightsRepositoryProvider.future);
          await weights.create({
            'animal': widget.animalId,
            'case': widget.caseId,
            'weight_g': w,
            'measured_at': _examinedAt.toUtc().toIso8601String(),
            'author': user.id,
            'org': org,
          });
          ref.invalidate(weightsForCaseProvider(widget.caseId));
        }
      } else {
        examId = existing.id;
        await exams.update(examId, body);
        // Re-derive the findings from scratch: the assessed set is small, so a
        // clean replace is simpler than diffing.
        for (final f in widget.findings) {
          await findingsRepo.delete(f.id);
        }
      }

      for (final entry in _findingStatus.entries) {
        await findingsRepo.create({
          'exam': examId,
          'system': entry.key.wire,
          'status': entry.value.wire,
          'note': _findingNotes[entry.key]!.text.trim(),
          'org': org,
        });
      }

      ref
        ..invalidate(examsForCaseProvider(widget.caseId))
        ..invalidate(examFindingsForCaseProvider(widget.caseId));
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? l10n.examEditTitle : l10n.examNewTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            DateField(
              label: l10n.examDateLabel,
              value: _examinedAt,
              enabled: !_busy,
              onPick: _pickDate,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Zone 1 — vitals, always visible (the fast path).
            Text(l10n.examGeneralSection, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Weight becomes a Weight entry on save; only on a new exam, so
                // editing can't duplicate it. Hidden when editing.
                if (!_isEditing) ...[
                  Expanded(
                    child: AppTextField(
                      controller: _weight,
                      label: l10n.examWeightLabel,
                      prefixIcon: Icons.scale_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_busy,
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
                    enabled: !_busy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.examBodyConditionLabel,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<int>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                for (var i = 1; i <= 5; i++)
                  ButtonSegment(value: i, label: Text('$i')),
              ],
              selected: {?_bodyCondition},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(
                      () => _bodyCondition = s.isEmpty ? null : s.first,
                    ),
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
              enabled: !_busy,
              labelOf: (v) => hydrationLabel(l10n, v),
              onChanged: (v) => setState(() => _hydration = v),
            ),
            const SizedBox(height: AppSpacing.md),
            _ChipRow<Mentation>(
              label: l10n.examMentationLabel,
              values: Mentation.values,
              selected: _mentation,
              enabled: !_busy,
              labelOf: (v) => mentationLabel(l10n, v),
              onChanged: (v) => setState(() => _mentation = v),
            ),
            const SizedBox(height: AppSpacing.md),
            _ChipRow<MmColor>(
              label: l10n.examMmColorLabel,
              values: MmColor.values,
              selected: _mmColor,
              enabled: !_busy,
              labelOf: (v) => mmColorLabel(l10n, v),
              onChanged: (v) => setState(() => _mmColor = v),
            ),
            const SizedBox(height: AppSpacing.md),
            _ChipRow<MmTexture>(
              label: l10n.examMmTextureLabel,
              values: MmTexture.values,
              selected: _mmTexture,
              enabled: !_busy,
              labelOf: (v) => mmTextureLabel(l10n, v),
              onChanged: (v) => setState(() => _mmTexture = v),
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
                      enabled: !_busy,
                      onStatusChanged: (status) => setState(() {
                        if (status == null) {
                          _findingStatus.remove(system);
                        } else {
                          _findingStatus[system] = status;
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Zone 3 — free notes.
            AppTextField(
              controller: _notes,
              label: l10n.examNotesLabel,
              prefixIcon: Icons.notes_outlined,
              enabled: !_busy,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: l10n.actionSave,
              icon: Icons.check,
              isLoading: _busy,
              onPressed: _save,
            ),
          ],
        ),
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
                onSelected:
                    enabled ? (sel) => onChanged(sel ? v : null) : null,
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
              ),
            ),
        ],
      ),
    );
  }
}
