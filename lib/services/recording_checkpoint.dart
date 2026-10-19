import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/activity.dart';

/// Crash/kill recovery for an activity in progress.
///
/// While recording, the app saves a small snapshot to the phone every few
/// seconds. If the phone's battery manager kills the app mid-ride, the
/// snapshot is still there the next time VITRAX opens, and the user can
/// save the ride instead of losing it.
class RecordingCheckpoint {
  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  static Future<void> save({
    required ActivityType type,
    required String? subtype,
    required double distanceMeters,
    required int elapsedSeconds,
    required DateTime startedAt,
    required List<GpsPoint> route,
  }) async {
    try {
      final f = await _file('recording_checkpoint.json');
      final tmp = await _file('recording_checkpoint.tmp');
      await tmp.writeAsString(jsonEncode({
        'type': type.name,
        'subtype': subtype,
        'distanceMeters': distanceMeters,
        'elapsedSeconds': elapsedSeconds,
        'startedAt': startedAt.toIso8601String(),
        'savedAt': DateTime.now().toIso8601String(),
        'route': route.map((p) => p.toJson()).toList(),
      }), flush: true);
      // Write to a temp file first, then swap, so a kill in the middle of
      // writing can never leave a half-written (unreadable) checkpoint.
      await tmp.rename(f.path);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final f = await _file('recording_checkpoint.json');
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(data['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt).inHours > 48) {
        await clear();
        return null;
      }
      return data;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file('recording_checkpoint.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
