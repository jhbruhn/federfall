// GeoPoint now lives in zugvogel_core (eiermann-d2a.3), hand-written rather
// than freezed — that package carries no code generation, because a git
// dependency cannot have build_runner run inside it.
//
// The class is unchanged where it matters: a const constructor, value equality,
// copyWith, and `fromPb` still reading {lon: 0, lat: 0} as null so an unset pin
// does not render as a plausible marker in the Gulf of Guinea.
//
// One deliberate consequence: freezed no longer generates a nested
// `$GeoPointCopyWith` for the models that carry a `GeoPoint?` field, because it
// only does that for types it generated itself. Nothing ever called those
// chains — checked across both apps before the move.
export 'package:zugvogel_core/zugvogel_core.dart' show GeoPoint;
