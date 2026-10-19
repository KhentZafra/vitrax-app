import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vitrax_app/screens/activity_selection_screen.dart';
import 'package:vitrax_app/screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'providers/activity_provider.dart';
import 'providers/chat_unread_provider.dart';
import 'services/badge_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'config/env.dart';
 
 
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    anonKey: Env.supabaseAnonKey,
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
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
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
