import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the microscopy add/edit form. Pass [sample] (and its [findings]) to
/// edit an existing record.
Future<bool?> showMicroscopySheet(
  BuildContext context, {
  required String caseId,
  MicroscopySample? sample,
  List<MicroscopyFinding> findings = const [],
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => MicroscopySheet(
      caseId: caseId,
      sample: sample,
      findings: findings,
    ),
  );
}

/// One scrolling form with progressive reveal, not a wizard: the probe kind
/// reveals the preparation, the examiner reveals the lab name, and the findings
/// list below is filtered to the terms that apply to the chosen probe.
///
/// A wizard was considered and rejected — `federfall-ui-prefers-unified-
/// consistent-views` favours one view, and the intake wizard exists because it
/// has ~20 fields. This has five, of which two are conditional.
class MicroscopySheet extends ConsumerStatefulWidget {
  const MicroscopySheet({
    required this.caseId,
    this.sample,
    this.findings = const [],
    super.key,
  });

  final String caseId;
  final MicroscopySample? sample;
  final List<MicroscopyFinding> findings;

  @override
  ConsumerState<MicroscopySheet> createState() => _MicroscopySheetState();
}

/// One free-text ("Sonstiges") row: a name the vocabulary does not have, with
/// its own grade.
class _FreeRow {
  _FreeRow({required this.text, required this.severity});

  final TextEditingController text;
  MicroscopySeverity severity;
}

class _MicroscopySheetState extends ConsumerState<MicroscopySheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _notes;
  late final TextEditingController _externalLab;
  late DateTime _examinedAt;
  MicroscopySampleType? _sampleType;
  MicroscopyMethod? _method;
  MicroscopyExaminedBy? _examinedBy;
  bool _noFindings = false;

  /// Grade per vocabulary entry id; an entry with no grade is simply not a
  /// finding on this sample.
  final Map<String, MicroscopySeverity> _grades = {};
  final List<_FreeRow> _freeRows = [];

  /// Stored attachments kept on save (edit only); removing one drops it.
  late final List<String> _existingAttachments;
  final _newFiles = <XFile>[];

  /// Set once the user has tried to save, so the required-probe error only
  /// appears after they asked for something impossible.
  bool _showSampleTypeError = false;

  bool get _isEditing => widget.sample != null;

  @override
  void initState() {
    super.initState();
    final s = widget.sample;
    _notes = TextEditingController(text: s?.notes ?? '');
    _externalLab = TextEditingController(text: s?.externalLab ?? '');
    _examinedAt =
        s?.examinedAt?.toLocal() ?? s?.created?.toLocal() ?? DateTime.now();
    _sampleType = s?.sampleType;
    _method = s?.method;
    _examinedBy = s?.examinedBy;
    _noFindings = s?.noFindings ?? false;
    _existingAttachments = [...?s?.attachments];
    for (final f in widget.findings) {
      final severity = f.severity;
      if (severity == null) continue;
      final type = f.findingType;
      if (type != null && type.isNotEmpty) {
        _grades[type] = severity;
      } else if (f.freeText case final text? when text.isNotEmpty) {
        _freeRows.add(
          _FreeRow(
            text: TextEditingController(text: text),
            severity: severity,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _externalLab.dispose();
    for (final row in _freeRows) {
      row.text.dispose();
    }
    super.dispose();
  }

  /// The vocabulary this probe offers, plus anything already graded on the
  /// record: a term a supervisor has since deactivated or narrowed must stay
  /// visible on the sample that already references it, or editing anything
  /// else would silently drop it.
  List<MicroscopyFindingType> _applicableTypes(
    List<MicroscopyFindingType> all,
  ) {
    final probe = _sampleType;
    return [
      for (final t in all)
        if (_grades.containsKey(t.id) || (t.active && _applies(t, probe))) t,
    ];
  }

  /// An entry with NO sample types ticked applies everywhere. Unset is what a
  /// supervisor gets by leaving the chips alone, and reading it as "applies to
  /// nothing" would make the entry they just created invisible in both lists.
  bool _applies(MicroscopyFindingType t, MicroscopySampleType? probe) =>
      t.sampleTypes.isEmpty || probe == null || t.sampleTypes.contains(probe);

  /// Switching the probe kind drops the grades that no longer have a row to
  /// sit on. Announced with an undo rather than done silently — the grade was
  /// a deliberate clinical entry, and the switch may itself be the mistake.
  void _onSampleTypeChanged(MicroscopySampleType next) {
    final previous = _sampleType;
    final previousMethod = _method;
    final all = ref.read(microscopyFindingTypesProvider).value ?? const [];
    final byId = {for (final t in all) t.id: t};
    final dropped = <String, MicroscopySeverity>{
      for (final entry in _grades.entries)
        if (byId[entry.key] case final type? when !_applies(type, next))
          entry.key: entry.value,
    };

    setState(() {
      _sampleType = next;
      _showSampleTypeError = false;
      // Direktabstrich / Flotation is a question about a faecal sample only;
      // the route clears it for a crop swab anyway, so do not leave a stale
      // value visible in the form.
      if (next != MicroscopySampleType.fecal) _method = null;
      _grades.removeWhere((id, _) => dropped.containsKey(id));
    });
    markDirty();

    if (dropped.isEmpty) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.microscopyGradesDropped(dropped.length)),
          action: SnackBarAction(
            label: l10n.microscopyUndo,
            // Undo puts the probe back too, not just the grades — otherwise
            // the restored rows would have nowhere to render.
            onPressed: () => setState(() {
              _sampleType = previous;
              _method = previousMethod;
              _grades.addAll(dropped);
            }),
          ),
        ),
      );
  }

  void _setGrade(String typeId, MicroscopySeverity? severity) {
    setState(() {
      if (severity == null) {
        _grades.remove(typeId);
      } else {
        _grades[typeId] = severity;
        // Grading anything contradicts "ohne Befund". Enforced here for feel
        // and in the route for truth.
        _noFindings = false;
      }
    });
    markDirty();
  }

  void _addFreeRow() {
    setState(() {
      _noFindings = false;
      _freeRows.add(
        _FreeRow(
          text: TextEditingController(),
          // A row you added by hand names something you saw, so it starts at
          // the weakest grade rather than at "no grade" — which the server
          // would reject anyway, severity being required on a finding.
          severity: MicroscopySeverity.plus,
        ),
      );
    });
    markDirty();
  }

  Future<void> _pickDate() async {
    final picked = await pickDateTime(context, initial: _examinedAt);
    if (picked != null) {
      setState(() => _examinedAt = picked);
      markDirty();
    }
  }

  Future<void> _addPhotos() async {
    final picked = await ref.read(imagePickerProvider).pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _newFiles.addAll(picked));
    markDirty();
  }

  Future<void> _capturePhoto() async {
    final shot = await ref
        .read(imagePickerProvider)
        .pickImage(source: ImageSource.camera);
    if (shot == null) return;
    setState(() => _newFiles.add(shot));
    markDirty();
  }

  Future<void> _addVideo(ImageSource source) async {
    // No new dependency: image_picker already covers both ends of this.
    final clip = await ref.read(imagePickerProvider).pickVideo(source: source);
    if (clip == null) return;
    setState(() => _newFiles.add(clip));
    markDirty();
  }

  Future<List<http.MultipartFile>> _multipartFiles() async {
    final files = <http.MultipartFile>[];
    for (final file in _newFiles) {
      files.add(
        http.MultipartFile.fromBytes(
          'attachments',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    }
    return files;
  }

  Uri Function(String)? _thumbUrl() {
    final repo = ref.watch(microscopySamplesRepositoryProvider).value;
    final id = widget.sample?.id;
    if (repo == null || id == null) return null;
    return (filename) => repo.fileUrl(id, filename, thumb: '200x200');
  }

  Future<void> _save() async {
    final probe = _sampleType;
    if (probe == null) {
      setState(() => _showSampleTypeError = true);
      return;
    }
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, _) = await requireUserOrg();
      final repo = await ref.read(microscopySamplesRepositoryProvider.future);
      final files = await _multipartFiles();
      final existing = widget.sample;

      // Who looked down the microscope. On a new in-house record that is the
      // person entering it; on an edit the stored examiner stands, so
      // correcting a typo does not reassign the examination to the editor.
      final examiner = switch (_examinedBy) {
        MicroscopyExaminedBy.inHouse => existing?.examiner ?? user.id,
        _ => '',
      };

      // One atomic call (federfall-lov0): the route persists the sample,
      // replaces the findings set and stores the attachments in a single
      // server-side transaction, so a mid-save network drop can never lose the
      // previous findings or duplicate the sample on retry.
      await repo.saveWithFindings({
        'id': ?existing?.id,
        if (existing == null) 'case': widget.caseId,
        'sample': {
          'sample_type': probe.wire,
          'method': ?_method?.wire,
          'examined_at': _examinedAt.toUtc().toIso8601String(),
          'examined_by': ?_examinedBy?.wire,
          'examiner': examiner,
          'external_lab': _examinedBy == MicroscopyExaminedBy.inHouse
              ? ''
              : _externalLab.text.trim(),
          'no_findings': _noFindings,
          'notes': _notes.text.trim(),
        },
        'findings': [
          for (final entry in _grades.entries)
            {'finding_type': entry.key, 'severity': entry.value.wire},
          for (final row in _freeRows)
            if (row.text.text.trim().isNotEmpty)
              {
                'free_text': row.text.text.trim(),
                'severity': row.severity.wire,
              },
        ],
        // The survivors; anything omitted is dropped server-side. Always sent
        // on an edit, so removing the last attachment actually removes it.
        if (existing != null) 'keep_attachments': _existingAttachments,
      }, attachments: files);
      ref.invalidate(caseBundleProvider(widget.caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final types = ref.watch(microscopyFindingTypesProvider);
    final applicable = _applicableTypes(types.value ?? const []);

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.microscopyEditTitle : l10n.microscopyNewTitle,
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
            showTime: true,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── The probe, and only then how it was prepared ────────────────
          Text(
            l10n.microscopyFieldSampleType,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<MicroscopySampleType>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final t in MicroscopySampleType.values)
                ButtonSegment(
                  value: t,
                  label: Text(microscopySampleTypeLabel(l10n, t)),
                ),
            ],
            selected: {?_sampleType},
            onSelectionChanged: isBusy
                ? null
                : (s) {
                    if (s.isEmpty) return;
                    _onSampleTypeChanged(s.first);
                  },
          ),
          if (_showSampleTypeError)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.microscopySampleTypeRequired,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_sampleType == MicroscopySampleType.fecal) ...[
            const SizedBox(height: AppSpacing.md),
            _ChipRow<MicroscopyMethod>(
              label: l10n.microscopyFieldMethod,
              values: MicroscopyMethod.values,
              selected: _method,
              enabled: !isBusy,
              labelOf: (v) => microscopyMethodLabel(l10n, v),
              onChanged: (v) {
                setState(() => _method = v);
                markDirty();
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),

          // ── Who did it, and only then where ─────────────────────────────
          _ChipRow<MicroscopyExaminedBy>(
            label: l10n.microscopyFieldExaminedBy,
            values: MicroscopyExaminedBy.values,
            selected: _examinedBy,
            enabled: !isBusy,
            labelOf: (v) => microscopyExaminedByLabel(l10n, v),
            onChanged: (v) {
              setState(() => _examinedBy = v);
              markDirty();
            },
          ),
          if (_examinedBy == MicroscopyExaminedBy.vet ||
              _examinedBy == MicroscopyExaminedBy.lab) ...[
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _externalLab,
              label: l10n.microscopyFieldExternalLab,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.words,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // ── Findings ────────────────────────────────────────────────────
          Text(
            l10n.microscopyFindingsSection,
            style: theme.textTheme.titleSmall,
          ),
          // "Ohne Befund" is about the whole sample, so it sits above the list
          // rather than in it. Leaving BOTH it and the grades unset is valid
          // and means "result pending" — with a lab that is the normal state
          // for a day or two.
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _noFindings,
            title: Text(l10n.microscopyFieldNoFindings),
            onChanged: isBusy
                ? null
                : (v) {
                    setState(() {
                      _noFindings = v ?? false;
                      if (_noFindings) {
                        _grades.clear();
                        for (final row in _freeRows) {
                          row.text.dispose();
                        }
                        _freeRows.clear();
                      }
                    });
                    markDirty();
                  },
          ),
          if (types.isLoading)
            const LinearProgressIndicator()
          else if (applicable.isEmpty && _freeRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                l10n.microscopyNoVocabulary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final type in applicable)
            _GradeRow(
              label: type.label,
              severity: _grades[type.id],
              enabled: !isBusy && !_noFindings,
              onChanged: (s) => _setGrade(type.id, s),
            ),
          for (var i = 0; i < _freeRows.length; i++)
            _FreeFindingRow(
              key: ObjectKey(_freeRows[i]),
              row: _freeRows[i],
              enabled: !isBusy && !_noFindings,
              onSeverityChanged: (s) {
                setState(() => _freeRows[i].severity = s);
                markDirty();
              },
              onRemove: () {
                setState(() => _freeRows.removeAt(i).text.dispose());
                markDirty();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isBusy || _noFindings ? null : _addFreeRow,
              icon: const Icon(Icons.add),
              label: Text(l10n.microscopyAddOther),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Attachments: photos AND video ───────────────────────────────
          Text(
            l10n.microscopyAttachmentsLabel,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_existingAttachments.isNotEmpty || _newFiles.isNotEmpty)
            EditablePhotoStrip(
              existing: _existingAttachments,
              newPhotos: _newFiles,
              thumbUrl: _thumbUrl(),
              onRemoveExisting: isBusy
                  ? null
                  : (i) {
                      setState(() => _existingAttachments.removeAt(i));
                      markDirty();
                    },
              onRemoveNew: isBusy
                  ? null
                  : (i) {
                      setState(() => _newFiles.removeAt(i));
                      markDirty();
                    },
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy ? null : _addPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.photoAddAction),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : _capturePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.photoCaptureAction),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : () => _addVideo(ImageSource.gallery),
                icon: const Icon(Icons.video_library_outlined),
                label: Text(l10n.microscopyAddVideo),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : () => _addVideo(ImageSource.camera),
                icon: const Icon(Icons.videocam_outlined),
                label: Text(l10n.microscopyRecordVideo),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          AppTextField(
            controller: _notes,
            label: l10n.examNotesLabel,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

/// A labelled single-select chip row over an enum, clearable by tapping the
/// selected chip.
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

/// One vocabulary row: the term, and a `+ / ++ / +++` selector that starts
/// unset — an ungraded term is simply not a finding on this sample.
class _GradeRow extends StatelessWidget {
  const _GradeRow({
    required this.label,
    required this.severity,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final MicroscopySeverity? severity;
  final bool enabled;
  final ValueChanged<MicroscopySeverity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          _SeveritySegments(
            severity: severity,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A "Sonstiges" row: a name the vocabulary does not carry, plus its grade.
class _FreeFindingRow extends StatelessWidget {
  const _FreeFindingRow({
    required this.row,
    required this.enabled,
    required this.onSeverityChanged,
    required this.onRemove,
    super.key,
  });

  final _FreeRow row;
  final bool enabled;
  final ValueChanged<MicroscopySeverity> onSeverityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: row.text,
                  label: l10n.microscopyOtherLabel,
                  enabled: enabled,
                  validator: Validators.required(l10n),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: _SeveritySegments(
              severity: row.severity,
              enabled: enabled,
              onChanged: (s) {
                // A free row always carries a grade; tapping the selected
                // segment must not clear it into an unsavable state.
                if (s != null) onSeverityChanged(s);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The `+ / ++ / +++` selector. The labels are symbols, not words — see
/// [microscopySeverityLabel].
class _SeveritySegments extends StatelessWidget {
  const _SeveritySegments({
    required this.severity,
    required this.enabled,
    required this.onChanged,
  });

  final MicroscopySeverity? severity;
  final bool enabled;
  final ValueChanged<MicroscopySeverity?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MicroscopySeverity>(
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      segments: [
        for (final s in MicroscopySeverity.values)
          ButtonSegment(value: s, label: Text(microscopySeverityLabel(s))),
      ],
      selected: {?severity},
      onSelectionChanged: enabled
          ? (s) => onChanged(s.isEmpty ? null : s.first)
          : null,
    );
  }
}
