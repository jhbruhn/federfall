import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockSamplesRepo extends Mock implements PbMicroscopySamplesRepository {}

const _types = [
  MicroscopyFindingType(
    id: 't_tricho',
    label: 'Trichomonaden',
    sampleTypes: [MicroscopySampleType.cropSwab],
  ),
  MicroscopyFindingType(
    id: 't_hefen',
    label: 'Hefen',
    sampleTypes: [MicroscopySampleType.cropSwab, MicroscopySampleType.fecal],
  ),
  MicroscopyFindingType(
    id: 't_spul',
    label: 'Spulwurmeier',
    sampleTypes: [MicroscopySampleType.fecal],
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late MockSamplesRepo samples;

  setUp(() {
    samples = MockSamplesRepo();
    when(
      () => samples.saveWithFindings(
        any(),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => 'm1');
    when(
      () => samples.fileUrl(
        any(),
        any(),
        thumb: any(named: 'thumb'),
        token: any(named: 'token'),
      ),
    ).thenAnswer(
      (i) => Uri.parse('https://pb.test/${i.positionalArguments[1]}'),
    );
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        microscopySamplesRepositoryProvider.overrideWith(
          (ref) async => samples,
        ),
        microscopyFindingTypesProvider.overrideWith((ref) async => _types),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> tapAndCapture(WidgetTester tester) async {
    await save(tester);
    return verify(
          () => samples.saveWithFindings(
            captureAny(),
            attachments: any(named: 'attachments'),
          ),
        ).captured.single
        as Map<String, dynamic>;
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the probe is required — saving without one asks for it', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));
    await save(tester);

    expect(find.text('Please choose a sample type'), findsOneWidget);
    verifyNever(
      () => samples.saveWithFindings(
        any(),
        attachments: any(named: 'attachments'),
      ),
    );
  });

  testWidgets('the preparation only appears for a faecal sample', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));

    await choose(tester, 'Crop swab');
    expect(find.text('Flotation'), findsNothing);

    await choose(tester, 'Faecal sample');
    expect(find.text('Flotation'), findsOneWidget);
  });

  // A flotation concentrates worm eggs a direct smear can miss entirely, so
  // the result is not interpretable without knowing which was done.
  testWidgets('a faecal sample cannot be saved without its preparation', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));
    await choose(tester, 'Faecal sample');
    await save(tester);

    expect(find.text('Please choose an examination method'), findsOneWidget);
    verifyNever(
      () => samples.saveWithFindings(
        any(),
        attachments: any(named: 'attachments'),
      ),
    );

    await choose(tester, 'Direct smear');
    expect(find.text('Please choose an examination method'), findsNothing);

    final body = await tapAndCapture(tester);
    expect(
      (body['sample'] as Map<String, dynamic>)['method'],
      'direct_smear',
    );
  });

  // The question only exists for a faecal sample; a crop swab has no
  // preparation to choose, and the route clears the column for one anyway.
  testWidgets('a crop swab saves without one', (tester) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));
    await choose(tester, 'Crop swab');

    final body = await tapAndCapture(tester);
    final sample = body['sample'] as Map<String, dynamic>;
    expect(sample['sample_type'], 'crop_swab');
    expect(sample.containsKey('method'), isFalse);
  });

  testWidgets('the findings list follows the chosen probe', (tester) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));

    await choose(tester, 'Crop swab');
    expect(find.text('Trichomonaden'), findsOneWidget);
    expect(find.text('Hefen'), findsOneWidget);
    expect(find.text('Spulwurmeier'), findsNothing);

    await choose(tester, 'Faecal sample');
    expect(find.text('Trichomonaden'), findsNothing);
    expect(find.text('Spulwurmeier'), findsOneWidget);
  });

  testWidgets('the lab name only appears once somebody else did it', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));

    await choose(tester, 'In-house');
    expect(find.widgetWithText(TextFormField, 'Lab/practice'), findsNothing);

    await choose(tester, 'Laboratory');
    expect(find.widgetWithText(TextFormField, 'Lab/practice'), findsOneWidget);
  });

  testWidgets('a graded finding is sent with its type and severity', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));

    await choose(tester, 'Faecal sample');
    await choose(tester, 'Flotation');
    // The grade selector for Spulwurmeier is the only one on that row.
    final row = find.ancestor(
      of: find.text('Spulwurmeier'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(of: row.first, matching: find.text('++')));
    await tester.pumpAndSettle();

    final body = await tapAndCapture(tester);
    expect(body['case'], 'c1');
    final sample = body['sample'] as Map<String, dynamic>;
    expect(sample['sample_type'], 'fecal');
    expect(sample['method'], 'flotation');
    expect(sample['no_findings'], isFalse);
    expect(body['findings'], [
      {'finding_type': 't_spul', 'severity': 'plus_plus'},
    ]);
  });

  testWidgets('"no findings" and a grade cannot both be set', (tester) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));
    await choose(tester, 'Crop swab');

    await tester.tap(find.text('No findings'));
    await tester.pumpAndSettle();

    // Ticked, the grade selectors are inert — the assertion is about the whole
    // sample, so it cannot coexist with a finding.
    final row = find.ancestor(
      of: find.text('Trichomonaden'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(of: row.first, matching: find.text('+')));
    await tester.pumpAndSettle();

    final body = await tapAndCapture(tester);
    expect((body['sample'] as Map<String, dynamic>)['no_findings'], isTrue);
    expect(body['findings'], isEmpty);
  });

  testWidgets('saving nothing at all is the legitimate pending state', (
    tester,
  ) async {
    await pump(tester, const MicroscopySheet(caseId: 'c1'));
    await choose(tester, 'Crop swab');
    await choose(tester, 'Laboratory');

    final body = await tapAndCapture(tester);
    final sample = body['sample'] as Map<String, dynamic>;
    expect(sample['no_findings'], isFalse);
    expect(body['findings'], isEmpty);
  });

  testWidgets(
    'switching the probe drops a grade that no longer fits, undoably',
    (tester) async {
      await pump(tester, const MicroscopySheet(caseId: 'c1'));
      await choose(tester, 'Crop swab');

      final row = find.ancestor(
        of: find.text('Trichomonaden'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: row.first, matching: find.text('+')),
      );
      await tester.pumpAndSettle();

      await choose(tester, 'Faecal sample');
      expect(
        find.textContaining('does not apply to the new sample type'),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Undo restores the probe too, or the grade has nowhere to sit.
      expect(find.text('Trichomonaden'), findsOneWidget);
      final body = await tapAndCapture(tester);
      expect(
        (body['sample'] as Map<String, dynamic>)['sample_type'],
        'crop_swab',
      );
      expect(body['findings'], [
        {'finding_type': 't_tricho', 'severity': 'plus'},
      ]);
    },
  );

  testWidgets('an edit sends the id, the full set and the surviving files', (
    tester,
  ) async {
    const existing = MicroscopySample(
      id: 'm1',
      caseId: 'c1',
      sampleType: MicroscopySampleType.fecal,
      method: MicroscopyMethod.flotation,
      examinedBy: MicroscopyExaminedBy.lab,
      externalLab: 'Labor Müller',
      attachments: ['smear.jpg'],
    );
    const findings = [
      MicroscopyFinding(
        id: 'f1',
        sample: 'm1',
        findingType: 't_spul',
        severity: MicroscopySeverity.plusPlus,
      ),
      MicroscopyFinding(
        id: 'f2',
        sample: 'm1',
        freeText: 'Ziliaten',
        severity: MicroscopySeverity.plus,
      ),
    ];

    await pump(
      tester,
      const MicroscopySheet(
        caseId: 'c1',
        sample: existing,
        findings: findings,
      ),
    );

    final body = await tapAndCapture(tester);
    expect(body['id'], 'm1');
    // The case is set on create only; the update rule refuses it anyway.
    expect(body.containsKey('case'), isFalse);
    expect(body['keep_attachments'], ['smear.jpg']);
    expect(
      body['findings'],
      containsAll(<Map<String, dynamic>>[
        {'finding_type': 't_spul', 'severity': 'plus_plus'},
        {'free_text': 'Ziliaten', 'severity': 'plus'},
      ]),
    );
  });

  testWidgets(
    'a term that no longer applies still shows on the record it is on',
    (tester) async {
      // A supervisor narrowed Trichomonaden to crop swabs after this faecal
      // sample was graded with it. Hiding the row would silently drop the
      // finding on the next save.
      const existing = MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        sampleType: MicroscopySampleType.fecal,
        method: MicroscopyMethod.flotation,
      );
      const findings = [
        MicroscopyFinding(
          id: 'f1',
          sample: 'm1',
          findingType: 't_tricho',
          severity: MicroscopySeverity.plusPlusPlus,
        ),
      ];

      await pump(
        tester,
        const MicroscopySheet(
          caseId: 'c1',
          sample: existing,
          findings: findings,
        ),
      );

      expect(find.text('Trichomonaden'), findsOneWidget);
      final body = await tapAndCapture(tester);
      expect(body['findings'], [
        {'finding_type': 't_tricho', 'severity': 'plus_plus_plus'},
      ]);
    },
  );
}
