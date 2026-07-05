import 'package:federfall/features/printing/printer_service.dart';

/// Web fallback (federfall-i0wq): selected by printer_service.dart's
/// `if (dart.library.io)` conditional import whenever `dart:io` isn't
/// available (every web target) — see that file's doc comment for why.
PrinterService createPrinterService() => NoopPrinterService();
