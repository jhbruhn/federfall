import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:federfall_models/src/models/geo_point.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'disposition.freezed.dart';

/// The outcome of a case (release, aviary placement, death, etc.). Typically
/// one final row per case; history is allowed.
@freezed
abstract class Disposition with _$Disposition {
  const factory Disposition({
    required String id,
    required String caseId,
    // Null when the server carries a wire value this app version does not
    // know — rendered as "unknown", never coerced to a real outcome.
    DispositionType? type,
    DateTime? disposedAt,
    String? reason,
    String? performedBy,
    // released (wild / outside release)
    String? releaseLocation,
    GeoPoint? releaseGeo,
    String? releaseType,
    // placed_in_aviary
    String? aviary,
    // transferred
    String? transferType,
    String? transferDestination,
    @Default(false) bool vetSignedOff,
    String? vet,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Disposition;

  factory Disposition.fromRecord(RecordModel r) {
    final d = r.data;
    return Disposition(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      type: DispositionType.fromWire(d['type']),
      disposedAt: pbDate(d['disposed_at']),
      reason: pbString(d['reason']),
      performedBy: pbString(d['performed_by']),
      releaseLocation: pbString(d['release_location']),
      releaseGeo: GeoPoint.fromPb(d['release_geo']),
      releaseType: pbString(d['release_type']),
      aviary: pbString(d['aviary']),
      transferType: pbString(d['transfer_type']),
      transferDestination: pbString(d['transfer_destination']),
      vetSignedOff: pbBool(d['vet_signed_off']),
      vet: pbString(d['vet']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
