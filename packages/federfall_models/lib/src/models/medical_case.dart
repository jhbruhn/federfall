import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:federfall_models/src/models/animal.dart';
import 'package:federfall_models/src/models/geo_point.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'medical_case.freezed.dart';

/// One care episode (admission → disposition). The unit carers work on; an
/// [Animal] may have many over its lifetime (re-admission).
///
/// Named [Case] for the domain term; the file is `medical_case` to avoid the
/// `case` keyword colliding in tooling.
@freezed
abstract class Case with _$Case {
  const factory Case({
    required String id,
    required String animal,
    String? caseNumber,
    AgeClass? ageClass,

    // intake
    DateTime? admittedAt,
    DateTime? foundAt,
    String? admittedBy,
    String? transportedBy,
    String? finder,

    // find location
    String? findLocation,
    GeoPoint? findGeo,
    String? city,
    String? region,

    @Default(<AdmissionReason>[]) List<AdmissionReason> reasonsForAdmission,
    int? intakeWeightG,
    String? intakeNotes,
    @Default(<String>[]) List<String> intakePhotos,

    CaseStatus? status,
    @Default(false) bool isReleasable,
    String? activeCarer,

    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Case;

  factory Case.fromRecord(RecordModel r) {
    final d = r.data;
    return Case(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      caseNumber: pbString(d['case_number']),
      ageClass: AgeClass.fromWire(d['age_class']),
      admittedAt: pbDate(d['admitted_at']),
      foundAt: pbDate(d['found_at']),
      admittedBy: pbString(d['admitted_by']),
      transportedBy: pbString(d['transported_by']),
      finder: pbString(d['finder']),
      findLocation: pbString(d['find_location']),
      findGeo: GeoPoint.fromPb(d['find_geo']),
      city: pbString(d['city']),
      region: pbString(d['region']),
      reasonsForAdmission:
          AdmissionReason.listFromWire(d['reasons_for_admission']),
      intakeWeightG: pbInt(d['intake_weight_g']),
      intakeNotes: pbString(d['intake_notes']),
      intakePhotos: pbStringList(d['intake_photos']),
      status: CaseStatus.fromWire(d['status']),
      isReleasable: pbBool(d['is_releasable']),
      activeCarer: pbString(d['active_carer']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
