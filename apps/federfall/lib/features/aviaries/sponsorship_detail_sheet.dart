import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/aviaries/sponsorship_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_sheet.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the full record of one Patenschaft.
///
/// The card on the animal detail is a summary — a name and one line of amount
/// and period. Everything else the row holds (the postal address, the mobile,
/// the pronouns somebody took the trouble to note, the notes) was reachable
/// only through the EDIT sheet, which means it was not reachable at all for a
/// coordinator looking at a bird that has left aviary care: they may read the
/// patronage but not write it, so no edit control is offered them. Reading is
/// its own act and gets its own surface.
///
/// [animalId] is null for an ORPHAN — a row whose bird was deleted
/// (`sponsorships.animal` deliberately does not cascade, 1700000085). Such a
/// row still has to be readable, because keeping it is the decision — a
/// Zuwendungsbestätigung is worthless without the donor's name and address
/// (federfall-5s5j.4). There is simply no bird left to resolve access or a live
/// read against, so the sheet shows what it was handed and offers no edit.
///
/// [showAnimalLink] adds a way through to the bird, for callers that are not
/// already standing on it — the patronage overview (federfall-ys7z).
Future<void> showSponsorshipDetailSheet(
  BuildContext context, {
  required String? animalId,
  required Sponsorship sponsorship,
  bool showAnimalLink = false,
}) => showAppSheet<void>(
  context,
  builder: (_) => _SponsorshipDetailSheet(
    animalId: animalId,
    initial: sponsorship,
    showAnimalLink: showAnimalLink,
  ),
);

class _SponsorshipDetailSheet extends ConsumerWidget {
  const _SponsorshipDetailSheet({
    required this.animalId,
    required this.initial,
    required this.showAnimalLink,
  });

  /// The sponsored bird, or null when there is none left to point at.
  final String? animalId;

  /// Whether to offer a way through to the bird's record.
  final bool showAnimalLink;

  /// The row as the card had it. Only a fallback: the sheet reads the live
  /// list below, so an edit made from inside it is reflected here rather than
  /// leaving a stale copy on screen behind the form that changed it.
  final Sponsorship initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    // Live, by id. A failed or pending read falls back to what the card already
    // showed — this is a detail view of a row the caller was holding, so having
    // it briefly disappear behind a spinner would be worse than a moment of the
    // known value. An orphan has no animal to read through, so it stays with
    // the row it was handed and offers no edit control — nothing may be written
    // to a patronage whose bird is gone anyway, since every write predicate
    // resolves through `animal.current_aviary.keeper`.
    final id = animalId;
    final hasAnimal = id != null && id.isNotEmpty;
    final rows = hasAnimal
        ? ref.watch(sponsorshipsForAnimalProvider(id)).value
        : null;
    final s = rows?.where((r) => r.id == initial.id).firstOrNull ?? initial;
    final canWrite =
        hasAnimal &&
        (ref.watch(sponsorshipAccessProvider(id)).value?.canWrite ?? false);

    String? date(DateTime? at) => at == null
        ? null
        : formatLocalDate(materialL10n, at, style: DateStyle.short);

    final address = [
      ?_trimmed(s.address),
      [?_trimmed(s.postalCode), ?_trimmed(s.city)].join(' ').trim(),
      ?_trimmed(s.region),
    ].where((line) => line.isNotEmpty).join('\n');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: AppSpacing.md,
              children: [
                Icon(
                  Icons.volunteer_activism_outlined,
                  color: s.isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.sponsorName,
                        style: theme.textTheme.titleMedium,
                      ),
                      // Pronouns belong beside the name, not in a labelled
                      // row further down: they are how to address this person,
                      // which is part of reading their name.
                      if (_trimmed(s.sponsorPronouns) case final p?)
                        Text(
                          p,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    s.isActive
                        ? l10n.sponsorshipStatusActive
                        : l10n.sponsorshipStatusEnded,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // The arrangement first — it is what most readers came for.
            if (s.amountCents case final cents?)
              _Row(
                label: l10n.sponsorshipFieldAmount,
                value: [
                  formatAmountCents(l10n, cents),
                  if (s.interval case final i?)
                    sponsorshipIntervalLabel(l10n, i),
                ].join(' '),
              )
            else if (s.interval case final i?)
              _Row(
                label: l10n.sponsorshipFieldInterval,
                value: sponsorshipIntervalLabel(l10n, i),
              ),
            if (date(s.startedAt) case final from?)
              _Row(label: l10n.sponsorshipFieldStarted, value: from),
            // Stated even when unset, because "läuft noch" is a fact about the
            // patronage and not a missing value.
            _Row(
              label: l10n.sponsorshipFieldEnded,
              value: date(s.endedAt) ?? l10n.sponsorshipStillRunning,
            ),

            if (_trimmed(s.mobile) case final mobile?) ...[
              const SizedBox(height: AppSpacing.sm),
              _Row(label: l10n.sponsorshipFieldMobile, value: mobile),
            ],
            if (address.isNotEmpty)
              _Row(label: l10n.sponsorshipFieldAddressLabel, value: address),

            if (_trimmed(s.notes) case final notes?) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.sponsorshipFieldNotes,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(notes, style: theme.textTheme.bodyMedium),
            ],

            if (date(s.created) case final recorded?) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.sponsorshipRecordedOn(recorded),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // Every action in ONE row. What is offered is narrower for a reader
            // than for a writer by one clause: a coordinator reads the
            // patronages of a bird that has left aviary care, and nobody may
            // edit or end one there (roles.dart's sponsorshipWritableBy).
            if (canWrite || (showAnimalLink && hasAnimal)) ...[
              const SizedBox(height: AppSpacing.md),
              _Actions(
                sponsorship: s,
                animalId: hasAnimal ? id : null,
                canWrite: canWrite,
                showAnimalLink: showAnimalLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The sheet's action row: end it, go to the bird, edit it.
///
/// One row, not a stack: these are peers, and „Patenschaft beenden" standing
/// full-width above the others read as a different class of action than it is.
/// A [Wrap], because three labelled buttons do not fit a narrow sheet in one
/// line — they drop to a second line right-aligned rather than overflowing.
///
/// Its own stateful widget so the sheet around it stays stateless: only ending
/// needs a busy flag and somewhere to put a failure. A failure stays HERE,
/// under the buttons, rather than becoming a snackbar over a sheet that still
/// shows the patronage as running.
class _Actions extends ConsumerStatefulWidget {
  const _Actions({
    required this.sponsorship,
    required this.animalId,
    required this.canWrite,
    required this.showAnimalLink,
  });

  final Sponsorship sponsorship;

  /// The sponsored bird, or null for an orphan.
  final String? animalId;
  final bool canWrite;
  final bool showAnimalLink;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;
  Object? _error;

  /// Ends the patronage as of today, after a confirmation that names the date
  /// it is about to write and says the record is kept.
  ///
  /// Deliberately NOT a [DestructiveDialog]: nothing is deleted — an ended
  /// patronage is never scrubbed (federfall-5s5j.4) — and clearing the date in
  /// the edit form makes it run again, so there is nothing here to warn about.
  Future<void> _end() async {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sponsorshipEndNowConfirmTitle),
        content: Text(
          l10n.sponsorshipEndNowConfirmBody(
            formatLocalDate(materialL10n, DateTime.now()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.sponsorshipEndNowConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await endSponsorship(ref, widget.sponsorship);
      // No pop: the sheet reads the row live, so it stays open and the status
      // chip flips to „Beendet" — which is the confirmation that it worked, and
      // the button disappears because the patronage is no longer running.
      if (mounted) setState(() => _busy = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final id = widget.animalId;
    final s = widget.sponsorship;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            // Ending it is its own action rather than a trip through the form:
            // „die Patenschaft ist beendet" is the one change somebody makes
            // without wanting to edit anything, while the form's date field
            // stays the way to record an end that was NOT today. Offered only
            // while it is actually running — on an ended one it would silently
            // move a date that is already set.
            if (widget.canWrite && s.isActive)
              TextButton.icon(
                onPressed: _busy ? null : _end,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.event_busy_outlined),
                label: Text(l10n.sponsorshipEndNowAction),
              ),
            // The way through to the bird, for a caller not already on it.
            if (widget.showAnimalLink && id != null)
              TextButton.icon(
                // Popped first: this sheet belongs to the list it was opened
                // from, and left up it would have to be dismissed before
                // anything on the bird's record is readable.
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go(AppRoutes.animalDetail(id));
                },
                icon: const Icon(Icons.pets_outlined),
                label: Text(l10n.sponsorshipsOpenAnimal),
              ),
            if (widget.canWrite && id != null)
              OutlinedButton.icon(
                onPressed: () => showSponsorshipSheet(
                  context,
                  animalId: id,
                  sponsorship: s,
                ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.sponsorshipEditTitle),
              ),
          ],
        ),
        if (_error case final error?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorMessage(l10n, error),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// [value] with the whitespace gone, or null when there is nothing left — so a
/// field somebody saved as a space does not render as an empty labelled row.
String? _trimmed(String? value) {
  final v = value?.trim() ?? '';
  return v.isEmpty ? null : v;
}

/// One labelled line, the shape `audit_detail_sheet.dart` uses.
///
/// The value is selectable: an address on a sponsor record exists to be copied
/// into a letter or a Zuwendungsbestätigung, and retyping it by hand off a
/// screen is how a postcode ends up wrong.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
