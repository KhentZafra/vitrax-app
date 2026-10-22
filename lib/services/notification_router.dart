import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_item.dart';
import '../models/feed_notification.dart';
import '../screens/chat_thread_screen.dart';
import '../screens/community_feed_screen.dart';
import 'badge_service.dart' show rootNavigatorKey;
import 'chat_service.dart';
import 'community_feed_service.dart';

/// Sends the user to the right place when a notification is tapped: the post
/// (like, reshare), the post with its comments open (comment, reply), or the
/// chat conversation (new message). Works from the in-app notification list
/// and from a push tapped on the lock screen.
class NotificationRouter {
  /// Opens the post behind a feed notification.
  static Future<void> openFeed(FeedNotification n, {BuildContext? context, FeedItem? known}) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final item = known ?? await CommunityFeedService.fetchOne(n.postKind, n.postId);
    if (item == null) {
      final ctx = rootNavigatorKey.currentState?.overlay?.context;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(content: Text('That post is no longer available.')));
      }
      return;
    }
    final withComments = n.type == 'comment' || n.type == 'reply';
    await nav.push(MaterialPageRoute(builder: (_) => FeedPostScreen(item: item, openComments: withComments)));
  }

  /// Opens a chat conversation by id.
  static Future<void> openChat(String conversationId) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final list = await ChatService.fetchConversations();
    final matches = list.where((c) => c.id == conversationId);
    if (matches.isEmpty) return;
    final c = matches.first;
    await nav.push(MaterialPageRoute(
      builder: (_) => ChatThreadScreen(conversationId: c.id, otherUserId: c.otherUserId, otherUserName: c.otherUserName),
    ));
  }

  /// Handles a tapped push by its data payload (see the send-chat-push and
  /// send-feed-push edge functions). Signed-out users are ignored.
  static Future<void> handlePush(Map<String, dynamic> data) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      switch (data['type']) {
        case 'chat_message':
          final id = data['conversation_id']?.toString();
          if (id != null) await openChat(id);
          break;
        case 'feed_notification':
          final postId = data['post_id']?.toString();
          if (postId == null) return;
          final n = FeedNotification(
            id: '',
            actorId: '',
            actorName: '',
            type: data['notification_type']?.toString() ?? 'like',
            postKind: data['post_kind']?.toString() ?? 'post',
            postId: postId,
            isRead: true,
            createdAt: DateTime.now(),
          );
          await openFeed(n);
          break;
      }
    } catch (e) {
      if (kDebugMode) print('NotificationRouter.handlePush failed: $e');
    }
  }
}
