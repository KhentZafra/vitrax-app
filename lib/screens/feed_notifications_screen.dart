import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/skeleton_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_item.dart';
import '../models/feed_notification.dart';
import '../services/feed_notification_service.dart';
import '../services/notification_router.dart';
import '../services/table_watcher.dart';
import '../services/badge_service.dart';
import '../widgets/user_avatar.dart';

/// Who liked, commented on, replied to or reshared your feed posts.
/// [items] is the feed already loaded by the caller, used to open the
/// comment thread when a comment/reply notification is tapped.
class FeedNotificationsScreen extends StatefulWidget {
  final List<FeedItem> items;
  final void Function(FeedItem item, int count) onCommentCount;
  /// true = opened from Community: only likes, comments, replies, reshares.
  /// false = the general Home bell: everything.
  final bool communityOnly;
  const FeedNotificationsScreen({super.key, required this.items, required this.onCommentCount, this.communityOnly = false});

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
    final list = await FeedNotificationService.fetch(communityOnly: widget.communityOnly);
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
    // Rows stay highlighted this visit (they were captured as unread),
    // but the bell badge clears.
    await FeedNotificationService.markAllRead(communityOnly: widget.communityOnly);
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
      case 'route_like':
        return Icons.favorite;
      case 'route_retrace':
        return Icons.directions_bike;
      case 'announcement':
        return Icons.campaign;
      case 'badge':
        return Icons.emoji_events;
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
    NotificationRouter.openNotification(n, known: matches.isEmpty ? null : matches.first);
  }

  /// "route_pioneer:bronze" -> "Route Pioneer (Bronze)".
  String _badgeText(String? body) {
    final parts = (body ?? '').split(':');
    if (parts.length != 2) return 'a new badge';
    final matches = BadgeService.defs.where((d) => d.key == parts[0]);
    final title = matches.isEmpty ? parts[0].replaceAll('_', ' ') : matches.first.title;
    final tier = parts[1].isEmpty ? '' : parts[1][0].toUpperCase() + parts[1].substring(1);
    return '$title ($tier)';
  }

  /// Official challenge announcement: a bright card so it stands out in the list.
  Widget _announcementTile(FeedNotification n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(n),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [Color(0xff1b3a8a), Color(0xff0b1c3d)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: n.isRead ? const Color(0xff2a3a66) : const Color(0xffFFC83D), width: n.isRead ? 1 : 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 22, backgroundColor: Color(0xffFFC83D), child: Icon(Icons.campaign, color: Colors.black, size: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('VITRAX ADMIN', style: TextStyle(color: Color(0xffFFC83D), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(width: 8),
                      Text(_ago(n.createdAt), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ]),
                    const SizedBox(height: 6),
                    Text(n.body ?? 'A new challenge is live. Join now!', style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 8),
                    const Text('Tap to view and join  >', style: TextStyle(color: Color(0xff6aa2ff), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        foregroundColor: Colors.white,
        title: Text(widget.communityOnly ? 'Community Notifications' : 'Notifications'),
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
                      if (n.isAnnouncement) return _announcementTile(n);
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
                                  n.isBadge
                                      ? const CircleAvatar(radius: 22, backgroundColor: Color(0xff2a2110), child: Icon(Icons.emoji_events, color: Color(0xffFFC83D), size: 24))
                                      : UserAvatar(avatarUrl: n.actorAvatarUrl, radius: 22),
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(color: (n.type == 'like' || n.type == 'route_like') ? Colors.red : (n.isBadge ? const Color(0xffFFC83D) : Colors.blue), shape: BoxShape.circle),
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
                                      n.isBadge
                                          ? TextSpan(children: [
                                              const TextSpan(text: 'You earned the '),
                                              TextSpan(text: _badgeText(n.body), style: const TextStyle(fontWeight: FontWeight.bold)),
                                              const TextSpan(text: ' badge.'),
                                            ])
                                          : TextSpan(children: [
                                              TextSpan(text: n.actorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              TextSpan(text: ' ${n.message}'),
                                            ]),
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                    if ((n.body ?? '').isNotEmpty && !n.isBadge)
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
