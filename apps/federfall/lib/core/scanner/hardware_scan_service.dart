/// A stream of raw barcode payloads from hardware scanner hardware (Zebra,
/// Honeywell, Datalogic, Newland, Urovo — via the `scanwedge` plugin), or an
/// always-empty stream on platforms/devices without one.
///
/// The `scanwedge` package itself unconditionally imports `dart:io` (its
/// `Scanwedge.deviceName` getter uses `Platform.isAndroid`), which fails to
/// even *compile* for web — so, mirroring `routing/url_strategy/`, the real
/// implementation lives in a native-only file and is swapped out for a stub
/// on web via a conditional export. The native file itself further no-ops on
/// iOS (`scanwedge` is Android-only) and on unsupported Android hardware.
library;

export 'hardware_scan_service_native.dart'
    if (dart.library.js_interop) 'hardware_scan_service_web.dart';
