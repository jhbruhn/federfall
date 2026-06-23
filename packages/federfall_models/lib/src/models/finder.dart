import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/models/app_user.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'finder.freezed.dart';

/// The external person who found/brought in a bird. GDPR-sensitive PII, kept
/// distinct from staff [AppUser]s and subject to a retention policy (FED-8.1).
@freezed
abstract class Finder with _$Finder {
  const factory Finder({
    required String id,
    String? firstName,
    String? lastName,
    String? organisation,
    String? phone,
    String? altPhone,
    String? email,
    String? address,
    String? postalCode,
    String? city,
    String? region,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Finder;

  factory Finder.fromRecord(RecordModel r) {
    final d = r.data;
    return Finder(
      id: r.id,
      firstName: pbString(d['first_name']),
      lastName: pbString(d['last_name']),
      organisation: pbString(d['organisation']),
      phone: pbString(d['phone']),
      altPhone: pbString(d['alt_phone']),
      email: pbString(d['email']),
      address: pbString(d['address']),
      postalCode: pbString(d['postal_code']),
      city: pbString(d['city']),
      region: pbString(d['region']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
