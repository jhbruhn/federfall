import 'package:pocketbase/pocketbase.dart';

/// A domain-level failure raised by the repository layer.
///
/// PocketBase surfaces transport/validation problems as [ClientException];
/// repositories translate those into this type so callers (and the UI error
/// states) depend on a stable shape rather than the SDK's. The original is kept
/// in [cause] for logging.
class RepositoryException implements Exception {
  const RepositoryException(
    this.message, {
    this.kind = RepositoryErrorKind.unknown,
    this.statusCode,
    this.cause,
  });

  /// Builds a [RepositoryException] from a PocketBase [ClientException],
  /// classifying it by HTTP status / connectivity.
  factory RepositoryException.fromClient(ClientException e) {
    final status = e.statusCode;
    final kind = switch (status) {
      0 => RepositoryErrorKind.network,
      401 || 403 => RepositoryErrorKind.unauthorized,
      404 => RepositoryErrorKind.notFound,
      400 || 422 => RepositoryErrorKind.validation,
      _ => RepositoryErrorKind.unknown,
    };
    return RepositoryException(
      _messageFor(kind, e),
      kind: kind,
      statusCode: status,
      cause: e,
    );
  }

  /// Human-oriented (non-localized) summary; the UI maps [kind] to localized
  /// copy where it matters.
  final String message;

  /// Coarse classification used for branching and UI mapping.
  final RepositoryErrorKind kind;

  /// Originating HTTP status code, when known.
  final int? statusCode;

  /// The underlying error, preserved for logging.
  final Object? cause;

  /// Whether this looks like a connectivity failure (no server reached).
  bool get isNetwork => kind == RepositoryErrorKind.network;

  static String _messageFor(RepositoryErrorKind kind, ClientException e) {
    return switch (kind) {
      RepositoryErrorKind.network => 'Could not reach the server',
      RepositoryErrorKind.unauthorized => 'Not authorized',
      RepositoryErrorKind.notFound => 'Not found',
      RepositoryErrorKind.validation => 'Invalid request',
      // Never produced by fromClient (a ClientException means the server
      // answered); listed for exhaustiveness.
      RepositoryErrorKind.unknownOutcome =>
        'The request outcome could not be determined',
      RepositoryErrorKind.unknown => e.toString(),
    };
  }

  @override
  String toString() =>
      'RepositoryException($kind, status: $statusCode): $message';
}

/// Coarse categories of repository failure.
enum RepositoryErrorKind {
  /// No response from the server (offline, DNS, timeout).
  network,

  /// Authentication/authorization rejected the request (401/403).
  unauthorized,

  /// The requested record does not exist (404).
  notFound,

  /// The server rejected the payload (400/422).
  validation,

  /// A write timed out client-side after the request left the device — the
  /// server may still have committed it, so blindly retrying can duplicate
  /// the change (e.g. a second animal+case from one intake).
  unknownOutcome,

  /// Anything else.
  unknown,
}
