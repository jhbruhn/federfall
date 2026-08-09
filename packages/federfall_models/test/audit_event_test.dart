import 'dart:io';

import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

/// The emitter that writes every row this file parses. Read as text rather
/// than mirrored, so the two cannot drift apart silently.
File _libAudit() {
  // Package root when `dart test` runs here; repo root under other runners.
  const rel = 'backend/pocketbase/pb_hooks/lib_audit.js';
  for (final prefix in ['../../', '', '../']) {
    final f = File('$prefix$rel');
    if (f.existsSync()) return f;
  }
  fail('cannot locate $rel from ${Directory.current.path}');
}

RecordModel _event(Map<String, dynamic> overrides) => RecordModel({
  'id': 'audt0000000001',
  'action': 'case.updated',
  'created': '2026-08-04 09:15:00.000Z',
  'org': 'org00000default',
  'actor_id': 'user0000000001',
  'actor_label': 'Anna Karin',
  'actor_role': 'carer',
  'actor_kind': 'user',
  'subject_collection': 'cases',
  'subject_id': 'case0000000001',
  'subject_label': '2026-014',
  'case_id': 'case0000000001',
  'severity': 'info',
  'request_id': 'req0000000001',
  ...overrides,
});

void main() {
  group('AuditAction registry', () {
    test('matches pb_hooks/lib_audit.js exactly', () {
      final src = _libAudit().readAsStringSync();
      final wire = RegExp(
        r'^  [A-Z0-9_]+: "([a-z0-9_]+\.[a-z0-9_]+)",',
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      // A broken regex would make every comparison below vacuously true.
      expect(
        wire.length,
        greaterThanOrEqualTo(40),
        reason: 'the registry parse found almost nothing — check the regex',
      );

      final dart = AuditAction.values.map((a) => a.wire).toSet();
      expect(
        dart.difference(wire),
        isEmpty,
        reason: 'these exist in Dart but no emitter can produce them',
      );
      expect(
        wire.difference(dart),
        isEmpty,
        reason: 'the server can emit these and the app would not name them',
      );
    });

    test('every wire value is unique', () {
      final wires = AuditAction.values.map((a) => a.wire).toList();
      expect(wires.toSet().length, wires.length);
    });
  });

  group('AuditEvent.fromRecord', () {
    test('maps the envelope, including the actor snapshot', () {
      final e = AuditEvent.fromRecord(_event({}));

      expect(e.action, AuditAction.caseUpdated);
      expect(e.rawAction, 'case.updated');
      expect(e.at.hour, 9);
      expect(e.actorLabel, 'Anna Karin');
      expect(e.actorRole, UserRole.carer);
      expect(e.actorKind, AuditActorKind.user);
      expect(e.subjectLabel, '2026-014');
      expect(e.caseId, 'case0000000001');
      expect(e.severity, AuditSeverity.info);
    });

    test('an unknown action keeps its wire value instead of failing', () {
      final e = AuditEvent.fromRecord(
        _event({
          'action': 'gerbil.teleported',
          'detail': {'distance': 4},
        }),
      );

      // The whole point of the envelope: a newer server can log something this
      // build has never heard of and the line still renders.
      expect(e.action, isNull);
      expect(e.rawAction, 'gerbil.teleported');
      expect(e.detail, isA<UnknownDetail>());
      expect((e.detail as UnknownDetail).raw['distance'], 4);
      expect(e.actorLabel, 'Anna Karin');
    });

    test('an unknown actor kind or severity degrades to a safe default', () {
      final e = AuditEvent.fromRecord(
        _event({
          'actor_kind': 'poltergeist',
          'severity': 'catastrophic',
          'actor_role': 'archduke',
        }),
      );

      expect(e.actorKind, AuditActorKind.system);
      expect(e.severity, AuditSeverity.info);
      expect(e.actorRole, isNull);
    });

    test('missing json columns become empty, not null crashes', () {
      final e = AuditEvent.fromRecord(
        RecordModel({
          'id': 'audt0000000002',
          'action': 'aviary.created',
          'created': '2026-08-04 09:15:00.000Z',
          'actor_kind': 'user',
        }),
      );

      expect(e.refs, isEmpty);
      expect(e.changes, isEmpty);
      expect(e.detail, isA<NoDetail>());
      expect(e.subjectLabel, '');
      expect(e.caseId, '');
    });

    test('reads changes, keeping redaction and truncation flags', () {
      final e = AuditEvent.fromRecord(
        _event({
          'changes': [
            {'field': 'weight_g', 'from': 300, 'to': 310},
            {'field': 'password', 'redacted': true},
            {'field': 'notes', 'from': 'a', 'to': 'b', 'truncated': true},
          ],
        }),
      );

      expect(e.changes, hasLength(3));
      // Wire values, as strings — CaseStatus.fromWire(change.to) is the point.
      expect(e.changes[0].from, '300');
      expect(e.changes[0].to, '310');
      expect(e.changes[1].redacted, isTrue);
      expect(
        e.changes[1].from,
        isNull,
        reason: 'a redacted change records that it happened, not the value',
      );
      expect(e.changes[2].truncated, isTrue);
    });

    test('reads refs as a flat id map, dropping empties', () {
      final e = AuditEvent.fromRecord(
        _event({
          'refs': {'animal': 'anml0000000001', 'aviary': ''},
        }),
      );

      expect(e.refs, {'animal': 'anml0000000001'});
    });
  });

  group('AuditDetail.parse', () {
    test('case.intake', () {
      final d = AuditDetail.parse(AuditAction.caseIntake, {
        'species': 'Türkentaube',
        'reidentified': false,
        'has_finder': true,
        'intake_photos': 2,
      });

      expect(
        d,
        const AuditDetail.caseIntake(
          species: 'Türkentaube',
          reidentified: false,
          hasFinder: true,
          intakePhotos: 2,
        ),
      );
    });

    test('case.handoff', () {
      expect(
        AuditDetail.parse(AuditAction.caseHandoff, {
          'from': 'user0000000001',
          'to': 'user0000000002',
          'carer_moved': true,
        }),
        const AuditDetail.caseHandoff(
          from: 'user0000000001',
          to: 'user0000000002',
        ),
      );
    });

    test('case.shared resolves the access enum', () {
      final d =
          AuditDetail.parse(
                AuditAction.caseShared,
                {'with': 'user0000000002', 'access': 'edit'},
              )
              as CaseShareDetail;

      expect(d.withUser, 'user0000000002');
      expect(d.access, ShareAccess.edit);
    });

    test('user.role_changed resolves both roles', () {
      final d =
          AuditDetail.parse(
                AuditAction.userRoleChanged,
                {'from': 'carer', 'to': 'coordinator'},
              )
              as RoleChangedDetail;

      expect(d.from, UserRole.carer);
      expect(d.to, UserRole.coordinator);
    });

    test('animal.merged keeps the duplicate that no longer exists', () {
      final d =
          AuditDetail.parse(AuditAction.animalMerged, {
                'duplicate_id': 'anml0000000009',
                'duplicate_label': 'Doppelt',
                'field_choices': {'name': 'duplicate'},
              })
              as AnimalMergedDetail;

      expect(d.duplicateId, 'anml0000000009');
      expect(d.duplicateLabel, 'Doppelt');
    });

    test('exam.saved', () {
      final d =
          AuditDetail.parse(
                AuditAction.examSaved,
                {'created': true, 'findings': 2, 'abnormal': 1},
              )
              as ExamSavedDetail;

      expect(d.findings, 2);
      expect(d.abnormal, 1);
      expect(d.created, isTrue);
    });

    test('microscopy.saved keeps the finding NAMES, not their ids', () {
      final d =
          AuditDetail.parse(AuditAction.microscopySaved, {
                'created': true,
                'sample_type': 'fecal',
                'method': 'flotation',
                'examined_by': 'lab',
                'no_findings': false,
                'findings': 2,
                'finding_labels': ['Spulwurmeier', 'Kokzidien-Oozysten'],
                'worst_severity': 'plus_plus',
                'attachments': 1,
              })
              as MicroscopySavedDetail;

      expect(d.findings, 2);
      expect(d.sampleType, MicroscopySampleType.fecal);
      expect(d.method, MicroscopyMethod.flotation);
      expect(d.examinedBy, MicroscopyExaminedBy.lab);
      expect(d.worstSeverity, MicroscopySeverity.plusPlus);
      expect(d.findingLabels, ['Spulwurmeier', 'Kokzidien-Oozysten']);
      expect(d.attachments, 1);
      expect(d.noFindings, isFalse);
      expect(d.created, isTrue);
    });

    test('microscopy.saved with nothing found has no worst grade', () {
      final d =
          AuditDetail.parse(AuditAction.microscopySaved, {
                'created': false,
                'sample_type': 'crop_swab',
                'no_findings': true,
                'findings': 0,
                'worst_severity': '',
              })
              as MicroscopySavedDetail;

      expect(d.noFindings, isTrue);
      expect(d.worstSeverity, isNull);
      expect(d.findingLabels, isEmpty);
      expect(d.method, isNull);
      expect(d.created, isFalse);
    });

    test('report.exported, with an all-time report having no year', () {
      final yearly =
          AuditDetail.parse(AuditAction.reportExported, {
                'report': 'annual',
                'format': 'csv',
                'year': 2019,
                'lang': 'de',
                'rows': 7,
              })
              as ReportExportedDetail;
      expect(yearly.format, 'csv');
      expect(yearly.year, 2019);
      expect(yearly.rows, 7);

      final allTime =
          AuditDetail.parse(AuditAction.reportExported, {
                'report': 'annual',
                'format': 'pdf',
                'year': null,
              })
              as ReportExportedDetail;
      expect(allTime.year, isNull);
    });

    test('auth.login_failed stands for a window, not one attempt', () {
      final d =
          AuditDetail.parse(
                AuditAction.authLoginFailed,
                {'method': 'password', 'window_minutes': 5},
              )
              as LoginFailedDetail;

      expect(d.windowMinutes, 5);
      expect(d.method, 'password');
    });

    test('auth.oauth2_login', () {
      final d =
          AuditDetail.parse(AuditAction.authOauth2Login, {
                'method': 'oauth2',
                'provider': 'oidc',
                'new_account': true,
              })
              as LoginDetail;

      expect(d.provider, 'oidc');
      expect(d.newAccount, isTrue);
    });

    test('oauth2.user_provisioned', () {
      final d =
          AuditDetail.parse(
                AuditAction.oauth2UserProvisioned,
                {'role': 'guest', 'first_user': false, 'email_verified': true},
              )
              as UserProvisionedDetail;

      expect(d.role, UserRole.guest);
      expect(d.firstUser, isFalse);
    });

    test('audit.purged', () {
      final d =
          AuditDetail.parse(
                AuditAction.auditPurged,
                {'count': 412, 'retention_days': 730},
              )
              as AuditPurgedDetail;

      expect(d.count, 412);
      expect(d.retentionDays, 730);
    });

    test('an absent or empty payload is none, not unknown', () {
      expect(
        AuditDetail.parse(AuditAction.caseUpdated, null),
        const AuditDetail.none(),
      );
      expect(
        AuditDetail.parse(AuditAction.caseUpdated, <String, dynamic>{}),
        const AuditDetail.none(),
      );
      expect(AuditDetail.parse(null, null), const AuditDetail.none());
    });

    test('a payload for an action this build cannot name is kept whole', () {
      final d = AuditDetail.parse(null, {'anything': 'at all'});

      expect(d, isA<UnknownDetail>());
      expect((d as UnknownDetail).raw, {'anything': 'at all'});
    });

    test('a known action with a payload of the wrong shape does not throw', () {
      final d =
          AuditDetail.parse(
                AuditAction.caseIntake,
                {
                  'species': 42,
                  'reidentified': 'yes please',
                  'intake_photos': 'many',
                },
              )
              as CaseIntakeDetail;

      expect(d.species, '42');
      expect(d.intakePhotos, 0);
    });

    test('every action parses into something renderable', () {
      // The envelope must always be enough: no action may blow up on an empty
      // payload, which is what an older row or a stripped detail looks like.
      for (final action in AuditAction.values) {
        expect(
          () => AuditDetail.parse(action, const <String, dynamic>{}),
          returnsNormally,
          reason: action.wire,
        );
      }
    });
  });
}
