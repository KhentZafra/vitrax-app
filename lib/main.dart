import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vitrax_app/screens/activity_selection_screen.dart';
import 'package:vitrax_app/screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart' show clearProfileCache;
import 'screens/routes_screen.dart' show clearRoutesCache;
import 'screens/community_feed_screen.dart' show clearFeedCache;
import 'package:provider/provider.dart';
import 'providers/activity_provider.dart';
import 'providers/chat_unread_provider.dart';
import 'services/badge_service.dart';
import 'services/connectivity_service.dart';
import 'services/error_logger.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'config/env.dart';
 
 
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash visibility: unexpected errors are saved to the app_errors table
  // (admins read it in Supabase), so a problem on someone else's phone is
  // not invisible. Logging never interrupts the app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorLogger.log(details.exception, details.stack, source: 'flutter');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogger.log(error, stack, source: 'platform');
    return true;
  };

  // Local notifications — no Firebase needed for this part. Must be
  // initialized before anything (like RecordScreen's stillness check-in
  // or hazard proximity prompt) tries to call NotificationService.show*.
  await NotificationService.init();

  // Firebase must be initialized before anything under it (Messaging
  // included) is touched. The actual project config comes from
  // android/app/google-services.json — this call has nothing
  // project-specific in it because the Google Services Gradle plugin
  // already generated the right native setup from that file.
  await Firebase.initializeApp();

  // Must be registered before runApp(), and the handler itself must be
  // a top-level function — see its own doc comment in
  // push_notification_service.dart for why.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
 
  // Real values live in config/env.dart, which is gitignored — see
  // config/env.example.dart for the template anyone cloning this repo
  // actually sees on GitHub.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  // Requests notification permission, grabs this device's FCM token,
  // and saves it to the signed-in user's profile — see
  // push_notification_service.dart for the full picture, including
  // what's NOT covered here (actually sending a push still needs a
  // server-side piece).
  await PushNotificationService.init();
 
  // Starts listening for online/offline changes app-wide. This is what
  // lets ActivityProvider auto-sync queued activities the moment
  // connectivity comes back, and what OfflineStatusBanner watches to
  // show/hide itself.
  ConnectivityService().start();
  await ConnectivityService().checkNow(); // establish the initial online/offline state before the UI renders
 
  // Screens remember their last data so tab switches are instant; forget it
  // when someone signs out so the next account never sees it.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.signedOut) {
      clearHomeCache();
      clearProfileCache();
      clearRoutesCache();
      clearFeedCache();
    }
  });

  runApp(const VitraxApp());
}
 
class VitraxApp extends StatelessWidget {
  const VitraxApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Root-level providers: this is what makes ActivityProvider and
      // ChatUnreadProvider available to every screen below. If this
      // wrapper is missing (or MaterialApp is built outside of it), any
      // screen using context.watch<...>() / Consumer / context.read<...>()
      // will throw "Could not find the correct Provider<...>".
      providers: [
        ChangeNotifierProvider(create: (_) => ActivityProvider()),
        ChangeNotifierProvider(create: (_) => ChatUnreadProvider()),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'VITRAX',
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          // No slide/fade animation when moving between screens (Home, Routes, ...).
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransitionsBuilder(),
            TargetPlatform.iOS: _NoTransitionsBuilder(),
            TargetPlatform.windows: _NoTransitionsBuilder(),
            TargetPlatform.macOS: _NoTransitionsBuilder(),
            TargetPlatform.linux: _NoTransitionsBuilder(),
          }),
          // Every screen's top bar is dark, so its title and back arrow must be white.
          appBarTheme: const AppBarTheme(foregroundColor: Colors.white, iconTheme: IconThemeData(color: Colors.white), titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        ),
        // Very large system font sizes crop text on small screens; keep the
        // app's text between 85% and 115% of normal.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            // The phone's font-size setting is kept between 85% and 115%, then
            // the whole app is shown 10% smaller. Change kAppTextScale to
            // make all text bigger or smaller.
            data: mq.copyWith(textScaler: TextScaler.linear((mq.textScaler.scale(1.0).clamp(0.85, 1.15) * kAppTextScale).toDouble())),
            child: child ?? const SizedBox.shrink(),
          );
        },
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/activitySelection': (context) => const ActivitySelectionScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}

/// Shows the next screen instantly instead of sliding or fading it in.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// App-wide text size multiplier (1.0 = normal, 0.9 = 10% smaller).
const double kAppTextScale = 0.9;
