import 'dart:io';

import 'package:federfall/features/cases/vet_appointments/vet_appointment_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
