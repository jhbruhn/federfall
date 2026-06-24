import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/home/account_actions.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Animals registry (FED-7.5): a searchable list of the org's persistent animal
/// identities. Search matches name or active ring/chip code. Each row opens the
/// animal's lifetime detail (FED-7.6).
class AnimalsScreen extends ConsumerStatefulWidget {
  const AnimalsScreen({super.key});

  @override
  ConsumerState<AnimalsScreen> createState() => _AnimalsScreenState();
}

class _AnimalsScreenState extends ConsumerState<AnimalsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = ref.watch(animalsRegistryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.animalsTitle),
        actions: const [AccountActions()],
      ),
      body: AsyncValueView<List<AnimalListItem>>(
        value: registry,
        onRetry: () => ref.invalidate(animalsRegistryProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (items) {
          final results = filterAnimals(items, _query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.animalsSearchHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? EmptyView(message: l10n.animalsEmpty)
                    : results.isEmpty
                    ? EmptyView(message: l10n.animalsNoMatches)
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) => _AnimalTile(results[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimalTile extends StatelessWidget {
  const _AnimalTile(this.item);

  final AnimalListItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final animal = item.animal;
    final hasName = animal.name != null && animal.name!.isNotEmpty;
    final status = animal.lifetimeStatus;

    final subtitle = [
      if (hasName) animal.species,
      if (item.codes.isNotEmpty) item.codes.join(', '),
      if (status != null) lifetimeStatusLabel(l10n, status),
    ].join(' · ');

    return ListTile(
      leading: AnimalAvatar(animalId: animal.id, radius: 20),
      title: Text(hasName ? animal.name! : animal.species),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.animalDetail(animal.id)),
    );
  }
}
