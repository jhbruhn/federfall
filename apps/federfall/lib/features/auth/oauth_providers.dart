import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'oauth_providers.g.dart';

/// The OAuth2 providers the server offers (name + display label), for the login
/// screen's sign-in buttons. Empty when none are configured. Read only when the
/// server advertises providers (serverInfo.auth.oauth2), so a passwordless or
/// password-only instance never makes the call.
@riverpod
Future<List<OAuthProvider>> oauthProviders(Ref ref) async {
  final repo = await ref.watch(authRepositoryProvider.future);
  return repo.oauthProviders();
}
