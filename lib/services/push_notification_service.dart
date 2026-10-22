import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_router.dart';
import 'notification_service.dart';

/// Push notifications via Firebase Cloud Messaging — for things that
/// happen on ANOTHER device or on the server and need to reach this one
/// even while the app is fully closed (a hazard reported near your
/// saved route, a new chat message, a challenge update). This is the
/// counterpart to NotificationService (local notifications), which
/// only handles things this device already knows about on its own.
///
/// This file only covers the CLIENT side: requesting permission,
/// obtaining this device's FCM token, saving it to Supabase so a
/// server-side function knows where to send things, and displaying
/// whatever arrives. Actually SENDING a push (e.g. the moment someone
/// reports a hazard) requires a separate server-side piece — a Supabase
/// Edge Function calling Firebase's send API with a service account —
/// which isn't part of this file.
class PushNotificationService {
  static final _supabase = Supabase.instance.client;
  static bool _initialized = false;

  /// Call once, early in main() after Firebase.initializeApp(). Safe to
  /// call more than once.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // iOS/Android 13+ both require this before a token is even issued —
    // skipping it means getToken() below can return null forever.
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    // Messages that arrive while the app is open and on screen — FCM
    // does NOT show these automatically (only background/terminated
    // ones get an automatic system notification), so this has to
    // display it manually via the existing local-notification plugin.
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'Vitrax';
      final body = message.notification?.body ?? '';
      if (body.isNotEmpty) NotificationService.showGeneric(title: title, body: body);
    });

    // Tapping a background/terminated-state notification to open the
    // app lands here. Not wired to navigate anywhere specific yet —
    // that would need each message's data payload to carry a route/id
    // and a navigator key set up in main.dart, which is a reasonable
    // next step once actual push-sending exists server-side, but isn't
    // needed for push to work at all.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) print('PushNotificationService: notification tapped — ${message.data}');
      NotificationRouter.handlePush(Map<String, dynamic>.from(message.data));
    });

    // App was fully closed and opened by tapping a push: wait a moment for
    // the first screen to appear, then go where the push points.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      Future<void>.delayed(const Duration(seconds: 2), () => NotificationRouter.handlePush(Map<String, dynamic>.from(initial.data)));
    }

    // Registers a device's token whenever it's known or changes —
    // called below both immediately (covers an already-signed-in user
    // relaunching the app) and on every future sign-in.
    _supabase.auth.onAuthStateChange.listen((_) => _registerToken());
    await _registerToken();

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) => _saveToken(newToken));
  }

  static Future<void> _registerToken() async {
    if (_supabase.auth.currentUser == null) return; // nothing to attach the token to yet
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(token);
  }

  /// Saves this device's current FCM token on the signed-in user's
  /// profile row, so a server-side function knows which device(s) to
  /// send that user's pushes to. Requires a `fcm_token text` column on
  /// `profiles` — see the migration note where this is called from.
  static Future<void> _saveToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('profiles').update({'fcm_token': token}).eq('id', user.id);
    } catch (e) {
      if (kDebugMode) print('PushNotificationService._saveToken failed: $e');
    }
  }

  /// Clears this device's token from the profile row — call on sign
  /// out, so a signed-out device doesn't keep receiving another user's
  /// pushes if someone else signs into the same profile later, or this
  /// user signs into a different device and this one goes stale.
  static Future<void> clearToken(String userId) async {
    try {
      await _supabase.from('profiles').update({'fcm_token': null}).eq('id', userId);
    } catch (e) {
      if (kDebugMode) print('PushNotificationService.clearToken failed: $e');
    }
  }
}

/// Handles a push arriving while the app is fully terminated or
/// backgrounded. Must be a TOP-LEVEL function (not a class method) and
/// annotated exactly like this — Firebase runs it in a separate isolate
/// with no access to the rest of the app's state, so it can only do
/// isolate-safe work. Registered in main.dart via
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler).
///
/// Deliberately empty: Android/iOS already show a system notification
/// automatically for a background/terminated message that has a
/// `notification` block (which is what the server-side sender should
/// always include) — this handler only needs to exist for any silent
/// "data-only" pushes that want custom background handling later.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
