import 'package:federfall/core/pocketbase/user_agent_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('stamps the User-Agent on every request', () async {
    String? seenUserAgent;
    final inner = MockClient((request) async {
      seenUserAgent = request.headers['user-agent'];
      return http.Response('ok', 200);
    });

    final client = UserAgentClient('federfall/1.2.3', inner);
    await client.get(Uri.parse('https://pigeons.example/api/health'));

    expect(seenUserAgent, 'federfall/1.2.3');
  });

  test('overrides an existing User-Agent header', () async {
    String? seenUserAgent;
    final inner = MockClient((request) async {
      seenUserAgent = request.headers['user-agent'];
      return http.Response('ok', 200);
    });

    final client = UserAgentClient('federfall/1.2.3', inner);
    await client.get(
      Uri.parse('https://pigeons.example/api/health'),
      headers: {'user-agent': 'Dart/3.12 (dart:io)'},
    );

    expect(seenUserAgent, 'federfall/1.2.3');
  });
}
