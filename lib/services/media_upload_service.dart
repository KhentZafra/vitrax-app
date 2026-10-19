import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/media_limits.dart';
import '../models/feed_item.dart';

/// Picks and uploads photos or videos for standalone community posts.
///
/// Storage layout: `community-media/{user_id}/{uuid}.{ext}` — enforced
/// both here and by the storage RLS policy in 009_community_posts.sql.
///
/// Size/duration limits live in [MediaLimits] — tune them there, not
/// here, so there's one place to change when you move to Supabase Pro.
class MediaUploadService {
  static final _supabase = Supabase.instance.client;
  static const _bucket = 'community-media';
  static const _uuid = Uuid();

  /// Opens the picker for a photo. Compressed client-side.
  static Future<File?> pickPhoto({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1280, imageQuality: 75);
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Opens the picker for a video, capped at [MediaLimits.maxVideoDuration].
  /// Note: this duration cap is only reliably enforced when *recording*
  /// via the camera — a video picked from the gallery can still be
  /// longer on some devices, which is exactly why [checkSizeLimit] below
  /// matters regardless of duration.
  static Future<File?> pickVideo({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: source, maxDuration: MediaLimits.maxVideoDuration);
    if (picked == null) return null;
    return _compressVideo(File(picked.path));
  }

  /// Re-encodes a video to a smaller size before upload (rural mobile data
  /// is slow and expensive). If compression fails for any reason the
  /// original file is used, so posting never breaks because of it.
  static Future<File> _compressVideo(File original) async {
    try {
      final info = await VideoCompress.compressVideo(
        original.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final out = info?.file;
      if (out != null && await out.exists() && await out.length() > 0 && await out.length() < await original.length()) {
        return out;
      }
    } catch (_) {}
    return original;
  }

  /// Checks [file] against the size cap for [mediaType]. Returns null if
  /// it's within limits, or a user-facing reason string if not.
  static Future<String?> checkSizeLimit(File file, FeedMediaType mediaType) async {
    final bytes = await file.length();
    final limit = mediaType == FeedMediaType.photo ? MediaLimits.maxPhotoSizeBytes : MediaLimits.maxVideoSizeBytes;
    if (bytes <= limit) return null;

    final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final limitMb = (limit / (1024 * 1024)).toStringAsFixed(0);
    if (mediaType == FeedMediaType.video) {
      return "That video is ${sizeMb}MB — over the ${limitMb}MB limit. Try a shorter clip.";
    }
    return "That photo is ${sizeMb}MB — over the ${limitMb}MB limit. Try a different one.";
  }

  /// Uploads [file] of [mediaType] for a standalone post and returns its
  /// public URL, or null on failure.
  static Future<String?> upload({required File file, required FeedMediaType mediaType}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final ext = mediaType == FeedMediaType.photo ? 'jpg' : 'mp4';
    final contentType = mediaType == FeedMediaType.photo ? 'image/jpeg' : 'video/mp4';
    final path = '${user.id}/${_uuid.v4()}.$ext';

    try {
      await _supabase.storage.from(_bucket).upload(
            path,
            file,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      return _supabase.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }
}
