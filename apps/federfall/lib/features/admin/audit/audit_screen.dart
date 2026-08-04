import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
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

  AuditQuery get _query => AuditQuery(severity: _severity);

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
          child: _SeverityFilter(
            selected: _severity,
            onChanged: (s) => setState(() => _severity = s),
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

/// Severity is the one filter worth putting in front of everyone: it separates
/// "who can get in and who can see what" from the day's clinical work, without
/// needing to know a single action name.
class _SeverityFilter extends StatelessWidget {
  const _SeverityFilter({required this.selected, required this.onChanged});

  final AuditSeverity? selected;
  final ValueChanged<AuditSeverity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final s in AuditSeverity.values)
            FilterChip(
              label: Text(auditSeverityLabel(l10n, s)),
              selected: selected == s,
              onSelected: (on) => onChanged(on ? s : null),
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
