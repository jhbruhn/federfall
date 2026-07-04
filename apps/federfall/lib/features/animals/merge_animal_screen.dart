import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Which record's value wins on a conflicting identity field.
enum _FieldChoice { current, other }

/// Which record's photo the survivor ends up with.
enum _PhotoChoice { current, other, none }

/// Supervisor duplicate-merge flow (federfall-eqy6): find the duplicate of
/// the animal opened from, pick which record survives, resolve any
/// conflicting identity fields, and submit — one atomic
/// `POST /api/federfall/merge-animals` call. Reachable only from the animal
/// detail screen's overflow menu (`canMergeAnimals`-gated); the server
/// re-checks the same role since the route bypasses collection API rules.
class MergeAnimalScreen extends ConsumerStatefulWidget {
  const MergeAnimalScreen({required this.animalId, super.key});

  final String animalId;

  @override
  ConsumerState<MergeAnimalScreen> createState() => _MergeAnimalScreenState();
}

class _MergeAnimalScreenState extends ConsumerState<MergeAnimalScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Animal? _candidate;

  bool _survivorIsCurrent = true;
  _FieldChoice _name = _FieldChoice.current;
  _FieldChoice _species = _FieldChoice.current;
  _FieldChoice _sex = _FieldChoice.current;
  _PhotoChoice _photo = _PhotoChoice.current;
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _pickCandidate(Animal a) {
    final current = ref.read(animalByIdProvider(widget.animalId)).value;
    final currentHasPhoto = (current?.photo ?? '').isNotEmpty;
    final candidateHasPhoto = (a.photo ?? '').isNotEmpty;
    setState(() {
      _candidate = a;
      // Fresh candidate → fresh defaults, so a stale choice from a previous
      // (discarded) pick can never travel into a new comparison. The photo
      // default skips whichever side has none, so the initial selection is
      // never a disabled segment.
      _survivorIsCurrent = true;
      _name = _FieldChoice.current;
      _species = _FieldChoice.current;
      _sex = _FieldChoice.current;
      _photo = currentHasPhoto
          ? _PhotoChoice.current
          : (candidateHasPhoto ? _PhotoChoice.other : _PhotoChoice.none);
    });
  }

  void _clearCandidate() {
    setState(() {
      _candidate = null;
      _searchController.clear();
      _query = '';
    });
  }

  Future<void> _submit(BuildContext context, Animal current) async {
    final candidate = _candidate;
    if (candidate == null) return;
    final l10n = context.l10n;
    final survivorId = _survivorIsCurrent ? current.id : candidate.id;
    final duplicateId = _survivorIsCurrent ? candidate.id : current.id;
    final survivorName = _title(_survivorIsCurrent ? current : candidate);
    final duplicateName = _title(_survivorIsCurrent ? candidate : current);
    final router = GoRouter.of(context);

    await confirmAndDelete(
      context,
      title: l10n.animalMergeConfirmTitle,
      message: l10n.animalMergeConfirmBody(duplicateName, survivorName),
      confirmLabel: l10n.animalMergeConfirmAction,
      action: () async {
        setState(() => _busy = true);
        try {
          final repo = await ref.read(animalsRepositoryProvider.future);
          final resultId = await repo.merge(
            survivor: survivorId,
            duplicate: duplicateId,
            fields: {
              'name': _wire(_name),
              'species': _wire(_species),
              'sex': _wire(_sex),
              'photo': switch (_photo) {
                _PhotoChoice.current => _wire(_FieldChoice.current),
                _PhotoChoice.other => _wire(_FieldChoice.other),
                _PhotoChoice.none => 'none',
              },
            },
          );
          ref
            ..invalidate(animalByIdProvider(current.id))
            ..invalidate(animalByIdProvider(candidate.id))
            ..invalidate(animalLifetimeProvider(current.id))
            ..invalidate(animalLifetimeProvider(candidate.id))
            ..invalidate(animalsRegistryProvider);
          if (!mounted) return;
          router.go(AppRoutes.animalDetail(resultId));
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
    );
  }

  /// [choice] is relative to "current vs. other"; the wire payload is
  /// relative to "survivor vs. duplicate", which flips when the candidate
  /// (not the animal opened from) is chosen as the survivor.
  String _wire(_FieldChoice choice) {
    final isCurrent = choice == _FieldChoice.current;
    final winnerIsSurvivor = isCurrent == _survivorIsCurrent;
    return winnerIsSurvivor ? 'survivor' : 'duplicate';
  }

  String _title(Animal a) {
    final name = a.name;
    return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = ref.watch(animalByIdProvider(widget.animalId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.animalMergeTitle)),
      body: AsyncValueView<Animal>(
        value: current,
        onRetry: () => ref.invalidate(animalByIdProvider(widget.animalId)),
        data: (current) => ContentBounds(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _CurrentAnimalCard(current),
              const SizedBox(height: AppSpacing.md),
              _CandidateSearch(
                controller: _searchController,
                query: _query,
                excludeAnimalId: current.id,
                enabled: !_busy,
                onSearch: (q) => setState(() => _query = q),
                onPick: _pickCandidate,
              ),
              if (_candidate case final candidate?) ...[
                const SizedBox(height: AppSpacing.md),
                _CandidatePickedCard(
                  animal: candidate,
                  enabled: !_busy,
                  onClear: _clearCandidate,
                ),
                const SizedBox(height: AppSpacing.lg),
                _SurvivorPicker(
                  current: current,
                  candidate: candidate,
                  survivorIsCurrent: _survivorIsCurrent,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _survivorIsCurrent = v),
                ),
                const SizedBox(height: AppSpacing.md),
                _FieldDiffSection(
                  current: current,
                  candidate: candidate,
                  name: _name,
                  species: _species,
                  sex: _sex,
                  photo: _photo,
                  enabled: !_busy,
                  onName: (v) => setState(() => _name = v),
                  onSpecies: (v) => setState(() => _species = v),
                  onSex: (v) => setState(() => _sex = v),
                  onPhoto: (v) => setState(() => _photo = v),
                ),
                const SizedBox(height: AppSpacing.md),
                _MovesSummary(
                  duplicateId: _survivorIsCurrent ? candidate.id : current.id,
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: l10n.animalMergeConfirmAction,
                  icon: Icons.merge_outlined,
                  isLoading: _busy,
                  onPressed: () => _submit(context, current),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The animal the flow was opened from, shown fixed at the top so it's always
/// visible while searching for its duplicate.
class _CurrentAnimalCard extends StatelessWidget {
  const _CurrentAnimalCard(this.animal);

  final Animal animal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = animal.name;
    final title = name == null || name.isEmpty
        ? animal.species
        : '$name · ${animal.species}';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: AnimalAvatar(animalId: animal.id, radius: 20),
        title: Text(title),
        subtitle: Text(l10n.animalMergeCurrentSubtitle),
      ),
    );
  }
}

/// Re-identification-style search (reuses [reidSearchProvider]) scoped to
/// finding the OTHER record of a duplicate pair — the animal the flow was
/// opened from is excluded from its own results.
class _CandidateSearch extends ConsumerWidget {
  const _CandidateSearch({
    required this.controller,
    required this.query,
    required this.excludeAnimalId,
    required this.enabled,
    required this.onSearch,
    required this.onPick,
  });

  final TextEditingController controller;
  final String query;
  final String excludeAnimalId;
  final bool enabled;
  final ValueChanged<String> onSearch;
  final ValueChanged<Animal> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: controller,
                label: l10n.animalMergeSearchLabel,
                hintText: l10n.animalMergeSearchHint,
                prefixIcon: Icons.search,
                enabled: enabled,
                textInputAction: TextInputAction.search,
                onChanged: (_) {},
                onSubmitted: (v) => onSearch(v.trim()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              icon: const Icon(Icons.search),
              tooltip: l10n.animalMergeSearchLabel,
              onPressed: enabled
                  ? () => onSearch(controller.text.trim())
                  : null,
            ),
          ],
        ),
        if (query.isNotEmpty)
          ref
              .watch(reidSearchProvider(query))
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (matches) {
                  final results = matches
                      .where((m) => m.animal.id != excludeAnimalId)
                      .toList();
                  if (results.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        l10n.reidNoMatches,
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Card(
                    margin: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final m in results)
                          ListTile(
                            leading: const Icon(Icons.pets_outlined),
                            title: Text(_animalTitle(m.animal)),
                            onTap: enabled ? () => onPick(m.animal) : null,
                          ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  String _animalTitle(Animal a) {
    final name = a.name;
    return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
  }
}

/// Summary of the picked duplicate candidate, with a way to change the pick.
class _CandidatePickedCard extends StatelessWidget {
  const _CandidatePickedCard({
    required this.animal,
    required this.enabled,
    required this.onClear,
  });

  final Animal animal;
  final bool enabled;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = animal.name;
    final title = name == null || name.isEmpty
        ? animal.species
        : '$name · ${animal.species}';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: AnimalAvatar(animalId: animal.id, radius: 20),
        title: Text(title),
        subtitle: Text(l10n.animalMergeCandidateSubtitle),
        trailing: TextButton(
          onPressed: enabled ? onClear : null,
          child: Text(l10n.animalMergeChangeCandidate),
        ),
      ),
    );
  }
}

/// Which of the two records keeps its id (and thus stays reachable at its
/// existing links/QR codes, etc.) — the other is deleted once the merge
/// commits.
class _SurvivorPicker extends StatelessWidget {
  const _SurvivorPicker({
    required this.current,
    required this.candidate,
    required this.survivorIsCurrent,
    required this.enabled,
    required this.onChanged,
  });

  final Animal current;
  final Animal candidate;
  final bool survivorIsCurrent;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.animalMergeSurvivorLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: true, label: Text(_title(current))),
            ButtonSegment(value: false, label: Text(_title(candidate))),
          ],
          selected: {survivorIsCurrent},
          onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
        ),
      ],
    );
  }

  String _title(Animal a) {
    final name = a.name;
    return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
  }
}

/// One picker per identity field that actually differs between the two
/// records — fields the app has no edit surface for (is_owned/tags/notes)
/// gap-fill on the server instead of cluttering this with controls for data
/// nobody can otherwise see or set (federfall-eqy6 concept).
class _FieldDiffSection extends StatelessWidget {
  const _FieldDiffSection({
    required this.current,
    required this.candidate,
    required this.name,
    required this.species,
    required this.sex,
    required this.photo,
    required this.enabled,
    required this.onName,
    required this.onSpecies,
    required this.onSex,
    required this.onPhoto,
  });

  final Animal current;
  final Animal candidate;
  final _FieldChoice name;
  final _FieldChoice species;
  final _FieldChoice sex;
  final _PhotoChoice photo;
  final bool enabled;
  final ValueChanged<_FieldChoice> onName;
  final ValueChanged<_FieldChoice> onSpecies;
  final ValueChanged<_FieldChoice> onSex;
  final ValueChanged<_PhotoChoice> onPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final rows = <Widget>[];

    void addChoiceRow(
      String label,
      String currentValue,
      String candidateValue,
      _FieldChoice selected,
      ValueChanged<_FieldChoice> onChanged,
    ) {
      if (currentValue == candidateValue) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<_FieldChoice>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _FieldChoice.current,
                    label: Text(
                      currentValue.isEmpty
                          ? l10n.animalMergeEmptyValue
                          : currentValue,
                    ),
                  ),
                  ButtonSegment(
                    value: _FieldChoice.other,
                    label: Text(
                      candidateValue.isEmpty
                          ? l10n.animalMergeEmptyValue
                          : candidateValue,
                    ),
                  ),
                ],
                selected: {selected},
                onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
              ),
            ],
          ),
        ),
      );
    }

    addChoiceRow(
      l10n.caseFieldName,
      current.name ?? '',
      candidate.name ?? '',
      name,
      onName,
    );
    addChoiceRow(
      l10n.caseFieldSpecies,
      current.species,
      candidate.species,
      species,
      onSpecies,
    );
    addChoiceRow(
      l10n.caseFieldSex,
      current.sex == null ? '' : sexLabel(l10n, current.sex!),
      candidate.sex == null ? '' : sexLabel(l10n, candidate.sex!),
      sex,
      onSex,
    );

    final currentPhoto = (current.photo ?? '').isNotEmpty;
    final candidatePhoto = (candidate.photo ?? '').isNotEmpty;
    if (currentPhoto || candidatePhoto) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.animalMergePhotoLabel,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<_PhotoChoice>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _PhotoChoice.current,
                    label: AnimalAvatar(animalId: current.id, radius: 16),
                    enabled: currentPhoto,
                  ),
                  ButtonSegment(
                    value: _PhotoChoice.other,
                    label: AnimalAvatar(animalId: candidate.id, radius: 16),
                    enabled: candidatePhoto,
                  ),
                  ButtonSegment(
                    value: _PhotoChoice.none,
                    label: Text(l10n.animalMergeNoPhoto),
                  ),
                ],
                selected: {photo},
                onSelectionChanged: enabled ? (s) => onPhoto(s.first) : null,
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return Text(
        l10n.animalMergeNoConflicts,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// Read-only preview of what the merge moves — every animal-scoped record on
/// the record that is ABOUT to be deleted (whichever side that ends up being
/// depends on [_SurvivorPicker]'s current selection).
class _MovesSummary extends ConsumerWidget {
  const _MovesSummary({required this.duplicateId});

  final String duplicateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cases = ref.watch(casesForAnimalProvider(duplicateId)).value?.length;
    final markings = ref
        .watch(markingsForAnimalProvider(duplicateId))
        .value
        ?.length;
    final weights = ref
        .watch(weightsForAnimalProvider(duplicateId))
        .value
        ?.length;
    final exams = ref.watch(examsForAnimalProvider(duplicateId)).value?.length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.animalMergeMovesTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.animalMergeCasesCount(cases ?? 0)),
            Text(l10n.animalMergeMarkingsCount(markings ?? 0)),
            Text(l10n.animalMergeWeightsCount(weights ?? 0)),
            Text(l10n.animalMergeExamsCount(exams ?? 0)),
          ],
        ),
      ),
    );
  }
}
