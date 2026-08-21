/// Immutable domain models for Federfall and the PocketBase
/// `RecordModel` → model mappers that build them.
library;

// GeoPoint is RE-EXPORTED, not imported: it is part of this package's
// public surface and reached consumers through a one-line file under src/
// that only named it — migration scaffolding from when the implementation
// moved to zugvogel_core. Nothing downstream changes.
export 'package:zugvogel_core/zugvogel_core.dart' show GeoPoint;

export 'src/audit_actions.dart';
export 'src/converters.dart'
    show
        pbBool,
        pbCount,
        pbDate,
        pbDouble,
        pbEnum,
        pbEnumList,
        pbInt,
        pbQuantity,
        pbString,
        pbStringList;
export 'src/dosing.dart';
export 'src/enums.dart';
export 'src/models/admission_reason.dart';
export 'src/models/animal.dart';
export 'src/models/app_user.dart';
export 'src/models/audit_event.dart';
export 'src/models/aviary.dart';
export 'src/models/carer_case_load.dart';
export 'src/models/case_activity.dart';
export 'src/models/case_bundle.dart';
export 'src/models/case_share.dart';
export 'src/models/case_summary.dart';
export 'src/models/clinical.dart';
export 'src/models/condition.dart';
export 'src/models/condition_label.dart';
export 'src/models/disposition.dart';
export 'src/models/egg_record.dart';
export 'src/models/exam.dart';
export 'src/models/finder.dart';
export 'src/models/marking.dart';
export 'src/models/marking_type.dart';
export 'src/models/medical_case.dart';
export 'src/models/medication_product.dart';
export 'src/models/medication_route.dart';
export 'src/models/microscopy.dart';
export 'src/models/organisation.dart';
export 'src/models/quarantine.dart';
export 'src/models/sponsorship.dart';
export 'src/models/vaccination.dart';
export 'src/models/vaccine_label.dart';
export 'src/models/vet_appointment.dart';
