import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements PbReadOnlyRepository<Object?> {}

void main() {
  group('attachmentKindOf', () {
    test('only what PocketBase thumbnails AND Flutter decodes is an image', () {
      expect(attachmentKindOf('roentgen_ab12cd34ef.png'), AttachmentKind.image);
      expect(attachmentKindOf('foto.JPG'), AttachmentKind.image);
      // A thumb of these would serve the ORIGINAL (1700000049).
      expect(attachmentKindOf('befund.pdf'), AttachmentKind.document);
      expect(attachmentKindOf('IMG_0001.heic'), AttachmentKind.document);
      expect(attachmentKindOf('scan.tiff'), AttachmentKind.document);
      expect(attachmentKindOf('no-extension'), AttachmentKind.document);
    });

    test('a video is neither', () {
      expect(attachmentKindOf('clip.mp4'), AttachmentKind.video);
      expect(attachmentKindOf('clip.MOV'), AttachmentKind.video);
    });
  });

  test("attachmentDisplayName strips PocketBase's random suffix, and only "
      'that', () {
    expect(attachmentDisplayName('befund_0123456789.pdf'), 'befund.pdf');
    expect(
      attachmentDisplayName('roentgen_links_ab12CD34ef.png'),
      'roentgen_links.png',
    );
    expect(attachmentDisplayName('befund_kurz.pdf'), 'befund_kurz.pdf');
  });

  group('AttachmentStrip', () {
    late MockRepo repo;

    setUp(() {
      repo = MockRepo();
      when(
        () => repo.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenReturn(Uri.parse('http://pb/f.png'));
    });

    Future<void> pump(WidgetTester tester, List<String> files) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AttachmentStrip(repo: repo, recordId: 'r1', files: files),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a document is a named chip and never asked for a thumbnail', (
      tester,
    ) async {
      await pump(tester, ['befund_0123456789.pdf']);

      expect(find.widgetWithText(InputChip, 'befund.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      verifyNever(
        () => repo.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      );
    });

    testWidgets('images, videos and documents each get their own form', (
      tester,
    ) async {
      await pump(tester, ['xray.png', 'clip.mp4', 'befund.pdf']);

      verify(() => repo.fileUrl('r1', 'xray.png', thumb: '200x200')).called(1);
      verifyNever(
        () => repo.fileUrl('r1', 'clip.mp4', thumb: any(named: 'thumb')),
      );
      expect(find.byType(VideoAttachmentThumb), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets(
      'holds its space with a spinner until the repository resolves',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AttachmentStrip(
                  repo: null,
                  recordId: 'r1',
                  files: ['a.png'],
                ),
              ),
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });
}
