import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/hazard_report.dart';
import 'hazard_service.dart';

/// Keeps hazard reports safe when the phone has no internet.
///
/// A hazard reported while offline used to stay only on the map for that one
/// recording and was lost. Now each one is saved as a small file on the phone.
/// Later (when internet returns, or the activity it belongs to syncs) every
/// file is uploaded, linked to its activity and shared with the community,
/// and only then deleted — so nothing is lost if the app closes in between.
///
/// An entry is one of two kinds:
///  * a hazard that was never uploaded (it has type / lat / lng / time), or
///  * a hazard that was uploaded but could not be linked or shared yet
///    (it has only a hazardId).
class OfflineHazardQueue {
  static const _uuid = Uuid();
  static bool _flushing = false;

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pending_hazards');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _file(String key) async => File('${(await _dir()).path}/$key.json');

  static Future<void> _write(String key, Map<String, dynamic> json) async => (await _file(key)).writeAsString(jsonEncode(json));

  /// Copies picked photos into the app's own folder (the picker's temp files
  /// can disappear) and returns the new paths.
  static Future<List<String>> _keepPhotos(List<File> files) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pending_hazard_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = <String>[];
    for (final f in files) {
      try {
        final copy = await f.copy('${dir.path}/${_uuid.v4()}.jpg');
        out.add(copy.path);
      } catch (_) {}
    }
    return out;
  }

  /// Adds photos to a hazard that is still waiting to be uploaded.
  static Future<void> addPhotos(String key, List<File> files) async {
    final f = await _file(key);
    if (!await f.exists()) return;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final photos = ((json['photos'] as List?) ?? const []).cast<String>().toList()..addAll(await _keepPhotos(files));
    json['photos'] = photos;
    await f.writeAsString(jsonEncode(json));
  }

  /// Photos for a hazard that is already uploaded but whose photos failed to
  /// upload (no connection). Only the photos are retried; nothing is shared.
  static Future<void> enqueuePhotosOnly(String hazardId, List<File> files) async {
    final key = _uuid.v4();
    await _write(key, {
      'hazard_id': hazardId,
      'photos': await _keepPhotos(files),
      'photos_only': true,
    });
  }

  /// Saves a hazard that could not be uploaded. Returns its key.
  static Future<String> enqueueUnsent(HazardReport h, {List<File> photos = const []}) async {
    final key = _uuid.v4();
    await _write(key, {
      'photos': await _keepPhotos(photos),
      'type': h.type.value,
      'lat': h.position.latitude,
      'lng': h.position.longitude,
      'reported_at': h.reportedAt.toIso8601String(),
      'end_lat': h.endPosition?.latitude,
      'end_lng': h.endPosition?.longitude,
      'length_m': h.lengthMeters,
      'auto': h.autoDetected,
      'hazard_id': null,
      'activity_ref': null,
      'shared': false,
      'linked': false,
    });
    return key;
  }

  /// Remembers an already-uploaded hazard that still has to be linked/shared.
  static Future<String> enqueueUploaded(String hazardId, {String? activityRef, bool shared = false}) async {
    final key = _uuid.v4();
    await _write(key, {
      'hazard_id': hazardId,
      'activity_ref': activityRef,
      'shared': shared,
      'linked': false,
    });
    return key;
  }

  /// Ties queued hazards to the activity they were reported during
  /// ([activityRef] is the activity id, or its `local_...` id while offline).
  static Future<void> setActivity(List<String> keys, String activityRef) async {
    for (final key in keys) {
      final f = await _file(key);
      if (!await f.exists()) continue;
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      json['activity_ref'] = activityRef;
      await f.writeAsString(jsonEncode(json));
    }
  }

  /// An offline activity just synced: its `local_...` id becomes a real id.
  static Future<void> activitySynced(String localId, String realId) async {
    final dir = await _dir();
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (json['activity_ref'] == localId) {
          json['activity_ref'] = realId;
          await f.writeAsString(jsonEncode(json));
        }
      } catch (_) {}
    }
  }

  /// Forget a queued hazard (the user undid it).
  static Future<void> remove(String key) async {
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }

  static Future<int> count() async {
    final dir = await _dir();
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length;
  }

  /// Uploads, links and shares everything that is waiting. Safe to call often.
  static Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final dir = await _dir();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
      for (final f in files) {
        try {
          final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final ref = json['activity_ref'] as String?;
          final realActivityId = (ref != null && !ref.startsWith('local_')) ? ref : null;

          var hazardId = json['hazard_id'] as String?;
          if (hazardId == null) {
            final saved = await HazardService.report(
              HazardReport(
                type: HazardTypeX.fromString(json['type'] as String),
                position: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
                reportedAt: DateTime.parse(json['reported_at'] as String),
                endPosition: (json['end_lat'] is num && json['end_lng'] is num)
                    ? LatLng((json['end_lat'] as num).toDouble(), (json['end_lng'] as num).toDouble())
                    : null,
                lengthMeters: (json['length_m'] as num?)?.toDouble(),
                autoDetected: json['auto'] == true,
              ),
              activityId: realActivityId,
            );
            if (saved?.id == null) continue; // still offline: try again later
            hazardId = saved!.id!;
            json['hazard_id'] = hazardId;
            json['linked'] = realActivityId != null;
            await f.writeAsString(jsonEncode(json));
          }

          // Photos waiting to be uploaded for this hazard.
          var photosPending = false;
          final waiting = ((json['photos'] as List?) ?? const []).cast<String>();
          if (waiting.isNotEmpty) {
            final remaining = <String>[];
            for (final path in waiting) {
              final photo = File(path);
              if (!await photo.exists()) continue;
              if (await HazardService.uploadPhotos(hazardId, [photo]) > 0) {
                await photo.delete();
              } else {
                remaining.add(path);
              }
            }
            // Give up on a photo after 8 failed rounds so it cannot block this
            // hazard forever (for example when the hazard already has 5 photos).
            final tries = ((json['photo_tries'] as num?) ?? 0).toInt() + (remaining.isEmpty ? 0 : 1);
            json['photo_tries'] = tries;
            if (tries >= 8) {
              for (final path in remaining) {
                try {
                  await File(path).delete();
                } catch (_) {}
              }
              remaining.clear();
            }
            json['photos'] = remaining;
            await f.writeAsString(jsonEncode(json));
            photosPending = remaining.isNotEmpty;
          }
          if (json['photos_only'] == true) {
            if (!photosPending) await f.delete();
            continue;
          }

          if (json['shared'] != true) {
            if (!await HazardService.shareHazards([hazardId])) continue;
            json['shared'] = true;
            await f.writeAsString(jsonEncode(json));
          }

          if (realActivityId != null && json['linked'] != true) {
            await HazardService.linkToActivity([hazardId], realActivityId);
            json['linked'] = true;
            await f.writeAsString(jsonEncode(json));
          }

          // Done once shared, and linked if it belongs to an activity that has synced.
          if (!photosPending && json['shared'] == true && (ref == null || json['linked'] == true)) {
            await f.delete();
          }
        } catch (_) {
          continue; // leave it for the next attempt
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
