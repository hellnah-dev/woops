import 'package:flutter/material.dart';

/// Standard confirmation for critical or irreversible actions.
/// Returns true only if the user explicitly taps the confirm button
/// (tapping outside, back, or Cancel all return false).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: icon == null ? null : Icon(icon, color: destructive ? scheme.error : scheme.primary),
        title: Text(title, textAlign: icon == null ? null : TextAlign.center),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            key: const Key('confirm-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: destructive ? scheme.error : null,
              foregroundColor: destructive ? scheme.onError : null,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
