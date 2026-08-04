import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/admin/admin_providers.dart';
import 'package:federfall/features/admin/audit/audit_detail_sheet.dart';
import 'package:federfall/features/admin/audit/audit_labels.dart';
import 'package:federfall/features/admin/audit/audit_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The supervisor-only audit log (federfall-qt96).
///
/// Reached from the management hub. The role is re-checked here so a typed-in
/// URL degrades to a polite refusal rather than an empty list — though the real
/// boundary is the collection's list rule, which returns nothing to anyone
/// else no matter what this screen does.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _scroll = ScrollController();
  AuditSeverity? _severity;
  DateTimeRange? _range;
  AuditTopic? _topic;
  _Actor? _actor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AuditQuery get _query => AuditQuery(
    severity: _severity,
    actorId: _actor?.id,
    actorKind: _actor?.kind,
    // A topic is a list of actions, which is what the query has always taken.
    actions: _topic?.actions ?? const [],
    from: _range?.start,
    // Half-open: the picker's end is the last DAY, so the bound is the start
    // of the next one or an event at 23:30 would fall outside its own range.
    to: _range == null
        ? null
        : DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1),
  );

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    // Within a screenful of the bottom. loadMore() is a no-op while a page is
    // in flight, so firing this on every scroll frame is safe.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      unawaited(ref.read(auditFeedProvider(_query).notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.auditTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final feed = ref.watch(auditFeedProvider(_query));

    return Scaffold(
      appBar: AppBar(
        // No up arrow when this is the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.auditTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _Filters(
            severity: _severity,
            range: _range,
            topic: _topic,
            actor: _actor,
            onSeverity: (s) => setState(() => _severity = s),
            onRange: (r) => setState(() => _range = r),
            onTopic: (t) => setState(() => _topic = t),
            onActor: (a) => setState(() => _actor = a),
          ),
        ),
      ),
      body: AsyncValueView(
        value: feed,
        onRetry: () => ref.invalidate(auditFeedProvider(_query)),
        data: (state) {
          if (state.events.isEmpty) {
            return EmptyView(
              icon: Icons.history_toggle_off,
              message: l10n.auditEmpty,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(auditFeedProvider(_query)),
            child: ListView.builder(
              controller: _scroll,
              // Always scrollable, so pull-to-refresh works on a short list.
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.events.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= state.events.length) {
                  // The tail of the list is either the next page arriving or
                  // the reason it did not. A failure has to be visible and
                  // recoverable here: this is the only place it shows, and a
                  // log the supervisor believes they have read to the end of is
                  // worse than one that says it stopped (federfall-ia9n).
                  if (state.pageError case final error?) {
                    return _PageErrorRow(
                      error: error,
                      onRetry: () => unawaited(
                        ref
                            .read(auditFeedProvider(_query).notifier)
                            .retryPage(),
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return AuditEventTile(event: state.events[i]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// The end of a feed that stopped short, with the way to carry on.
class _PageErrorRow extends StatelessWidget {
  const _PageErrorRow({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        spacing: AppSpacing.sm,
        children: [
          Text(
            loadErrorMessage(l10n, error),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ],
      ),
    );
  }
}

/// Who the log filters on: a member, or the machine acting on its own.
///
/// A system row has no actor id at all, so "what did the machine do" can only
/// be asked by kind — which is why this carries both and the query takes both.
@immutable
class _Actor {
  const _Actor({required this.label, this.id, this.kind});

  final String label;
  final String? id;
  final AuditActorKind? kind;
}

/// The four questions a supervisor arrives with.
///
/// Severity separates who can get in and who can see what from the day's
/// clinical work, without the reader having to know a single action name. The
/// period answers "what happened while I was away", and it is what keeps an
/// append-only feed that only grows from having to be scrolled to reach
/// anything old. The other two — "what did this person do" and "what happened
/// to the birds" — the query layer could answer from the start; only the screen
/// could not ask (federfall-ybua.6).
class _Filters extends ConsumerWidget {
  const _Filters({
    required this.severity,
    required this.range,
    required this.topic,
    required this.actor,
    required this.onSeverity,
    required this.onRange,
    required this.onTopic,
    required this.onActor,
  });

  final AuditSeverity? severity;
  final DateTimeRange? range;
  final AuditTopic? topic;
  final _Actor? actor;
  final ValueChanged<AuditSeverity?> onSeverity;
  final ValueChanged<DateTimeRange?> onRange;
  final ValueChanged<AuditTopic?> onTopic;
  final ValueChanged<_Actor?> onActor;

  /// [days] back from today, inclusive of today.
  static DateTimeRange _lastDays(int days) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      end: end,
      start: end.subtract(Duration(days: days - 1)),
    );
  }

  bool _isPreset(int days) {
    final preset = _lastDays(days);
    return range != null &&
        range!.start == preset.start &&
        range!.end == preset.end;
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      // The log cannot contain the future, so offering it would only mislead.
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: range,
    );
    if (picked != null) onRange(picked);
  }

  /// The actor picker: every member of the org, plus the machine actors, since
  /// „was that me or the retention job" is a question the log has to answer.
  Future<void> _pickActor(
    BuildContext context,
    List<AppUser> members,
  ) async {
    final l10n = context.l10n;
    final choices = <_Actor?>[
      null,
      const _Actor(label: '', kind: AuditActorKind.system),
      const _Actor(label: '', kind: AuditActorKind.cron),
      for (final m in members)
        _Actor(label: (m.name?.isEmpty ?? true) ? m.email : m.name!, id: m.id),
    ];

    String name(_Actor? choice) => switch (choice?.kind) {
      null when choice == null => l10n.auditFilterAnyActor,
      AuditActorKind.system => l10n.auditActorSystem,
      AuditActorKind.cron => l10n.auditActorCron,
      AuditActorKind.superuser => l10n.auditActorSuperuser,
      _ => choice!.label,
    };

    final picked = await showAppSheet<_Actor?>(
      context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final choice in choices)
              ListTile(
                title: Text(name(choice)),
                trailing:
                    (choice?.id ?? choice?.kind?.wire) ==
                        (actor?.id ?? actor?.kind?.wire)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, choice),
              ),
          ],
        ),
      ),
    );
    // Distinguishing "picked Alle" from "dismissed the sheet" needs the sheet
    // to say which it was, and a nullable result cannot. So the choice is
    // applied only when it actually differs from what is already selected.
    if (context.mounted && picked != actor) onActor(picked);
  }

  Future<void> _pickTopic(BuildContext context) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<AuditTopic?>(
      context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in <AuditTopic?>[null, ...AuditTopic.values])
              ListTile(
                title: Text(
                  t == null
                      ? l10n.auditFilterAnyTopic
                      : auditTopicLabel(l10n, t),
                ),
                trailing: t == topic ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, t),
              ),
          ],
        ),
      ),
    );
    if (context.mounted && picked != topic) onTopic(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final custom =
        range != null && !_isPreset(1) && !_isPreset(7) && !_isPreset(30);
    // Watched, not read on demand: the picker needs the roster resolved by the
    // time it opens, and this screen is supervisor-only, where the roster is
    // already loaded for the rest of the admin area.
    final members = ref.watch(orgMembersProvider).value ?? const <AppUser>[];
    final dates = DateFormat.yMd(l10n.localeName);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        spacing: AppSpacing.xs,
        children: [
          FilterChip(
            label: Text(l10n.auditFilterAll),
            selected:
                severity == null &&
                range == null &&
                topic == null &&
                actor == null,
            onSelected: (_) {
              onSeverity(null);
              onRange(null);
              onTopic(null);
              onActor(null);
            },
          ),
          // Who, and what area of work — the two the data layer could always
          // answer. Pickers rather than chips: one has a roster behind it.
          FilterChip(
            avatar: const Icon(Icons.person_outline, size: 18),
            label: Text(
              switch (actor?.kind) {
                null => actor?.label ?? l10n.auditFilterActor,
                AuditActorKind.cron => l10n.auditActorCron,
                AuditActorKind.system => l10n.auditActorSystem,
                AuditActorKind.superuser => l10n.auditActorSuperuser,
                AuditActorKind.user => actor!.label,
              },
            ),
            selected: actor != null,
            onSelected: (_) => _pickActor(context, members),
          ),
          FilterChip(
            avatar: const Icon(Icons.topic_outlined, size: 18),
            label: Text(
              topic == null
                  ? l10n.auditFilterTopic
                  : auditTopicLabel(l10n, topic!),
            ),
            selected: topic != null,
            onSelected: (_) => _pickTopic(context),
          ),
          for (final s in AuditSeverity.values)
            FilterChip(
              label: Text(auditSeverityLabel(l10n, s)),
              selected: severity == s,
              onSelected: (on) => onSeverity(on ? s : null),
            ),
          const SizedBox(width: AppSpacing.xs),
          for (final (days, label) in [
            (1, l10n.auditFilterToday),
            (7, l10n.auditFilter7Days),
            (30, l10n.auditFilter30Days),
          ])
            FilterChip(
              label: Text(label),
              selected: _isPreset(days),
              onSelected: (on) => onRange(on ? _lastDays(days) : null),
            ),
          FilterChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
              custom
                  ? l10n.auditFilterRangeLabel(
                      dates.format(range!.start),
                      dates.format(range!.end),
                    )
                  : l10n.auditFilterCustom,
            ),
            selected: custom,
            onSelected: (_) => _pick(context),
          ),
        ],
      ),
    );
  }
}

/// One entry: what happened, to what, by whom, when — plus whatever context the
/// event carried.
class AuditEventTile extends StatelessWidget {
  const AuditEventTile({required this.event, this.showCase = true, super.key});

  final AuditEvent event;

  /// Whether to name the case. False inside the per-case section, where every
  /// row belongs to the same case and repeating its number on each line is
  /// noise rather than context.
  final bool showCase;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final line = auditLine(l10n, event);
    final facts = showCase
        ? line.facts
        : line.facts.where((f) => f.label != l10n.auditFactCase).toList();
    final when = DateFormat.yMd(
      l10n.localeName,
    ).add_Hm().format(event.at.toLocal());
    final who = auditActorName(l10n, event);

    return ListTile(
      isThreeLine: facts.isNotEmpty,
      // The line is a summary — a diff shows the first few of N changes. The
      // sheet is where the rest of the row is reachable (federfall-ybua.5).
      onTap: () => showAuditDetailSheet(context, event),
      leading: Icon(
        line.icon,
        color: event.severity == AuditSeverity.security
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      ),
      title: Text(line.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.subtitle == null
                ? '$who · $when'
                : '$who · $when · ${line.subtitle}',
            style: theme.textTheme.bodySmall,
          ),
          for (final fact in facts)
            Text(
              fact.value.isEmpty ? fact.label : '${fact.label}: ${fact.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The "what happened on this case" section of the case detail.
///
/// Deliberately not the case timeline: that is the clinical chronology a carer
/// reads, this is who touched the record. Supervisors only, so it renders
/// nothing at all for anyone else rather than an empty section they cannot
/// explain.
class CaseActivitySection extends ConsumerWidget {
  const CaseActivitySection({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;
    if (!canManageTeam(role)) return const SizedBox.shrink();

    final log = ref.watch(caseActivityLogProvider(caseId));

    return log.maybeWhen(
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                l10n.auditCaseSectionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final e in events) AuditEventTile(event: e, showCase: false),
          ],
        );
      },
      // A failed or pending audit read must never hold up the case detail —
      // it is supplementary context, not part of the record.
      orElse: () => const SizedBox.shrink(),
    );
  }
}
