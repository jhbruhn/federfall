import 'dart:async';

import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/route_selection.dart';
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

/// How long the search field waits for the typing to stop before asking the
/// server — the search is a query now, not a pass over a local list.
const _searchDebounce = Duration(milliseconds: 300);

class _AnimalsScreenState extends ConsumerState<AnimalsScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) setState(() => _query = text);
    });
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    // Within a screenful of the bottom. loadMore() is a no-op while a page is
    // in flight, so firing this on every scroll frame is safe.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      unawaited(
        ref.read(animalRegistryFeedProvider(_query).notifier).loadMore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.liveRefresh(
      const ['animals', 'cases'],
      () => ref.invalidate(animalRegistryFeedProvider),
    );
    final feed = ref.watch(animalRegistryFeedProvider(_query));
    final selectedId = selectedDetailId(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.animalsTitle),
        actions: const [AccountMenu()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.animalsSearchHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          // Inside the Column, not around it: the search field has to stay put
          // while the results below it load, or typing loses focus on every
          // request.
          Expanded(
            child: AsyncValueView<AnimalRegistryState>(
              value: feed,
              onRetry: () => ref.invalidate(animalRegistryFeedProvider(_query)),
              data: (state) => _results(state, selectedId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(AnimalRegistryState state, String? selectedId) {
    final l10n = context.l10n;
    if (state.items.isEmpty) {
      // Which emptiness this is can no longer be read off the loaded rows —
      // the server sent only what matched. An active search says it instead.
      return _query.trim().isEmpty
          ? EmptyView(
              icon: Icons.pets_outlined,
              title: l10n.animalsEmpty,
              message: l10n.animalsEmptyBody,
              actionLabel: l10n.casesEmptyAction,
              actionIcon: Icons.add,
              onAction: () => context.push(AppRoutes.newCase),
            )
          : EmptyView(message: l10n.animalsNoMatches);
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(animalRegistryFeedProvider(_query).future),
      child: ListView.builder(
        controller: _scroll,
        // Always scrollable, so pull-to-refresh works on a short list.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.items.length) {
            return PagedListTail(
              error: state.pageError,
              onRetry: () => unawaited(
                ref
                    .read(animalRegistryFeedProvider(_query).notifier)
                    .retryPage(),
              ),
            );
          }
          return _AnimalTile(
            state.items[i],
            selected: state.items[i].animal.id == selectedId,
          );
        },
      ),
    );
  }
}

class _AnimalTile extends StatelessWidget {
  const _AnimalTile(this.item, {this.selected = false});

  final AnimalListItem item;

  /// Highlighted when its detail is open in the adjacent pane (two-pane).
  final bool selected;

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
      selected: selected,
      leading: AnimalAvatar(animalId: animal.id, radius: 20),
      title: Text(hasName ? animal.name! : animal.species),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.animalDetail(animal.id)),
    );
  }
}
