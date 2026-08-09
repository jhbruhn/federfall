import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSamplesRepo extends Mock implements PbMicroscopySamplesRepository {}

const _types = [
  MicroscopyFindingType(id: 't_spul', label: 'Spulwurmeier'),
  MicroscopyFindingType(id: 't_kok', label: 'Kokzidien-Oozysten'),
];

void main() {
  late MockSamplesRepo samples;

  setUp(() {
    samples = MockSamplesRepo();
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

  Future<void> pump(
    WidgetTester tester, {
    required MicroscopySample sample,
    List<MicroscopyFinding> findings = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
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
          home: Scaffold(
            body: MicroscopyTile(
              sample: sample,
              findings: findings,
              caseId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the probe, its preparation and the lab', (tester) async {
    await pump(
      tester,
      sample: MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        sampleType: MicroscopySampleType.fecal,
        method: MicroscopyMethod.flotation,
        examinedBy: MicroscopyExaminedBy.lab,
        externalLab: 'Labor Müller',
        examinedAt: DateTime(2026, 8, 9, 9, 12),
      ),
    );

    expect(find.text('Faecal sample · Flotation'), findsOneWidget);
    expect(find.text('Labor Müller'), findsOneWidget);
  });

  testWidgets('lists the findings worst first, graded', (tester) async {
    await pump(
      tester,
      sample: const MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        sampleType: MicroscopySampleType.fecal,
      ),
      findings: const [
        MicroscopyFinding(
          id: 'f1',
          sample: 'm1',
          findingType: 't_kok',
          severity: MicroscopySeverity.plus,
        ),
        MicroscopyFinding(
          id: 'f2',
          sample: 'm1',
          findingType: 't_spul',
          severity: MicroscopySeverity.plusPlus,
        ),
      ],
    );

    expect(
      find.text('Spulwurmeier ++, Kokzidien-Oozysten +'),
      findsOneWidget,
    );
  });

  testWidgets('a free-text finding names itself', (tester) async {
    await pump(
      tester,
      sample: const MicroscopySample(id: 'm1', caseId: 'c1'),
      findings: const [
        MicroscopyFinding(
          id: 'f1',
          sample: 'm1',
          freeText: 'Ziliaten',
          severity: MicroscopySeverity.plus,
        ),
      ],
    );

    expect(find.text('Ziliaten +'), findsOneWidget);
  });

  // The distinction the whole `no_findings` column exists for: a clean result
  // and one nobody has read yet must never render the same.
  testWidgets('a clean sample reads "no findings"', (tester) async {
    await pump(
      tester,
      sample: const MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        sampleType: MicroscopySampleType.cropSwab,
        noFindings: true,
      ),
    );
    expect(find.text('No findings'), findsOneWidget);
    expect(find.text('Result pending'), findsNothing);
  });

  testWidgets('an unread sample reads "result pending", not "no findings"', (
    tester,
  ) async {
    await pump(
      tester,
      sample: const MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        sampleType: MicroscopySampleType.cropSwab,
        examinedBy: MicroscopyExaminedBy.lab,
      ),
    );
    expect(find.text('Result pending'), findsOneWidget);
    expect(find.text('No findings'), findsNothing);
  });

  // A diagnosis is a human call; the tile only offers the shortcut.
  testWidgets('a graded sample offers the diagnosis shortcut', (tester) async {
    await pump(
      tester,
      sample: const MicroscopySample(id: 'm1', caseId: 'c1'),
      findings: const [
        MicroscopyFinding(
          id: 'f1',
          sample: 'm1',
          findingType: 't_spul',
          severity: MicroscopySeverity.plusPlusPlus,
        ),
      ],
    );
    expect(find.text('Create diagnosis'), findsOneWidget);
  });

  // Two parasites are two diagnoses. A single shortcut could only pre-fill
  // one of them, and which one it picked would be arbitrary to the reader.
  testWidgets('each finding gets its own, named diagnosis shortcut', (
    tester,
  ) async {
    await pump(
      tester,
      sample: const MicroscopySample(id: 'm1', caseId: 'c1'),
      findings: const [
        MicroscopyFinding(
          id: 'f1',
          sample: 'm1',
          findingType: 't_spul',
          severity: MicroscopySeverity.plusPlus,
        ),
        MicroscopyFinding(
          id: 'f2',
          sample: 'm1',
          findingType: 't_kok',
          severity: MicroscopySeverity.plus,
        ),
      ],
    );

    expect(find.text('Create diagnosis: Spulwurmeier'), findsOneWidget);
    expect(find.text('Create diagnosis: Kokzidien-Oozysten'), findsOneWidget);
    // The unqualified label belongs to the single-finding case only.
    expect(find.text('Create diagnosis'), findsNothing);
  });

  testWidgets('a sample with nothing found offers no diagnosis', (
    tester,
  ) async {
    await pump(
      tester,
      sample: const MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        noFindings: true,
      ),
    );
    expect(find.text('Create diagnosis'), findsNothing);
  });

  // Requesting `?thumb=` for a video serves the ORIGINAL, so a 50 MB clip
  // would be downloaded to paint a 96px tile (the 1700000049 finding).
  testWidgets('a video attachment gets a placeholder, never a thumbnail', (
    tester,
  ) async {
    await pump(
      tester,
      sample: const MicroscopySample(
        id: 'm1',
        caseId: 'c1',
        attachments: ['clip.mp4', 'smear.jpg'],
      ),
    );

    expect(find.byType(VideoAttachmentThumb), findsOneWidget);
    verifyNever(
      () => samples.fileUrl('m1', 'clip.mp4', thumb: any(named: 'thumb')),
    );
    verify(
      () => samples.fileUrl('m1', 'smear.jpg', thumb: '200x200'),
    ).called(1);
  });
}
