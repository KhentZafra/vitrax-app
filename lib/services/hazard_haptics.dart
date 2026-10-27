import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Long phone vibration played right before every spoken message while
/// recording, so the rider notices even with the volume low or muted.
class HazardHaptics {
  static const Duration buzzDuration = Duration(seconds: 3);

  /// Vibrates for [buzzDuration] and completes when it is over.
  static Future<void> buzz() async {
    try {
      final has = await Vibration.hasVibrator();
      if (has) {
        await Vibration.vibrate(duration: buzzDuration.inMilliseconds, amplitude: 255);
      } else {
        // No vibration motor API: fall back to repeated haptic pulses.
        final end = DateTime.now().add(buzzDuration);
        while (DateTime.now().isBefore(end)) {
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        return;
      }
    } catch (_) {
      return; // never block speech because vibration failed
    }
    await Future<void>.delayed(buzzDuration);
  }

  static Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
