import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:meta/meta.dart';
import 'package:pocketbase/pocketbase.dart';

/// What a supervisor is looking for in the audit log.
///
/// Every field narrows; leaving one out means "any". Turned into a bound
/// filter by [PbAuditEventsRepository.filterFor], so nothing here is ever
/// interpolated into a filter string.
@immutable
class AuditQuery {
  const AuditQuery({
    this.actorId,
    this.actorKind,
    this.actions = const [],
    this.severity,
    this.caseId,
    this.subjectId,
    this.subjectCollection,
    this.requestId,
    this.from,
    this.to,
  });

  /// Who acted. Matches the snapshot id, so it still finds the events of a
  /// member who has since been deleted.
  final String? actorId;

  /// Which KIND of actor. The practical use is finding what the machine did on
  /// its own — a cron scrub, a provisioning — which no actor id can express,
  /// since a system row has none.
  final AuditActorKind? actorKind;

  /// Any of these actions. Empty means all of them.
  final List<AuditAction> actions;

  /// Exactly this severity — the practical use is `security` alone.
  final AuditSeverity? severity;
  final String? caseId;
  final String? subjectId;
  final String? subjectCollection;

  /// The rows one HTTP request produced. A single human action can write
  /// several — an intake, a handoff and the carer move it derives — and this
  /// is what puts them back together.
  final String? requestId;

  /// Inclusive lower bound on when it happened.
  final DateTime? from;

  /// Exclusive upper bound.
  final DateTime? to;

  bool get isEmpty =>
      actorId == null &&
      actorKind == null &&
      actions.isEmpty &&
      severity == null &&
      caseId == null &&
      subjectId == null &&
      subjectCollection == null &&
      requestId == null &&
      from == null &&
      to == null;

  AuditQuery copyWith({
    String? actorId,
    AuditActorKind? actorKind,
    List<AuditAction>? actions,
    AuditSeverity? severity,
    String? caseId,
    String? subjectId,
    String? subjectCollection,
    String? requestId,
    DateTime? from,
    DateTime? to,
    bool clearActor = false,
    bool clearSeverity = false,
    bool clearRange = false,
  }) => AuditQuery(
    actorId: clearActor ? null : (actorId ?? this.actorId),
    actorKind: clearActor ? null : (actorKind ?? this.actorKind),
    actions: actions ?? this.actions,
    severity: clearSeverity ? null : (severity ?? this.severity),
    caseId: caseId ?? this.caseId,
    subjectId: subjectId ?? this.subjectId,
    subjectCollection: subjectCollection ?? this.subjectCollection,
    requestId: requestId ?? this.requestId,
    from: clearRange ? null : (from ?? this.from),
    to: clearRange ? null : (to ?? this.to),
  );

  @override
  bool operator ==(Object other) =>
      other is AuditQuery &&
      other.actorId == actorId &&
      other.actorKind == actorKind &&
      _sameActions(other.actions) &&
      other.severity == severity &&
      other.caseId == caseId &&
      other.subjectId == subjectId &&
      other.subjectCollection == subjectCollection &&
      other.requestId == requestId &&
      other.from == from &&
      other.to == to;

  bool _sameActions(List<AuditAction> other) {
    if (other.length != actions.length) return false;
    for (var i = 0; i < actions.length; i++) {
      if (other[i] != actions[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    actorId,
    actorKind,
    Object.hashAll(actions),
    severity,
    caseId,
    subjectId,
    subjectCollection,
    requestId,
    from,
    to,
  );
}

/// Reads of the supervisor-only audit log (`audit_events`).
///
/// Read-only at the type level, not by convention: the collection has no write
/// rules at all — only server hooks can append to it — so a `create` here would
/// be a 403 at runtime. Extending [PbReadOnlyRepository] makes it a compile
/// error instead.
class PbAuditEventsRepository extends PbReadOnlyRepository<AuditEvent> {
  PbAuditEventsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'audit_events',
        fromRecord: AuditEvent.fromRecord,
      );

  /// One page of the feed matching [query], newest first.
  ///
  /// Paged by cursor rather than page number because the thing being read is
  /// append-only and grows while it is read — see [PbReadOnlyRepository.page].
  /// There is deliberately no "load everything" convenience: this collection
  /// is the one that grows without bound.
  Future<PbPage<AuditEvent>> search({
    AuditQuery query = const AuditQuery(),
    PbCursor? after,
    int perPage = 50,
  }) => page(filter: filterFor(query), after: after, perPage: perPage);

  /// The rows one request produced, in the order they were written — a single
  /// action's full footprint, which is what `request_id` is recorded for.
  ///
  /// [list] rather than [search]: this is a bounded handful (an intake writes
  /// four or five), read as a sequence rather than as a feed, so the keyset
  /// paging and the fixed newest-first sort that [search] needs are both wrong
  /// here.
  Future<List<AuditEvent>> forRequest(String requestId) => list(
    filter: filterFor(AuditQuery(requestId: requestId)),
    sort: 'created,id',
  );

  /// Everything that happened on one case, newest first — what the case
  /// detail's activity section shows.
  Future<PbPage<AuditEvent>> forCase(
    String caseId, {
    PbCursor? after,
    int perPage = 50,
  }) => search(
    query: AuditQuery(caseId: caseId),
    after: after,
    perPage: perPage,
  );

  /// The bound filter for [query], or null when it narrows nothing.
  ///
  /// Exposed for tests and for callers that need to combine it; building it by
  /// hand is what [PbFilter] exists to prevent.
  PbFilter? filterFor(AuditQuery query) {
    if (query.isEmpty) return null;

    final clauses = <String>[];
    final params = <String, dynamic>{};

    void eq(String field, String key, String? value) {
      if (value == null || value.isEmpty) return;
      clauses.add('$field = {:$key}');
      params[key] = value;
    }

    eq('actor_id', 'actor', query.actorId);
    eq('actor_kind', 'akind', query.actorKind?.wire);
    eq('case_id', 'case', query.caseId);
    eq('subject_id', 'subject', query.subjectId);
    eq('subject_collection', 'coll', query.subjectCollection);
    eq('severity', 'sev', query.severity?.wire);
    eq('request_id', 'req', query.requestId);

    if (query.actions.isNotEmpty) {
      // An OR group, parenthesised so it cannot swallow the other clauses.
      final or = <String>[];
      for (var i = 0; i < query.actions.length; i++) {
        or.add('action = {:a$i}');
        params['a$i'] = query.actions[i].wire;
      }
      clauses.add('(${or.join(' || ')})');
    }

    if (query.from != null) {
      clauses.add('created >= {:from}');
      params['from'] = query.from!.toUtc();
    }
    if (query.to != null) {
      clauses.add('created < {:to}');
      params['to'] = query.to!.toUtc();
    }

    return filterExpr(clauses.join(' && '), params);
  }
}
