import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Picks and uploads a photo for a shared activity.
///
/// Storage layout: `activity-photos/{user_id}/{activity_id}.jpg` — the
/// path shape is enforced both here and by the storage RLS policy in
/// 008_activity_photos.sql, so a user can only ever write into their own
/// folder.
class PhotoUploadService {
  static final _supabase = Supabase.instance.client;
  static const _bucket = 'activity-photos';

  /// Opens the picker (camera or gallery) and returns the picked file, or
  /// null if the user backed out. Compressed client-side to keep uploads
  /// fast on mobile data.
  static Future<File?> pickPhoto({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 75,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Uploads [file] for [activityId] and returns its public URL, or null
  /// on failure. Overwrites any previous photo for the same activity
  /// (upsert), so re-sharing with a new photo just replaces it.
  static Future<String?> uploadForActivity({
    required File file,
    required String activityId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final path = '${user.id}/$activityId.jpg';

    try {
      await _supabase.storage.from(_bucket).upload(
            path,
            file,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return _supabase.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }
}
