import 'package:federfall/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Leaves a screen that is normally *pushed* over the navigation shell — the
/// management hub, statistics, the worklist, the profile.
///
/// Those are top-level routes with no parent page of their own, so their back
/// stack can be empty: on a cold open (a shared link, a web reload, an Android
/// process restore) or after a redirect refresh there is nothing beneath them.
/// Pops when it can and falls back to the home landing when it cannot, so the
/// screen is never a dead end.
///
/// Resolved via [GoRouter.maybeOf] so a screen using this still pumps in widget
/// tests that mount it without a router (cf. `selectedDetailId`).
void backOrHome(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(AppRoutes.home);
  }
}

/// App-bar back arrow that calls [backOrHome]. Use it instead of relying on
/// `AppBar`'s implied leading, which silently disappears when there is nothing
/// to pop — exactly the case that strands the user.
class BackOrHomeButton extends StatelessWidget {
  const BackOrHomeButton({super.key});

  @override
  Widget build(BuildContext context) =>
      BackButton(onPressed: () => backOrHome(context));
}

/// Applies the same fallback to the *system* back gesture (the Android back
/// button, a browser back on an empty stack), which would otherwise leave the
/// app entirely from a cold-opened overlay route.
class BackOrHomeScope extends StatelessWidget {
  const BackOrHomeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    return PopScope(
      canPop: router?.canPop() ?? false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) router?.go(AppRoutes.home);
      },
      child: child,
    );
  }
}
