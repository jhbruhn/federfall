import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class _MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

Animal _animal(String id, {String? name}) =>
    Animal(id: id, species: 'Columba livia', name: name);

void main() {
  // The registry is server-filtered and paged now (federfall-trep): the search
  // is a query, and only the page on screen's markings are read.
  group('AnimalRegistryFeed', () {
    late _MockAnimalsRepo animals;
    late _MockMarkingsRepo markings;

    setUp(() {
      animals = _MockAnimalsRepo();
      markings = _MockMarkingsRepo();
      when(() => markings.activeByAnimals(any())).thenAnswer((_) async => []);
    });

    void stubBrowse(PbPage<Animal> Function() answer) {
      when(
        () => animals.browse(
          text: any(named: 'text'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenAnswer((_) async => answer());
    }

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          markingsRepositoryProvider.overrideWith((ref) async => markings),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the search term is what the server is asked', () async {
      stubBrowse(() => const PbPage(items: []));

      await makeContainer().read(animalRegistryFeedProvider('pip').future);

      final text = verify(
        () => animals.browse(
          text: captureAny(named: 'text'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).captured.single;
      expect(text, 'pip');
    });

    test("rows carry the codes of the page's own markings", () async {
      stubBrowse(
        () => PbPage(
          items: [
            _animal('a1', name: 'Pip'),
            _animal('a2'),
          ],
        ),
      );
      when(() => markings.activeByAnimals(any())).thenAnswer(
        (_) async => const [
          Marking(id: 'm1', animal: 'a1', type: 'ring', code: 'DE-1234'),
          Marking(id: 'm2', animal: 'a1', type: 'chip', code: 'CHIP-42'),
          // A codeless marking (a colour band, say) contributes nothing.
          Marking(id: 'm3', animal: 'a2', type: 'band'),
        ],
      );

      final state = await makeContainer().read(
        animalRegistryFeedProvider('').future,
      );

      expect(state.items.map((i) => i.animal.id), ['a1', 'a2']);
      expect(state.items.first.codes, ['DE-1234', 'CHIP-42']);
      expect(state.items.last.codes, isEmpty);
      // Only the animals on this page, not every active marking in the org.
      final asked =
          verify(
                () => markings.activeByAnimals(captureAny()),
              ).captured.single
              as Iterable<String>;
      expect(asked, ['a1', 'a2']);
    });

    test('loadMore appends the next page', () async {
      var call = 0;
      stubBrowse(
        () => call++ == 0
            ? PbPage(
                items: [_animal('a1', name: 'Anton')],
                cursor: const PbCursor(value: 'Anton', id: 'a1'),
              )
            : PbPage(items: [_animal('a2', name: 'Berta')]),
      );
      final container = makeContainer();
      final feed = animalRegistryFeedProvider('');
      await container.read(feed.future);

      await container.read(feed.notifier).loadMore();

      final state = container.read(feed).requireValue;
      expect(state.items.map((i) => i.animal.id), ['a1', 'a2']);
      expect(state.hasMore, isFalse);
      // Resumed from the cursor, not from a page number.
      final after = verify(
        () => animals.browse(
          text: any(named: 'text'),
          after: captureAny(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).captured;
      expect(after.last, const PbCursor(value: 'Anton', id: 'a1'));
    });

    test('a failed page keeps the rows already on screen', () async {
      var call = 0;
      stubBrowse(() {
        if (call++ == 0) {
          return PbPage(
            items: [_animal('a1', name: 'Anton')],
            cursor: const PbCursor(value: 'Anton', id: 'a1'),
          );
        }
        throw const RepositoryException('boom');
      });
      final container = makeContainer();
      final feed = animalRegistryFeedProvider('');
      await container.read(feed.future);

      await container.read(feed.notifier).loadMore();

      final state = container.read(feed).requireValue;
      expect(state.items.map((i) => i.animal.id), ['a1']);
      expect(state.pageError, isA<RepositoryException>());
      expect(state.cursor, const PbCursor(value: 'Anton', id: 'a1'));
    });
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
