import 'package:federfall/ui/layout/window_size.dart';
import 'package:flutter/widgets.dart';

/// Caps flat page content to a readable [maxWidth] and centres it, so lists,
/// settings rows and chart bars don't stretch edge-to-edge on a wide window.
///
/// Safe at any width — below [maxWidth] it simply fills the available space, so
/// it can wrap a body unconditionally without a breakpoint check. Wrap a
/// scrolling child (e.g. a `ListView`): the child still fills the height; only
/// its width is bounded.
class ContentBounds extends StatelessWidget {
  const ContentBounds({
    required this.child,
    this.maxWidth = kContentMaxWidth,
    super.key,
  });

  final Widget child;

  /// Width cap; defaults to [kContentMaxWidth].
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
