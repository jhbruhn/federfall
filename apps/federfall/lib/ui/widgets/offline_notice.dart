// OfflineNotice now lives in zugvogel_ui (eiermann-d2a.9). It reads the
// de-flapped online signal from zugvogel_pb_client and its one line of copy
// from the injected ZugvogelStrings, so the strip knows neither which server
// it is watching nor which language it is speaking.
export 'package:zugvogel_ui/zugvogel_ui.dart' show OfflineNotice;
