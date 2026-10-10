import 'package:flutter/foundation.dart';

import '../services/chat_service.dart';
import '../services/table_watcher.dart';

/// Holds the app-wide unread-conversations count so any screen's bottom
/// nav / tab bar can show a badge without each one running its own
/// query. Call [refresh] whenever the count might have changed: app
/// start, returning to a screen with a nav bar, and right after a chat
/// thread is opened (marking it read) or closed.
///
/// Deliberately simple (a manual refresh(), not a live subscription) —
/// this app doesn't push background notifications, so "exactly live to
/// the second" isn't the goal; "correct the next time you look at a
/// screen with the badge on it" is.
class ChatUnreadProvider extends ChangeNotifier {
  int _count = 0;
  int get count => _count;
  bool get hasUnread => _count > 0;

  TableWatcher? _watcher;

  /// Live: any message change re-counts unread conversations, so the
  /// badge updates the moment someone writes to you.
  void _ensureWatching() {
    if (_watcher != null) return;
    _watcher = TableWatcher(() => refresh(), debounce: const Duration(milliseconds: 400))..watch('messages');
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    _ensureWatching();
    final newCount = await ChatService.fetchUnreadConversationCount();
    if (newCount == _count) return; // avoid a pointless rebuild
    _count = newCount;
    notifyListeners();
  }
}
