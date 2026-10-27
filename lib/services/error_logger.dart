import 'dart:io' show Platform;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Saves unexpected app errors to the `app_errors` table so crashes on other
/// people's phones can be seen. Safe by design: it never throws, never logs
/// the same error twice per session, and stops after 20 errors per session.
class ErrorLogger {
  static final Set<String> _seen = {};
  static int _count = 0;

  static String _cut(String text, int max) => text.length <= max ? text : text.substring(0, max);

  static Future<void> log(Object error, StackTrace? stack, {String source = 'app'}) async {
    try {
      if (_count >= 20) return;
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final message = error.toString();
      if (!_seen.add(message.split('\n').first)) return;
      _count++;
      await Supabase.instance.client.from('app_errors').insert({
        'user_id': user.id,
        'message': _cut(message, 500),
        'stack': _cut(stack?.toString() ?? '', 3000),
        'source': source,
        'platform': Platform.operatingSystem,
      });
    } catch (_) {
      // Logging must never cause another error.
    }
  }
}
