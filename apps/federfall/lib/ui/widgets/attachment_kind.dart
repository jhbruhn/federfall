// isVideoAttachment and VideoAttachmentThumb now live in zugvogel_ui
// (eiermann-d2a.10). The rule they encode is PocketBase's, not federfall's:
// `?thumb=` produces a variant for images only and silently serves the
// original for anything else, so a video tile must never ask for a thumbnail.
//
// The video extension list is the package's now. A file field's own MIME
// allowlist still comes from this app's migration; the two only have to agree
// on what counts as *not an image*.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show VideoAttachmentThumb, isVideoAttachment;
