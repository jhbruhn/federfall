import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/location/location_picker_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGeocodingRepo extends Mock implements GeocodingRepository {}

void main() {
  late MockGeocodingRepo geo;

  setUp(() {
    geo = MockGeocodingRepo();
    when(() => geo.reverse(any(), any())).thenAnswer((_) async => null);
  });

  Future<void> pump(WidgetTester tester) async {
    // A roomy surface so the search bar, FAB and address card all lay out.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geocodingRepositoryProvider.overrideWith((ref) async => geo),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocationPickerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts with the hint and a disabled confirm button', (
    tester,
  ) async {
    await pump(tester);

    expect(
      find.text('Move the map or search to set the location'),
      findsOneWidget,
    );
    final useButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use this location'),
    );
    expect(useButton.onPressed, isNull);
  });

  testWidgets('searching with no results shows the empty state', (
    tester,
  ) async {
    when(() => geo.forward(any())).thenAnswer((_) async => const []);
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'nowhere');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('selecting a search result enables confirm and returns it', (
    tester,
  ) async {
    when(() => geo.forward(any())).thenAnswer(
      (_) async => const [
        GeoResult(
          lat: 51.96,
          lon: 7.63,
          displayName: 'Domplatz, Münster',
          city: 'Münster',
          region: 'NRW',
        ),
      ],
    );

    PickedLocation? picked;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geocodingRepositoryProvider.overrideWith((ref) async => geo),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showLocationPicker(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Dom');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Domplatz, Münster').last);
    await tester.pumpAndSettle();

    final useButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use this location'),
    );
    expect(useButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Use this location'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.city, 'Münster');
    expect(picked!.region, 'NRW');
    expect(picked!.geo.lat, closeTo(51.96, 0.001));
  });
}
