import 'dart:async';

import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps the whole app and reveals one strip while the backend is unreachable.
///
/// Exactly one instance exists, above the router (`MaterialApp.builder`) rather
/// than one per screen. Connectivity is an app-wide fact, so it gets a single
/// place to be stated: the strip never moves between screens, never repeats
/// itself on a screen that already failed to load, and it also covers the
/// routes pushed outside the navigation shell — the intake wizard, admin and
/// login — which is where finding out late actually costs the user something.
///
/// Its counterpart is `AsyncValueView`, which keeps already-loaded data on
/// screen when a *refresh* fails on the network: this strip states the cause
/// once, so the content below it can stay readable instead of being replaced by
/// a full-screen error (federfall-gmnc).
///
/// Only a confirmed offline reading is shown. `onlineStatusProvider` already
/// de-flaps across two probes, so a strip that appears has staying power; the
/// provider's loading and error states render nothing, because not knowing is
/// not the same as being offline.
class OfflineNotice extends ConsumerStatefulWidget {
  const OfflineNotice({required this.child, super.key});

  /// The app below the strip — in practice the router's navigator.
  final Widget child;

  @override
  ConsumerState<OfflineNotice> createState() => _OfflineNoticeState();
}

class _OfflineNoticeState extends ConsumerState<OfflineNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    // Leaves faster than it arrives: the good news needs no dwelling on.
    reverseDuration: const Duration(milliseconds: 160),
  );

  late final Animation<double> _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline =
        ref.watch(onlineStatusProvider).value == OnlineStatus.offline;
    // Both calls are no-ops once the animation sits at that end, so driving
    // them from build keeps the strip a plain function of the signal.
    if (offline) {
      unawaited(_controller.forward());
    } else {
      unawaited(_controller.reverse());
    }

    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;

    return Column(
      children: [
        // While the strip is up it owns the status-bar inset, so it reads as
        // one band running to the top edge of the screen; the app below gets
        // that inset back as the strip retracts. Driving both from the same
        // value makes the content's total offset exactly
        // `statusBarHeight + reveal * stripHeight` — a linear slide with no
        // jump at either end, and no double inset in between.
        ExcludeSemantics(
          excluding: !offline,
          child: SizeTransition(
            sizeFactor: _reveal,
            // Bottom-aligned, so the band behaves like a shade pulled down
            // over the app: its line of copy rides the leading edge and stays
            // legible for the whole slide, instead of being sliced through the
            // middle by a clip that grows downwards past it.
            alignment: AlignmentDirectional.bottomStart,
            child: _OfflineStrip(topInset: statusBarHeight, opacity: _reveal),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (context, child) => MediaQuery(
              data: mediaQuery.copyWith(
                padding: mediaQuery.padding.copyWith(
                  top: statusBarHeight * (1 - _reveal.value),
                ),
              ),
              child: child!,
            ),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// The strip itself: a tonal band with an icon and one line of copy.
///
/// Deliberately has no action and no dismiss. There is nothing to retry —
/// `onlineStatusProvider` re-probes on every interface change, on resume and on
/// a 30 s heartbeat — and a state indicator the user can dismiss would go on
/// being false after they dismissed it.
class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.topInset, required this.opacity});

  /// Status-bar inset to absorb, so the band reaches the screen's top edge.
  final double topInset;

  /// Fades the contents in as the band arrives, so the copy is not readable
  /// before the surface it sits on has finished growing behind it.
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.labelLarge?.copyWith(
      color: colors.onSecondaryContainer,
    );
    // The icon grows with the text — and is boxed to exactly one line of it, so
    // it keeps sitting beside the *first* line rather than drifting to the
    // vertical middle once the sentence wraps at a large text scale.
    final scaler = MediaQuery.textScalerOf(context);
    final iconSize = scaler.scale(18);
    final lineHeight =
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.4);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        // A tonal surface, not `error`: an unreachable server is a state the
        // user is in, often expected in the field, and not a fault to alarm
        // them about.
        color: colors.secondaryContainer,
        child: Padding(
          padding: EdgeInsets.only(
            top: topInset + AppSpacing.sm,
            bottom: AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
          ),
          child: FadeTransition(
            opacity: opacity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lineHeight,
                  child: Center(
                    child: Icon(
                      Icons.cloud_off_outlined,
                      size: iconSize,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Wraps rather than truncating, so the sentence survives a
                // large text scale instead of losing its second half — but
                // never past three lines, beyond which a notice about not
                // being able to save would take more of the screen than the
                // work it is interrupting.
                Expanded(
                  child: Text(
                    context.l10n.offlineNotice,
                    style: style,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
