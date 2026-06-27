import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviary_form_sheet.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/route_selection.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Aviary registry (FED-6.1): the org's aviaries with their keeper, location
/// and capacity. Coordinators/supervisors can create and edit; everyone can
/// view. (Residents/occupancy land in FED-6.2.)
class AviariesScreen extends ConsumerWidget {
  const AviariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    ref.liveRefresh(
      const ['aviaries', 'dispositions', 'animals'],
      () => ref.invalidate(aviariesProvider),
    );
    final aviaries = ref.watch(aviariesProvider);
    final canManage = canManageAviaries(
      ref.watch(currentUserProvider).value?.role,
    );
    final selectedId = selectedDetailId(context);
    // When the list is empty its empty-state already offers an "add aviary"
    // CTA (also gated on canManage), so suppress the FAB then to avoid two
    // identical actions. While loading or on error keep it (for managers).
    final showFab = canManage && (aviaries.value?.isNotEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aviariesTitle),
        actions: const [AccountMenu()],
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => showAviaryFormSheet(context),
              tooltip: l10n.aviaryNewTitle,
              child: const Icon(Icons.add),
            )
          : null,
      body: AsyncValueView<List<Aviary>>(
        value: aviaries,
        onRetry: () => ref.invalidate(aviariesProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.holiday_village_outlined,
                title: l10n.aviariesEmpty,
                message: l10n.aviariesEmptyBody,
                actionLabel: canManage ? l10n.aviaryNewTitle : null,
                actionIcon: Icons.add,
                onAction: canManage
                    ? () => showAviaryFormSheet(context)
                    : null,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(aviariesProvider.future),
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => _AviaryTile(
                    list[i],
                    selected: list[i].id == selectedId,
                  ),
                ),
              ),
      ),
    );
  }
}

class _AviaryTile extends ConsumerWidget {
  const _AviaryTile(this.aviary, {this.selected = false});

  final Aviary aviary;

  /// Highlighted when its detail is open in the adjacent pane (two-pane).
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final keeper = aviary.keeper == null
        ? null
        : ref.watch(orgMembersByIdProvider).value?[aviary.keeper];

    final subtitle = [
      if (keeper != null) memberLabel(keeper),
      ?aviary.location,
      if (aviary.capacity != null) l10n.aviaryCapacityValue(aviary.capacity!),
      if (!aviary.active) l10n.aviaryInactive,
    ].join(' · ');

    return ListTile(
      selected: selected,
      leading: const Icon(Icons.holiday_village_outlined),
      title: Text(aviary.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.aviaryDetail(aviary.id)),
    );
  }
}
