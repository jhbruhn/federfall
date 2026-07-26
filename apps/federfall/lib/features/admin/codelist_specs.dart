import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';

/// The org's diagnosis vocabulary — the only list with a description, a
/// notifiable flag and a contagious flag on top of the shared
/// `{label, active}` shape.
final conditionsCodelistSpec = CodelistSpec<Condition>(
  watchList: (ref) => ref.watch(conditionsProvider),
  refresh: (ref) => ref.invalidate(conditionsProvider),
  repository: (ref) => ref.read(conditionsRepositoryProvider.future),
  id: (c) => c.id,
  label: (c) => c.label,
  active: (c) => c.active,
  description: (c) => c.description,
  notifiable: (c) => c.isNotifiable,
  contagious: (c) => c.isContagious,
  tileIcon: Icons.label_outline,
  emptyIcon: Icons.checklist_outlined,
  title: (l10n) => l10n.conditionsAdminTitle,
  emptyMessage: (l10n) => l10n.conditionsAdminEmpty,
  newTitle: (l10n) => l10n.conditionCodelistNewTitle,
  editTitle: (l10n) => l10n.conditionCodelistEditTitle,
  deleteAction: (l10n) => l10n.conditionCodelistDeleteAction,
  deleteConfirm: (l10n, label) => l10n.conditionCodelistDeleteConfirm(label),
  activeHelp: (l10n) => l10n.conditionActiveHelp,
  countReferences: (ref, c) async {
    final repo = await ref.read(caseConditionsRepositoryProvider.future);
    return repo.countForCondition(c.id);
  },
  inUse: (l10n, count) => l10n.conditionCodelistInUse(count),
);

/// The org's reasons-for-admission vocabulary.
final admissionReasonsCodelistSpec = CodelistSpec<AdmissionReason>(
  watchList: (ref) => ref.watch(admissionReasonsProvider),
  refresh: (ref) => ref.invalidate(admissionReasonsProvider),
  repository: (ref) => ref.read(admissionReasonsRepositoryProvider.future),
  id: (r) => r.id,
  label: (r) => r.label,
  active: (r) => r.active,
  tileIcon: Icons.label_outline,
  emptyIcon: Icons.checklist_outlined,
  title: (l10n) => l10n.admissionReasonsAdminTitle,
  emptyMessage: (l10n) => l10n.admissionReasonsAdminEmpty,
  newTitle: (l10n) => l10n.admissionReasonCodelistNewTitle,
  editTitle: (l10n) => l10n.admissionReasonCodelistEditTitle,
  deleteAction: (l10n) => l10n.admissionReasonCodelistDeleteAction,
  deleteConfirm: (l10n, label) =>
      l10n.admissionReasonCodelistDeleteConfirm(label),
  activeHelp: (l10n) => l10n.admissionReasonActiveHelp,
  countReferences: (ref, r) async {
    final repo = await ref.read(casesRepositoryProvider.future);
    return repo.countForAdmissionReason(r.id);
  },
  inUse: (l10n, count) => l10n.admissionReasonCodelistInUse(count),
);

/// The org's marking vocabulary (ring kinds, microchip, temporary markers…).
final markingTypesCodelistSpec = CodelistSpec<MarkingType>(
  watchList: (ref) => ref.watch(markingTypesProvider),
  refresh: (ref) => ref.invalidate(markingTypesProvider),
  repository: (ref) => ref.read(markingTypesRepositoryProvider.future),
  id: (t) => t.id,
  label: (t) => t.label,
  active: (t) => t.active,
  tileIcon: Icons.sell_outlined,
  emptyIcon: Icons.sell_outlined,
  title: (l10n) => l10n.markingTypesAdminTitle,
  emptyMessage: (l10n) => l10n.markingTypesAdminEmpty,
  newTitle: (l10n) => l10n.markingTypeCodelistNewTitle,
  editTitle: (l10n) => l10n.markingTypeCodelistEditTitle,
  deleteAction: (l10n) => l10n.markingTypeCodelistDeleteAction,
  deleteConfirm: (l10n, label) => l10n.markingTypeCodelistDeleteConfirm(label),
  activeHelp: (l10n) => l10n.markingTypeActiveHelp,
  countReferences: (ref, t) async {
    final repo = await ref.read(markingsRepositoryProvider.future);
    return repo.countForType(t.id);
  },
  inUse: (l10n, count) => l10n.markingTypeCodelistInUse(count),
  // The only list whose referencing relation (`markings.type`) is required —
  // PocketBase rejects the delete while any marking uses the type.
  deleteBlockedWhenInUse: true,
);

/// The org's routes-of-administration vocabulary (oral, subcutaneous…).
final medicationRoutesCodelistSpec = CodelistSpec<MedicationRoute>(
  watchList: (ref) => ref.watch(medicationRoutesProvider),
  refresh: (ref) => ref.invalidate(medicationRoutesProvider),
  repository: (ref) => ref.read(medicationRoutesRepositoryProvider.future),
  id: (r) => r.id,
  label: (r) => r.label,
  active: (r) => r.active,
  tileIcon: Icons.label_outline,
  emptyIcon: Icons.medication_outlined,
  title: (l10n) => l10n.medicationRoutesAdminTitle,
  emptyMessage: (l10n) => l10n.medicationRoutesAdminEmpty,
  newTitle: (l10n) => l10n.medicationRouteCodelistNewTitle,
  editTitle: (l10n) => l10n.medicationRouteCodelistEditTitle,
  deleteAction: (l10n) => l10n.medicationRouteCodelistDeleteAction,
  deleteConfirm: (l10n, label) =>
      l10n.medicationRouteCodelistDeleteConfirm(label),
  activeHelp: (l10n) => l10n.medicationRouteActiveHelp,
  // Three collections point at a route: the prescription, every dose logged
  // against it, and the drug catalogue. Counted concurrently and summed — the
  // dialog reports one number for "records that would lose this route".
  countReferences: (ref, r) async {
    final prescriptions = await ref.read(medicationsRepositoryProvider.future);
    final doses = await ref.read(
      medicationAdministrationsRepositoryProvider.future,
    );
    final products = await ref.read(
      medicationProductsRepositoryProvider.future,
    );
    final counts = await Future.wait([
      prescriptions.countForRoute(r.id),
      doses.countForRoute(r.id),
      products.countForRoute(r.id),
    ]);
    return counts.reduce((a, b) => a + b);
  },
  inUse: (l10n, count) => l10n.medicationRouteCodelistInUse(count),
);
