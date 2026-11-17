import '../widgets/dialog_buttons.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'badge_service.dart' show rootNavigatorKey;

/// Tells people when a newer VITRAX build is available.
///
/// The website publishes a small file, https://www.vitraxapp.com/version.json:
///   {"version":"1.0.1","build":2,"minBuild":1,"apk":"https://github.com/...","notes":"..."}
/// If its "build" is higher than this app's build number, a dialog offers the
/// download. Installing that APK over the old app is an update (same signing
/// key), so the account and data stay. Any failure here is silent: the check
/// must never get in the way of using the app.
class UpdateChecker {
  static const _manifestUrl = 'https://www.vitraxapp.com/version.json';
  static const _allowedHosts = {'github.com', 'www.vitraxapp.com', 'vitraxapp.com'};
  static bool _checkedThisLaunch = false;

  static Future<void> check() async {
    if (_checkedThisLaunch) return;
    _checkedThisLaunch = true;
    try {
      final res = await http
          .get(Uri.parse('$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body);
      if (j is! Map) return;

      final remoteBuild = (j['build'] as num?)?.toInt() ?? 0;
      final minBuild = (j['minBuild'] as num?)?.toInt() ?? 0;
      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (remoteBuild <= localBuild) return;

      final apk = Uri.tryParse((j['apk'] as String?) ?? '');
      if (apk == null || apk.scheme != 'https' || !_allowedHosts.contains(apk.host)) return;

      final version = (j['version'] as String?) ?? '';
      final notes = (j['notes'] as String?) ?? '';
      final mustUpdate = localBuild < minBuild;

      final ctx = rootNavigatorKey.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: !mustUpdate,
        builder: (dctx) => PopScope(
          canPop: !mustUpdate,
          child: AlertDialog(
            backgroundColor: const Color(0xff141414),
            title: Text(
              version.isEmpty ? 'Update available' : 'Update available: v$version',
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              [
                if (notes.isNotEmpty) notes,
                'Tap Update, open the downloaded file and choose Install. Your account and activities stay as they are.',
                if (mustUpdate) 'This update is required to keep using VITRAX.',
              ].join('\n\n'),
              style: TextStyle(color: Colors.grey.shade400, height: 1.4),
            ),
            actions: [
              if (!mustUpdate)
                DialogSafeButton(label: 'Later', onPressed: () => Navigator.pop(dctx)),
              TextButton(
                onPressed: () async {
                  await launchUrl(apk, mode: LaunchMode.externalApplication);
                  if (!mustUpdate && dctx.mounted) Navigator.pop(dctx);
                },
                child: const Text('Update', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Offline, blocked or malformed file: just carry on.
    }
  }
}
