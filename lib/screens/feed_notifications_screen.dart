import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/skeleton_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_item.dart';
import '../models/feed_notification.dart';
import '../services/feed_notification_service.dart';
import '../services/notification_router.dart';
import '../services/table_watcher.dart';
import '../widgets/user_avatar.dart';

/// Who liked, commented on, replied to or reshared your feed posts.
/// [items] is the feed already loaded by the caller, used to open the
/// comment thread when a comment/reply notification is tapped.
class FeedNotificationsScreen extends StatefulWidget {
  final List<FeedItem> items;
  final void Function(FeedItem item, int count) onCommentCount;
  const FeedNotificationsScreen({super.key, required this.items, required this.onCommentCount});

  @override
  State<FeedNotificationsScreen> createState() => _FeedNotificationsScreenState();
}

class _FeedNotificationsScreenState extends State<FeedNotificationsScreen> {
  List<FeedNotification> _list = [];
  bool _loading = true;
  TableWatcher? _watcher;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Live: a new like/comment appears at the top while this is open.
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me != null) {
      _watcher = TableWatcher(_load, debounce: const Duration(milliseconds: 300))
        ..watch('feed_notifications', event: PostgresChangeEvent.insert, filterColumn: 'user_id', filterValue: me);
    }
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await FeedNotificationService.fetch();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
    // Rows stay highlighted this visit (they were captured as unread),
    // but the bell badge clears.
    await FeedNotificationService.markAllRead();
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _icon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'reshare':
        return Icons.repeat;
      default:
        return Icons.chat_bubble;
    }
  }

  void _open(FeedNotification n) {
    // Use the copy already loaded in the feed when there is one; otherwise
    // the router fetches the post. Likes and reshares open the post too.
    final kind = n.postKind == 'activity' ? FeedItemKind.activityShare : FeedItemKind.standalonePost;
    final matches = widget.items.where((i) => i.id == n.postId && i.kind == kind);
    NotificationRouter.openFeed(n, known: matches.isEmpty ? null : matches.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
      ),
      body: _loading
          ? const ListSkeleton()
          : _list.isEmpty
              ? Center(child: Text('No notifications yet.', style: TextStyle(color: Colors.grey.shade500)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xff1a1a1a)),
                    itemBuilder: (_, i) {
                      final n = _list[i];
                      return InkWell(
                        onTap: () => _open(n),
                        child: Container(
                          color: n.isRead ? Colors.transparent : const Color(0xff0f1a2e),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  UserAvatar(avatarUrl: n.actorAvatarUrl, radius: 22),
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(color: n.type == 'like' ? Colors.red : Colors.blue, shape: BoxShape.circle),
                                      child: Icon(_icon(n.type), size: 10, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: n.actorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        TextSpan(text: ' ${n.message}'),
                                      ]),
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                    if ((n.body ?? '').isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('"${n.body}"', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(_ago(n.createdAt), style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
