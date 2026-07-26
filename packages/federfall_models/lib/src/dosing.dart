import 'dart:math' as math;

import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dosing.freezed.dart';

/// Weight-based dose arithmetic (federfall-6d3a.1).
///
/// This is the ONE place where grams become kilograms. Weights are stored in
/// grams (`weights.weight_g`) and rates are prescribed per kilogram, and that
/// decimal shift is the classic way a dose calculation kills a patient — so it
/// lives in a single pure, exhaustively tested function rather than in a
/// widget.
///
/// The unit of the amount (mg, ml, IU, …) is the caller's free-text choice and
/// is deliberately NOT modelled: [calculateDose] only ever multiplies and
/// divides, so the amount comes out in whatever unit the rate went in. The one
/// unit relation it does rely on is that a concentration is expressed as
/// *amount unit per millilitre* — you cannot turn mg/kg into ml unless the
/// concentration is in mg/ml. Keeping that implicit removes the whole class of
/// mg-vs-µg mismatch instead of trying to detect it.

/// How old the newest weight may be before a per-kilogram dose derived from it
/// is flagged [DoseWarning.staleWeight].
///
/// Three days: a bird in rehab is weighed most days, and a squab or a
/// re-feeding adult moves fast enough that a older figure is a different bird
/// for dosing purposes.
const Duration doseWeightMaxAge = Duration(days: 3);

/// The smallest volume worth calling a measurement. Below this a syringe
/// graduation is guesswork and the drug has to be diluted first.
const double minMeasurableVolumeMl = 0.05;

/// Dilution factors offered for an unmeasurably small volume, smallest first.
const List<int> doseDilutionFactors = [10, 100, 1000];

/// Significant digits kept in a calculated amount or volume. The raw quotient
/// carries a dozen digits of false precision; a dose is given with a syringe,
/// not a spectrometer.
const int doseSignificantDigits = 4;

/// Something the carer must see before acting on a calculated dose.
enum DoseWarning {
  /// No body weight on record, so a per-kilogram rate cannot be resolved at
  /// all — weigh the bird.
  missingWeight,

  /// The newest weight is older than [doseWeightMaxAge]. The dose is still
  /// calculated (the carer may know it is still valid), but a stale weight
  /// used *silently* is worse than no calculator.
  staleWeight,

  /// The volume to draw is below [minMeasurableVolumeMl]; see
  /// [DoseCalculation.dilutionFactor].
  unmeasurableVolume,
}

/// The result of [calculateDose]: the amount to give, the volume to draw when
/// a concentration is known, and everything the carer must be warned about.
///
/// [amount] is null when the inputs cannot produce one (no rate, or a
/// per-kilogram rate without a weight) — [warnings] then carries the reason.
@freezed
abstract class DoseCalculation with _$DoseCalculation {
  const factory DoseCalculation({
    double? amount,
    double? volumeMl,

    /// The dilution that would bring an unmeasurable [volumeMl] up to a
    /// drawable one: `1:factor`, so the drawn volume becomes
    /// `volumeMl * factor`. Only set alongside
    /// [DoseWarning.unmeasurableVolume].
    int? dilutionFactor,
    @Default(<DoseWarning>[]) List<DoseWarning> warnings,
  }) = _DoseCalculation;

  const DoseCalculation._();

  /// Whether there is a number to show (and to offer as the dose).
  bool get hasAmount => amount != null;
}

/// Derives the dose for one administration.
///
/// [rate] is per kilogram of body weight or per animal, per [basis]. [weightG]
/// is the bird's weight in grams and [weighedAt] when it was measured — both
/// only matter for [DoseBasis.perKilogram]. [concentrationPerMl] is the
/// product's strength in *rate units per millilitre* (1.5 for a 1.5 mg/ml
/// solution when the rate is in mg/kg); omit it for a drug that is not drawn
/// up and no volume is reported.
///
/// [now] defaults to the current time and exists so the staleness rule is
/// testable.
DoseCalculation calculateDose({
  required double rate,
  required DoseBasis basis,
  double? weightG,
  DateTime? weighedAt,
  double? concentrationPerMl,
  DateTime? now,
}) {
  if (!rate.isFinite || rate <= 0) return const DoseCalculation();

  final warnings = <DoseWarning>[];
  double? amount;

  switch (basis) {
    case DoseBasis.perAnimal:
      amount = rate;
    case DoseBasis.perKilogram:
      if (weightG == null || !weightG.isFinite || weightG <= 0) {
        warnings.add(DoseWarning.missingWeight);
      } else {
        amount = rate * weightG / 1000;
        final at = weighedAt;
        if (at != null &&
            (now ?? DateTime.now()).difference(at) > doseWeightMaxAge) {
          warnings.add(DoseWarning.staleWeight);
        }
      }
  }

  if (amount == null) return DoseCalculation(warnings: warnings);

  double? volumeMl;
  int? dilutionFactor;
  final concentration = concentrationPerMl;
  if (concentration != null && concentration.isFinite && concentration > 0) {
    volumeMl = amount / concentration;
    if (volumeMl < minMeasurableVolumeMl) {
      warnings.add(DoseWarning.unmeasurableVolume);
      dilutionFactor = doseDilutionFactors.firstWhere(
        (f) => volumeMl! * f >= minMeasurableVolumeMl,
        orElse: () => doseDilutionFactors.last,
      );
    }
  }

  return DoseCalculation(
    amount: roundToSignificantDigits(amount),
    volumeMl: volumeMl == null ? null : roundToSignificantDigits(volumeMl),
    dilutionFactor: dilutionFactor,
    warnings: warnings,
  );
}

/// Rounds [value] to [digits] significant digits, so a calculated dose reads
/// `5.24` rather than `5.239999999999999`. Significant digits (not decimal
/// places) because doses span microlitres to millilitres and a fixed number of
/// decimals would either round a small one to zero or pad a large one with
/// noise.
double roundToSignificantDigits(
  double value, {
  int digits = doseSignificantDigits,
}) {
  if (value == 0 || !value.isFinite) return value;
  final magnitude = (math.log(value.abs()) / math.ln10).floor();
  final factor = math.pow(10, digits - 1 - magnitude).toDouble();
  if (!factor.isFinite || factor == 0) return value;
  return (value * factor).round() / factor;
}
