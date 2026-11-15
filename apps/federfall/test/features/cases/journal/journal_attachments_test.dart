import 'dart:io';

import 'package:federfall/features/cases/journal/journal_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the client allowlist admits photos and PDF, nothing active', () {
    expect(isAcceptedJournalAttachment('befund.pdf'), isTrue);
    expect(isAcceptedJournalAttachment('LABOR.PDF'), isTrue);
    expect(isAcceptedJournalAttachment('wunde.jpg'), isTrue);
    expect(isAcceptedJournalAttachment('evil.html'), isFalse);
    expect(isAcceptedJournalAttachment('evil.svg'), isFalse);
    expect(isAcceptedJournalAttachment('arztbrief.docx'), isFalse);
    expect(isAcceptedJournalAttachment('README'), isFalse);
  });

  // Same guard as the vet appointments': the two lists are written in two
  // languages and nothing else connects them.
  test("the client allowlist is exactly the migration's", () {
    final source = File(
      '../../backend/pocketbase/pb_migrations/'
      '1700000096_journal_pdf_attachments.js',
    ).readAsStringSync();
    // The UP migration's list is the first one in the file.
    final block = RegExp(
      r'mimeTypes\s*=\s*\[([^\]]*)\]',
    ).firstMatch(source)!.group(1)!;
    final server = RegExp(
      '"([^"]+)"',
    ).allMatches(block).map((m) => m.group(1)).toSet();

    expect(server, contains('application/pdf'));
    expect(kJournalFileTypes.values.toSet(), server);
  });
}
