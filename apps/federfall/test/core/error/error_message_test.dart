import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('de'));

  RepositoryException repo(int status) =>
      RepositoryException.fromClient(ClientException(statusCode: status));

  test('maps repository error kinds to localized messages', () {
    expect(errorMessage(l10n, repo(0)), l10n.errorOffline);
    expect(errorMessage(l10n, repo(401)), l10n.errorUnauthorized);
    expect(errorMessage(l10n, repo(404)), l10n.errorNotFound);
    expect(errorMessage(l10n, repo(422)), l10n.errorValidation);
    expect(errorMessage(l10n, repo(500)), l10n.errorGenericTitle);
  });

  test('falls back to generic for non-repository errors', () {
    expect(errorMessage(l10n, StateError('x')), l10n.errorGenericTitle);
  });

  test('recognizes only connectivity failures as network errors', () {
    expect(isNetworkError(repo(0)), isTrue);
    expect(isNetworkError(repo(401)), isFalse);
    expect(isNetworkError(StateError('x')), isFalse);
  });

  test('load surfaces report the missing content, not the connection', () {
    // The offline strip states the connection app-wide, and a failed read has
    // no entry to keep — so the write-flavoured `errorOffline` is not reused.
    expect(loadErrorMessage(l10n, repo(0)), l10n.errorLoadFailed);
    expect(loadErrorMessage(l10n, repo(401)), l10n.errorUnauthorized);
    expect(loadErrorMessage(l10n, StateError('x')), l10n.errorGenericTitle);
  });
}
