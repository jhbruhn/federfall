import 'package:federfall/ui/ui.dart';

/// PocketBase caps `vet_appointments.attachments` at ten files (1700000094).
const int kVetAppointmentMaxAttachments = 10;

/// What `vet_appointments.attachments` admits, by extension — the client-side
/// mirror of 1700000094's MIME allowlist, checked before a file is staged so a
/// wrong pick is refused with its name rather than as a failed save. The server
/// sniffs the content and stays the authority.
///
/// Keyed by extension because that is all a picked file reliably carries; the
/// MIME values exist so `vet_appointment_attachments_test.dart` can hold this
/// map and the migration's list to the SAME set — add a type in one place and
/// that test fails until the other agrees.
const Map<String, String> kVetAppointmentFileTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
  'dcm': 'application/dicom',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
};

/// Whether a picked file may be uploaded at all (see
/// [kVetAppointmentFileTypes]).
bool isAcceptedVetAttachment(String nameOrPath) =>
    kVetAppointmentFileTypes.containsKey(attachmentExtension(nameOrPath));
