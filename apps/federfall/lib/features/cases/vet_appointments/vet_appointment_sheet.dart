import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/reminders/reminder_lead.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the vet-appointment add/edit form. Pass [appointment] to edit;
/// [focusOutcome] scrolls the outcome field into focus, for the
/// "add the result" action on the timeline tile.
Future<bool?> showVetAppointmentSheet(
  BuildContext context, {
  required String caseId,
  VetAppointment? appointment,
  bool focusOutcome = false,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => VetAppointmentSheet(
      caseId: caseId,
      appointment: appointment,
      focusOutcome: focusOutcome,
    ),
  );
}

/// Form for a vet appointment on a case (federfall-fnpo): when, which practice,
/// why — plus, once the visit is behind us, what came of it.
///
/// The record is written twice in its life, so the form has two faces: before
/// the visit it asks for the appointment and its reminder, after the visit it
/// also offers the outcome. The outcome field is hidden until it can honestly
/// be filled in, because an empty "Ergebnis" box on a future appointment
/// invites writing down a result nobody has yet.
class VetAppointmentSheet extends ConsumerStatefulWidget {
  const VetAppointmentSheet({
    required this.caseId,
    this.appointment,
    this.focusOutcome = false,
    super.key,
  });

  final String caseId;
  final VetAppointment? appointment;
  final bool focusOutcome;

  @override
  ConsumerState<VetAppointmentSheet> createState() =>
      _VetAppointmentSheetState();
}

class _VetAppointmentSheetState extends ConsumerState<VetAppointmentSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _vet;
  late final TextEditingController _reason;
  late final TextEditingController _outcome;
  late DateTime _startsAt;

  /// The per-appointment reminder override: null = follow the device default.
  Duration? _lead;
  late bool _muted;

  bool get _isEditing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    _vet = TextEditingController(text: a?.vet ?? '');
    _reason = TextEditingController(text: a?.reason ?? '');
    _outcome = TextEditingController(text: a?.outcome ?? '');
    // A new appointment defaults to the next full hour tomorrow — nobody books
    // a vet for "right now", and a sensible default is one fewer tap than a
    // picker starting at the current minute.
    _startsAt =
        a?.startsAt?.toLocal() ??
        DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day + 1,
          9,
        );
    final leadMinutes = a?.reminderLeadMinutes;
    _lead = leadMinutes == null ? null : Duration(minutes: leadMinutes);
    _muted = a?.reminderMuted ?? false;
  }

  @override
  void dispose() {
    _vet.dispose();
    _reason.dispose();
    _outcome.dispose();
    super.dispose();
  }

  /// Whether the visit is far enough along that an outcome makes sense: it has
  /// happened, or someone already marked it attended.
  bool get _showOutcome =>
      _isEditing &&
      (widget.appointment!.attendedAt != null ||
          _startsAt.isBefore(DateTime.now()));

  Future<void> _pickStartsAt() async {
    final picked = await pickDateTime(
      context,
      initial: _startsAt,
      // pickDateTime defaults lastDate to today — an appointment is in the
      // future, so it has to be widened explicitly or the picker refuses every
      // date that matters.
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) {
      setState(() => _startsAt = picked);
      markDirty();
    }
  }

  Future<void> _pickLead() async {
    final l10n = context.l10n;
    final picked = await showAppSheet<_LeadChoice>(
      context,
      builder: (_) => _LeadPickerSheet(
        selected: _muted
            ? const _LeadChoice.muted()
            : (_lead == null
                  ? const _LeadChoice.deviceDefault()
                  : _LeadChoice.lead(_lead!)),
        l10n: l10n,
      ),
    );
    if (picked == null) return;
    setState(() {
      _muted = picked.muted;
      // A muted appointment keeps whatever lead was chosen before, so
      // un-muting restores it rather than silently reverting to the default.
      if (!picked.muted) _lead = picked.lead;
    });
    markDirty();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
      final body = <String, dynamic>{
        'starts_at': _startsAt.toUtc().toIso8601String(),
        'vet': _vet.text.trim(),
        'reason': _reason.text.trim(),
        if (_showOutcome) 'outcome': _outcome.text.trim(),
        // PocketBase has no null for a number field, so "follow the device
        // default" is written as the empty value, which reads back as 0 and the
        // mapper turns into null again.
        'reminder_lead_minutes': _lead?.inMinutes ?? '',
        'reminder_muted': _muted,
      };

      final existing = widget.appointment;
      if (existing == null) {
        await repo.create({
          ...body,
          'case': widget.caseId,
          'created_by': user.id,
          'org': org,
        });
      } else {
        await repo.update(existing.id, body);
      }

      ref
        ..invalidate(caseBundleProvider(widget.caseId))
        ..invalidate(worklistSourceProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing
            ? l10n.vetAppointmentEditTitle
            : l10n.vetAppointmentNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.vetAppointmentStartsAtLabel,
            value: _startsAt,
            enabled: !isBusy,
            showTime: true,
            onPick: _pickStartsAt,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _vet,
            label: l10n.vetAppointmentVetLabel,
            enabled: !isBusy,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _reason,
            label: l10n.vetAppointmentReasonLabel,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_showOutcome) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _outcome,
              label: l10n.vetAppointmentOutcomeLabel,
              enabled: !isBusy,
              autofocus: widget.focusOutcome,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          const Divider(height: AppSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.vetAppointmentReminderLabel),
            subtitle: Text(l10n.vetAppointmentReminderScopeHint),
            trailing: Text(
              _muted
                  ? l10n.vetAppointmentReminderNone
                  : (_lead == null
                        ? l10n.vetAppointmentReminderDefault
                        : reminderLeadLabel(l10n, _lead!)),
            ),
            onTap: isBusy ? null : _pickLead,
          ),
        ],
      ),
    );
  }
}

/// The reminder choice for one appointment: the device default, an explicit
/// lead, or no reminder at all.
@immutable
class _LeadChoice {
  const _LeadChoice.deviceDefault() : lead = null, muted = false;
  const _LeadChoice.lead(Duration this.lead) : muted = false;
  const _LeadChoice.muted() : lead = null, muted = true;

  final Duration? lead;
  final bool muted;

  @override
  bool operator ==(Object other) =>
      other is _LeadChoice && other.lead == lead && other.muted == muted;

  @override
  int get hashCode => Object.hash(lead, muted);
}

class _LeadPickerSheet extends StatelessWidget {
  const _LeadPickerSheet({required this.selected, required this.l10n});

  final _LeadChoice selected;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = <(_LeadChoice, String)>[
      (const _LeadChoice.deviceDefault(), l10n.vetAppointmentReminderDefault),
      for (final lead in kReminderLeadChoices)
        (_LeadChoice.lead(lead), reminderLeadLabel(l10n, lead)),
      (const _LeadChoice.muted(), l10n.vetAppointmentReminderNone),
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
                l10n.vetAppointmentReminderLabel,
                style: theme.textTheme.titleLarge,
              ),
            ),
            RadioGroup<_LeadChoice>(
              groupValue: selected,
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                children: [
                  for (final (choice, label) in choices)
                    RadioListTile<_LeadChoice>(
                      value: choice,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
