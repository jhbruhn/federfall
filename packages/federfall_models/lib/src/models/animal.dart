import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'animal.freezed.dart';

/// The persistent animal identity that spans every admission (case).
@freezed
abstract class Animal with _$Animal {
  const factory Animal({
    required String id,
    required String species,
    String? name,
    Sex? sex,
    @Default(false) bool isOwned,
    LifetimeStatus? lifetimeStatus,
    @Default(<String>[]) List<String> tags,
    String? notes,
    String? photo,
    String? currentAviary,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Animal;

  factory Animal.fromRecord(RecordModel r) {
    final d = r.data;
    return Animal(
      id: r.id,
      species: pbString(d['species']) ?? '',
      name: pbString(d['name']),
      sex: Sex.fromWire(d['sex']),
      isOwned: pbBool(d['is_owned']),
      lifetimeStatus: LifetimeStatus.fromWire(d['lifetime_status']),
      tags: pbStringList(d['tags']),
      notes: pbString(d['notes']),
      photo: pbString(d['photo']),
      currentAviary: pbString(d['current_aviary']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
