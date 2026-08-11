import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart'
    show vaccineLabelsProvider;
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A free-text field with suggestions from the `vaccine_labels` view — the same
/// editable-dropdown shape `SpeciesField` uses, and for the same reason: the
/// value stays free text, the list only offers what this org has already
/// recorded (1700000088), so nothing dead is proposed and nothing is seeded.
///
/// [onSelected] fires only when a suggestion is PICKED, never while typing.
/// That is what lets the vaccine field prefill the target it was recorded
/// against without overwriting something the user is in the middle of writing.
class VaccineSuggestionField extends ConsumerWidget {
  const VaccineSuggestionField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.options,
    required this.enabled,
    this.onSelected,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  /// The suggestions, already ordered by the caller (the provider sorts by
  /// recency, which is the ranking that matters here).
  final List<String> options;
  final bool enabled;
  final ValueChanged<String>? onSelected;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return DropdownMenu<String>(
      controller: controller,
      enabled: enabled,
      requestFocusOnTap: true,
      enableFilter: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      label: Text(label),
      leadingIcon: Icon(icon),
      errorText: errorText,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      onSelected: (value) {
        if (value != null) onSelected?.call(value);
      },
      // Same rule as SpeciesField: filter while a partial value is being typed,
      // show everything once the field holds a complete known value, so the
      // caret browses instead of showing one row.
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
        for (final o in options) DropdownMenuEntry<String>(value: o, label: o),
      ],
    );
  }
}

/// The distinct product names this org has recorded, most recent first.
List<String> vaccineOptions(WidgetRef ref) {
  final labels = ref.watch(vaccineLabelsProvider).value ?? const [];
  final seen = <String>{};
  return [
    for (final l in labels)
      if (l.vaccine.isNotEmpty && seen.add(l.vaccine.toLowerCase())) l.vaccine,
  ];
}

/// The distinct targets this org has recorded, most recent first.
List<String> targetOptions(WidgetRef ref) {
  final labels = ref.watch(vaccineLabelsProvider).value ?? const [];
  final seen = <String>{};
  return [
    for (final l in labels)
      if (l.target case final t? when t.isNotEmpty && seen.add(t.toLowerCase()))
        t,
  ];
}

/// The target [vaccine] was last recorded against, if any — what the sheet
/// prefills when a product is picked from the list.
String? targetForVaccine(WidgetRef ref, String vaccine) {
  final labels = ref.watch(vaccineLabelsProvider).value ?? const [];
  final key = vaccine.trim().toLowerCase();
  for (final l in labels) {
    if (l.vaccine.toLowerCase() == key && (l.target?.isNotEmpty ?? false)) {
      return l.target;
    }
  }
  return null;
}

/// Shown under the vaccine field the first time an org records anything, so an
/// empty suggestion list reads as "type it" rather than as a broken picker.
String vaccineEmptyHint(BuildContext context) =>
    context.l10n.vaccinationSuggestionsEmpty;
