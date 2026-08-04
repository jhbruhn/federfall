import 'dart:io';

import 'package:federfall/features/admin/audit/audit_labels.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

AuditEvent _event({
  AuditAction? action = AuditAction.caseUpdated,
  String? rawAction,
  AuditDetail detail = const AuditDetail.none(),
  AuditActorKind actorKind = AuditActorKind.user,
  AuditSeverity severity = AuditSeverity.info,
  String actorLabel = 'Anna Karin',
  String actorId = 'usr_anna',
  String subjectLabel = '2026-014',
  String subjectCollection = 'cases',
  List<AuditFieldChange> changes = const [],
  String? ip,
  String caseLabel = '',
}) => AuditEvent(
  id: 'audt1',
  rawAction: rawAction ?? action?.wire ?? 'x.y',
  action: action,
  at: DateTime.utc(2026, 8, 4, 9),
  actorKind: actorKind,
  severity: severity,
  detail: detail,
  actorLabel: actorLabel,
  actorId: actorId,
  subjectLabel: subjectLabel,
  subjectCollection: subjectCollection,
  changes: changes,
  ip: ip,
  caseLabel: caseLabel,
);

void main() {
  late AppLocalizations de;
  late AppLocalizations en;

  setUpAll(() async {
    // In the app the localization delegates load these; a pure unit test has
    // to ask for them itself before any DateFormat runs.
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
    de = await AppLocalizations.delegate.load(const Locale('de'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('every action is renderable', () {
    test('in both languages, from the envelope alone', () {
      // The contract the whole design rests on: an event with no detail and no
      // changes still produces a usable line. If this fails, some action has a
      // title only its payload could supply.
      for (final action in AuditAction.values) {
        for (final l10n in [de, en]) {
          final line = auditLine(l10n, _event(action: action));
          expect(line.title, isNotEmpty, reason: action.wire);
          expect(
            line.title,
            isNot(contains(action.wire)),
            reason: '${action.wire} has no translated title, only its raw name',
          );
        }
      }
    });

    test('German and English titles actually differ where they should', () {
      // Guards against a copy-paste that left the English file German. A few
      // legitimately coincide (System, Format), so this is a proportion.
      final same = AuditAction.values
          .where(
            (a) =>
                auditActionTitle(de, a, a.wire) ==
                auditActionTitle(en, a, a.wire),
          )
          .length;
      expect(same, lessThan(AuditAction.values.length ~/ 4));
    });
  });

  group('unknown things degrade instead of blanking', () {
    test('an unknown action names itself', () {
      final line = auditLine(
        de,
        _event(action: null, rawAction: 'gerbil.teleported'),
      );

      expect(line.title, contains('gerbil.teleported'));
      expect(line.subtitle, '2026-014', reason: 'the envelope still renders');
    });

    test('an unknown field falls back to the column name', () {
      expect(auditFieldLabel(de, 'cases', 'wing_span_cm'), 'wing_span_cm');
    });

    test('a timestamp is formatted, not shown as PocketBase stored it', () {
      final shown = auditValueLabel(
        de,
        'dispositions',
        'disposed_at',
        '2026-06-21 09:00:00.000Z',
      );

      expect(shown, isNot(contains('T')));
      expect(shown, isNot(contains('.000Z')));
      expect(shown, contains('2026'));
    });

    test('a field that only looks like a date is left alone', () {
      expect(auditValueLabel(de, 'cases', 'notes', '2026-06-21'), '2026-06-21');
    });

    test('the outcome type is translated, not shown as its wire value', () {
      // The reason it is stored as 'died' rather than as a label: the server
      // must not decide which language the log is read in.
      expect(
        auditValueLabel(de, 'dispositions', 'type', 'died'),
        de.dispositionDied,
      );
      expect(
        auditValueLabel(en, 'dispositions', 'type', 'died'),
        en.dispositionDied,
      );
    });

    test('an unknown enum value falls back to the stored string', () {
      expect(
        auditValueLabel(de, 'cases', 'status', 'quantum_superposition'),
        'quantum_superposition',
      );
    });

    test(
      'a known enum value is shown the way the rest of the app shows it',
      () {
        expect(
          auditValueLabel(de, 'cases', 'status', 'in_care'),
          de.caseStatusInCare,
        );
        expect(
          auditValueLabel(de, 'users', 'role', 'supervisor'),
          de.userRoleSupervisor,
        );
      },
    );
  });

  group('actor', () {
    test('a person is named', () {
      expect(auditActorName(de, _event()), 'Anna Karin');
    });

    test('a machine is not pretended to be a person', () {
      expect(
        auditActorName(
          de,
          _event(actorKind: AuditActorKind.system, actorLabel: ''),
        ),
        de.auditActorSystem,
      );
      expect(
        auditActorName(
          de,
          _event(actorKind: AuditActorKind.cron, actorLabel: ''),
        ),
        de.auditActorCron,
      );
    });

    test('a deleted member is still named from the snapshot', () {
      // The reason the log stores a label instead of a relation.
      expect(
        auditActorName(de, _event(actorLabel: 'Weg Gegangen')),
        'Weg Gegangen',
      );
    });
  });

  group('changes', () {
    test('a redacted change says so and shows no value', () {
      final text = auditChangeText(
        de,
        'users',
        const AuditFieldChange(field: 'password', redacted: true),
      );

      expect(text, de.auditChangeRedacted);
      expect(text, isNot(contains('→')));
    });

    test('an old and a new value are shown as a transition', () {
      final text = auditChangeText(
        de,
        'cases',
        const AuditFieldChange(
          field: 'status',
          from: 'in_care',
          to: 'disposed',
        ),
      );

      expect(text, contains(de.caseStatusInCare));
      expect(text, contains(de.caseStatusDisposed));
    });

    test('a first value reads as set, not as a transition from nothing', () {
      final text = auditChangeText(
        de,
        'animals',
        const AuditFieldChange(field: 'name', to: 'Pip'),
      );

      expect(text, de.auditChangeSet('Pip'));
    });

    test('a cleared value says what it was', () {
      final text = auditChangeText(
        de,
        'animals',
        const AuditFieldChange(field: 'name', from: 'Pip'),
      );

      expect(text, de.auditChangeCleared('Pip'));
    });

    test('a disposition records what it DID to the case and the bird', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.dispositionCreated,
          subjectCollection: 'dispositions',
          subjectLabel: '',
          detail: const AuditDetail.disposition(
            caseStatus: CaseStatus.disposed,
            lifetimeStatus: LifetimeStatus.deceased,
          ),
        ),
      );

      expect(
        line.facts,
        containsAll([
          AuditFact(de.auditFactCaseNow, de.caseStatusDisposed),
          AuditFact(de.auditFactAnimalNow, de.lifetimeStatusDeceased),
        ]),
      );
    });

    test('deleting the last disposition shows the case reopening', () {
      // The reversal was invisible before: the case quietly went back to
      // in_care and nothing said so.
      final line = auditLine(
        de,
        _event(
          action: AuditAction.dispositionDeleted,
          subjectCollection: 'dispositions',
          subjectLabel: '',
          detail: const AuditDetail.disposition(
            caseStatus: CaseStatus.inCare,
            lifetimeStatus: LifetimeStatus.inCare,
          ),
        ),
      );

      expect(
        line.facts,
        contains(AuditFact(de.auditFactCaseNow, de.caseStatusInCare)),
      );
    });

    test('a create reads as values being set, not as a diff from nothing', () {
      // federfall-9k2g: creates carry their content in the same `changes`
      // shape an update uses, so one renderer covers all three verbs.
      final line = auditLine(
        de,
        _event(
          action: AuditAction.dispositionCreated,
          subjectCollection: 'dispositions',
          subjectLabel: '',
          changes: const [AuditFieldChange(field: 'type', to: 'released')],
        ),
      );

      expect(line.title, de.auditActionDispositionCreated);
      // Not "1 Feld geändert: Ausgang: gesetzt auf …" — nothing changed, an
      // outcome was recorded.
      expect(
        line.facts.single,
        AuditFact(de.auditFieldType, de.dispositionReleased),
      );
      expect(
        line.facts.single.value,
        isNot(contains(de.auditChangeSet(''))),
      );
    });

    test('a delete reads as what was destroyed', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.eggRecordDeleted,
          subjectCollection: 'egg_records',
          subjectLabel: '',
          changes: const [AuditFieldChange(field: 'count', from: '4')],
        ),
      );

      expect(line.facts.single, AuditFact(de.auditFieldCount, '4'));
    });

    test('a real update still reads as a transition', () {
      final line = auditLine(
        de,
        _event(
          changes: const [
            AuditFieldChange(field: 'status', from: 'in_care', to: 'disposed'),
          ],
        ),
      );

      expect(line.facts.single.label, de.auditChangeSummary(1));
      expect(line.facts.single.value, contains(de.caseStatusInCare));
      expect(line.facts.single.value, contains(de.caseStatusDisposed));
    });

    test('the line summarises how many fields changed', () {
      final line = auditLine(
        de,
        _event(
          changes: const [
            AuditFieldChange(field: 'status', from: 'in_care', to: 'disposed'),
            AuditFieldChange(field: 'name', to: 'Pip'),
          ],
        ),
      );

      expect(
        line.facts.map((f) => f.label),
        contains(de.auditChangeSummary(2)),
      );
    });
  });

  group('details become facts', () {
    test('an intake shows the species', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseIntake,
          detail: const AuditDetail.caseIntake(
            species: 'Türkentaube',
            reidentified: true,
            hasFinder: true,
          ),
        ),
      );

      expect(line.facts.map((f) => f.value), contains('Türkentaube'));
      expect(
        line.facts.map((f) => f.label),
        contains(de.auditFactReidentified),
      );
    });

    test('a role change shows both roles by their app names', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.userRoleChanged,
          detail: const AuditDetail.roleChanged(
            from: UserRole.carer,
            to: UserRole.supervisor,
          ),
        ),
      );

      expect(line.facts.map((f) => f.value), contains(de.userRoleCarer));
      expect(line.facts.map((f) => f.value), contains(de.userRoleSupervisor));
    });

    test('a failed login is described as a window, never as a count', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.authLoginFailed,
          detail: const AuditDetail.loginFailed(windowMinutes: 5),
        ),
      );

      expect(
        line.facts.single.label,
        de.auditFactFailureWindow(5),
        reason: 'one row stands for a window of failures, not one attempt',
      );
    });

    test('an all-time report reads as all-time, not as a missing year', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.reportExported,
          detail: const AuditDetail.reportExported(format: 'csv'),
        ),
      );

      expect(line.facts.map((f) => f.value), contains(de.auditFactPeriodAll));
      expect(line.facts.map((f) => f.value), contains('CSV'));
    });

    test('an unknown payload adds no facts but does not break the line', () {
      final line = auditLine(
        de,
        _event(detail: const AuditDetail.unknown({'weird': true})),
      );

      expect(line.facts, isEmpty);
      expect(line.title, isNotEmpty);
    });

    test('the client IP only shows when it was recorded', () {
      expect(auditLine(de, _event()).facts, isEmpty);
      expect(
        auditLine(de, _event(ip: '10.0.0.4')).facts.map((f) => f.value),
        contains('10.0.0.4'),
      );
    });
  });

  group('the case a row belongs to', () {
    test('is named by its number', () {
      final line = auditLine(
        de,
        _event(subjectLabel: '', caseLabel: '2026-014'),
      );

      expect(
        line.facts,
        contains(AuditFact(de.auditFactCase, '2026-014')),
      );
    });

    test('is not repeated when the case IS the subject', () {
      final line = auditLine(
        de,
        _event(subjectLabel: '2026-099', caseLabel: '2026-099'),
      );

      expect(line.subtitle, '2026-099');
      expect(line.facts.map((f) => f.label), isNot(contains(de.auditFactCase)));
    });

    test('a row belonging to no case says nothing about one', () {
      expect(auditLine(de, _event()).facts, isEmpty);
    });
  });

  test('a security event gets the security icon whatever its domain', () {
    final line = auditLine(
      de,
      _event(
        action: AuditAction.userRoleChanged,
        severity: AuditSeverity.security,
      ),
    );

    expect(line.icon, Icons.shield_outlined);
  });

  // federfall-ybua.1 — a person is named, never numbered. These two actions
  // carried a bare user id where the name was already resolved one field away.
  group('a person in a payload is named', () {
    test('a handoff names who took the case on', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseHandoff,
          subjectLabel: 'Bernd Weber',
          subjectCollection: 'placements',
          detail: const AuditDetail.caseHandoff(
            to: 'usr_bernd',
            toLabel: 'Bernd Weber',
            from: 'usr_anna',
            fromLabel: 'Anna Karin',
          ),
        ),
      );

      expect(
        line.facts,
        contains(AuditFact(de.auditFactHandoffTo, 'Bernd Weber')),
      );
      expect(
        line.facts.map((f) => f.value).join(' '),
        isNot(contains('usr_')),
        reason: 'no id may reach the screen when a label was recorded',
      );
    });

    test('who handed it over is not repeated when it was the actor', () {
      // from_user is the acting carer on every handoff made through the app,
      // and the actor is already on the line above.
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseHandoff,
          subjectCollection: 'placements',
          detail: const AuditDetail.caseHandoff(
            to: 'usr_bernd',
            toLabel: 'Bernd Weber',
            from: 'usr_anna',
            fromLabel: 'Anna Karin',
          ),
        ),
      );

      expect(
        line.facts.map((f) => f.label),
        isNot(contains(de.auditFactHandoffFrom)),
      );
    });

    test('a share names the member it was shared with', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseShared,
          subjectCollection: 'case_shares',
          subjectLabel: 'Bernd Weber',
          detail: const AuditDetail.caseShare(
            withUser: 'usr_bernd',
            withLabel: 'Bernd Weber',
            access: ShareAccess.read,
          ),
        ),
      );

      expect(
        line.facts,
        contains(AuditFact(de.auditFactSharedWith, 'Bernd Weber')),
      );
    });

    test('an unlabelled row still shows the id rather than nothing', () {
      // Rows written before the server recorded the names. Illegible, but a
      // blank would be worse — and it is what the fallback exists for.
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseShared,
          subjectCollection: 'case_shares',
          detail: const AuditDetail.caseShare(withUser: 'usr_bernd'),
        ),
      );

      expect(
        line.facts,
        contains(AuditFact(de.auditFactSharedWith, 'usr_bernd')),
      );
    });

    test('the subject label is dropped when a fact already names it', () {
      // Otherwise the recipient appears twice: once labelled, once as a bare
      // name in the subtitle with nothing saying what it is.
      final line = auditLine(
        de,
        _event(
          action: AuditAction.caseShared,
          subjectCollection: 'case_shares',
          subjectLabel: 'Bernd Weber',
          detail: const AuditDetail.caseShare(
            withUser: 'usr_bernd',
            withLabel: 'Bernd Weber',
          ),
        ),
      );

      expect(line.subtitle, isNull);
    });
  });

  // federfall-ybua.2 — a relation's stored value is an id; the server snapshots
  // what it pointed at, and that is what has to reach the screen.
  group('a relation change reads as a name', () {
    const move = AuditFieldChange(
      field: 'current_aviary',
      from: 'avy_quarantine',
      to: 'avy_flight',
      fromLabel: 'Quarantäne 1',
      toLabel: 'Freiflug',
    );

    test('both sides of a move show the aviary, not its id', () {
      expect(
        auditChangeText(de, 'animals', move),
        de.auditChangeArrow('Quarantäne 1', 'Freiflug'),
      );
    });

    test('a snapshotted label is not run through the enum resolution', () {
      // The label is already human text. `status` is the trap: a label reaching
      // CaseStatus.fromWire would fall back to itself today and silently break
      // the day someone names an aviary after a status.
      const relation = AuditFieldChange(
        field: 'status',
        to: 'anything',
        toLabel: 'Freiflug',
      );

      expect(auditChangeSide(de, 'x', relation, newValue: true), 'Freiflug');
    });

    // federfall-g5ap — `cases.admission_reasons` is a MULTI relation, so its
    // stored value is a JSON id array. The server joins the labels it
    // snapshotted for the whole set; the screen must show that and never fall
    // back to the array, which is the shape this shipped in.
    test('a multi-relation shows the joined labels, not the id array', () {
      final line = auditLine(
        de,
        _event(
          changes: const [
            AuditFieldChange(
              field: 'admission_reasons',
              from: '["adr_collision"]',
              to: '["adr_collision","adr_cat"]',
              fromLabel: 'Kollision',
              toLabel: 'Kollision, Katzenangriff',
            ),
          ],
        ),
      );

      expect(
        line.facts,
        contains(
          AuditFact(
            de.auditChangeSummary(1),
            '${de.caseReasonsFieldLabel}: '
            '${de.auditChangeArrow('Kollision', 'Kollision, Katzenangriff')}',
          ),
        ),
      );
      expect(line.facts.map((f) => f.value).join(), isNot(contains('adr_')));
    });

    test('an id with no label still renders, as the id', () {
      const bare = AuditFieldChange(field: 'current_aviary', to: 'avy_flight');

      expect(
        auditChangeText(de, 'animals', bare),
        de.auditChangeSet('avy_flight'),
      );
    });

    test('a create shows the label of what it pointed at', () {
      final line = auditLine(
        de,
        _event(
          action: AuditAction.markingCreated,
          subjectCollection: 'markings',
          changes: const [
            AuditFieldChange(
              field: 'type',
              to: 'mtp_ring',
              toLabel: 'Fußring',
            ),
          ],
        ),
      );

      expect(line.facts, contains(AuditFact(de.markingFieldType, 'Fußring')));
    });
  });

  // federfall-ybua.3 — both label functions take a collection; until now they
  // ignored it, so a column name shared by two collections was rendered as
  // whichever one happened to be written first.
  group('a shared column name is not a shared meaning', () {
    test('type is the outcome on a disposition and the kind on a marking', () {
      expect(auditFieldLabel(de, 'dispositions', 'type'), de.auditFieldType);
      expect(auditFieldLabel(de, 'markings', 'type'), de.markingFieldType);
      expect(
        auditFieldLabel(de, 'markings', 'type'),
        isNot(auditFieldLabel(de, 'dispositions', 'type')),
      );
    });

    test('an exam finding status resolves through its own enum', () {
      expect(
        auditValueLabel(de, 'exam_findings', 'status', 'abnormal'),
        findingStatusLabel(de, FindingStatus.abnormal),
      );
      expect(
        auditValueLabel(de, 'exam_findings', 'status', 'abnormal'),
        isNot('abnormal'),
        reason: 'it fell back to the raw English wire value',
      );
    });

    test('a case status still resolves through CaseStatus', () {
      expect(
        auditValueLabel(de, 'cases', 'status', 'in_care'),
        caseStatusLabel(de, CaseStatus.inCare),
      );
    });
  });

  // federfall-ybua.4 — the fallback to the raw column name is the right safety
  // net for a field nobody has translated. It is the wrong outcome for the
  // fields the server's own allowlist picked as "what this event was about".
  test('every field the server records has a translated label', () {
    // Read from the emitter itself, so a new CONTENT_FIELDS entry cannot ship
    // without a label — the same both-halves pinning as
    // app_theme_fallbacks_test.
    final source = File(
      '../../backend/pocketbase/pb_hooks/lib_audit.js',
    ).readAsStringSync();
    final block = source
        .split('const CONTENT_FIELDS = {')[1]
        .split('\n};')
        .first;
    final fields = RegExp(r'(\w+):\s*\[([^\]]*)\]')
        .allMatches(block)
        .expand(
          (m) => RegExp('"([a-z_]+)"')
              .allMatches(m.group(2)!)
              .map((f) => (collection: m.group(1)!, field: f.group(1)!)),
        )
        .toList();

    expect(fields, isNotEmpty, reason: 'the allowlist could not be read');
    for (final entry in fields) {
      for (final l10n in [de, en]) {
        expect(
          auditFieldLabel(l10n, entry.collection, entry.field),
          isNot(entry.field),
          reason:
              '${entry.collection}.${entry.field} shows its column name in '
              '${l10n.localeName}',
        );
      }
    }
  });

  // federfall-ybua.6 — the topic filter is only usable if every action is
  // reachable through exactly one of them.
  group('topics partition the actions', () {
    test('every action belongs to exactly one topic', () {
      for (final action in AuditAction.values) {
        final owners = AuditTopic.values
            .where((t) => t.actions.contains(action))
            .toList();
        expect(
          owners,
          hasLength(1),
          reason: '${action.wire} belongs to $owners',
        );
      }
    });

    test('no topic is empty, and together they cover the registry', () {
      final covered = AuditTopic.values.expand((t) => t.actions).toSet();
      expect(covered, hasLength(AuditAction.values.length));
      for (final t in AuditTopic.values) {
        expect(t.actions, isNotEmpty, reason: '$t');
      }
    });

    test('each topic is named in both languages', () {
      for (final t in AuditTopic.values) {
        expect(auditTopicLabel(de, t), isNotEmpty);
        expect(auditTopicLabel(en, t), isNotEmpty);
      }
    });
  });
}
