import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'care_area.freezed.dart';

/// A room a carer houses birds in — „Quarantänezimmer", „Garage" — from the
/// `care_areas` collection (1700000097, federfall-r67n).
///
/// It belongs to one person ([owner]), because it is part of their home: two
/// carers' „Garage" are two different garages. A case points at one through
/// `Case.area`, and the case list groups by them in [position] order — the
/// order the owner walks through their rooms, not the alphabet.
@freezed
abstract class CareArea with _$CareArea {
  const factory CareArea({
    required String id,
    required String name,
    required String owner,
    @Default(0) int position,
    String? org,
  }) = _CareArea;

  factory CareArea.fromRecord(RecordModel r) {
    final d = r.data;
    return CareArea(
      id: r.id,
      name: pbString(d['name']) ?? '',
      owner: pbString(d['owner']) ?? '',
      position: pbInt(d['position']) ?? 0,
      org: pbString(d['org']),
    );
  }
}
