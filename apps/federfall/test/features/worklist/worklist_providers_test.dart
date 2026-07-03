import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalidating the derived worklist recomputes from the cached source '
      'without refetching (federfall-zosx)', () async {
    var fetches = 0;
    final container = ProviderContainer(
      overrides: [
        worklistSourceProvider.overrideWith((ref) async {
          fetches++;
          return const WorklistSource();
        }),
      ],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose providers alive across invalidations, as the
    // watching screen would.
    final sub = container.listen(worklistProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(worklistProvider.future);
    expect(fetches, 1);

    // The per-minute ticker invalidates only the derived provider — that must
    // not hit the source again (the whole point of the split).
    container.invalidate(worklistProvider);
    await container.read(worklistProvider.future);
    expect(fetches, 1);

    // A data change invalidates the source → one refetch, derived follows.
    container.invalidate(worklistSourceProvider);
    await container.read(worklistProvider.future);
    expect(fetches, 2);
  });
}
