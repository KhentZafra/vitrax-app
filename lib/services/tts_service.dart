import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Spoken audio alerts — for hazards encountered while actively
/// recording an activity, where the panel's feedback was clear: a
/// cyclist doing 30 km/h or a runner on a steep hill cannot safely look
/// down at a phone mounted to a handlebar or armband. This reads the
/// alert out loud instead, through the phone speaker or connected
/// earphones, alongside (not instead of) the existing visual banner and
/// system notification in record_screen.dart — some users will have
/// their phone muted or in a pocket, so the visual/notification path
/// stays as a backup.
///
/// Kept deliberately simple: one shared FlutterTts instance, lazily
/// initialized on first use. No queueing beyond what the plugin already
/// does internally — record_screen.dart's own _sessionPromptedHazardIds
/// already prevents the same hazard from being announced twice, so
/// there's no risk of a rapid-fire pile-up of announcements to manage
/// here.
class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      // Slightly slower than default speech rate — this is meant to be
      // heard clearly over wind/road noise while moving, not read.
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
    } catch (e) {
      if (kDebugMode) print('TtsService._ensureInitialized failed: $e');
    }
  }

  /// Speaks a hazard alert, e.g. "Caution: pothole reported 40 meters
  /// ahead." [distanceMeters] is rounded to the nearest 10m — GPS isn't
  /// precise enough to justify a more exact figure, and a round number
  /// is easier to parse by ear anyway. Kept alongside [speakThen] (rather
  /// than replaced by it) since not every caller needs a follow-up
  /// action after the speech finishes.
  static Future<void> speakHazardAlert({
    required String hazardLabel,
    required double distanceMeters,
  }) async {
    await _ensureInitialized();
    if (!_initialized) return;

    final roundedDistance = (distanceMeters / 10).round() * 10;
    try {
      await _tts.stop(); // don't let an older alert overlap a new one
      await _tts.speak('Caution: $hazardLabel reported $roundedDistance meters ahead.');
    } catch (e) {
      if (kDebugMode) print('TtsService.speakHazardAlert failed: $e');
    }
  }

  /// Speaks [message], then calls [onDone] once the speech actually
  /// finishes — used to chain straight into voice-command listening
  /// (see VoiceCommandService) without the microphone racing to open
  /// while the phone is still talking, which would just have it hear
  /// itself. Falls back to calling [onDone] immediately if TTS itself
  /// isn't available, so a broken speech engine never blocks the
  /// voice-command flow entirely — the on-screen buttons still work.
  static Future<void> speakThen(String message, VoidCallback onDone) async {
    await _ensureInitialized();
    if (!_initialized) {
      onDone();
      return;
    }
    try {
      await _tts.stop();
      _tts.setCompletionHandler(onDone);
      await _tts.speak(message);
    } catch (e) {
      if (kDebugMode) print('TtsService.speakThen failed: $e');
      onDone();
    }
  }

  /// Stops any in-progress speech immediately — call this when the
  /// recording session ends or the screen is disposed, so an alert
  /// doesn't keep talking after the user has left the tracking screen.
  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
