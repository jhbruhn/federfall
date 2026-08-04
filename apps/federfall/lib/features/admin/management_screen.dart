import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/admin/audit/audit_screen.dart';
import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/features/admin/codelist_specs.dart';
import 'package:federfall/features/admin/medication_products_screen.dart';
import 'package:federfall/features/admin/org_settings_screen.dart';
import 'package:federfall/features/admin/team_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/back_or_home.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The groups the hub sorts its sections into. A flat list of eight entries
/// reads as one undifferentiated pile; grouping says *what kind* of setting
/// each one is before the user has to read every label.
enum AdminSectionGroup {
  /// Who the organisation is and who may act for it.
  organisation,

  /// The pick-lists the rest of the app offers — what a team may choose from.
  codelists,

  /// What the system recorded about itself.
  oversight;

  String title(AppLocalizations l10n) => switch (this) {
    AdminSectionGroup.organisation => l10n.adminGroupOrganisation,
    AdminSectionGroup.codelists => l10n.adminGroupCodelists,
    AdminSectionGroup.oversight => l10n.adminGroupOversight,
  };

  /// The sections in this group, in declaration order.
  Iterable<AdminSection> get sections =>
      AdminSection.values.where((s) => s.group == this);
}

/// One admin section reachable from the hub. Carries everything the hub tile
/// and the router need, so the two cannot drift: the router declares one child
/// route per value rather than repeating the list.
///
/// Declared grouped, so [AdminSectionGroup.sections] is an in-order filter and
/// the hub's reading order is this file's.
enum AdminSection {
  team(
    AdminSectionGroup.organisation,
    Icons.group_outlined,
    AppRoutes.manageTeam,
    AppRoutes.manageTeamSegment,
  ),
  orgSettings(
    AdminSectionGroup.organisation,
    Icons.business_outlined,
    AppRoutes.orgSettings,
    AppRoutes.orgSettingsSegment,
  ),
  conditions(
    AdminSectionGroup.codelists,
    Icons.checklist_outlined,
    AppRoutes.conditionsAdmin,
    AppRoutes.conditionsAdminSegment,
  ),
  admissionReasons(
    AdminSectionGroup.codelists,
    Icons.flight_land_outlined,
    AppRoutes.admissionReasonsAdmin,
    AppRoutes.admissionReasonsAdminSegment,
  ),
  markingTypes(
    AdminSectionGroup.codelists,
    Icons.sell_outlined,
    AppRoutes.markingTypesAdmin,
    AppRoutes.markingTypesAdminSegment,
  ),
  medicationRoutes(
    AdminSectionGroup.codelists,
    Icons.medication_outlined,
    AppRoutes.medicationRoutesAdmin,
    AppRoutes.medicationRoutesAdminSegment,
  ),
  medicationProducts(
    AdminSectionGroup.codelists,
    Icons.inventory_2_outlined,
    AppRoutes.medicationProductsAdmin,
    AppRoutes.medicationProductsAdminSegment,
  ),
  audit(
    AdminSectionGroup.oversight,
    Icons.history_toggle_off,
    AppRoutes.audit,
    AppRoutes.auditSegment,
  );

  const AdminSection(this.group, this.icon, this.route, this.segment);

  /// The hub group this section is listed under.
  final AdminSectionGroup group;

  final IconData icon;

  /// Absolute path, for navigating to this section.
  final String route;

  /// Last path component, for declaring it as a child of the hub route.
  final String segment;

  String title(AppLocalizations l10n) => switch (this) {
    AdminSection.team => l10n.manageTeamTitle,
    AdminSection.orgSettings => l10n.orgSettingsTitle,
    AdminSection.conditions => l10n.conditionsAdminTitle,
    AdminSection.admissionReasons => l10n.admissionReasonsAdminTitle,
    AdminSection.markingTypes => l10n.markingTypesAdminTitle,
    AdminSection.medicationRoutes => l10n.medicationRoutesAdminTitle,
    AdminSection.medicationProducts => l10n.medProductsAdminTitle,
    AdminSection.audit => l10n.auditTitle,
  };

  /// One line on what this section governs. The titles are short nouns
  /// ("Marking types"), which say what a screen is called but not what
  /// choosing it changes elsewhere in the app.
  String subtitle(AppLocalizations l10n) => switch (this) {
    AdminSection.team => l10n.manageTeamSubtitle,
    AdminSection.orgSettings => l10n.orgSettingsSubtitle,
    AdminSection.conditions => l10n.conditionsAdminSubtitle,
    AdminSection.admissionReasons => l10n.admissionReasonsAdminSubtitle,
    AdminSection.markingTypes => l10n.markingTypesAdminSubtitle,
    AdminSection.medicationRoutes => l10n.medicationRoutesAdminSubtitle,
    AdminSection.medicationProducts => l10n.medProductsAdminSubtitle,
    AdminSection.audit => l10n.auditSubtitle,
  };

  Widget screen() => switch (this) {
    AdminSection.team => const TeamScreen(),
    AdminSection.orgSettings => const OrgSettingsScreen(),
    AdminSection.conditions => CodelistAdminScreen(
      spec: conditionsCodelistSpec,
    ),
    AdminSection.admissionReasons => CodelistAdminScreen(
      spec: admissionReasonsCodelistSpec,
    ),
    AdminSection.markingTypes => CodelistAdminScreen(
      spec: markingTypesCodelistSpec,
    ),
    AdminSection.medicationRoutes => CodelistAdminScreen(
      spec: medicationRoutesCodelistSpec,
    ),
    AdminSection.medicationProducts => const MedicationProductsScreen(),
    AdminSection.audit => const AuditScreen(),
  };
}

/// Management hub (federfall-dri): one home for the org's admin surfaces — the
/// team roster, organisation settings and the condition code-list. (Reporting
/// is reached from the account menu / rail, not here.)
///
/// Every section has a real URL: [section] comes from the route, not from
/// internal state, so a section is linkable, survives a reload, and the address
/// bar tracks where the user actually is. This is still NOT a go_router
/// two-pane (federfall-zbe) — the hub renders the section itself, in the right
/// pane on wide screens and full-screen on narrow ones, so `/admin` stays one
/// ordinary route whose back-to-app affordance never disappears. Declaring the
/// sections as *children* of `/admin` is what gives a directly-opened section
/// URL the hub beneath it, and so a working back button.
///
/// Supervisor-gated; re-checks the role so a typed-in URL degrades gracefully.
/// The real boundary remains the server API rules.
class ManagementScreen extends ConsumerWidget {
  const ManagementScreen({this.section, super.key});

  /// The section to show, or `null` for the bare hub.
  final AdminSection? section;

  /// Opens [target]. `go`, never `push`: go_router does not update the address
  /// bar for an imperative push, so a pushed section left the URL pointing at
  /// the hub. Because the sections are declared as children of `/admin`, `go`
  /// also puts the hub page beneath the section for free — that is what makes
  /// the narrow back arrow work — and going from one section to a sibling
  /// swaps the child rather than stacking a third page.
  void _open(BuildContext context, AdminSection target) =>
      context.go(target.route);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // Narrow: the section owns the whole screen. Its own app bar carries the
    // back button to the hub page below it in the stack.
    if (!expanded && section != null) return section!.screen();

    // The hub is its own Scaffold so it carries the "Administration" app bar
    // (and, since this screen sits over the app, the back-to-app button) —
    // mirroring the list pane of the cases/animals/aviaries surfaces.
    final hub = Scaffold(
      appBar: AppBar(
        // "Leave administration", not "pop one page". The hub is shown either
        // as the whole screen (narrow) or as the left pane beside a section
        // (wide), so this arrow always means leaving the hub. On wide that
        // deliberately skips the deselected in-between state a plain pop would
        // land on: the hub is on screen either way, so popping there reads as
        // nothing having happened. A cold open has nothing beneath it to pop
        // at all, which is the other half of the same fix.
        leading: BackButton(onPressed: () => context.go(AppRoutes.home)),
        title: Text(l10n.adminTitle),
      ),
      body: ListView(
        children: [
          for (final group in AdminSectionGroup.values) ...[
            _GroupHeader(title: group.title(l10n)),
            for (final s in group.sections)
              _HubTile(
                icon: s.icon,
                title: s.title(l10n),
                subtitle: s.subtitle(l10n),
                // Only the wide layout keeps a persistent selection to
                // highlight.
                selected: expanded && s == section,
                onTap: () => _open(context, s),
              ),
          ],
        ],
      ),
    );

    if (!expanded) return BackOrHomeScope(child: hub);

    // Wide: hub on the left, the selected section (its own Scaffold) or the
    // empty-selection placeholder on the right — no outer app bar, so it reads
    // exactly like the other two-pane surfaces.
    return BackOrHomeScope(
      child: Row(
        children: [
          SizedBox(width: kListPaneWidth, child: hub),
          const VerticalDivider(width: 1),
          Expanded(
            child:
                section?.screen() ??
                DetailPanePlaceholder(
                  icon: Icons.manage_accounts_outlined,
                  message: l10n.adminSelectSection,
                ),
          ),
        ],
      ),
    );
  }
}

/// Heading over one group of hub rows.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.lg,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// One hub row: a labelled icon over a line of explanation, opening its section
/// (in the side pane on wide screens, or full-screen on narrow ones),
/// highlighted while active.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    selected: selected,
    onTap: onTap,
  );
}
