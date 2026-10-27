import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'hazard_haptics.dart';

/// Spoken audio alerts for rides. The rule: ONE message at a time.
///
/// * A message that is speaking is never cut off by another message.
/// * Important messages (questions, "thank you", errors) wait in line and
///   play, in order, after the current one finishes.
/// * Ambient messages (cautions, "you are inside a hazard area") are only
///   spoken when nothing else is speaking or waiting. If the app is busy
///   they are dropped, because a stale caution is worse than none.
/// * Every message is preceded by a 3-second phone vibration.
/// * [stop] ends the current speech and clears the line. Anything cleared
///   never fires its follow-up action.
class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static final List<_Item> _queue = [];
  static bool _running = false;
  static int _generation = 0;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      // Slightly slower than default — meant to be heard over wind/road
      // noise while moving, not read.
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // speak() now finishes only when the speech has finished, which is
      // what lets us play one message at a time.
      await _tts.awaitSpeakCompletion(true);
      _initialized = true;
    } catch (e) {
      if (kDebugMode) print('TtsService._ensureInitialized failed: $e');
    }
  }

  static bool get isBusy => _running || _queue.isNotEmpty;

  static Future<void> _enqueue(
    String message, {
    VoidCallback? onDone,
    required bool important,
  }) async {
    await _ensureInitialized();
    if (!_initialized) {
      onDone?.call(); // broken speech engine must never block the flow
      return;
    }
    if (!important && isBusy) return; // drop ambient while anything is speaking
    _queue.add(_Item(message, onDone, _generation));
    _pump();
  }

  static Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        if (item.generation != _generation) continue; // cleared by stop()
        // Long vibration first (3 s) so the rider's attention is caught,
        // then the message is spoken.
        await HazardHaptics.buzz();
        if (item.generation != _generation) continue; // stopped meanwhile
        try {
          await _tts.speak(item.message).timeout(const Duration(seconds: 25));
        } catch (e) {
          if (kDebugMode) print('TtsService speak failed: $e');
          try {
            await _tts.stop();
          } catch (_) {}
        }
        if (item.generation == _generation) item.onDone?.call();
      }
    } finally {
      _running = false;
    }
  }

  /// Hazard alert (ambient). Kept for older callers.
  static Future<void> speakHazardAlert({
    required String hazardLabel,
    required double distanceMeters,
  }) {
    final rounded = (distanceMeters / 10).round() * 10;
    return _enqueue('Caution: $hazardLabel reported $rounded meters ahead.', important: false);
  }

  /// Speaks [message], then calls [onDone] once it has actually finished
  /// (used to open the microphone only after the question is over).
  /// Important: it waits for anything already speaking instead of cutting
  /// it off.
  static Future<void> speakThen(String message, VoidCallback onDone) =>
      _enqueue(message, onDone: onDone, important: true);

  /// One-off message. [important] messages (answers, errors) queue behind
  /// the current speech; the default, ambient messages, are dropped if
  /// anything is already speaking.
  static Future<void> speak(String message, {bool important = false}) =>
      _enqueue(message, important: important);

  /// Stops speaking now and clears everything waiting. Cleared messages
  /// never run their follow-up action.
  static Future<void> stop() async {
    _generation++;
    _queue.clear();
    HazardHaptics.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

class _Item {
  final String message;
  final VoidCallback? onDone;
  final int generation;
  _Item(this.message, this.onDone, this.generation);
}
