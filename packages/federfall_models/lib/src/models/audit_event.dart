import 'package:federfall_models/src/audit_actions.dart';
import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'audit_event.freezed.dart';

/// Who performed an audited action (`audit_events.actor_kind`).
enum AuditActorKind {
  /// A signed-in member of the organisation.
  user('user'),

  /// A hook acting on its own — provisioning, bootstrap, a retention scrub.
  system('system'),

  /// A scheduled job.
  cron('cron'),

  /// Somebody working in the PocketBase admin dashboard.
  superuser('superuser');

  const AuditActorKind(this.wire);

  final String wire;

  static AuditActorKind? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// How much attention an event deserves (`audit_events.severity`).
///
/// Exists so the log can be filtered without knowing every action by name:
/// [security] is who can get in and who can see what, [notice] is destructive
/// or irreversible, [info] is the day's work.
enum AuditSeverity {
  info('info'),
  notice('notice'),
  security('security');

  const AuditSeverity(this.wire);

  final String wire;

  static AuditSeverity? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// One field that changed, as recorded in `audit_events.changes`.
///
/// [from] and [to] hold WIRE values, not labels — `"in_care"`, not „In Pflege".
/// That is exactly what the `wire` convention on every domain enum is for:
/// `CaseStatus.fromWire(change.to)` turns one back into something renderable.
///
/// When [redacted] is true both values are absent by design: a credential or a
/// finder's contact detail is recorded as HAVING changed, never as what it
/// changed to. [truncated] means a long text was clipped for storage.
///
/// A relation-valued field additionally carries [fromLabel] / [toLabel]: what
/// the target record was CALLED when the row was written. The id alone is
/// unreadable, and resolving it now would be wrong twice over — the target may
/// be gone, and if it was renamed since, the row would silently change what it
/// says about the past. Absent on rows written before the server recorded them.
@freezed
abstract class AuditFieldChange with _$AuditFieldChange {
  /// Required by freezed for the [fromDisplay] / [toDisplay] getters below.
  const AuditFieldChange._();

  const factory AuditFieldChange({
    required String field,
    String? from,
    String? to,
    String? fromLabel,
    String? toLabel,
    @Default(false) bool redacted,
    @Default(false) bool truncated,
  }) = _AuditFieldChange;

  /// What to show for the old value: the snapshotted label when the server
  /// recorded one, else the stored value (an enum wire string, a date, or —
  /// for a relation logged before the labels existed — a bare id).
  String? get fromDisplay =>
      (fromLabel?.isNotEmpty ?? false) ? fromLabel : from;

  /// What to show for the new value. See [fromDisplay].
  String? get toDisplay => (toLabel?.isNotEmpty ?? false) ? toLabel : to;

  /// Named `fromPb` like [GeoPoint.fromPb], not `fromJson`: freezed reads a
  /// `fromJson` factory as an opt-in to json_serializable codegen, and this is
  /// a hand-written mapper over a PocketBase json column.
  factory AuditFieldChange.fromPb(Map<String, dynamic> json) =>
      AuditFieldChange(
        field: pbString(json['field']) ?? '',
        from: pbString(json['from']),
        to: pbString(json['to']),
        fromLabel: pbString(json['from_label']),
        toLabel: pbString(json['to_label']),
        redacted: pbBool(json['redacted']),
        truncated: pbBool(json['truncated']),
      );
}

/// The action-specific payload of an [AuditEvent].
///
/// Deliberately never load-bearing: the envelope alone must render a usable
/// line, and a detail only enriches it. That is what makes a new action on the
/// server additive — an older client that has never heard of it falls to
/// [UnknownDetail] and still renders the envelope instead of breaking.
@freezed
sealed class AuditDetail with _$AuditDetail {
  /// The action carries no payload; everything is in the envelope.
  const factory AuditDetail.none() = NoDetail;

  /// `case.intake`
  const factory AuditDetail.caseIntake({
    required String species,
    required bool reidentified,
    required bool hasFinder,
    @Default(0) int intakePhotos,
  }) = CaseIntakeDetail;

  /// `case.handoff` — [from] and [to] are user ids, [fromLabel] / [toLabel]
  /// the names they had at the time. Prefer the label; the id is what
  /// correlates the row with the rest of the request.
  const factory AuditDetail.caseHandoff({
    required String to,
    String? from,
    String? toLabel,
    String? fromLabel,
  }) = CaseHandoffDetail;

  /// `case.shared` / `case.share_revoked` — [withUser] is an id, [withLabel]
  /// the member's name at the time.
  const factory AuditDetail.caseShare({
    required String withUser,
    String? withLabel,
    ShareAccess? access,
  }) = CaseShareDetail;

  /// `user.role_changed`
  const factory AuditDetail.roleChanged({
    UserRole? from,
    UserRole? to,
  }) = RoleChangedDetail;

  /// `animal.merged` — the duplicate no longer exists anywhere else.
  const factory AuditDetail.animalMerged({
    required String duplicateId,
    required String duplicateLabel,
  }) = AnimalMergedDetail;

  /// `exam.saved`
  const factory AuditDetail.examSaved({
    required int findings,
    required int abnormal,
    @Default(true) bool created,
  }) = ExamSavedDetail;

  /// `report.exported` — [year] is null for an all-time report.
  const factory AuditDetail.reportExported({
    required String format,
    int? year,
    String? lang,
    int? rows,
  }) = ReportExportedDetail;

  /// `case_report.printed` — `pdf` or `receipt`.
  const factory AuditDetail.caseReportPrinted({
    required String format,
  }) = CaseReportPrintedDetail;

  /// `auth.login` / `auth.oauth2_login`
  const factory AuditDetail.login({
    required String method,
    String? provider,
    @Default(false) bool newAccount,
  }) = LoginDetail;

  /// `auth.login_failed` — one row stands for a whole window of failures, not
  /// for a single attempt. See [windowMinutes].
  const factory AuditDetail.loginFailed({
    required int windowMinutes,
    String? method,
  }) = LoginFailedDetail;

  /// `oauth2.user_provisioned`
  const factory AuditDetail.userProvisioned({
    UserRole? role,
    @Default(false) bool firstUser,
  }) = UserProvisionedDetail;

  /// `disposition.*` — what the disposition DID, beyond being recorded.
  /// Writing one closes the case and re-derives the bird's lifetime status;
  /// deleting the last one reopens it. Those are consequences of the same act,
  /// not events of their own.
  const factory AuditDetail.disposition({
    CaseStatus? caseStatus,
    LifetimeStatus? lifetimeStatus,
    String? currentAviary,
    String? currentAviaryLabel,
  }) = DispositionDetail;

  /// `audit.purged`
  const factory AuditDetail.auditPurged({
    required int count,
    int? retentionDays,
  }) = AuditPurgedDetail;

  /// A payload this build does not recognise — a newer server, or an action
  /// whose shape changed. Kept whole so nothing is silently lost.
  const factory AuditDetail.unknown(Map<String, dynamic> raw) = UnknownDetail;

  /// Builds the typed payload for [action] out of the raw `detail` json.
  ///
  /// Never throws and never returns null: an unrecognised action or a payload
  /// that does not fit becomes [UnknownDetail], an absent one [NoDetail].
  static AuditDetail parse(AuditAction? action, Object? raw) {
    if (raw is! Map) return const AuditDetail.none();
    final json = Map<String, dynamic>.from(raw);
    if (json.isEmpty) return const AuditDetail.none();

    AuditDetail fallback() => AuditDetail.unknown(json);

    return switch (action) {
      AuditAction.caseIntake => AuditDetail.caseIntake(
        species: pbString(json['species']) ?? '',
        reidentified: pbBool(json['reidentified']),
        hasFinder: pbBool(json['has_finder']),
        intakePhotos: pbInt(json['intake_photos']) ?? 0,
      ),
      AuditAction.caseHandoff => AuditDetail.caseHandoff(
        to: pbString(json['to']) ?? '',
        from: pbString(json['from']),
        toLabel: pbString(json['to_label']),
        fromLabel: pbString(json['from_label']),
      ),
      AuditAction.caseShared ||
      AuditAction.caseShareRevoked => AuditDetail.caseShare(
        withUser: pbString(json['with']) ?? '',
        withLabel: pbString(json['with_label']),
        access: ShareAccess.fromWire(json['access']),
      ),
      AuditAction.userRoleChanged => AuditDetail.roleChanged(
        from: UserRole.fromWire(json['from']),
        to: UserRole.fromWire(json['to']),
      ),
      AuditAction.animalMerged => AuditDetail.animalMerged(
        duplicateId: pbString(json['duplicate_id']) ?? '',
        duplicateLabel: pbString(json['duplicate_label']) ?? '',
      ),
      AuditAction.examSaved => AuditDetail.examSaved(
        findings: pbInt(json['findings']) ?? 0,
        abnormal: pbInt(json['abnormal']) ?? 0,
        created: pbBool(json['created']),
      ),
      AuditAction.reportExported => AuditDetail.reportExported(
        format: pbString(json['format']) ?? '',
        year: pbInt(json['year']),
        lang: pbString(json['lang']),
        rows: pbInt(json['rows']),
      ),
      AuditAction.caseReportPrinted => AuditDetail.caseReportPrinted(
        format: pbString(json['format']) ?? '',
      ),
      AuditAction.authLogin || AuditAction.authOauth2Login => AuditDetail.login(
        method: pbString(json['method']) ?? '',
        provider: pbString(json['provider']),
        newAccount: pbBool(json['new_account']),
      ),
      AuditAction.authLoginFailed => AuditDetail.loginFailed(
        windowMinutes: pbInt(json['window_minutes']) ?? 0,
        method: pbString(json['method']),
      ),
      AuditAction.oauth2UserProvisioned => AuditDetail.userProvisioned(
        role: UserRole.fromWire(json['role']),
        firstUser: pbBool(json['first_user']),
      ),
      AuditAction.dispositionCreated ||
      AuditAction.dispositionUpdated ||
      AuditAction.dispositionDeleted => AuditDetail.disposition(
        caseStatus: CaseStatus.fromWire(json['case_status']),
        lifetimeStatus: LifetimeStatus.fromWire(json['lifetime_status']),
        currentAviary: pbString(json['current_aviary']),
        currentAviaryLabel: pbString(json['current_aviary_label']),
      ),
      AuditAction.auditPurged => AuditDetail.auditPurged(
        count: pbInt(json['count']) ?? 0,
        retentionDays: pbInt(json['retention_days']),
      ),
      _ => fallback(),
    };
  }
}

/// One entry in the supervisor-only audit log (`audit_events`).
///
/// Everything about it is a SNAPSHOT: the actor's name and role, the subject's
/// label and collection are stored as text rather than relations, because a
/// case, an animal or a member can be deleted and the record of what happened
/// to them has to survive that. Consequently nothing here is expandable — what
/// you see is what was true when it happened, which is the point.
@freezed
abstract class AuditEvent with _$AuditEvent {
  const factory AuditEvent({
    required String id,

    /// The stored action string, always present.
    required String rawAction,
    required DateTime at,
    required AuditActorKind actorKind,
    required AuditSeverity severity,
    required AuditDetail detail,

    /// The recognised action, or null when this build has never heard of
    /// [rawAction] — a normal state, not an error.
    AuditAction? action,
    String? org,
    String? actorId,

    /// The actor's name as it was at the time. Present even when [actorId]
    /// points at a member who has since been deleted.
    @Default('') String actorLabel,
    UserRole? actorRole,
    @Default('') String subjectCollection,
    @Default('') String subjectId,

    /// What the subject was called. Always empty for a finder — a member of
    /// the public is never named in this log.
    @Default('') String subjectLabel,

    /// The case this belongs to, if any. Indexed server-side: it is what the
    /// per-case activity view filters on.
    @Default('') String caseId,

    /// The case NUMBER as it was, so a line can name its case without a
    /// lookup that would fail once the case is deleted. Empty on rows that
    /// belong to no case, and on rows written before the column existed.
    @Default('') String caseLabel,
    @Default(<String, String>{}) Map<String, String> refs,
    @Default(<AuditFieldChange>[]) List<AuditFieldChange> changes,

    /// Only recorded when the organisation opted in.
    String? ip,
    String? userAgent,

    /// Correlates the rows one request produced.
    @Default('') String requestId,
  }) = _AuditEvent;

  factory AuditEvent.fromRecord(RecordModel r) {
    final d = r.data;
    final rawAction = pbString(d['action']) ?? '';
    final action = AuditAction.fromWire(rawAction);
    return AuditEvent(
      id: r.id,
      rawAction: rawAction,
      action: action,
      at: pbDate(d['created']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      org: pbString(d['org']),
      actorId: pbString(d['actor_id']),
      actorLabel: pbString(d['actor_label']) ?? '',
      actorRole: UserRole.fromWire(d['actor_role']),
      actorKind:
          AuditActorKind.fromWire(d['actor_kind']) ?? AuditActorKind.system,
      subjectCollection: pbString(d['subject_collection']) ?? '',
      subjectId: pbString(d['subject_id']) ?? '',
      subjectLabel: pbString(d['subject_label']) ?? '',
      caseId: pbString(d['case_id']) ?? '',
      caseLabel: pbString(d['case_label']) ?? '',
      refs: _refs(d['refs']),
      changes: _changes(d['changes']),
      detail: AuditDetail.parse(action, d['detail']),
      severity: AuditSeverity.fromWire(d['severity']) ?? AuditSeverity.info,
      ip: pbString(d['ip']),
      userAgent: pbString(d['user_agent']),
      requestId: pbString(d['request_id']) ?? '',
    );
  }

  static Map<String, String> _refs(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final s = pbString(v);
      if (s != null && s.isNotEmpty) out['$k'] = s;
    });
    return out;
  }

  static List<AuditFieldChange> _changes(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          AuditFieldChange.fromPb(Map<String, dynamic>.from(item)),
    ];
  }
}
