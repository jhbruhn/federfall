// PagedListTail now lives in zugvogel_ui (eiermann-d2a.9). Keyset paging is
// zugvogel_data's, and the sentinel that drives it — load-more on scroll, an
// inline failure with a retry — is the same widget in both apps.
export 'package:zugvogel_ui/zugvogel_ui.dart' show PagedListTail;
