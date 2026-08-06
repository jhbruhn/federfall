import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Find another animal of this org by re-identification search, and pick it.
///
/// Used wherever a flow has one animal in hand and needs a second: merging a
/// duplicate pair (`merge_animal_screen.dart`) and re-attributing an egg record
/// to the bird that actually laid it (`egg_reassign_sheet.dart`). Both had
/// their own copy of this widget, identical down to the exclude filter and the
/// empty-result text; the only real difference was the field's label, which is
/// now a parameter.
///
/// Search is submit-driven, not as-you-type: [reidSearchProvider] is a server
/// round trip over markings and animals, so it fires on the search action or
/// the button — never on every keystroke.
///
/// [excludeAnimalId] keeps the animal the flow was opened from out of its own
/// results: an animal can be neither merged with nor re-attributed to itself,
/// and offering it would only produce an error one tap later.
class AnimalSearchPicker extends ConsumerWidget {
  const AnimalSearchPicker({
    required this.controller,
    required this.query,
    required this.label,
    required this.excludeAnimalId,
    required this.onSearch,
    required this.onPick,
    this.hintText,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;

  /// The term the results currently shown belong to — the caller holds it, so
  /// typing on after a search does not silently re-query or clear the list.
  final String query;

  /// Field label, also the search button's tooltip. Each caller names what it
  /// is looking for ("the other record", "the laying bird").
  final String label;

  final String? hintText;

  /// The animal this flow is about, which is never a valid answer to it.
  final String excludeAnimalId;

  final ValueChanged<String> onSearch;
  final ValueChanged<Animal> onPick;

  /// False while the caller is saving, so a second pick cannot race the write.
  final bool enabled;

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
                label: label,
                hintText: hintText,
                prefixIcon: Icons.search,
                enabled: enabled,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => onSearch(v.trim()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              icon: const Icon(Icons.search),
              tooltip: label,
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
                // A failed search renders as nothing rather than as an error
                // block: the field is still there to try again with, and this
                // is a lookup aid, not the flow itself.
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
                            title: Text(animalTitle(m.animal)),
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
}
