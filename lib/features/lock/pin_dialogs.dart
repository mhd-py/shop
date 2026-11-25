import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/pin_repository.dart';

/// Asks for one or more 4-digit PINs. When [confirmNew] is true the last two
/// fields must match. Returns the values, or null when cancelled.
Future<List<String>?> askPinFields(
  BuildContext context, {
  required String title,
  required List<String> labels,
  bool confirmNew = false,
}) {
  final ctls = [for (final _ in labels) TextEditingController()];
  String? error;
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctls[i],
                  autofocus: i == 0,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: labels[i],
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (error case final e?)
              Text(e, style: const TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = [for (final c in ctls) c.text];
              if (v.any((p) => PinRepository.validatePin(p) != null)) {
                setLocal(() => error = 'PIN must be 4 digits');
              } else if (confirmNew &&
                  v[v.length - 1] != v[v.length - 2]) {
                setLocal(() => error = 'PINs do not match');
              } else {
                Navigator.pop(ctx, v);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/// Shows the recovery code once. The shopkeeper must tap to close it.
Future<void> showRecoveryCode(BuildContext context, String code) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.vpn_key_outlined),
        title: const Text('Your recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Write this code down and keep it safe. It is the '
                'only way to reset a forgotten PIN. It will not be shown '
                'again.'),
            const SizedBox(height: 16),
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              child: const Text('Copy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I wrote it down')),
        ],
      ),
    );
