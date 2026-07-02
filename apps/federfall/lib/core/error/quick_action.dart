import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Runs a one-tap quick action (worklist mark-done, quarantine end-now, tile
/// or code-list delete …) and surfaces a failure as the standard
/// [errorMessage] snackbar.
///
/// The form sheets show repository errors inline, but these shortcuts have no
/// surface of their own — without this, a failed call (offline, server error)
/// was completely silent. Messenger and l10n are snapshotted before the await
/// so a tile disposed mid-flight can still report.
Future<void> runQuickAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Object catch (error, stackTrace) {
    reportCaughtError(error, stackTrace);
    messenger.showSnackBar(
      SnackBar(content: Text(errorMessage(l10n, error))),
    );
  }
}
