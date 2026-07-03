import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAviariesRepo extends Mock implements PbAviariesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

void main() {
  late MockAviariesRepo aviaries;
  late MockAnimalsRepo animals;
  late ProviderContainer container;

  setUp(() {
    aviaries = MockAviariesRepo();
    animals = MockAnimalsRepo();
    container = ProviderContainer(
      overrides: [
        aviariesRepositoryProvider.overrideWith((ref) async => aviaries),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
      ],
    );
    addTearDown(container.dispose);
  });

  test('aviaries lists all aviaries name-sorted', () async {
    when(
      () => aviaries.list(sort: 'name'),
    ).thenAnswer((_) async => const [Aviary(id: 'av1', name: 'Voliere 1')]);

    final result = await container.read(aviariesProvider.future);

    expect(result, [const Aviary(id: 'av1', name: 'Voliere 1')]);
  });

  test('activeAviaries delegates to the repository', () async {
    when(
      () => aviaries.active(),
    ).thenAnswer((_) async => const [Aviary(id: 'av1', name: 'Voliere 1')]);

    final result = await container.read(activeAviariesProvider.future);

    expect(result, [const Aviary(id: 'av1', name: 'Voliere 1')]);
  });

  test('aviaryById fetches a single aviary', () async {
    when(
      () => aviaries.getOne('av1'),
    ).thenAnswer((_) async => const Aviary(id: 'av1', name: 'Voliere 1'));

    final result = await container.read(aviaryByIdProvider('av1').future);

    expect(result.name, 'Voliere 1');
  });

  test('aviaryResidents lists the animals housed in an aviary', () async {
    when(
      () => animals.residentsOf('av1'),
    ).thenAnswer((_) async => const [Animal(id: 'a1', species: 'Taube')]);

    final result = await container.read(aviaryResidentsProvider('av1').future);

    expect(result, [const Animal(id: 'a1', species: 'Taube')]);
  });

  test('aviaryOccupancyCounts tallies residents per aviary', () async {
    when(() => animals.housed()).thenAnswer(
      (_) async => const [
        Animal(id: 'a1', species: 'Taube', currentAviary: 'av1'),
        Animal(id: 'a2', species: 'Taube', currentAviary: 'av1'),
        Animal(id: 'a3', species: 'Taube', currentAviary: 'av2'),
      ],
    );

    final result = await container.read(aviaryOccupancyCountsProvider.future);

    expect(result, {'av1': 2, 'av2': 1});
  });

  test('aviaryOccupancyCounts ignores animals without an aviary', () async {
    when(
      () => animals.housed(),
    ).thenAnswer((_) async => const [Animal(id: 'a1', species: 'Taube')]);

    final result = await container.read(aviaryOccupancyCountsProvider.future);

    expect(result, isEmpty);
  });
}
