// MapAttribution now lives in zugvogel_ui (eiermann-d2a.11). It reads the
// effective map source from zugvogel_pb_client's mapConfigProvider, so the
// credit follows a source the server prescribes at runtime — which is the
// whole reason attribution cannot be a constant in the widget.
export 'package:zugvogel_ui/zugvogel_ui.dart' show MapAttribution;
