import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'sponsorship.freezed.dart';

/// A Patenschaft: who sponsors an aviary resident, and what they give
/// (federfall-5s5j).
///
/// The sponsor's details live INLINE on the row rather than in a shared person
/// table (1700000085 says why): a shared table would let one keeper read a
/// sponsor's address the moment another keeper's bird acquired that same
/// sponsor. Somebody sponsoring two birds is therefore two rows, on purpose.
///
/// Who may read it is not on this record at all. The server resolves it live
/// through `animal.current_aviary.keeper`, so MOVING THE BIRD MOVES ITS
/// SPONSORSHIP — and once the bird leaves aviary care altogether, only a
/// coordinator or supervisor can reach the row. There is deliberately no frozen
/// aviary snapshot to keep in step.
@freezed
abstract class Sponsorship with _$Sponsorship {
  const factory Sponsorship({
    required String id,
    required String animal,
    required String sponsorName,

    /// Free text, e.g. „sie/ihr" — a fixed list would be presumptuous.
    String? sponsorPronouns,
    String? address,
    String? postalCode,
    String? city,
    String? region,
    String? mobile,

    /// INTEGER CENTS, never a double: money in a binary float accumulates error
    /// the moment anything sums it, and these totals get reconciled against a
    /// bank statement. Parsed and rendered at the UI edge only.
    int? amountCents,
    SponsorshipInterval? interval,
    DateTime? startedAt,

    /// Unset means the patronage is still running — see [isActive].
    DateTime? endedAt,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Sponsorship;

  factory Sponsorship.fromRecord(RecordModel r) {
    final d = r.data;
    return Sponsorship(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      sponsorName: pbString(d['sponsor_name']) ?? '',
      sponsorPronouns: pbString(d['sponsor_pronouns']),
      address: pbString(d['address']),
      postalCode: pbString(d['postal_code']),
      city: pbString(d['city']),
      region: pbString(d['region']),
      mobile: pbString(d['mobile']),
      amountCents: pbInt(d['amount_cents']),
      interval: SponsorshipInterval.fromWire(d['interval']),
      startedAt: pbDate(d['started_at']),
      endedAt: pbDate(d['ended_at']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// Whether the patronage is still running.
extension SponsorshipState on Sponsorship {
  /// An unset [endedAt] means active. A FUTURE end date still counts as active:
  /// „läuft bis Dezember" is a running patronage, not an ended one.
  bool get isActive =>
      endedAt == null || endedAt!.isAfter(DateTime.now().toUtc());
}
