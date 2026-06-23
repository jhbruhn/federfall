import 'package:flutter/material.dart';

/// A tappable, read-only date field rendered like the app's text inputs, with
/// an optional clear action for nullable dates. Tapping it opens the caller's
/// date picker via [onPick].
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.placeholder,
    this.enabled = true,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final text = value == null
        ? (placeholder ?? '')
        : materialL10n.formatMediumDate(value!);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: value != null && enabled && onClear != null
              ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear)
              : null,
        ),
        child: Text(text),
      ),
    );
  }
}
