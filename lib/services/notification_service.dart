import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (on-device) notifications — no Firebase, no server, no
/// internet required. These show as real system notifications, so
/// they're visible even if the app is backgrounded or the phone is
/// locked, unlike a Flutter Dialog which only exists while the app is
/// actually on screen.
///
/// This is deliberately separate from push notifications (Firebase
/// Cloud Messaging): local notifications are for things THIS device
/// already knows about on its own (the stillness safety check-in,
/// a nearby hazard) — push is for things that happen elsewhere (another
/// user's action) and need a server to relay. See PushNotificationService
/// (added separately, once the Firebase project exists) for that side.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Call once, early in main() before runApp(). Safe to call more than
  /// once — subsequent calls are no-ops.
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(settings);

    // Android 13+ requires runtime notification permission — without
    // this, every notification silently never appears, with no error.
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  static const _safetyChannel = AndroidNotificationDetails(
    'vitrax_safety',
    'Safety Check-ins',
    channelDescription: 'Alerts when the app hasn\'t detected movement during a recording',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _hazardChannel = AndroidNotificationDetails(
    'vitrax_hazards',
    'Hazard Alerts',
    channelDescription: 'Alerts when passing a community-reported hazard while recording',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _generalChannel = AndroidNotificationDetails(
    'vitrax_general',
    'Vitrax Updates',
    channelDescription: 'Chat messages, challenge updates, and other activity from other users',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Renders an incoming Firebase push message as a system notification.
  /// This is what PushNotificationService calls for a foreground message
  /// — FCM shows background/terminated-state notifications automatically
  /// on Android using the payload's own notification block, but a
  /// message arriving while the app is open needs to be displayed
  /// manually, or the user would see nothing at all.
  static Future<void> showGeneric({required String title, required String body}) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000), // unique per message, so these stack rather than replace each other
        title,
        body,
        const NotificationDetails(android: _generalChannel, iOS: DarwinNotificationDetails()),
      );
    } catch (e) {
      if (kDebugMode) print('NotificationService.showGeneric failed: $e');
    }
  }

  /// "Are you okay?" — mirrors the in-app _CheckInDialog in
  /// record_screen.dart, but as a real system notification so it's
  /// visible even if the phone is locked or the app is backgrounded
  /// when the stillness timer fires.
  static Future<void> showStillnessAlert() async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        1001, // fixed id — a second stillness alert replaces the first rather than stacking
        'Still there?',
        "We haven't detected movement in a while. Open Vitrax to check in.",
        const NotificationDetails(android: _safetyChannel, iOS: DarwinNotificationDetails()),
      );
    } catch (e) {
      if (kDebugMode) print('NotificationService.showStillnessAlert failed: $e');
    }
  }

  /// Mirrors the in-app proximity banner in record_screen.dart, for the
  /// same reason — visible even if the phone is locked when you pass
  /// the hazard.
  static Future<void> showHazardNearby(String hazardLabel) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        1002,
        'Hazard nearby',
        'Is this $hazardLabel still here? Open Vitrax to confirm.',
        const NotificationDetails(android: _hazardChannel, iOS: DarwinNotificationDetails()),
      );
    } catch (e) {
      if (kDebugMode) print('NotificationService.showHazardNearby failed: $e');
    }
  }

  /// Statement-only notice (no question) for a hazard the rider is inside
  /// of but already reported or confirmed.
  static Future<void> showInsideHazard(String hazardLabel) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        1003,
        'Hazard area',
        'You are inside a reported $hazardLabel area. Ride carefully.',
        const NotificationDetails(android: _hazardChannel, iOS: DarwinNotificationDetails()),
      );
    } catch (e) {
      if (kDebugMode) print('NotificationService.showInsideHazard failed: $e');
    }
  }

  /// One notice for a crowded area (many hazards together), so the rider
  /// gets a single notification instead of one per hazard.
  static Future<void> showAreaHazards(int count) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        1003,
        'Hazards in this area',
        '$count reported hazards here. Ride carefully.',
        const NotificationDetails(android: _hazardChannel, iOS: DarwinNotificationDetails()),
      );
    } catch (e) {
      if (kDebugMode) print('NotificationService.showAreaHazards failed: $e');
    }
  }

  /// Clears a previously-shown notification — call when the in-app
  /// dialog/banner it mirrors gets resolved (dismissed, answered, or
  /// the underlying condition clears on its own), so a stale system
  /// notification doesn't linger after it's no longer relevant.
  static Future<void> cancelStillnessAlert() => _plugin.cancel(1001);
  static Future<void> cancelHazardAlert() => _plugin.cancel(1002);
}
