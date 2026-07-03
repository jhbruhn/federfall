import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_agent_client.g.dart';

/// Builds the app's HTTP `User-Agent`, e.g. `federfall/1.2.3`.
///
/// The PocketBase Dart SDK never sets a `User-Agent`, so requests otherwise go
/// out with the platform default (`Dart/<v> (dart:io)` on native). The version
/// comes from the running build via [PackageInfo] (driven by release-please
/// through `pubspec.yaml`); it falls back to `0.0.0` when unavailable.
Future<String> loadUserAgent() async {
  final info = await PackageInfo.fromPlatform();
  final version = info.version.isEmpty ? '0.0.0' : info.version;
  return 'federfall/$version';
}

/// The app-wide HTTP `User-Agent` string. Resolved once and cached.
@Riverpod(keepAlive: true)
Future<String> userAgent(Ref ref) => loadUserAgent();

/// An [http.Client] that stamps a fixed `User-Agent` on every request before
/// delegating to [_inner].
///
/// Pass it to `PocketBase(..., httpClientFactory: ...)` so every call the SDK
/// makes identifies the app instead of using the platform HTTP default.
class UserAgentClient extends http.BaseClient {
  UserAgentClient(this.userAgent, [http.Client? inner])
    : _inner = inner ?? http.Client();

  /// The `User-Agent` value set on every outgoing request.
  final String userAgent;

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['user-agent'] = userAgent;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
