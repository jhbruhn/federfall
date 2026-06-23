import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('pickAvatarSource', () {
    const animal = Animal(id: 'a1', species: 'Columba livia', name: 'Pip');

    Case caseWith(String id, List<String> photos) =>
        Case(id: id, animal: 'a1', intakePhotos: photos);

    test('prefers the animal photo when set', () {
      final src = pickAvatarSource(
        animal.copyWith(photo: 'face.jpg'),
        [caseWith('c1', ['intake.jpg'])],
      );
      expect(src!.collection, AvatarCollection.animals);
      expect(src.recordId, 'a1');
      expect(src.filename, 'face.jpg');
    });

    test('falls back to the newest case with an intake photo', () {
      // Cases are newest-first; the newest has no photo, so the next wins.
      final src = pickAvatarSource(animal, [
        caseWith('c2', const []),
        caseWith('c1', ['first.jpg', 'second.jpg']),
      ]);
      expect(src!.collection, AvatarCollection.cases);
      expect(src.recordId, 'c1');
      expect(src.filename, 'first.jpg');
    });

    test('returns null when nothing has a photo', () {
      expect(pickAvatarSource(animal, [caseWith('c1', const [])]), isNull);
      expect(pickAvatarSource(animal, const []), isNull);
    });
  });
}
