import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'organisation.freezed.dart';

/// An organisation — the tenancy boundary every other record is tagged with.
@freezed
abstract class Organisation with _$Organisation {
  const factory Organisation({
    required String id,
    required String name,
    String? contactEmail,
    String? contactPhone,
    @Default(<String, dynamic>{}) Map<String, dynamic> settings,
    DateTime? created,
    DateTime? updated,
  }) = _Organisation;

  factory Organisation.fromRecord(RecordModel r) {
    final d = r.data;
    return Organisation(
      id: r.id,
      name: pbString(d['name']) ?? '',
      contactEmail: pbString(d['contact_email']),
      contactPhone: pbString(d['contact_phone']),
      settings: switch (d['settings']) {
        final Map<String, dynamic> m => m,
        _ => const <String, dynamic>{},
      },
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
