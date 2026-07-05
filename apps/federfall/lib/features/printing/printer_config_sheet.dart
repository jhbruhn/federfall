import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/printing/printer_labels.dart';
import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/printing/printer_settings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configure the receipt printer (federfall-i0wq): scan and pick a device (or
/// hand-enter a network host:port — `scanAll` may not surface a TCP printer
/// reliably, per the epic notes) and choose the paper width. Selecting a
/// device saves it immediately and closes the sheet — this is a picker, not a
/// form with a separate save step.
Future<void> showPrinterConfigSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _PrinterConfigSheet());

class _PrinterConfigSheet extends ConsumerStatefulWidget {
  const _PrinterConfigSheet();

  @override
  ConsumerState<_PrinterConfigSheet> createState() =>
      _PrinterConfigSheetState();
}

class _PrinterConfigSheetState extends ConsumerState<_PrinterConfigSheet> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  final _formKey = GlobalKey<FormState>();

  Stream<List<PrinterDeviceRef>>? _scanStream;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // No manual .listen() here on purpose: a second subscriber racing the
  // StreamBuilder below for a broadcast stream's events can — and did, for
  // a scan result that arrives before the StreamBuilder itself gets to
  // subscribe — consume the data before the UI ever sees it (broadcast
  // streams don't replay past events to a late subscriber). The
  // StreamBuilder is the ONLY subscriber; scanning-vs-done state is read
  // straight off its own snapshot instead of a side-channel `_scanning` bool.
  void _startScan() {
    setState(() => _scanStream = ref.read(printerServiceProvider).scan());
  }

  Future<void> _select(PrinterDeviceRef device) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    try {
      await ref.read(printerSettingsProvider.notifier).setDevice(device);
      if (mounted) navigator.pop();
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    }
  }

  Future<void> _addManual() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    await _select(NetworkPrinterDeviceRef(name: host, host: host, port: port));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final paperSize =
        ref.watch(printerSettingsProvider).value?.paperSize ??
        ReceiptPaperSize.mm72;

    return SafeArea(
      child: Padding(
        // The manual host/port entry has text fields near the bottom of a
        // scrollable sheet — without insetting for the keyboard here (same
        // pattern as edit_profile_sheet.dart), it overlaps them instead of
        // the sheet scrolling clear.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.printerConfigTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ReceiptPaperSize>(
                initialValue: paperSize,
                decoration: InputDecoration(
                  labelText: l10n.printerPaperSizeLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final size in ReceiptPaperSize.values)
                    DropdownMenuItem(
                      value: size,
                      child: Text(paperSizeLabel(l10n, size)),
                    ),
                ],
                onChanged: (size) {
                  if (size == null) return;
                  unawaited(
                    ref
                        .read(printerSettingsProvider.notifier)
                        .setPaperSize(
                          size,
                        ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              StreamBuilder<List<PrinterDeviceRef>>(
                stream: _scanStream,
                builder: (context, snapshot) {
                  // No stream yet (before the first "Scan" tap) reads the
                  // same as "done" — show the button, not a spinner.
                  final scanning =
                      _scanStream != null &&
                      snapshot.connectionState != ConnectionState.done;
                  if (snapshot.hasError) {
                    reportCaughtError(
                      snapshot.error!,
                      snapshot.stackTrace ?? StackTrace.current,
                      context: 'Printer scan failed',
                    );
                  }
                  final devices = snapshot.data ?? const [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.printerScanAction,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (scanning)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            TextButton(
                              onPressed: _startScan,
                              child: Text(l10n.printerScanAction),
                            ),
                        ],
                      ),
                      if (_scanStream != null && devices.isEmpty && !scanning)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            l10n.printerScanEmpty,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        for (final device in devices)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.print_outlined),
                            title: Text(device.name),
                            subtitle: Text(printerDeviceDetail(l10n, device)),
                            onTap: () => _select(device),
                          ),
                    ],
                  );
                },
              ),
              const Divider(height: AppSpacing.lg),
              Text(
                l10n.printerManualEntryTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: l10n.printerManualHostLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '' : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.printerManualPortLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            int.tryParse(v?.trim() ?? '') == null ? '' : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _addManual,
                  child: Text(l10n.printerManualAddAction),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
