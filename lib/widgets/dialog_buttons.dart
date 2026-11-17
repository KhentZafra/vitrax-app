import 'package:flutter/material.dart';

/// Buttons for confirm dialogs, so every one looks the same:
/// - [DialogSafeButton]: the harmless choice (Cancel, Keep, Stay), bright blue.
/// - [DialogDangerButton]: the action that deletes or removes something,
///   white text on a red background.
class DialogSafeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const DialogSafeButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xff4DA3FF),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class DialogDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const DialogDangerButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xffE53935),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xff5A2A2A),
        disabledForegroundColor: Colors.white54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
