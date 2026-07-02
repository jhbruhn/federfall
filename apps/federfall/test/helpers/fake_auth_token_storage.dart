import 'package:federfall/core/pocketbase/auth_token_storage.dart';

/// In-memory [AuthTokenStorage] so tests don't touch the platform keychain.
class FakeAuthTokenStorage implements AuthTokenStorage {
  FakeAuthTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String data) async => value = data;

  @override
  Future<void> delete() async => value = null;
}
