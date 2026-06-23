import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Animal lifetime detail (FED-7.6). Placeholder for now: shows the animal's
/// identity in the title and a coming-soon body. The full lifetime record
/// (markings + all cases) lands with FED-7.6.
class AnimalDetailScreen extends ConsumerWidget {
  const AnimalDetailScreen({required this.animalId, super.key});

  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final animal = ref.watch(animalByIdProvider(animalId));
    return Scaffold(
      appBar: AppBar(
        title: Text(animal.value?.name ?? l10n.animalsTitle),
      ),
      body: EmptyView(
        icon: Icons.pets_outlined,
        message: l10n.animalDetailComingSoon,
      ),
    );
  }
}
