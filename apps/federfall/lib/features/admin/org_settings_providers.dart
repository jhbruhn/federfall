import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'org_settings_providers.g.dart';

/// Settings-JSON key holding the finder-PII retention window in months
/// (DSGVO/GDPR; default 24 = two years). The automated purge that consumes it
/// is FED-8.1; this surfaces the value so a supervisor can configure it.
const finderRetentionMonthsKey = 'finderRetentionMonths';

/// Default finder-PII retention if the org hasn't set one (two years).
const defaultFinderRetentionMonths = 24;

/// Settings-JSON key holding the org-wide default quarantine duration in days,
/// used to prefill the intake form and as the backend hook's fallback when a
/// case is created without an explicit quarantine.
const quarantineDefaultDaysKey = 'quarantineDefaultDays';

/// Default quarantine duration if the org hasn't set one (two weeks). Mirrors
/// the backend hook fallback in pb_hooks/main.pb.js.
const defaultQuarantineDays = 14;

/// Reads [quarantineDefaultDaysKey] from the given org settings, coercing the
/// JSON number and falling back to [defaultQuarantineDays] when unset/invalid.
int quarantineDefaultDaysOf(Map<String, dynamic> settings) =>
    switch (settings[quarantineDefaultDaysKey]) {
      final int v when v > 0 => v,
      final num v when v > 0 => v.toInt(),
      _ => defaultQuarantineDays,
    };

/// The org-wide default quarantine duration in days for the signed-in user,
/// used to prefill the intake form. Falls back to [defaultQuarantineDays].
@riverpod
Future<int> orgQuarantineDefaultDays(Ref ref) async {
  final org = await ref.watch(currentOrganisationProvider.future);
  return quarantineDefaultDaysOf(org.settings);
}

/// The signed-in user's own organisation (the tenancy boundary). Supervisors
/// edit it from the org settings screen (UX Phase A).
@riverpod
Future<Organisation> currentOrganisation(Ref ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final orgId = user?.org;
  if (orgId == null || orgId.isEmpty) {
    throw const RepositoryException('the current user has no organisation');
  }
  final repo = await ref.watch(organisationsRepositoryProvider.future);
  return repo.getOne(orgId);
}
