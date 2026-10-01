import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Picks and uploads a user's profile photo.
///
/// Storage layout: `avatars/{user_id}.jpg` — one file per user, always
/// the same path, so a new upload simply overwrites the old one
/// (upsert) rather than accumulating old photos forever. Mirrors the
/// same bucket-per-user-id pattern as PhotoUploadService /
/// MediaUploadService; the storage RLS policy (see the SQL this ships
/// with) only lets a user write to their own `{user_id}.jpg`.
class AvatarService {
  static final _supabase = Supabase.instance.client;
  static const _bucket = 'avatars';

  /// Opens the picker (camera or gallery) and returns the picked file,
  /// or null if the user backed out. Cropped-ish via maxWidth/maxHeight
  /// (a square-ish box) and compressed client-side — an avatar is shown
  /// small everywhere, so there's no reason to upload a multi-megabyte
  /// original.
  static Future<File?> pickAvatar({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Uploads [file] as the current user's avatar, updates
  /// `profiles.avatar_url` to match, and returns the new URL (or null on
  /// failure). The stored URL carries a `?v=<timestamp>` query parameter
  /// — the file path itself never changes (always `{user_id}.jpg`), so
  /// without a cache-busting parameter, every screen that already cached
  /// the old image (Flutter's own image cache, or an OS/CDN cache level)
  /// would keep showing the old photo after a user updates it.
  static Future<String?> uploadAvatar(File file) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final path = '${user.id}.jpg';

    try {
      await _supabase.storage.from(_bucket).upload(
            path,
            file,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final publicUrl = _supabase.storage.from(_bucket).getPublicUrl(path);
      final versionedUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await _supabase.from('profiles').update({'avatar_url': versionedUrl}).eq('id', user.id);

      return versionedUrl;
    } catch (e) {
      return null;
    }
  }

  /// Removes the current user's avatar — clears `profiles.avatar_url`
  /// so every screen falls back to initials/icon again. The underlying
  /// file in storage is left in place (harmless orphan, same tradeoff
  /// PhotoUploadService makes); only the reference is cleared.
  static Future<bool> removeAvatar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('profiles').update({'avatar_url': null}).eq('id', user.id);
      return true;
    } catch (e) {
      return false;
    }
  }
}
