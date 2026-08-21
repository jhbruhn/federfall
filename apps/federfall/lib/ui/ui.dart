/// Shared UI building blocks: theme tokens, base widgets and validators.
library;

export 'package:federfall/theme/app_spacing.dart';
export 'package:federfall/theme/app_theme.dart';
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show fileCacheKey;
// The shared kit, named symbol by symbol rather than as a bare
// `export 'package:zugvogel_ui/zugvogel_ui.dart'`. That is not a style
// preference: the bare form was tried and it collides. federfall keeps its own
// `Validators`, `formatNumber`, `MapTileLayer`, `errorMessage` and
// `loadErrorMessage`, all exported from this same barrel, so a wholesale
// re-export makes five names ambiguous and 24 call sites stop compiling.
//
// This list is what thirty-one one-line files in this directory used to say
// between them: migration scaffolding that kept every import path working while
// the implementations moved to zugvogel. With the move landed they were a hop
// with nothing in it — a reader following a widget to its definition went
// through a file that only named it, and `grep` found the shim rather than the
// code.
//
// Writing it out has a second effect worth keeping: zugvogel gaining a widget
// does not silently widen federfall's public UI surface.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show
        AppTextField,
        AsyncValueView,
        BreakdownBars,
        BreakdownCard,
        BreakdownPie,
        BreakdownRow,
        CachedFileImage,
        ChartEntry,
        ContentBounds,
        DateField,
        DateStyle,
        DestructiveActionButton,
        DestructiveChoice,
        DestructiveDialog,
        DetailHeader,
        DiscardGuard,
        EditablePhotoStrip,
        EmptyView,
        ErrorView,
        IconChip,
        ImageCropScreen,
        ImageViewerScreen,
        JpegEncodeRequest,
        KpiCard,
        KpiGrid,
        LoadingView,
        LocalPhotoThumb,
        MapAttribution,
        MapWheelZoom,
        MenuAction,
        OfflineNotice,
        PagedListTail,
        PrimaryButton,
        StagedPhotos,
        TagChip,
        VideoAttachmentThumb,
        axisLabel,
        buildMenuItems,
        chartGrid,
        confirmDiscardChanges,
        encodeRgbaAsJpeg,
        fittingAxisLabels,
        formatLocalDate,
        isVideoAttachment,
        labelBounds,
        narrowMonthLabel,
        pickDate,
        pickDateTime,
        showAppSheet,
        showImageCropper,
        showImageViewer;

export 'form_sheet.dart';
export 'layout/list_detail_scaffold.dart';
export 'layout/window_size.dart';
export 'number_format.dart';
export 'validators.dart';
export 'widgets/map_tile_layer.dart';
