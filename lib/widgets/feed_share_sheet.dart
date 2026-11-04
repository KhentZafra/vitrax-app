import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/feed_item.dart';
import '../services/chat_service.dart';
import '../services/community_feed_service.dart';
import 'user_avatar.dart';

/// Share options for a feed post: send it to a chat, or reshare it to
/// the community feed (credited to the original poster).
/// [onReshared] fires after a successful reshare so the feed can reload.
Future<void> showFeedShareSheet(BuildContext context, {required FeedItem item, required VoidCallback onReshared}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xff141414),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (sheetContext) => _ShareOptions(item: item, onReshared: onReshared, hostContext: context),
  );
}

String _originalOwnerId(FeedItem item) => item.isReshare ? item.originalUserId! : item.posterUserId;

String _originalOwnerName(FeedItem item) => item.isReshare ? (item.originalName ?? 'a Vitrax user') : item.sharerName;

/// Plain-text body used when a post is sent into a chat.
String _chatBody(FeedItem item) {
  final owner = _originalOwnerName(item);
  final caption = (item.isReshare ? item.originalCaption : item.caption)?.trim() ?? '';
  final a = item.activity;
  final buffer = StringBuffer('Shared a post by $owner');
  if (a != null) buffer.write('\n${a.title} · ${a.distanceKm.toStringAsFixed(1)} km');
  if (caption.isNotEmpty) buffer.write('\n"$caption"');
  if (item.mediaUrl != null) buffer.write('\n${item.mediaUrl}');
  return buffer.toString();
}

class _ShareOptions extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onReshared;
  final BuildContext hostContext;
  const _ShareOptions({required this.item, required this.onReshared, required this.hostContext});

  Future<void> _reshare(BuildContext sheetContext) async {
    final messenger = ScaffoldMessenger.of(hostContext);
    final note = TextEditingController();
    final owner = _originalOwnerName(item);
    final go = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1f1f1f),
        title: const Text('Reshare to community', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will be posted on your feed and credited to $owner.', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: const Color(0xff141414),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reshare')),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (go != true) return;

    final ok = await CommunityFeedService.reshare(item, note: text);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    messenger.clearSnackBars();
    messenger..clearSnackBars()..showSnackBar(SnackBar(content: Text(ok ? 'Reshared to the community.' : "Couldn't reshare this post.")));
    if (ok) onReshared();
  }

  Future<void> _sendInChat(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    await showModalBottomSheet<void>(
      context: hostContext,
      isScrollControlled: true,
      backgroundColor: const Color(0xff141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => FractionallySizedBox(heightFactor: 0.6, child: _ChatPicker(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwn = _originalOwnerId(item) == Supabase.instance.client.auth.currentUser?.id;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.send_outlined, color: Colors.blue),
            title: const Text('Send in chat', style: TextStyle(color: Colors.white)),
            subtitle: Text('Send this post to someone you\'ve chatted with', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            onTap: () => _sendInChat(context),
          ),
          ListTile(
            enabled: !isOwn,
            leading: Icon(Icons.repeat, color: isOwn ? Colors.grey.shade700 : Colors.blue),
            title: Text('Reshare to community', style: TextStyle(color: isOwn ? Colors.grey.shade600 : Colors.white)),
            subtitle: Text(
              isOwn ? "You can't reshare your own post" : 'Post it on your feed, credited to ${_originalOwnerName(item)}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            onTap: isOwn ? null : () => _reshare(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ChatPicker extends StatefulWidget {
  final FeedItem item;
  const _ChatPicker({required this.item});

  @override
  State<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends State<_ChatPicker> {
  List<ChatConversation> _conversations = [];
  bool _loading = true;
  String? _sendingTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ChatService.fetchConversations();
    if (!mounted) return;
    setState(() {
      _conversations = list;
      _loading = false;
    });
  }

  Future<void> _send(ChatConversation c) async {
    if (_sendingTo != null) return;
    setState(() => _sendingTo = c.id);
    final ok = await ChatService.sendMessage(c.id, _chatBody(widget.item));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.clearSnackBars();
    messenger..clearSnackBars()..showSnackBar(SnackBar(content: Text(ok ? 'Sent to ${c.otherUserName}.' : "Couldn't send. They may have blocked messages.")));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Send to...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1, color: Color(0xff2a2a2a)),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.blue))
              : _conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No chats yet. Tap a member\'s name in the feed and choose Message to start one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _conversations.length,
                      itemBuilder: (_, i) {
                        final c = _conversations[i];
                        return ListTile(
                          leading: UserAvatar(avatarUrl: c.otherUserAvatarUrl, radius: 20),
                          title: Text(c.otherUserName, style: const TextStyle(color: Colors.white)),
                          trailing: _sendingTo == c.id
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                              : const Icon(Icons.send, color: Colors.blue, size: 18),
                          onTap: () => _send(c),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
