import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviary_form_sheet.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Aviary detail / occupancy (FED-6.2): the aviary's identity plus the animals
/// currently resident in it. Coordinators/supervisors can edit.
class AviaryDetailScreen extends ConsumerWidget {
  const AviaryDetailScreen({required this.aviaryId, super.key});

  final String aviaryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final aviary = ref.watch(aviaryByIdProvider(aviaryId));
    final residents =
        ref.watch(aviaryResidentsProvider(aviaryId)).value ?? const <Animal>[];
    final canManage = canManageAviaries(
      ref.watch(currentUserProvider).value?.role,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aviaryDetailTitle),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.aviaryEditTitle,
              onPressed: () {
                final value = aviary.value;
                if (value != null) {
                  unawaited(showAviaryFormSheet(context, aviary: value));
                }
              },
            ),
        ],
      ),
      body: AsyncValueView<Aviary>(
        value: aviary,
        onRetry: () => ref.invalidate(aviaryByIdProvider(aviaryId)),
        errorMessage: (e) => errorMessage(l10n, e),
        loading: const LinearProgressIndicator(),
        data: (av) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Header(aviary: av, residentCount: residents.length),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.aviaryResidentsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (residents.isEmpty)
              EmptyView(
                icon: Icons.pets_outlined,
                message: l10n.aviaryNoResidents,
              )
            else
              for (final animal in residents) _ResidentTile(animal),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.aviary, required this.residentCount});

  final Aviary aviary;
  final int residentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final keeper = aviary.keeper == null
        ? null
        : ref.watch(orgMembersByIdProvider).value?[aviary.keeper];
    final subtitle = [
      if (keeper != null) memberLabel(keeper),
      ?aviary.location,
    ].join(' · ');
    final occupancy = aviary.capacity != null
        ? l10n.aviaryOccupancyOfCapacity(residentCount, aviary.capacity!)
        : l10n.aviaryOccupancy(residentCount);

    return DetailHeader(
      title: aviary.name,
      subtitle: subtitle,
      chipLabel: occupancy,
    );
  }
}

class _ResidentTile extends StatelessWidget {
  const _ResidentTile(this.animal);

  final Animal animal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasName = animal.name != null && animal.name!.isNotEmpty;
    final status = animal.lifetimeStatus;
    final subtitle = [
      if (hasName) animal.species,
      if (status != null) lifetimeStatusLabel(l10n, status),
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AnimalAvatar(animalId: animal.id),
      title: Text(hasName ? animal.name! : animal.species),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.animalDetail(animal.id)),
    );
  }
}
