import 'dart:convert';

import 'package:federfall_data/federfall_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockAuthStore extends Mock implements AuthStore {}

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  late _MockPb pb;
  late _MockAuthStore authStore;

  setUp(() {
    pb = _MockPb();
    authStore = _MockAuthStore();
    when(() => pb.authStore).thenReturn(authStore);
    when(() => authStore.isValid).thenReturn(false);
    // buildURL isn't stubbed with a fixed return — call through to a real
    // Uri built from the recorded path/query so the assertions below double
    // as a check that PbCaseReportRepository builds the params it claims to.
    when(
      () => pb.buildURL(any(), any()),
    ).thenAnswer((invocation) {
      final path = invocation.positionalArguments[0] as String;
      final query = invocation.positionalArguments[1] as Map<String, dynamic>?;
      return Uri.parse(
        'http://pb.test$path',
      ).replace(queryParameters: query);
    });
  });

  group('fetchPdf', () {
    test(
      'requests report.pdf with lang and no tzOffsetMinutes by default',
      () async {
        Uri? seenUri;
        final repo = PbCaseReportRepository(
          pb,
          httpClient: MockClient((request) async {
            seenUri = request.url;
            return http.Response.bytes(utf8.encode('%PDF-1'), 200);
          }),
        );

        final bytes = await repo.fetchPdf('case1');

        expect(seenUri!.path, '/api/federfall/cases/case1/report.pdf');
        expect(seenUri!.queryParameters, {'lang': 'de'});
        expect(bytes, utf8.encode('%PDF-1'));
      },
    );

    test('includes tzOffsetMinutes when given', () async {
      Uri? seenUri;
      final repo = PbCaseReportRepository(
        pb,
        httpClient: MockClient((request) async {
          seenUri = request.url;
          return http.Response.bytes(<int>[], 200);
        }),
      );

      await repo.fetchPdf('case1', lang: 'en', tzOffsetMinutes: 120);

      expect(seenUri!.queryParameters, {
        'lang': 'en',
        'tzOffsetMinutes': '120',
      });
    });

    test('sends the auth token when the auth store is valid', () async {
      when(() => authStore.isValid).thenReturn(true);
      when(() => authStore.token).thenReturn('tok-123');
      Map<String, String>? seenHeaders;
      final repo = PbCaseReportRepository(
        pb,
        httpClient: MockClient((request) async {
          seenHeaders = request.headers;
          return http.Response.bytes(<int>[], 200);
        }),
      );

      await repo.fetchPdf('case1');

      expect(seenHeaders!['Authorization'], 'tok-123');
    });
  });

  group('fetchReceiptPng', () {
    test('builds ?widthDots=<N>&lang=<lang> for the same route', () async {
      Uri? seenUri;
      final repo = PbCaseReportRepository(
        pb,
        httpClient: MockClient((request) async {
          seenUri = request.url;
          return http.Response.bytes(<int>[0x89, 0x50, 0x4e, 0x47], 200);
        }),
      );

      final bytes = await repo.fetchReceiptPng('case1', widthDots: 512);

      expect(seenUri!.path, '/api/federfall/cases/case1/report.pdf');
      expect(seenUri!.queryParameters, {'widthDots': '512', 'lang': 'de'});
      expect(bytes, <int>[0x89, 0x50, 0x4e, 0x47]);
    });

    test(
      'includes tzOffsetMinutes and a non-default lang when given',
      () async {
        Uri? seenUri;
        final repo = PbCaseReportRepository(
          pb,
          httpClient: MockClient((request) async {
            seenUri = request.url;
            return http.Response.bytes(<int>[], 200);
          }),
        );

        await repo.fetchReceiptPng(
          'case1',
          widthDots: 384,
          lang: 'en',
          tzOffsetMinutes: -60,
        );

        expect(seenUri!.queryParameters, {
          'widthDots': '384',
          'lang': 'en',
          'tzOffsetMinutes': '-60',
        });
      },
    );

    test(
      'a non-200 response is translated into a RepositoryException',
      () async {
        final repo = PbCaseReportRepository(
          pb,
          httpClient: MockClient((request) async {
            return http.Response('bad request', 400);
          }),
        );

        expect(
          () => repo.fetchReceiptPng('case1', widthDots: 512),
          throwsA(isA<RepositoryException>()),
        );
      },
    );

    test('a hung request fails fast as a network error', () async {
      final repo = PbCaseReportRepository(
        pb,
        networkTimeout: const Duration(milliseconds: 50),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response.bytes(<int>[], 200);
        }),
      );

      expect(
        () => repo.fetchReceiptPng('case1', widthDots: 512),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.isNetwork,
            'isNetwork',
            true,
          ),
        ),
      );
    });
  });
}
