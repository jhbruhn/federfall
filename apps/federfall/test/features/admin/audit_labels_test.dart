import 'package:federfall/features/admin/audit/audit_labels.dart';
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
      expect(
        line.facts.single.value,
        contains(de.dispositionReleased),
        reason: 'the outcome must be visible, it is the point of the row',
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

      expect(line.facts.single.value, contains(de.auditChangeCleared('4')));
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
}
