import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_unread_provider.dart';
import '../services/chat_service.dart';
import 'chat_thread_screen.dart';

/// Standalone "Messages" screen — still usable anywhere a full pushable
/// screen is wanted. Just a thin Scaffold/AppBar wrapper around
/// [ChatConversationsList], which holds the actual list/loading logic.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), title: const Text('Messages')),
      body: const SafeArea(child: ChatConversationsList()),
    );
  }
}

/// The conversations list itself, with no Scaffold/AppBar of its own —
/// meant to be embedded directly wherever it's needed (e.g. as the
/// "Chat" tab inside CommunityFeedScreen), as well as inside
/// [ChatListScreen] above for standalone use.
class ChatConversationsList extends StatefulWidget {
  const ChatConversationsList({super.key});

  @override
  State<ChatConversationsList> createState() => _ChatConversationsListState();
}

class _ChatConversationsListState extends State<ChatConversationsList> {
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final conversations = await ChatService.fetchConversations();
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _isLoading = false;
    });
    // Keep the app-wide badge (bottom nav / "Chat" tab) in sync with
    // whatever this screen just found, in case it changed somewhere the
    // provider wasn't already refreshed (e.g. a message arrived while
    // this list — not a thread — was the visible screen).
    context.read<ChatUnreadProvider>().refresh();
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return DateFormat.jm().format(time);
    }
    return DateFormat.MMMd().format(time);
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.blue))
        : RefreshIndicator(
            onRefresh: _load,
            child: _conversations.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 100),
                        child: Column(
                          children: [
                            Icon(Icons.chat_bubble_outline, color: Colors.grey.shade700, size: 40),
                            const SizedBox(height: 12),
                            Text('No conversations yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Message someone from the Community Feed to start.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1, indent: 76),
                    itemBuilder: (context, index) {
                      final c = _conversations[index];
                      return ListTile(
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: c.id, otherUserId: c.otherUserId, otherUserName: c.otherUserName)));
                          _load();
                        },
                        leading: CircleAvatar(radius: 22, backgroundColor: const Color(0xff222222), child: const Icon(Icons.person, color: Colors.grey)),
                        title: Text(
                          c.otherUserName,
                          style: TextStyle(color: Colors.white, fontWeight: c.isUnread ? FontWeight.bold : FontWeight.w600),
                        ),
                        subtitle: Text(
                          c.lastMessageBody ?? 'Say hello 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.isUnread ? Colors.white : Colors.grey.shade500,
                            fontSize: 13,
                            fontWeight: c.isUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _timeLabel(c.lastMessageAt),
                              style: TextStyle(color: c.isUnread ? Colors.blue : Colors.grey.shade600, fontSize: 11, fontWeight: c.isUnread ? FontWeight.bold : FontWeight.normal),
                            ),
                            if (c.isUnread) ...[
                              const SizedBox(height: 6),
                              Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          );
  }
}
