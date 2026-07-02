import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over [TextFormField] applying the app's input conventions
/// (outlined, labelled, consistent spacing). Keeps form code declarative.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.hintText,
    this.prefixIcon,
    this.textInputAction,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  /// `null` grows without limit; pair with [minLines] for prose fields.
  final int? maxLines;
  final int? minLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofocus: autofocus,
      enabled: enabled,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      minLines: minLines,
      textCapitalization: textCapitalization,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        // Keep the resting label at the top of multiline fields instead of
        // vertically centered.
        alignLabelWithHint: maxLines != 1,
      ),
    );
  }
}
