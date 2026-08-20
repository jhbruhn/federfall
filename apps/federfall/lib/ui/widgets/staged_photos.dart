// StagedPhotos and LocalPhotoThumb now live in zugvogel_ui (eiermann-d2a.10).
// The add/capture labels became injected strings; everything else — decoding a
// picked file, refusing to decode a picked video — was never federfall's.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show LocalPhotoThumb, StagedPhotos;
