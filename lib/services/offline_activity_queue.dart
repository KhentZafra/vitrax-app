import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/activity.dart';

/// Local, offline-first persistence for a finished GPS recording that
/// couldn't be pushed to Supabase immediately — either because there's
/// no connection at all, or the insert call failed for a transient
/// reason. This is the panel's "Telemetry Missing Link" solution: the
/// phone's GPS doesn't need internet to work, so a finished recording is
/// never allowed to just disappear because the network was down.
///
/// Each pending activity is one JSON file on local storage
/// (`<app documents>/pending_activities/<uuid>.json`). A background sync
/// (triggered by ActivityProvider whenever connectivity comes back, or
/// on app start) reads every file here, tries to insert it, and deletes
/// the file only after a confirmed successful insert — so a crash or
/// killed app mid-sync can never lose data, it just retries next time.
class OfflineActivityQueue {
  static const _uuid = Uuid();

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pending_activities');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves a finished recording locally. Returns a client-side Activity
  /// with a local id (prefixed `local_`) and `pendingSync: true`, so the
  /// UI (completion modal, Home's recent list) can display it right away
  /// even though it hasn't reached Supabase yet.
  static Future<Activity> enqueue(Activity activity) async {
    final localId = 'local_${_uuid.v4()}';
    final dir = await _dir();
    final file = File('${dir.path}/$localId.json');
    await file.writeAsString(jsonEncode(activity.toLocalJson()));
    return activity.copyWith(id: localId, pendingSync: true);
  }

  /// Reads every pending activity currently queued, oldest first isn't
  /// guaranteed by filesystem order so callers that care about order
  /// should sort by startedAt themselves.
  static Future<List<Activity>> loadAll() async {
    final dir = await _dir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));

    final results = <Activity>[];
    for (final file in files) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final localId = file.uri.pathSegments.last.replaceAll('.json', '');
        results.add(Activity.fromLocalJson(json, localId: localId));
      } catch (_) {
        // A corrupted single file shouldn't block syncing the rest.
        continue;
      }
    }
    return results;
  }

  static Future<int> count() async => (await loadAll()).length;

  /// Removes a pending activity's local file — call only after a
  /// confirmed successful Supabase insert.
  static Future<void> remove(String localId) async {
    final dir = await _dir();
    final file = File('${dir.path}/$localId.json');
    if (await file.exists()) await file.delete();
  }
}
