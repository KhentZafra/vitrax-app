import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Hands-free "yes/no" voice answers — specifically for the hazard
/// "is this still here?" prompt in record_screen.dart, where the person
/// asking is mid-run or mid-ride and shouldn't have to look at, or tap,
/// their phone to answer. Deliberately narrow in scope (yes/no only,
/// not general voice commands) — a wider vocabulary would need much
/// more robust matching to avoid misfires while someone is talking to a
/// running partner, out of breath, or riding past traffic noise.
///
/// This is a hands-free SHORTCUT, never a replacement: record_screen.dart
/// keeps its on-screen "Still Here" / "It's Clear" buttons exactly as
/// they were, for anyone who prefers tapping, is somewhere too noisy for
/// speech recognition to work, or simply doesn't get a clean result in
/// the listening window below.
class VoiceCommandService {
  static final SpeechToText _speech = SpeechToText();
  static bool _available = false;
  static bool _checkedAvailability = false;

  /// Triggers the microphone permission prompt right away, ahead of any
  /// actual recording — call this once, as soon as record_screen.dart
  /// opens, rather than letting the first hazard proximity trigger it
  /// mid-run. Asking upfront means the person deals with the OS
  /// permission dialog while standing still looking at their phone
  /// (the normal, expected moment for a permission prompt), not while
  /// they're moving and the phone is mid-sentence reading out a hazard
  /// alert. Safe to call every time the screen opens — [_ensureAvailable]
  /// only actually asks Android/iOS once per app install; every call
  /// after the first just returns the already-known answer.
  static Future<void> warmUp() async {
    await _ensureAvailable();
  }

  static Future<bool> _ensureAvailable() async {
    if (_checkedAvailability) return _available;
    _checkedAvailability = true;
    try {
      _available = await _speech.initialize(
        onError: (error) {
          if (kDebugMode) print('VoiceCommandService init error: $error');
        },
      );
    } catch (e) {
      if (kDebugMode) print('VoiceCommandService._ensureAvailable failed: $e');
      _available = false;
    }
    return _available;
  }

  // Simple whole-word matching rather than String.contains — contains
  // would wrongly match "no" inside "know", "I don't know", etc.
  static bool _matchesWord(String text, List<String> words) {
    final spoken = text.toLowerCase().split(RegExp(r'\s+'));
    return spoken.any(words.contains);
  }

  static bool _isYes(String text) {
    final lower = text.toLowerCase();
    return _matchesWord(lower, ['yes', 'yeah', 'yep', 'yup']) || lower.contains('still here') || lower.contains('still there');
  }

  static bool _isNo(String text) {
    final lower = text.toLowerCase();
    return _matchesWord(lower, ['no', 'nope', 'nah']) || lower.contains('cleared') || lower.contains('is clear') || lower.contains("it's clear");
  }

  /// Listens for a short window (a few seconds) for a spoken "yes" or
  /// "no" (and a few natural variants — "still here", "it's clear",
  /// etc.). Calls [onYes] or [onNo] the instant a match is heard, and
  /// stops listening immediately after. Calls neither if nothing
  /// recognizable comes back before the window closes, or if speech
  /// recognition isn't available on this device at all (no microphone
  /// permission granted, or no speech-recognition service installed) —
  /// in both cases the caller's on-screen buttons remain the answer.
  static Future<void> listenForYesNo({
    required VoidCallback onYes,
    required VoidCallback onNo,
  }) async {
    final available = await _ensureAvailable();
    if (!available) return;

    var handled = false;
    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(seconds: 2),
        onResult: (result) {
          if (handled) return;
          final text = result.recognizedWords;
          if (_isYes(text)) {
            handled = true;
            _speech.stop();
            onYes();
          } else if (_isNo(text)) {
            handled = true;
            _speech.stop();
            onNo();
          }
        },
      );
    } catch (e) {
      if (kDebugMode) print('VoiceCommandService.listenForYesNo failed: $e');
    }
  }

  /// Stops listening immediately — call this if the prompt is dismissed
  /// or answered by tap while a voice-listening window is still open,
  /// so the microphone doesn't keep running for no reason.
  static Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }
}
