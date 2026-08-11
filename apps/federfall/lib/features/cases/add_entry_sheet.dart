import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_sheet.dart';
import 'package:federfall/features/cases/conditions/condition_entry_sheet.dart';
import 'package:federfall/features/cases/disposition/disposition_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_sheet.dart';
import 'package:federfall/features/cases/eggs/egg_entry_sheet.dart';
import 'package:federfall/features/cases/exams/exam_sheet.dart';
import 'package:federfall/features/cases/follow_ups/follow_up_sheet.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/features/cases/microscopy/microscopy_sheet.dart';
import 'package:federfall/features/cases/placements/placement_sheet.dart';
import 'package:federfall/features/cases/quarantine/quarantine_sheet.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_sheet.dart';
import 'package:federfall/features/cases/weights/weight_entry_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kinds of entry a carer can add to a case chronology (xc8). The picker
/// sheet returns one of these; the caller opens the matching create sheet on a
/// live screen context (so popping the picker first never deactivates it).
enum _AddKind {
  note,
  weight,
  egg,
  vaccination,
  exam,
  microscopy,
  condition,
  quarantine,
  prescription,
  dose,
  marking,
  placement,
  vetAppointment,
  followUp,
  outcome,
}

/// Opens the add-entry picker (xc8.1): one grouped, icon-led bottom sheet that
/// replaces the old tiny `+` → flat 11-item popup. The sheet only chooses a
/// kind; this function then opens the corresponding create sheet, so the picker
/// is dismissed before the next sheet mounts.
Future<void> showAddEntrySheet(
  BuildContext context, {
  required Case medicalCase,
}) async {
  final kind = await showAppSheet<_AddKind>(
    context,
    builder: (_) => _AddEntrySheet(medicalCase: medicalCase),
  );
  if (kind == null || !context.mounted) return;

  final caseId = medicalCase.id;
  final animalId = medicalCase.animal;
  switch (kind) {
    case _AddKind.note:
      await showJournalEntrySheet(context, caseId: caseId);
    case _AddKind.weight:
      await showWeightEntrySheet(context, animalId: animalId, caseId: caseId);
    case _AddKind.egg:
      await showEggEntrySheet(context, animalId: animalId);
    case _AddKind.vaccination:
      await showVaccinationSheet(context, animalId: animalId);
    case _AddKind.exam:
      await showExamSheet(context, caseId: caseId, animalId: animalId);
    case _AddKind.microscopy:
      await showMicroscopySheet(context, caseId: caseId);
    case _AddKind.condition:
      await showConditionEntrySheet(context, caseId: caseId);
    case _AddKind.quarantine:
      await showQuarantineSheet(context, caseId: caseId);
    case _AddKind.prescription:
      await showPrescriptionSheet(context, caseId: caseId);
    case _AddKind.dose:
      await showAdministrationSheet(context, caseId: caseId);
    case _AddKind.marking:
      await showMarkingSheet(context, animalId: animalId, caseId: caseId);
    // One kind, not two: a handoff IS a placement whose carer differs, so
    // the sheet's own carer field makes that choice instead of the picker
    // asking for it before the field is visible (federfall-0se6).
    case _AddKind.placement:
      await showPlacementSheet(context, medicalCase: medicalCase);
    case _AddKind.vetAppointment:
      await showVetAppointmentSheet(context, caseId: caseId);
    case _AddKind.followUp:
      await showFollowUpSheet(context, caseId: caseId);
    case _AddKind.outcome:
      await showDispositionSheet(context, caseId: caseId);
  }
}

/// One selectable entry kind in the picker. [enabled] controls whether it can
/// be chosen — a disabled kind stays visible (so the layout and muscle memory
/// don't shift) but is greyed out and inert.
class _Entry {
  const _Entry(this.kind, this.icon, this.label, {this.enabled = true});

  final _AddKind kind;
  final IconData icon;
  final String label;
  final bool enabled;
}

class _AddEntrySheet extends ConsumerWidget {
  const _AddEntrySheet({required this.medicalCase});

  final Case medicalCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    // The outcome action ends the case. Once a disposition exists we disable it
    // rather than hiding it, so the sheet's layout and muscle memory stay put.
    final dispositions = ref
        .watch(dispositionsForCaseProvider(medicalCase.id))
        .value;
    final isDisposed = dispositions != null && dispositions.isNotEmpty;
    // Weight, egg, vaccination and marking are ANIMAL-scoped and follow
    // custody since
    // 1700000079, which `canEditCase` (the gate on the FAB that opens this
    // sheet) does not imply: the carer of a disposed case may still write its
    // journal after the bird has moved on. Disabled rather than hidden, like
    // the outcome action above.
    final holdsBird =
        ref.watch(canWriteAnimalProvider(medicalCase.animal)).value ?? false;

    final groups = <(String, List<_Entry>)>[
      (
        l10n.timelineGroupClinical,
        [
          _Entry(
            _AddKind.note,
            Icons.sticky_note_2_outlined,
            l10n.timelineAddNote,
          ),
          _Entry(
            _AddKind.weight,
            Icons.monitor_weight_outlined,
            l10n.timelineAddWeight,
            enabled: holdsBird,
          ),
          _Entry(
            _AddKind.exam,
            Icons.monitor_heart_outlined,
            l10n.timelineAddExam,
          ),
          _Entry(
            _AddKind.microscopy,
            Icons.biotech_outlined,
            l10n.timelineAddMicroscopy,
          ),
          // Enabled whatever the animal's recorded sex says: pigeon sex is
          // often unknown or wrong at intake, and a bird recorded as male that
          // lays an egg is exactly the case worth logging.
          _Entry(
            _AddKind.egg,
            Icons.egg_outlined,
            l10n.timelineAddEgg,
            enabled: holdsBird,
          ),
          // Animal-scoped like the weight and the egg above, so it needs the
          // same custody gate rather than `canEditCase`.
          _Entry(
            _AddKind.vaccination,
            Icons.vaccines_outlined,
            l10n.timelineAddVaccination,
            enabled: holdsBird,
          ),
          _Entry(
            _AddKind.condition,
            Icons.coronavirus_outlined,
            l10n.timelineAddCondition,
          ),
          _Entry(
            _AddKind.quarantine,
            Icons.shield_outlined,
            l10n.timelineAddQuarantine,
          ),
        ],
      ),
      (
        l10n.timelineGroupMedication,
        [
          _Entry(
            _AddKind.prescription,
            Icons.medication_outlined,
            l10n.timelineAddPrescription,
          ),
          _Entry(_AddKind.dose, Icons.vaccines_outlined, l10n.timelineAddDose),
        ],
      ),
      (
        l10n.timelineGroupMovement,
        [
          _Entry(
            _AddKind.marking,
            Icons.sell_outlined,
            l10n.timelineAddMarking,
            enabled: holdsBird,
          ),
          _Entry(
            _AddKind.placement,
            Icons.move_down_outlined,
            l10n.placementTitle,
          ),
        ],
      ),
      (
        l10n.timelineGroupLifecycle,
        [
          _Entry(
            _AddKind.vetAppointment,
            Icons.medical_services_outlined,
            l10n.timelineAddVetAppointment,
          ),
          _Entry(
            _AddKind.followUp,
            Icons.event_repeat_outlined,
            l10n.timelineAddFollowUp,
          ),
          _Entry(
            _AddKind.outcome,
            Icons.sports_score,
            l10n.timelineRecordOutcome,
            enabled: !isDisposed,
          ),
        ],
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.timelineAddEntryTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            for (final (header, entries) in groups)
              if (entries.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    header.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                for (final entry in entries)
                  ListTile(
                    enabled: entry.enabled,
                    leading: Opacity(
                      opacity: entry.enabled ? 1 : 0.38,
                      child: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                        child: Icon(entry.icon, size: 20),
                      ),
                    ),
                    title: Text(entry.label),
                    onTap: entry.enabled
                        ? () => Navigator.of(context).pop(entry.kind)
                        : null,
                  ),
              ],
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
