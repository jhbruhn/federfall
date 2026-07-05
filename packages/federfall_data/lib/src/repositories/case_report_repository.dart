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
  });

  final PocketBase pb;

  /// Longer than the 15s used for geocoding (`PbGeocodingRepository`) — Typst
  /// compiles the whole case timeline server-side before responding.
  final Duration networkTimeout;

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
    final res = await http.get(
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
  });

  /// Mirrors `PbGeocodingRepository._guard`: timeout → network,
  /// [ClientException] → [RepositoryException.fromClient], any other failure
  /// wrapped so the UI error states get a stable type.
  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op().timeout(networkTimeout);
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
