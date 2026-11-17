import 'dialog_buttons.dart';
import 'package:flutter/material.dart';

/// Asks "Unblock [name]?" and returns true only if the user confirms.
Future<bool> confirmUnblock(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xff141414),
      title: Text('Unblock $name?', style: const TextStyle(color: Colors.white)),
      content: const Text(
        'They will be able to message you again, and you will be able to message them.',
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        DialogSafeButton(label: 'Cancel', onPressed: () => Navigator.pop(dialogContext, false)),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Unblock', style: TextStyle(color: Colors.blue))),
      ],
    ),
  );
  return result == true;
}
