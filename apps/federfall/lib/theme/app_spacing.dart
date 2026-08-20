// The spacing scale now lives in zugvogel_ui (eiermann-d2a.9) as
// ZugvogelSpacing. `AppSpacing` stays as the name ~500 call sites in this app
// already use: a typedef, so `AppSpacing.md` resolves to the same constant
// rather than to a copy of it.
import 'package:zugvogel_ui/zugvogel_ui.dart';

/// This app's name for [ZugvogelSpacing]. A scale is not brand — no product
/// identity lives in a gap width — so it is shared rather than injected.
typedef AppSpacing = ZugvogelSpacing;
