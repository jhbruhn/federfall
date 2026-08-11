import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the Patenschaft form as a modal bottom sheet. Pass [sponsorship] to
/// edit an existing one; omit it to record a new one. Resolves to `true` on
/// save.
Future<bool?> showSponsorshipSheet(
  BuildContext context, {
  required String animalId,
  Sponsorship? sponsorship,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) =>
        SponsorshipSheet(animalId: animalId, sponsorship: sponsorship),
  );
}

/// Form for one Patenschaft (federfall-5s5j): who sponsors this bird, how to
/// reach them, what they give and for how long.
///
/// `animal` is sent on CREATE only. The server freezes it (1700000085's update
/// rule), and for a reason this form has to respect rather than work around:
/// re-pointing a patronage would push a sponsor's address into another
/// keeper's view with no warning anywhere. Moving the BIRD is the one route,
/// and the disposition sheet says so before it happens.
class SponsorshipSheet extends ConsumerStatefulWidget {
  const SponsorshipSheet({
    required this.animalId,
    this.sponsorship,
    super.key,
  });

  final String animalId;
  final Sponsorship? sponsorship;

  @override
  ConsumerState<SponsorshipSheet> createState() => _SponsorshipSheetState();
}

class _SponsorshipSheetState extends ConsumerState<SponsorshipSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _name;
  late final TextEditingController _pronouns;
  late final TextEditingController _address;
  late final TextEditingController _postalCode;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _mobile;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  SponsorshipInterval? _interval;
  DateTime? _startedAt;
  DateTime? _endedAt;

  bool get _isEditing => widget.sponsorship != null;

  @override
  void initState() {
    super.initState();
    final s = widget.sponsorship;
    _name = TextEditingController(text: s?.sponsorName ?? '');
    _pronouns = TextEditingController(text: s?.sponsorPronouns ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _postalCode = TextEditingController(text: s?.postalCode ?? '');
    _city = TextEditingController(text: s?.city ?? '');
    _region = TextEditingController(text: s?.region ?? '');
    _mobile = TextEditingController(text: s?.mobile ?? '');
    // Filled in didChangeDependencies: the amount needs the locale's decimal
    // separator, and Localizations is not resolvable from initState.
    _amount = TextEditingController();
    _notes = TextEditingController(text: s?.notes ?? '');
    _interval = s?.interval ?? SponsorshipInterval.monthly;
    // New patronages start today; that is what somebody entering one in the
    // moment means, and it can be moved.
    _startedAt = _isEditing ? s?.startedAt?.toLocal() : DateTime.now();
    _endedAt = s?.endedAt?.toLocal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once, and only for an existing record. Re-running it on a later
    // dependency change would overwrite whatever is being typed.
    if (_amountPrefilled) return;
    _amountPrefilled = true;
    final cents = widget.sponsorship?.amountCents;
    if (cents == null) return;
    // A plain locale-formatted number rather than formatAmountCents: the
    // currency symbol belongs beside the field (a suffix), never inside a value
    // somebody is about to edit.
    _amount.text = formatNumber(context.l10n, cents / 100);
  }

  bool _amountPrefilled = false;

  @override
  void dispose() {
    _name.dispose();
    _pronouns.dispose();
    _address.dispose();
    _postalCode.dispose();
    _city.dispose();
    _region.dispose();
    _mobile.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await pickDate(
      context,
      initial: _startedAt ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startedAt = picked);
      markDirty();
    }
  }

  Future<void> _pickEnd() async {
    final picked = await pickDate(context, initial: _endedAt ?? DateTime.now());
    if (picked != null) {
      setState(() => _endedAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final repo = await ref.read(sponsorshipsRepositoryProvider.future);
      final amountText = _amount.text.trim();
      // Validated already; null here means the field was left empty.
      final cents = amountText.isEmpty ? null : parseAmountToCents(amountText);
      final s = widget.sponsorship;

      // Empty strings rather than omitted keys on UPDATE: a cleared field has
      // to be cleared server-side, and a null-aware key would leave the old
      // value standing.
      final values = <String, dynamic>{
        'sponsor_name': _name.text.trim(),
        'sponsor_pronouns': _pronouns.text.trim(),
        'address': _address.text.trim(),
        'postal_code': _postalCode.text.trim(),
        'city': _city.text.trim(),
        'region': _region.text.trim(),
        'mobile': _mobile.text.trim(),
        'amount_cents': cents,
        'interval': _interval?.wire ?? '',
        'started_at': _startedAt?.toUtc().toIso8601String() ?? '',
        'ended_at': _endedAt?.toUtc().toIso8601String() ?? '',
        'notes': _notes.text.trim(),
      };

      if (s == null) {
        // `animal` and `org` on create only — both are frozen afterwards.
        await repo.create({
          ...values,
          'animal': widget.animalId,
          'org': org,
        });
      } else {
        await repo.update(s.id, values);
      }

      ref
        ..invalidate(sponsorshipsForAnimalProvider(widget.animalId))
        ..invalidate(sponsorshipCountForAnimalProvider(widget.animalId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing
            ? l10n.sponsorshipEditTitle
            : l10n.sponsorshipNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _name,
            label: l10n.sponsorshipFieldName,
            enabled: !isBusy,
            validator: Validators.required(l10n),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _pronouns,
            label: l10n.sponsorshipFieldPronouns,
            hintText: l10n.sponsorshipFieldPronounsHint,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _mobile,
            label: l10n.sponsorshipFieldMobile,
            keyboardType: TextInputType.phone,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _address,
            label: l10n.sponsorshipFieldAddress,
            enabled: !isBusy,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: AppTextField(
                  controller: _postalCode,
                  label: l10n.sponsorshipFieldPostalCode,
                  keyboardType: TextInputType.number,
                  enabled: !isBusy,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  controller: _city,
                  label: l10n.sponsorshipFieldCity,
                  enabled: !isBusy,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _region,
            label: l10n.sponsorshipFieldRegion,
            enabled: !isBusy,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _amount,
            label: l10n.sponsorshipFieldAmount,
            suffixText: '€',
            // A decimal keyboard, and a comma allowed through: German input is
            // `12,50` and the parser swaps it for a dot.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            ],
            enabled: !isBusy,
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null; // optional
              return parseAmountToCents(v) == null
                  ? l10n.sponsorshipAmountInvalid
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<SponsorshipInterval>(
            initialValue: _interval,
            decoration: InputDecoration(
              labelText: l10n.sponsorshipFieldInterval,
              prefixIcon: const Icon(Icons.repeat_outlined),
            ),
            items: [
              for (final i in SponsorshipInterval.values)
                DropdownMenuItem(
                  value: i,
                  child: Text(sponsorshipIntervalLabel(l10n, i)),
                ),
            ],
            onChanged: isBusy
                ? null
                : (i) {
                    setState(() => _interval = i ?? _interval);
                    markDirty();
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.sponsorshipFieldStarted,
            value: _startedAt,
            placeholder: l10n.sponsorshipDateUnset,
            enabled: !isBusy,
            onPick: _pickStart,
            onClear: () {
              setState(() => _startedAt = null);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.sponsorshipFieldEnded,
            value: _endedAt,
            // An empty end date is the normal state of a running patronage, so
            // the placeholder says that rather than „nicht gesetzt".
            placeholder: l10n.sponsorshipStillRunning,
            enabled: !isBusy,
            onPick: _pickEnd,
            onClear: () {
              setState(() => _endedAt = null);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notes,
            label: l10n.sponsorshipFieldNotes,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
