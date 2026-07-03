import 'package:federfall/routing/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds concrete detail and query paths from their segments', () {
    expect(AppRoutes.aviaryDetail('av1'), '/aviaries/av1');
    expect(AppRoutes.animalDetail('a1'), '/animals/a1');
    expect(AppRoutes.caseDetail('c1'), '/cases/c1');
    expect(AppRoutes.newCaseForAnimal('a1'), '/cases/new?animal=a1');
    expect(
      AppRoutes.casesBrowse('scope=all&activity=active'),
      '/cases/browse?scope=all&activity=active',
    );
  });
}
