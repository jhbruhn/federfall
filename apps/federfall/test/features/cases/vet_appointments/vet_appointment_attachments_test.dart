import 'dart:io';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_attachments.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockVetAppointmentsRepo extends Mock
    implements PbVetAppointmentsRepository {}

void main() {
  group('attachment kinds', () {
    test(
      'only what PocketBase thumbnails AND Flutter decodes is a preview',
      () {
        expect(isPreviewableImage('roentgen_ab12cd34ef.png'), isTrue);
        expect(isPreviewableImage('foto.JPG'), isTrue);
        // A thumb of these would serve the ORIGINAL (1700000049).
        expect(isPreviewableImage('befund.pdf'), isFalse);
        expect(isPreviewableImage('IMG_0001.heic'), isFalse);
        expect(isPreviewableImage('scan.tiff'), isFalse);
        expect(isPreviewableImage('no-extension'), isFalse);
      },
    );

    test('the client allowlist refuses markup the server would too', () {
      expect(isAcceptedVetAttachment('befund.pdf'), isTrue);
      expect(isAcceptedVetAttachment('serie.dcm'), isTrue);
      expect(isAcceptedVetAttachment('arztbrief.DOCX'), isTrue);
      expect(isAcceptedVetAttachment('evil.html'), isFalse);
      expect(isAcceptedVetAttachment('evil.svg'), isFalse);
      expect(isAcceptedVetAttachment('README'), isFalse);
    });

    // The two lists are written in two languages and nothing else connects
    // them: a type added only to the migration is refused on the device, one
    // added only here fails as an opaque 400 after the upload.
    test("the client allowlist is exactly the migration's", () {
      final source = File(
        '../../backend/pocketbase/pb_migrations/'
        '1700000094_vet_appointment_attachments.js',
      ).readAsStringSync();
      final block = RegExp(
        r'mimeTypes:\s*\[([^\]]*)\]',
      ).firstMatch(source)!.group(1)!;
      final server = RegExp(
        '"([^"]+)"',
      ).allMatches(block).map((m) => m.group(1)).toSet();

      expect(server, isNotEmpty);
      expect(kVetAppointmentFileTypes.values.toSet(), server);
    });

    test("strips PocketBase's random suffix, and only that", () {
      expect(attachmentDisplayName('befund_0123456789.pdf'), 'befund.pdf');
      expect(
        attachmentDisplayName('roentgen_links_ab12CD34ef.png'),
        'roentgen_links.png',
      );
      expect(attachmentDisplayName('befund_kurz.pdf'), 'befund_kurz.pdf');
    });
  });

  testWidgets('a PDF is a named chip and never asked for a thumbnail', (
    tester,
  ) async {
    final repo = MockVetAppointmentsRepo();
    final container = ProviderContainer(
      overrides: [
        vetAppointmentsRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VetAppointmentAttachments(
              appointment: VetAppointment(
                id: 'va1',
                caseId: 'c1',
                attachments: ['befund_0123456789.pdf'],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'befund.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    verifyNever(
      () => repo.fileUrl(any(), any(), thumb: any(named: 'thumb')),
    );
  });
}
