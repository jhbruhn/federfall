/// Immutable domain models for Federfall and the PocketBase
/// `RecordModel` → model mappers that build them.
library;

export 'src/converters.dart'
    show
        pbBool,
        pbDate,
        pbDouble,
        pbEnum,
        pbEnumList,
        pbInt,
        pbString,
        pbStringList;
export 'src/enums.dart';
export 'src/models/admission_reason.dart';
export 'src/models/animal.dart';
export 'src/models/app_user.dart';
export 'src/models/aviary.dart';
export 'src/models/case_activity.dart';
export 'src/models/case_share.dart';
export 'src/models/case_summary.dart';
export 'src/models/clinical.dart';
export 'src/models/condition.dart';
export 'src/models/disposition.dart';
export 'src/models/exam.dart';
export 'src/models/finder.dart';
export 'src/models/geo_point.dart';
export 'src/models/marking.dart';
export 'src/models/medical_case.dart';
export 'src/models/organisation.dart';
export 'src/models/quarantine.dart';
