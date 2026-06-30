import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the org-wide `animal_species` view: the distinct species
/// (animal kinds) the org has recorded, for autocompleting the intake species
/// field. Each record maps to its plain species string.
class PbAnimalSpeciesRepository extends PbRepository<String> {
  PbAnimalSpeciesRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'animal_species',
        fromRecord: _species,
      );

  static String _species(RecordModel r) => pbString(r.data['species']) ?? '';

  /// Every distinct species recorded in the org, alphabetically.
  Future<List<String>> all() => list(sort: 'species');
}
