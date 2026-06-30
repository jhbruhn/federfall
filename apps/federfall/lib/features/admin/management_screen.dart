import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/admin/admission_reasons_admin_screen.dart';
import 'package:federfall/features/admin/conditions_admin_screen.dart';
import 'package:federfall/features/admin/marking_types_admin_screen.dart';
import 'package:federfall/features/admin/medication_routes_admin_screen.dart';
import 'package:federfall/features/admin/org_settings_screen.dart';
import 'package:federfall/features/admin/team_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One admin section reachable from the hub.
enum _AdminSection {
  team(Icons.group_outlined, AppRoutes.manageTeam),
  orgSettings(Icons.business_outlined, AppRoutes.orgSettings),
  conditions(Icons.checklist_outlined, AppRoutes.conditionsAdmin),
  admissionReasons(Icons.flight_land_outlined, AppRoutes.admissionReasonsAdmin),
  markingTypes(Icons.sell_outlined, AppRoutes.markingTypesAdmin),
  medicationRoutes(
    Icons.medication_outlined,
    AppRoutes.medicationRoutesAdmin,
  );

  const _AdminSection(this.icon, this.route);

  final IconData icon;
  final String route;

  String title(AppLocalizations l10n) => switch (this) {
    _AdminSection.team => l10n.manageTeamTitle,
    _AdminSection.orgSettings => l10n.orgSettingsTitle,
    _AdminSection.conditions => l10n.conditionsAdminTitle,
    _AdminSection.admissionReasons => l10n.admissionReasonsAdminTitle,
    _AdminSection.markingTypes => l10n.markingTypesAdminTitle,
    _AdminSection.medicationRoutes => l10n.medicationRoutesAdminTitle,
  };

  Widget screen() => switch (this) {
    _AdminSection.team => const TeamScreen(),
    _AdminSection.orgSettings => const OrgSettingsScreen(),
    _AdminSection.conditions => const ConditionsAdminScreen(),
    _AdminSection.admissionReasons => const AdmissionReasonsAdminScreen(),
    _AdminSection.markingTypes => const MarkingTypesAdminScreen(),
    _AdminSection.medicationRoutes => const MedicationRoutesAdminScreen(),
  };
}

/// Management hub (federfall-dri): one home for the org's admin surfaces — the
/// team roster, organisation settings and the condition code-list. (Reporting
/// is reached from the account menu / rail, not here.)
///
/// On wide screens it lays the hub and the selected section out side-by-side,
/// holding the selection itself (federfall-zbe) rather than via go_router — so
/// this stays a single pushed route whose back-to-app affordance never
/// disappears. On narrow screens it pushes the section's own full-screen route.
///
/// Supervisor-gated; re-checks the role so a typed-in URL degrades gracefully.
/// The real boundary remains the server API rules.
class ManagementScreen extends ConsumerStatefulWidget {
  const ManagementScreen({super.key});

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  _AdminSection? _selected;

  void _open(_AdminSection section) {
    if (context.isExpanded) {
      setState(() => _selected = section);
    } else {
      // Narrow: the section is its own full-screen route, with a back button.
      unawaited(context.push(section.route));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final expanded = context.isExpanded;
    // The hub is its own Scaffold so it carries the "Administration" app bar
    // (and, since this screen is pushed over the app, the back-to-app button) —
    // mirroring the list pane of the cases/animals/aviaries surfaces.
    final hub = Scaffold(
      appBar: AppBar(title: Text(l10n.adminTitle)),
      body: ListView(
        children: [
          for (final section in _AdminSection.values)
            _HubTile(
              icon: section.icon,
              title: section.title(l10n),
              // Only the wide layout keeps a persistent selection to highlight.
              selected: expanded && section == _selected,
              onTap: () => _open(section),
            ),
        ],
      ),
    );

    if (!expanded) return hub;

    // Wide: hub on the left, the selected section (its own Scaffold) or the
    // empty-selection placeholder on the right — no outer app bar, so it reads
    // exactly like the other two-pane surfaces.
    return Row(
      children: [
        SizedBox(width: kListPaneWidth, child: hub),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected?.screen() ??
              DetailPanePlaceholder(
                icon: Icons.manage_accounts_outlined,
                message: l10n.adminSelectSection,
              ),
        ),
      ],
    );
  }
}

/// One hub row: a labelled icon that opens its section (in the side pane on
/// wide screens, or full-screen on narrow ones), highlighted while active.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    selected: selected,
    onTap: onTap,
  );
}
