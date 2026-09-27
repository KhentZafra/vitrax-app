/// Single source of truth for media upload limits. Tune these here only
/// — everything else (picker UI text, size checks) reads from this file,
/// so bumping a limit later (e.g. after moving to Supabase Pro) never
/// requires hunting through multiple files.
///
/// Note: raising these numbers doesn't require a Supabase plan change up
/// to 50MB (Free plan's hard ceiling). Going higher than that requires
/// Pro, where the platform limit can be raised well beyond what you'd
/// actually want here — the cap below is about UX, bandwidth, and
/// storage cost, not just what Supabase allows.
class MediaLimits {
  static const maxVideoDuration = Duration(seconds: 30);
  static const maxVideoSizeBytes = 30 * 1024 * 1024; // 30MB
  static const maxPhotoSizeBytes = 8 * 1024 * 1024; // 8MB

  static int get maxVideoSizeMb => maxVideoSizeBytes ~/ (1024 * 1024);
  static int get maxPhotoSizeMb => maxPhotoSizeBytes ~/ (1024 * 1024);
}

