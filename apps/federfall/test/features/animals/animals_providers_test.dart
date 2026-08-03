import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

AnimalListItem _item(
  String id, {
  String? name,
  String species = 'Columba livia',
  List<String> codes = const [],
}) => AnimalListItem(
  animal: Animal(id: id, species: species, name: name),
  codes: codes,
);

List<String> _ids(List<AnimalListItem> items) =>
    items.map((i) => i.animal.id).toList();

void main() {
  final registry = [
    _item('a1', name: 'Pip', codes: const ['DE-1234']),
    _item('a2', name: 'Fritz', codes: const ['NL-9999']),
    _item('a3', codes: const ['CHIP-42']),
  ];

  test('empty query returns everything', () {
    expect(filterAnimals(registry, '   '), registry);
  });

  test('matches by animal name, case-insensitively', () {
    expect(_ids(filterAnimals(registry, 'pip')), ['a1']);
  });

  test('matches by active marking code, case-insensitively', () {
    expect(_ids(filterAnimals(registry, 'chip-42')), ['a3']);
    expect(_ids(filterAnimals(registry, 'nl-99')), ['a2']);
  });

  test('returns nothing when neither name nor code matches', () {
    expect(filterAnimals(registry, 'zzz'), isEmpty);
  });

  // The avatar resolves `animals.photo` only (federfall-v1yh) — no case-scoped
  // intake-photo fallback, which is what made the portrait depend on who was
  // looking. Intake promotes the first admission photo onto the animal.
  group('animal avatar URL', () {
    ProviderContainer containerFor(Animal animal, PbAnimalsRepository repo) {
      final container = ProviderContainer(
        overrides: [
          animalByIdProvider('a1').overrideWith((ref) async => animal),
          animalsRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('thumbnail and full-res URLs come from animals.photo', () async {
      final repo = _MockAnimalsRepo();
      final thumb = Uri.parse('https://pb.test/face.jpg?thumb=200x200');
      final full = Uri.parse('https://pb.test/face.jpg');
      when(
        () => repo.fileUrl('a1', 'face.jpg', thumb: '200x200'),
      ).thenReturn(thumb);
      when(() => repo.fileUrl('a1', 'face.jpg')).thenReturn(full);
      final container = containerFor(
        const Animal(id: 'a1', species: 'Columba livia', photo: 'face.jpg'),
        repo,
      );

      expect(await container.read(animalAvatarUrlProvider('a1').future), thumb);
      expect(
        await container.read(animalAvatarFullUrlProvider('a1').future),
        full,
      );
    });

    test('is null without a photo, and asks for no file URL', () async {
      final repo = _MockAnimalsRepo();
      final container = containerFor(
        const Animal(id: 'a1', species: 'Columba livia'),
        repo,
      );

      expect(
        await container.read(animalAvatarUrlProvider('a1').future),
        isNull,
      );
      verifyNever(() => repo.fileUrl(any(), any(), thumb: any(named: 'thumb')));
    });
  });
}
