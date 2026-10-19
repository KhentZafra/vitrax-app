import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Helps keep GPS recording alive with the screen off.
///
/// Android phones (especially Xiaomi, Oppo, Vivo, Realme, Huawei, Samsung)
/// stop apps in the background to save battery. The foreground service
/// notification protects recording on most phones; this adds the second
/// protection: asking the user to exempt VITRAX from battery optimization.
class BackgroundGuard {
  static const _channel = MethodChannel('vitrax/background');

  static Future<bool> isExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? false;
    } catch (_) {
      return true; // can't tell, so don't nag
    }
  }

  static Future<String> _manufacturer() async {
    try {
      return (await _channel.invokeMethod<String>('manufacturer')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<File> _flag() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}bg_guide_seen');
  }

  /// Forget that the guide was shown, so it appears again next time.
  /// Used after a recording was lost, which proves the phone is killing us.
  static Future<void> resetSeen() async {
    try {
      final f = await _flag();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static String _tipFor(String maker) {
    if (maker.contains('xiaomi') || maker.contains('redmi') || maker.contains('poco')) {
      return 'On Xiaomi/Redmi/POCO: open Settings > Apps > Manage apps > VITRAX, turn on "Autostart", and set Battery saver to "No restrictions".';
    }
    if (maker.contains('oppo') || maker.contains('realme') || maker.contains('oneplus')) {
      return 'On Oppo/Realme/OnePlus: open Settings > Battery > VITRAX (or App battery management) and allow background activity and auto-launch.';
    }
    if (maker.contains('vivo') || maker.contains('iqoo')) {
      return 'On Vivo: open Settings > Battery > Background power consumption > VITRAX and choose "Allow", and allow Autostart.';
    }
    if (maker.contains('huawei') || maker.contains('honor')) {
      return 'On Huawei/Honor: open Settings > Apps > App launch > VITRAX and turn on "Manage manually" with all three switches on.';
    }
    if (maker.contains('samsung')) {
      return 'On Samsung: open Settings > Battery > Background usage limits and make sure VITRAX is not in "Sleeping apps" or "Deep sleeping apps".';
    }
    return 'If recording ever stops with the screen off, open your phone\'s Settings > Apps > VITRAX > Battery and choose "Unrestricted" or "No restrictions".';
  }

  /// Shows the guide once (unless the phone already exempts VITRAX).
  /// Returns when the user has finished with it.
  static Future<void> ensureReady(BuildContext context) async {
    if (!Platform.isAndroid) return;
    try {
      if (await isExempt()) return;
      final flag = await _flag();
      if (await flag.exists()) return;
      final maker = await _manufacturer();
      if (!context.mounted) return;

      final allow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xff141414),
          title: const Text('Keep recording with the screen off', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To record your whole ride while your phone is locked or in your pocket, VITRAX needs to be allowed to run in the background. Without this, some phones stop the recording to save battery.',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(_tipFor(maker), style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3D7DFF), foregroundColor: Colors.white),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      try {
        await flag.writeAsString('1');
      } catch (_) {}

      if (allow == true) {
        final ok = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
        if (ok != true) await _channel.invokeMethod<bool>('openAppSettings');
        // Give the system screen time to show before recording starts.
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (_) {}
  }
}
