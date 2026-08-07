import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall_models/federfall_models.dart';

/// Stand-ins for the two keyset-paged list feeds, for tests that only need a
/// screen to render — the router, the navigation shell — rather than to
/// exercise the paging itself.
///
/// Both are server-backed families now (federfall-trep), so overriding them at
/// the provider is what keeps such a test off the network without stubbing a
/// repository it does not care about. Tests ABOUT the feeds override the
/// repositories instead, so the query they send is still under test.

/// A case browser holding [cases], exhausted (no further page).
class FakeCaseBrowseFeed extends CaseBrowseFeed {
  FakeCaseBrowseFeed({
    this.cases = const [],
    this.animalsById = const {},
    this.rowsFor,
    this.onQuery,
  });

  final List<Case> cases;
  final Map<String, Animal> animalsById;

  /// Stands in for the server's answer to a particular query, for the handful
  /// of behaviours that genuinely turn on the result changing with the filter
  /// — the auto-widen when the open case is out of scope. Overrides [cases].
  final List<Case> Function(CaseQuery query)? rowsFor;

  /// Called with the query the screen asked for. The filtering itself is the
  /// server's now, so a caller that wants to check WHICH question was asked —
  /// a deep link, say — inspects it here instead of counting rows.
  final void Function(CaseQuery query)? onQuery;

  @override
  Future<CaseBrowseState> build(CaseQuery query) async {
    onQuery?.call(query);
    return CaseBrowseState(
      browse: query.toBrowseQuery('me'),
      cases: rowsFor?.call(query) ?? cases,
      animalsById: animalsById,
    );
  }
}

/// An animals registry holding [items], exhausted (no further page).
class FakeAnimalRegistryFeed extends AnimalRegistryFeed {
  FakeAnimalRegistryFeed({this.items = const []});

  final List<AnimalListItem> items;

  @override
  Future<AnimalRegistryState> build(String search) async =>
      AnimalRegistryState(items: items);
}
