import 'package:federfall/ui/layout/window_size.dart';
import 'package:flutter/material.dart';

/// Opens a modal bottom sheet with the app's standard configuration — scroll
/// controlled, a drag handle, and capped to [kSheetMaxWidth] so it floats
/// centred on wide windows instead of stretching edge-to-edge (it still fills
/// the screen below that width). The one place every create/edit sheet routes
/// through, so the wide-screen treatment stays consistent and lives in a single
/// spot.
///
/// [builder] and the returned `Future<T?>` behave exactly like
/// [showModalBottomSheet]: the content closes itself with
/// `Navigator.pop(context, result)`.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
    builder: builder,
  );
}
