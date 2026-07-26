import 'package:federfall_models/federfall_models.dart';
import 'package:test/test.dart';

void main() {
  // A pigeon-sized bird and a typical enrofloxacin-style rate: the numbers the
  // rest of this file leans on.
  const weightG = 262.0;
  final weighedAt = DateTime.utc(2026, 7, 26, 8);
  final now = DateTime.utc(2026, 7, 26, 18);

  group('calculateDose', () {
    test('multiplies a per-kilogram rate by the weight in kilograms', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        weighedAt: weighedAt,
        now: now,
      );

      // 20 mg/kg × 0.262 kg — the g→kg shift is the whole point of this test.
      expect(r.amount, 5.24);
      expect(r.volumeMl, isNull);
      expect(r.warnings, isEmpty);
      expect(r.hasAmount, isTrue);
    });

    test('reports no amount and a warning without a weight', () {
      final r = calculateDose(
        rate: 20,
        now: now,
      );

      expect(r.amount, isNull);
      expect(r.hasAmount, isFalse);
      expect(r.warnings, [DoseWarning.missingWeight]);
    });

    test('treats a zero or negative weight as no weight at all', () {
      for (final w in [0.0, -1.0]) {
        final r = calculateDose(
          rate: 20,
          weightG: w,
          now: now,
        );
        expect(r.amount, isNull, reason: 'weight $w');
        expect(r.warnings, [DoseWarning.missingWeight]);
      }
    });

    test('returns nothing at all for a missing or nonsensical rate', () {
      for (final rate in [0.0, -5.0, double.nan]) {
        final r = calculateDose(
          rate: rate,
          weightG: weightG,
          now: now,
        );
        expect(r, const DoseCalculation(), reason: 'rate $rate');
      }
    });

    test('still calculates on a stale weight, but warns', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        weighedAt: now.subtract(doseWeightMaxAge + const Duration(hours: 1)),
        now: now,
      );

      expect(r.amount, 5.24);
      expect(r.warnings, [DoseWarning.staleWeight]);
    });

    test('does not warn on a weight exactly at the age limit', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        weighedAt: now.subtract(doseWeightMaxAge),
        now: now,
      );

      expect(r.warnings, isEmpty);
    });

    test('cannot judge staleness without a measurement date', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        now: now,
      );

      expect(r.amount, 5.24);
      expect(r.warnings, isEmpty);
    });

    test('divides by the concentration to get the volume to draw', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        concentrationPerMl: 15,
        now: now,
      );

      // 5.24 mg ÷ 15 mg/ml.
      expect(r.volumeMl, 0.3493);
      expect(r.warnings, isEmpty);
      expect(r.dilutionFactor, isNull);
    });

    test('ignores a zero or negative concentration', () {
      for (final c in [0.0, -1.0]) {
        final r = calculateDose(
          rate: 20,
          weightG: weightG,
          concentrationPerMl: c,
          now: now,
        );
        expect(r.amount, 5.24, reason: 'concentration $c');
        expect(r.volumeMl, isNull);
      }
    });

    test('suggests the smallest dilution making a tiny volume drawable', () {
      // 0.262 mg from a 100 mg/ml stock = 0.00262 ml: pure fiction on a
      // syringe. 1:10 is still under the limit, 1:100 clears it.
      final r = calculateDose(
        rate: 1,
        weightG: weightG,
        concentrationPerMl: 100,
        now: now,
      );

      expect(r.volumeMl, 0.00262);
      expect(r.warnings, [DoseWarning.unmeasurableVolume]);
      expect(r.dilutionFactor, 100);
    });

    test('caps the dilution suggestion at the largest offered factor', () {
      final r = calculateDose(
        rate: 0.001,
        weightG: weightG,
        concentrationPerMl: 1000,
        now: now,
      );

      expect(r.warnings, [DoseWarning.unmeasurableVolume]);
      expect(r.dilutionFactor, doseDilutionFactors.last);
    });

    test('does not warn on a volume exactly at the measurable limit', () {
      final r = calculateDose(
        rate: 20,
        weightG: weightG,
        // 5.24 mg at 104.8 mg/ml is 0.05 ml on the nose.
        concentrationPerMl: 104.8,
        now: now,
      );

      expect(r.volumeMl, minMeasurableVolumeMl);
      expect(r.warnings, isEmpty);
    });

    test('collects a stale weight and an unmeasurable volume together', () {
      final r = calculateDose(
        rate: 1,
        weightG: weightG,
        weighedAt: now.subtract(const Duration(days: 30)),
        concentrationPerMl: 100,
        now: now,
      );

      expect(r.warnings, [
        DoseWarning.staleWeight,
        DoseWarning.unmeasurableVolume,
      ]);
    });

    test('drops the false precision of a repeating quotient', () {
      final r = calculateDose(
        rate: 10,
        weightG: 333,
        concentrationPerMl: 3,
        now: now,
      );

      expect(r.amount, 3.33);
      expect(r.volumeMl, 1.11);
    });
  });

  group('roundToSignificantDigits', () {
    test('keeps four significant digits across magnitudes', () {
      expect(roundToSignificantDigits(5.239999999999999), 5.24);
      expect(roundToSignificantDigits(0.000123456), 0.0001235);
      expect(roundToSignificantDigits(1234567), 1235000);
      expect(roundToSignificantDigits(9.9999), 10);
    });

    test('passes through zero and non-finite values', () {
      expect(roundToSignificantDigits(0), 0);
      expect(roundToSignificantDigits(double.infinity), double.infinity);
      expect(roundToSignificantDigits(double.nan).isNaN, isTrue);
    });

    test('handles negatives symmetrically', () {
      expect(roundToSignificantDigits(-5.239999999999999), -5.24);
    });
  });
}
