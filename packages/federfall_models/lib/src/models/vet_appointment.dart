import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'vet_appointment.freezed.dart';

/// A booked visit at a vet on a case (federfall-fnpo): when, which practice,
/// why — and, written after the visit, what came of it.
///
/// Distinct from `FollowUp` on purpose. A follow-up is a date-only self-recheck
/// with one note; an appointment has a time of day, an external party, and an
/// [outcome] that is not the same text as the [reason] it was booked. The
/// worklist has to tell those apart.
///
/// [attendedAt] and [cancelledAt] both end the appointment's claim on the
/// worklist, but only one of them means the bird was seen — a cancellation is
/// not "not yet attended".
@freezed
abstract class VetAppointment with _$VetAppointment {
  const factory VetAppointment({
    required String id,
    required String caseId,

    /// The appointment instant. Server-required, but kept nullable for the same
    /// defensive reason `FollowUp.dueAt` is: one garbage date must not make a
    /// whole list() call throw.
    DateTime? startsAt,
    String? vet,
    String? reason,
    String? outcome,
    DateTime? attendedAt,
    DateTime? cancelledAt,

    /// Per-appointment override of the device-wide reminder lead. `null` means
    /// "follow the device default"; it travels with the record, so a handoff
    /// keeps it.
    int? reminderLeadMinutes,

    /// No reminder for this appointment, whatever the device default says.
    /// Separate from [reminderLeadMinutes] so un-muting restores the previously
    /// chosen lead instead of silently falling back to the default.
    @Default(false) bool reminderMuted,
    String? createdBy,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _VetAppointment;

  factory VetAppointment.fromRecord(RecordModel r) {
    final d = r.data;
    final lead = pbInt(d['reminder_lead_minutes']);
    return VetAppointment(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      startsAt: pbDate(d['starts_at']),
      vet: pbString(d['vet']),
      reason: pbString(d['reason']),
      outcome: pbString(d['outcome']),
      attendedAt: pbDate(d['attended_at']),
      cancelledAt: pbDate(d['cancelled_at']),
      // PocketBase has no null for a number field — clearing one stores 0, and
      // an absent field reads as 0 too — so zero is the only available "not
      // set", and the server cannot help: it skips `min` validation for a zero
      // on an optional field. Hence muting lives in its own bool rather than
      // in a sentinel here. (0 minutes of notice would not be a reminder
      // anyway.)
      reminderLeadMinutes: (lead == null || lead <= 0) ? null : lead,
      reminderMuted: pbBool(d['reminder_muted']),
      createdBy: pbString(d['created_by']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
