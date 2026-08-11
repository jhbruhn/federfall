import 'package:federfall/features/cases/animal_species_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The species field: a Material 3 editable dropdown. The caret opens the full
/// list of kinds the org has recorded (`animal_species` view); typing filters
/// it; any value can still be typed freely (free text is kept).
///
/// Shared by every place an animal's kind is entered, so intake and the
/// case-less resident create offer the same vocabulary. A [DropdownMenu] is not
/// a `Form` field, so "required" is enforced by the host and shown through
/// [errorText].
class SpeciesField extends ConsumerWidget {
  const SpeciesField({
    required this.controller,
    required this.enabled,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final known = ref.watch(animalSpeciesProvider).value ?? const <String>[];

    return DropdownMenu<String>(
      controller: controller,
      enabled: enabled,
      requestFocusOnTap: true,
      enableFilter: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      label: Text(l10n.caseFieldSpecies),
      leadingIcon: const Icon(Icons.pets_outlined),
      errorText: errorText,
      // Match the app's card/sheet tone — the default menu surface reads as
      // near-black in dark mode against the grey-ish surfaceContainer used
      // elsewhere.
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      // While typing a partial value, filter by it; but once the field holds a
      // complete (already-known) value, show the whole list so the caret
      // browses all kinds. Free text not in the list is still kept.
      filterCallback: (entries, filter) {
        final query = filter.trim().toLowerCase();
        if (query.isEmpty ||
            entries.any((e) => e.label.toLowerCase() == query)) {
          return entries;
        }
        return entries
            .where((e) => e.label.toLowerCase().contains(query))
            .toList();
      },
      dropdownMenuEntries: [
        for (final s in known) DropdownMenuEntry<String>(value: s, label: s),
      ],
    );
  }
}
