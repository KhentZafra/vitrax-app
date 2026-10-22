import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../config/media_limits.dart';
import '../models/activity.dart';
import '../models/feed_item.dart';
import '../providers/activity_provider.dart';
import '../providers/chat_unread_provider.dart';
import '../services/community_feed_service.dart';
import '../services/media_upload_service.dart';
import '../services/feed_notification_service.dart';
import '../services/table_watcher.dart';
import '../widgets/feed_comments_sheet.dart';
import '../widgets/feed_share_sheet.dart';
import '../widgets/nav_badge.dart';
import '../widgets/user_actions_sheet.dart';
import 'challenges_screen.dart';
import 'chat_list_screen.dart';
import 'feed_notifications_screen.dart';
import 'profile_screen.dart';
import '../services/photo_upload_service.dart';
import '../widgets/route_nav_icon.dart';
import '../widgets/user_avatar.dart';
import 'routes_screen.dart';

/// Community feed — two ways to post: share one of your recorded
/// activities (optionally with a photo + caption), or post a standalone
/// photo/video with a caption and no activity attached. Both kinds are
/// merged into one feed, sorted newest-first. Likes are wired up for
/// both kinds. Comments are stubbed (count only).
class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  int _topTab = 0; // 0 = Feed, 1 = Challenges, 2 = Chat
  bool _searching = false;
  final _searchController = TextEditingController();

  List<FeedItem> _items = [];
  bool _isLoading = true;
  String? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();
  String? _myAvatarUrl;
  int _notifCount = 0;
  TableWatcher? _feedWatcher;
  TableWatcher? _notifWatcher;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    context.read<ActivityProvider>().loadActivities();
    context.read<ChatUnreadProvider>().refresh();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 700) {
        _loadMore();
      }
    });
    _load();
    _loadMyAvatar();
    _refreshNotifCount();
    _startLive();
  }

  /// Live updates: new posts, likes and comments refresh the feed, and a
  /// new notification bumps the bell - no pull-to-refresh needed. The
  /// 30s ticker keeps "5m ago" labels current.
  void _startLive() {
    _feedWatcher = TableWatcher(() => _load(silent: true), debounce: const Duration(milliseconds: 800))
      ..watch('community_posts')
      ..watch('feed_comments')
      ..watch('post_likes')
      ..watch('activity_likes');
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me != null) {
      _notifWatcher = TableWatcher(_refreshNotifCount, debounce: const Duration(milliseconds: 300))
        ..watch('feed_notifications', event: PostgresChangeEvent.insert, filterColumn: 'user_id', filterValue: me);
    }
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshNotifCount() async {
    final n = await FeedNotificationService.unreadCount();
    if (!mounted) return;
    setState(() => _notifCount = n);
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FeedNotificationsScreen(items: _items, onCommentCount: _setCommentCount)),
    );
    if (mounted) _refreshNotifCount();
  }

  /// Just for the composer bar's own avatar at the top of the feed —
  /// every other avatar on this screen (post authors) comes through
  /// FeedItem.sharerAvatarUrl from the feed query itself.
  Future<void> _loadMyAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await Supabase.instance.client.from('profiles').select('avatar_url').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      setState(() => _myAvatarUrl = profile?['avatar_url'] as String?);
    } catch (_) {
      // Non-critical — the composer bar just keeps its placeholder icon.
    }
  }

  @override
  void dispose() {
    _feedWatcher?.dispose();
    _notifWatcher?.dispose();
    _ticker?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final page = await CommunityFeedService.fetchFeedPage();
    if (!mounted) return;
    setState(() {
      if (silent && _items.length > page.items.length && page.items.isNotEmpty) {
        // A live refresh while the user has scrolled deeper: replace the
        // newest page but keep the older posts already loaded below it.
        final tailTime = page.items.last.createdAt;
        final older = _items.where((p) => p.createdAt.isBefore(tailTime)).toList();
        _items = [...page.items, ...older];
      } else {
        _items = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      }
      _isLoading = false;
    });
  }

  /// Loads the next 20 posts when the user scrolls near the bottom.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _isLoading || _cursor == null) return;
    setState(() => _loadingMore = true);
    final page = await CommunityFeedService.fetchFeedPage(before: _cursor);
    if (!mounted) return;
    setState(() {
      final have = _items.map((p) => '${p.kind}:${p.id}').toSet();
      _items = [..._items, ...page.items.where((p) => !have.contains('${p.kind}:${p.id}'))];
      _cursor = page.cursor ?? _cursor;
      _hasMore = page.hasMore;
      _loadingMore = false;
    });
  }

  List<FeedItem> get _visibleItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((p) => p.sharerName.toLowerCase().contains(query) || (p.caption ?? '').toLowerCase().contains(query)).toList();
  }

  Future<void> _toggleLike(FeedItem item) async {
    final index = _items.indexWhere((p) => p.id == item.id && p.kind == item.kind);
    if (index == -1) return;

    setState(() {
      _items[index] = item.copyWith(
        likedByMe: !item.likedByMe,
        likeCount: item.likedByMe ? item.likeCount - 1 : item.likeCount + 1,
      );
    });

    final result = await CommunityFeedService.toggleLike(item, currentlyLiked: item.likedByMe);
    if (result == null && mounted) {
      setState(() => _items[index] = item);
    }
  }

  void _setCommentCount(FeedItem item, int count) {
    final index = _items.indexWhere((p) => p.id == item.id && p.kind == item.kind);
    if (index == -1 || _items[index].commentCount == count) return;
    setState(() => _items[index] = _items[index].copyWith(commentCount: count));
  }

  Future<void> _openComposerChoice() async {
    ScaffoldMessenger.of(context).clearSnackBars();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Share to Community', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.directions_run, color: Colors.blue),
              title: const Text('Share an activity', style: TextStyle(color: Colors.white)),
              subtitle: Text('Post one of your recordings, with an optional photo', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              onTap: () => Navigator.pop(context, 'activity'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined, color: Colors.blue),
              title: const Text('New post', style: TextStyle(color: Colors.white)),
              subtitle: Text('Share a photo or video — no activity needed', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              onTap: () => Navigator.pop(context, 'post'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'activity') {
      await _shareActivityFlow();
    } else if (choice == 'post') {
      await _newPostFlow();
    }
  }

  Future<void> _shareActivityFlow() async {
    final provider = context.read<ActivityProvider>();
    final unshared = provider.allActivities.where((a) => !a.shared).toList();

    if (!mounted) return;
    if (unshared.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record an activity first, then share it here.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<Activity>(
      context: context,
      backgroundColor: const Color(0xff111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _ActivityPickerSheet(activities: unshared),
    );
    if (chosen == null || chosen.id == null || !mounted) return;

    final details = await showModalBottomSheet<_ComposeDetails>(
      context: context,
      backgroundColor: const Color(0xff141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => const _PhotoAndCaptionSheet(title: 'Share your activity'),
    );
    if (details == null || !mounted) return;

    String? photoUrl;
    if (details.photoFile != null) {
      photoUrl = await PhotoUploadService.uploadForActivity(file: details.photoFile!, activityId: chosen.id!);
      if (photoUrl == null && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't upload the photo — sharing without it.")),
        );
      }
    }
    if (!mounted) return;

    final success = await provider.markActivityShared(chosen.id!, caption: details.caption, photoUrl: photoUrl);
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    if (success) {
      _load();
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share right now, Please try again later.')),
      );
    }
  }

  Future<void> _newPostFlow() async {
    final result = await showModalBottomSheet<_NewPostResult>(
      context: context,
      backgroundColor: const Color(0xff141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => const _NewPostSheet(),
    );
    if (result == null || !mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading…'), duration: Duration(seconds: 30)),
    );

    final mediaUrl = await MediaUploadService.upload(file: result.file, mediaType: result.mediaType);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();

    if (mediaUrl == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't upload, Please check your connection and try again.")),
      );
      return;
    }

    final success = await CommunityFeedService.createPost(mediaUrl: mediaUrl, mediaType: result.mediaType, caption: result.caption);
    if (!mounted) return;

    if (success) {
      _load();
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post right now, Please try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTopTabs(),
            Expanded(
              child: switch (_topTab) {
                0 => _buildFeed(),
                1 => _buildChallengesStub(),
                _ => _buildChatTab(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text('Community', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: _openNotifications,
            icon: NavBadge(count: _notifCount, child: const Icon(Icons.notifications_none, color: Colors.white)),
            style: IconButton.styleFrom(backgroundColor: const Color(0xff141414), shape: const CircleBorder()),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setState(() => _searching = !_searching),
            icon: Icon(_searching ? Icons.close : Icons.search, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: const Color(0xff141414), shape: const CircleBorder()),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          _TopTabButton(label: 'Feed', selected: _topTab == 0, onTap: () => setState(() => _topTab = 0)),
          const SizedBox(width: 20),
          _TopTabButton(label: 'Challenges', selected: _topTab == 1, onTap: () => setState(() => _topTab = 1)),
          const SizedBox(width: 20),
          Consumer<ChatUnreadProvider>(
            builder: (context, unread, _) => _TopTabButton(label: 'Chat', selected: _topTab == 2, badgeCount: unread.count, onTap: () => setState(() => _topTab = 2)),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesStub() {
    return const ChallengesScreen();
  }

  Widget _buildChatTab() {
    return const ChatConversationsList();
  }

  Widget _buildFeed() {
    return Skeletonizer(
      enabled: _isLoading,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search posts…',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: const Color(0xff141414),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
              ),
            _buildComposerBar(),
            const SizedBox(height: 16),
            if (!_isLoading && _visibleItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    _items.isEmpty ? 'No posts yet. Be the first to share!' : 'No posts match your search.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              ...(_isLoading
                  ? List.generate(2, (_) => const _PostSkeleton())
                  : _visibleItems.map((item) => _FeedItemCard(item: item, onLike: () => _toggleLike(item), onCommentCount: (n) => _setCommentCount(item, n), onReshared: _load))),
            if (!_isLoading && _loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            if (!_isLoading && !_hasMore && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("You're all caught up", style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerBar() {
    return InkWell(
      onTap: _openComposerChoice,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xff111111), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)),
        child: Row(
          children: [
            UserAvatar(avatarUrl: _myAvatarUrl, radius: 18),
            const SizedBox(width: 12),
            const Expanded(child: Text('Share your activity, a photo, or a video…', style: TextStyle(color: Colors.blue, fontSize: 14))),
            const Icon(Icons.add_circle_outline, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  void _navigateFromNav(int index) {
    const currentIndex = 3;
    if (index == currentIndex) return;
    switch (index) {
      case 0:
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoutesScreen()));
        break;
      case 2:
        Navigator.of(context).pushNamedAndRemoveUntil('/activitySelection', (route) => false);
        break;
      case 4:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        break;
    }
  }

  Widget _buildBottomNav() {
    return Container(
      height: 90,
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavTab(icon: Icons.home_rounded, label: 'Home', selected: false, onTap: () => _navigateFromNav(0)),
          _NavTab(customIcon: (color) => RouteNavIcon(color: color), label: 'Routes', selected: false, onTap: () => _navigateFromNav(1)),
          _RecordNavTab(onTap: () => _navigateFromNav(2)),
          Consumer<ChatUnreadProvider>(
            builder: (context, unread, _) =>
                _NavTab(icon: Icons.chat_bubble_outline, label: 'Community', selected: true, badgeCount: unread.count, onTap: () => _navigateFromNav(3)),
          ),
          _NavTab(icon: Icons.person_outline, label: 'You', selected: false, onTap: () => _navigateFromNav(4)),
        ],
      ),
    );
  }
}

class _TopTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  const _TopTabButton({required this.label, required this.selected, required this.onTap, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NavBadge(
            count: badgeCount,
            child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey.shade500, fontSize: 16, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(height: 6),
          Container(width: 24, height: 3, decoration: BoxDecoration(color: selected ? Colors.blue : Colors.transparent, borderRadius: BorderRadius.circular(2))),
        ],
      ),
    );
  }
}

class _ActivityPickerSheet extends StatelessWidget {
  final List<Activity> activities;
  const _ActivityPickerSheet({required this.activities});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share an activity', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: activities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final a = activities[index];
                  return InkWell(
                    onTap: () => Navigator.pop(context, a),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xff1a1a1a), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(a.type == ActivityType.run ? Icons.directions_run : Icons.pedal_bike, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                Text('${a.distanceKm.toStringAsFixed(1)} km', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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
          ],
        ),
      ),
    );
  }
}

class _ComposeDetails {
  final String? caption;
  final File? photoFile;
  const _ComposeDetails({this.caption, this.photoFile});
}

class _PhotoAndCaptionSheet extends StatefulWidget {
  final String title;
  const _PhotoAndCaptionSheet({required this.title});

  @override
  State<_PhotoAndCaptionSheet> createState() => _PhotoAndCaptionSheetState();
}

class _PhotoAndCaptionSheetState extends State<_PhotoAndCaptionSheet> {
  final _controller = TextEditingController();
  File? _photo;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _picking = true);
    final file = await PhotoUploadService.pickPhoto(source: source);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (file != null) _photo = file;
    });
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff1a1a1a),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Colors.white),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _picking ? null : _showSourcePicker,
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xff1a1a1a),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                  image: _photo != null ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover) : null,
                ),
                child: _picking
                    ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                    : _photo == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade500, size: 28),
                                const SizedBox(height: 8),
                                Text('Add a photo (optional)', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                              ],
                            ),
                          )
                        : Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: InkWell(
                                onTap: () => setState(() => _photo = null),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: _photo == null,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Share how it went…',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: const Color(0xff1a1a1a),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel', style: TextStyle(color: Colors.grey)))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _ComposeDetails(caption: _controller.text.trim().isEmpty ? null : _controller.text.trim(), photoFile: _photo),
                    ),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPostResult {
  final File file;
  final FeedMediaType mediaType;
  final String? caption;
  const _NewPostResult({required this.file, required this.mediaType, this.caption});
}

class _NewPostSheet extends StatefulWidget {
  const _NewPostSheet();

  @override
  State<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends State<_NewPostSheet> {
  final _controller = TextEditingController();
  File? _media;
  FeedMediaType? _mediaType;
  VideoPlayerController? _previewController;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _setMedia(File file, FeedMediaType type) async {
    _previewController?.dispose();
    _previewController = null;

    if (type == FeedMediaType.video) {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0);
      controller.play();
      _previewController = controller;
    }

    if (!mounted) return;
    setState(() {
      _media = file;
      _mediaType = type;
    });
  }

  Future<void> _pick(ImageSource source, FeedMediaType type) async {
    setState(() => _picking = true);
    final file = type == FeedMediaType.photo ? await MediaUploadService.pickPhoto(source: source) : await MediaUploadService.pickVideo(source: source);
    if (!mounted) return;

    if (file != null) {
      final sizeError = await MediaUploadService.checkSizeLimit(file, type);
      if (!mounted) return;
      if (sizeError != null) {
        setState(() => _picking = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sizeError)));
        return;
      }
    }

    setState(() => _picking = false);
    if (file != null) await _setMedia(file, type);
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff1a1a1a),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Colors.white),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera, FeedMediaType.photo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('Choose photo from gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery, FeedMediaType.photo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: Colors.white),
              title: const Text('Record a video', style: TextStyle(color: Colors.white)),
              subtitle: Text('Up to ${MediaLimits.maxVideoDuration.inSeconds} seconds', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera, FeedMediaType.video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined, color: Colors.white),
              title: const Text('Choose video from gallery', style: TextStyle(color: Colors.white)),
              subtitle: Text('Up to ${MediaLimits.maxVideoDuration.inSeconds}s and ${MediaLimits.maxVideoSizeMb}MB', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery, FeedMediaType.video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_picking) return const Center(child: CircularProgressIndicator(color: Colors.blue));
    if (_media == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade500, size: 30),
            const SizedBox(height: 8),
            Text('Add a photo or video', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      );
    }
    if (_mediaType == FeedMediaType.photo) {
      return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(_media!, fit: BoxFit.cover, width: double.infinity, height: double.infinity));
    }
    if (_previewController != null && _previewController!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: _previewController!.value.size.width, height: _previewController!.value.size.height, child: VideoPlayer(_previewController!)),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: Colors.blue));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New post', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _showSourcePicker,
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(color: const Color(0xff1a1a1a), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildPreview()),
                    if (_media != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          onTap: () {
                            _previewController?.dispose();
                            _previewController = null;
                            setState(() {
                              _media = null;
                              _mediaType = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write a caption…',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: const Color(0xff1a1a1a),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel', style: TextStyle(color: Colors.grey)))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _media == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              _NewPostResult(file: _media!, mediaType: _mediaType!, caption: _controller.text.trim().isEmpty ? null : _controller.text.trim()),
                            ),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Post'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onLike;
  final ValueChanged<int> onCommentCount;
  final VoidCallback onReshared;
  const _FeedItemCard({required this.item, required this.onLike, required this.onCommentCount, required this.onReshared});

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  /// Tapping a poster's photo or name opens View profile / Message /
  /// Block / Report (not straight into a chat).
  void _openUserMenu(BuildContext context) {
    showUserActionsSheet(
      context,
      userId: item.posterUserId,
      userName: item.sharerName,
      avatarUrl: item.sharerAvatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activity = item.activity;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: const Color(0xff0d0d0d), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _openUserMenu(context),
                  borderRadius: BorderRadius.circular(20),
                  child: UserAvatar(avatarUrl: item.sharerAvatarUrl, radius: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _openUserMenu(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.sharerName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        if (item.isReshare) const Text('Reshared a post', style: TextStyle(color: Colors.blue, fontSize: 13)),
                        if (activity != null) Text('${activity.title} · ${activity.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: Colors.blue, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Text(_relativeTime(item.createdAt), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          if (item.mediaUrl != null || activity != null)
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: SizedBox(height: 220, width: double.infinity, child: _buildMedia(activity)),
            ),
          if ((item.caption ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(item.caption!, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
            ),
          if (item.isReshare)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xff1a1a1a), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xff2a2a2a))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => showUserActionsSheet(context, userId: item.originalUserId!, userName: item.originalName ?? 'A Vitrax user'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.repeat, color: Colors.blue, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Originally posted by ${item.originalName ?? 'a Vitrax user'}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    if ((item.originalCaption ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(item.originalCaption!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                InkWell(
                  onTap: onLike,
                  child: Row(
                    children: [
                      Icon(item.likedByMe ? Icons.favorite : Icons.favorite_border, color: item.likedByMe ? Colors.red : Colors.blue, size: 20),
                      const SizedBox(width: 6),
                      Text('${item.likeCount}', style: const TextStyle(color: Colors.blue, fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                InkWell(
                  onTap: () => showFeedCommentsSheet(context, item: item, onCountChanged: onCommentCount),
                  child: Row(children: [const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 19), const SizedBox(width: 6), Text('${item.commentCount}', style: const TextStyle(color: Colors.blue, fontSize: 14))]),
                ),
                const SizedBox(width: 24),
                InkWell(
                  onTap: () => showFeedShareSheet(context, item: item, onReshared: onReshared),
                  child: const Icon(Icons.share_outlined, color: Colors.blue, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(Activity? activity) {
    if (item.mediaType == FeedMediaType.video && item.mediaUrl != null) {
      return _InlineVideo(url: item.mediaUrl!);
    }
    if (item.mediaType == FeedMediaType.photo && item.mediaUrl != null) {
      return Image.network(
        item.mediaUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(color: const Color(0xff141414), child: const Center(child: CircularProgressIndicator(color: Colors.blue)));
        },
        errorBuilder: (context, error, stackTrace) => activity != null ? _RouteSketchBackground(points: activity.route) : Container(color: const Color(0xff141414)),
      );
    }
    if (activity != null) return _RouteSketchBackground(points: activity.route);
    return Container(color: const Color(0xff141414), child: Center(child: Icon(Icons.image_outlined, color: Colors.grey.shade700, size: 32)));
  }
}

/// Video player for the feed: tap the video to play/pause, plus a
/// bottom control bar with an explicit play/pause button, a scrubbable
/// timeline (drag anywhere on it to jump to that point), current/total
/// time, and a mute toggle.
class _InlineVideo extends StatefulWidget {
  final String url;
  const _InlineVideo({required this.url});

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? _controller;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      controller.setVolume(0);
      setState(() => _controller = controller);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(color: const Color(0xff141414), child: const Center(child: CircularProgressIndicator(color: Colors.blue)));
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, value, child) {
        return GestureDetector(
          onTap: _togglePlay,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: value.size.width, height: value.size.height, child: VideoPlayer(c)),
              ),
              // Brief center play icon only while paused — tapping the
              // video always toggles play, this is just a visual cue.
              if (!value.isPlaying)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              // Bottom control bar: play/pause, scrubbable timeline,
              // elapsed/total time, mute toggle.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 2),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // allowScrubbing lets the user drag/tap anywhere on
                      // this bar to jump to that point in the video.
                      VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        padding: EdgeInsets.zero,
                        colors: const VideoProgressColors(playedColor: Colors.blueAccent, bufferedColor: Colors.white30, backgroundColor: Colors.white12),
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: _togglePlay,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                            ),
                          ),
                          Text(
                            '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: _toggleMute,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(height: 300, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: const Color(0xff0d0d0d), borderRadius: BorderRadius.circular(16)));
  }
}

class _RouteSketchBackground extends StatelessWidget {
  final List<GpsPoint> points;
  const _RouteSketchBackground({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff141414),
      child: points.length > 1 ? CustomPaint(painter: _SketchPainter(points), child: const SizedBox.expand()) : Center(child: Icon(Icons.map_outlined, color: Colors.grey.shade700, size: 32)),
    );
  }
}

class _SketchPainter extends CustomPainter {
  final List<GpsPoint> points;
  _SketchPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final latRange = (maxLat - minLat).abs() < 0.0001 ? 0.0001 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 0.0001 ? 0.0001 : (maxLng - minLng);

    const padding = 24.0;
    Offset project(GpsPoint p) {
      final x = padding + ((p.lng - minLng) / lngRange) * (size.width - padding * 2);
      final y = size.height - padding - ((p.lat - minLat) / latRange) * (size.height - padding * 2);
      return Offset(x, y);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(path, Paint()..color = Colors.blue..strokeWidth = 4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(project(points.first), 6, Paint()..color = Colors.green);
    canvas.drawCircle(project(points.last), 6, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => false;
}

class _NavTab extends StatelessWidget {
  final IconData? icon;
  final Widget Function(Color color)? customIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  // Only the "Community" tab passes this (see _buildBottomNav) — it's
  // where unread chat conversations live, so this is the one spot in
  // the bottom nav that needs to show something new is waiting.
  final int badgeCount;

  const _NavTab({this.icon, this.customIcon, required this.label, required this.selected, required this.onTap, this.badgeCount = 0})
      : assert(icon != null || customIcon != null);

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.blueAccent : Colors.grey;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavBadge(count: badgeCount, child: customIcon != null ? customIcon!(color) : Icon(icon, color: color, size: 24)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _RecordNavTab extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordNavTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
              // Nudged 2px right so the triangle's visual center (its
              // bulk sits left of its bounding box) lines up with the
              // circle's actual center instead of looking off-balance.
              child: const Center(child: Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30))),
            ),
          ),
          const Text('Record', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}


/// A single post on its own screen. Opened from a notification (someone
/// liked or reshared it) or a push tap. [openComments] also pops up the
/// comments straight away (used for comment and reply notifications).
class FeedPostScreen extends StatefulWidget {
  final FeedItem item;
  final bool openComments;
  const FeedPostScreen({super.key, required this.item, this.openComments = false});

  @override
  State<FeedPostScreen> createState() => _FeedPostScreenState();
}

class _FeedPostScreenState extends State<FeedPostScreen> {
  late FeedItem _item = widget.item;

  @override
  void initState() {
    super.initState();
    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFeedCommentsSheet(context, item: _item, onCountChanged: _setCount);
      });
    }
  }

  void _setCount(int n) {
    if (mounted && _item.commentCount != n) setState(() => _item = _item.copyWith(commentCount: n));
  }

  Future<void> _like() async {
    final before = _item;
    setState(() => _item = before.copyWith(likedByMe: !before.likedByMe, likeCount: before.likedByMe ? before.likeCount - 1 : before.likeCount + 1));
    final r = await CommunityFeedService.toggleLike(before, currentlyLiked: before.likedByMe);
    if (r == null && mounted) setState(() => _item = before);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), foregroundColor: Colors.white, title: const Text('Post')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [_FeedItemCard(item: _item, onLike: _like, onCommentCount: _setCount, onReshared: () {})],
      ),
    );
  }
}
