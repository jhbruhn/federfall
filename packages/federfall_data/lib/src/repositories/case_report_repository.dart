import 'dart:async';
import 'dart:typed_data';

import 'package:federfall_data/src/repository_exception.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Fetches the per-case PDF report (federfall-gdp8), rendered server-side by
/// `pb_hooks/case_report.pb.js` (Typst), via
/// `GET /api/federfall/cases/{id}/report.pdf`.
///
/// Deliberately does NOT use [PocketBase.send]: that method reads the response
/// via `response.stream.bytesToString()`
/// (pocketbase-0.24.0/lib/src/client.dart), which corrupts binary data — fine
/// for the JSON every other repository fetches, fatal for a PDF. This issues
/// the request directly with `package:http` instead and reads `bodyBytes`.
///
/// A single-method class rather than the usual interface + `Pb`-prefixed impl
/// split (unlike e.g. `GeocodingRepository`) — one member would just trip the
/// `one_member_abstracts` lint; mock this concrete class directly in tests.
class PbCaseReportRepository {
  PbCaseReportRepository(
    this.pb, {
    this.networkTimeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final PocketBase pb;

  /// Longer than the 15s used for geocoding (`PbGeocodingRepository`) — Typst
  /// compiles the whole case timeline server-side before responding.
  final Duration networkTimeout;

  /// Injectable so tests can supply a `package:http/testing.dart` MockClient
  /// instead of hitting the network (see case_report_repository_test.dart).
  final http.Client _httpClient;

  /// The compiled PDF bytes for [caseId], or throws [RepositoryException].
  ///
  /// [lang] picks the report's translation dict (`typst/report.typ`'s
  /// `STRINGS`) — an unmapped value falls back to German server-side, so
  /// there's no need to validate it here.
  ///
  /// [tzOffsetMinutes] is the caller's own UTC offset (e.g.
  /// `DateTime.now().timeZoneOffset.inMinutes`) — the server has no timezone
  /// database to resolve a zone name against (see case_report.pb.js), so it
  /// asks the client to just say its offset directly rather than guessing a
  /// zone. `null` (the default) omits the param entirely and falls back to a
  /// hard-coded Europe/Berlin rule server-side.
  Future<Uint8List> fetchPdf(
    String caseId, {
    String lang = 'de',
    int? tzOffsetMinutes,
  }) => _guard(() async {
    final uri = pb.buildURL('/api/federfall/cases/$caseId/report.pdf', {
      'lang': lang,
      if (tzOffsetMinutes != null) 'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    return _get(uri);
  });

  /// The compiled receipt PNG bytes for [caseId] (federfall-i0wq), rendered
  /// server-side at exactly [widthDots] pixels wide by `typst/receipt.typ`.
  ///
  /// [widthDots] is the printer head's raster width in dots — the caller's
  /// stored paper-size setting (see the printer-connectivity settings
  /// screen), NOT a named format: for raster ESC/POS printing 1 image px = 1
  /// printer dot, so this is the only thing that determines paper fit
  /// server-side (see case_report.pb.js). [lang] and [tzOffsetMinutes] mirror
  /// [fetchPdf].
  Future<Uint8List> fetchReceiptPng(
    String caseId, {
    required int widthDots,
    String lang = 'de',
    int? tzOffsetMinutes,
  }) => _guard(() async {
    final uri = pb.buildURL('/api/federfall/cases/$caseId/report.pdf', {
      'widthDots': '$widthDots',
      'lang': lang,
      if (tzOffsetMinutes != null) 'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    return _get(uri);
  });

  /// The annual report for [year] (federfall-dk0c), rendered server-side by
  /// `pb_hooks/annual_report.pb.js` — a Typst PDF, or the same table as a CSV
  /// when [csv] is set.
  ///
  /// The report covers the cases *admitted* in [year]; a null [year] reports
  /// every case on record. The period's boundaries are the CALLER'S midnight,
  /// so [tzOffsetMinutes] decides which side of New Year a late-evening
  /// admission falls on — pass it (see [fetchPdf] for why the server cannot
  /// work it out itself).
  ///
  /// Both formats come off one route because they are one table: the hook
  /// reads the `case_report_rows` view for either. The CSV is written
  /// server-side rather than here so its columns cannot drift from the PDF's
  /// case list, and it arrives BOM-prefixed and localized — the caller only
  /// has to hand the bytes to a share sheet.
  ///
  /// The longer timeout is deliberate: unlike a single case, this compiles a
  /// whole year of them (a landscape table page per ~20 cases).
  Future<Uint8List> fetchAnnualReport({
    int? year,
    bool csv = false,
    String lang = 'de',
    int? tzOffsetMinutes,
    Duration? timeout,
  }) => _guard(() async {
    final uri = pb.buildURL('/api/federfall/reports/annual', {
      if (year != null) 'year': '$year',
      if (csv) 'format': 'csv',
      'lang': lang,
      if (tzOffsetMinutes != null) 'tzOffsetMinutes': '$tzOffsetMinutes',
    });
    return _get(uri);
  }, timeout: timeout ?? const Duration(minutes: 2));

  Future<Uint8List> _get(Uri uri) async {
    final res = await _httpClient.get(
      uri,
      headers: {
        if (pb.authStore.isValid) 'Authorization': pb.authStore.token,
      },
    );
    if (res.statusCode != 200) {
      throw RepositoryException.fromClient(
        ClientException(url: uri, statusCode: res.statusCode),
      );
    }
    return res.bodyBytes;
  }

  /// Mirrors `PbGeocodingRepository._guard`: timeout → network,
  /// [ClientException] → [RepositoryException.fromClient], any other failure
  /// wrapped so the UI error states get a stable type.
  ///
  /// [timeout] overrides [networkTimeout] for the calls that legitimately take
  /// longer than fetching one case's report.
  Future<R> _guard<R>(Future<R> Function() op, {Duration? timeout}) async {
    try {
      return await op().timeout(timeout ?? networkTimeout);
    } on TimeoutException {
      throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    } on RepositoryException {
      rethrow;
    } on Object catch (e) {
      throw RepositoryException('Unexpected repository failure: $e', cause: e);
    }
  }
}
