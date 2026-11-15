import 'package:federfall/ui/ui.dart';

/// PocketBase caps `journal_entries.attachments` at twenty files
/// (1700000007).
const int kJournalMaxAttachments = 20;

/// What `journal_entries.attachments` admits, by extension — the client-side
/// mirror of 1700000096's MIME allowlist: the four photo types plus PDF. A
/// picked file outside it is refused with its name before the upload.
///
/// The MIME values exist so `journal_attachments_test.dart` can hold this map
/// and the migration's list to the SAME set.
const Map<String, String> kJournalFileTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
};

/// Whether a picked file may be attached to a journal entry (see
/// [kJournalFileTypes]).
bool isAcceptedJournalAttachment(String nameOrPath) =>
    kJournalFileTypes.containsKey(attachmentExtension(nameOrPath));
