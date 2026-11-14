import 'package:pocketbase/pocketbase.dart';
import 'package:zugvogel_data/zugvogel_data.dart';

/// The refusal code of a keyed write whose key was already used for a
/// DIFFERENT body (federfall-lebw).
///
/// A wire value: the backend's `lib_idempotency.js` sends it as a `data` key
/// beside a 409, and renaming either side breaks the other.
const idempotencyKeyReusedCode = 'idempotency_key_reused';

/// Translates a [ClientException] from one of the idempotency-keyed write
/// routes (intake, prescribe-batch, administer-batch, vaccinate-batch).
///
/// A 409 there means the server already COMMITTED a different body under this
/// key — the key row is written in the same transaction as the records — and
/// refused to answer this request with that first response. It is recognised
/// by the status, which nothing else on those routes answers; the `data` key
/// is not needed for that (and `RepositoryException.fromClient` only reads
/// codes for a 400/422). It becomes a validation error carrying
/// [idempotencyKeyReusedCode], so the app's `ServerCodeStrings` turns it into
/// its own sentence wherever the error is rendered. Anything else is
/// translated as usual.
RepositoryException idempotentWriteException(ClientException e) {
  if (e.statusCode == 409) {
    return RepositoryException(
      'This idempotency key already committed a different request',
      kind: RepositoryErrorKind.validation,
      statusCode: 409,
      cause: e,
      serverCodes: const [idempotencyKeyReusedCode],
    );
  }
  return RepositoryException.fromClient(e);
}

/// Whether [error] is the refusal [idempotentWriteException] produces.
///
/// A screen that sees it must take a FRESH key before the user can save again:
/// the old one will keep answering 409 for as long as the server remembers it.
bool isIdempotencyKeyReused(Object error) =>
    error is RepositoryException &&
    error.serverCodes.contains(idempotencyKeyReusedCode);
