import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/skeleton_views.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_unread_provider.dart';
import '../services/chat_service.dart';
import '../services/table_watcher.dart';
import '../widgets/user_avatar.dart';
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
///
/// Long-press a chat for: Archive, Report, Block, Delete conversation.
/// Archived chats leave this list and live behind an "Archived chats" row
/// at the top (like Telegram).
class ChatConversationsList extends StatefulWidget {
  const ChatConversationsList({super.key});

  @override
  State<ChatConversationsList> createState() => _ChatConversationsListState();
}

class _ChatConversationsListState extends State<ChatConversationsList> {
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;
  TableWatcher? _watcher;
  Timer? _ticker;

  List<ChatConversation> get _active => _conversations.where((c) => !c.isArchived).toList();
  List<ChatConversation> get _archived => _conversations.where((c) => c.isArchived).toList();

  @override
  void initState() {
    super.initState();
    _load();
    // Live: new/updated messages refresh the list without a spinner.
    _watcher = TableWatcher(() => _load(silent: true))..watch('messages');
    // Re-draw every 30s so "3:05 PM" vs "Yesterday" labels stay current.
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
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

  Future<void> _openArchived() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()));
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const ListSkeleton();

    final active = _active;
    final archived = _archived;
    final showArchivedRow = archived.isNotEmpty;

    if (active.isEmpty && !showArchivedRow) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
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
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: active.length + (showArchivedRow ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1, indent: 76),
        itemBuilder: (context, index) {
          if (showArchivedRow && index == 0) {
            return _ArchivedRow(archived: archived, onTap: _openArchived);
          }
          final c = active[index - (showArchivedRow ? 1 : 0)];
          return ConversationTile(
            conversation: c,
            onChanged: _load,
          );
        },
      ),
    );
  }
}

String _timeLabel(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return DateFormat.jm().format(time);
  }
  return DateFormat.MMMd().format(time);
}

/// The "Archived chats" row pinned at the top of the list (Telegram style).
class _ArchivedRow extends StatelessWidget {
  final List<ChatConversation> archived;
  final VoidCallback onTap;
  const _ArchivedRow({required this.archived, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = archived.where((c) => c.isUnread).length;
    final names = archived.take(3).map((c) => c.otherUserName).join(', ');
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(
        radius: 22,
        backgroundColor: Color(0xff2a3a55),
        child: Icon(Icons.archive_outlined, color: Colors.white, size: 22),
      ),
      title: const Text('Archived chats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(names, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      trailing: unread > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            )
          : Text('${archived.length}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
    );
  }
}

/// One chat in the list. Tap opens the chat; long-press opens the menu.
class ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final Future<void> Function() onChanged;
  const ConversationTile({super.key, required this.conversation, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return ListTile(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: c.id, otherUserId: c.otherUserId, otherUserName: c.otherUserName)));
        await onChanged();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showConversationMenu(context, c, onChanged);
      },
      leading: UserAvatar(avatarUrl: c.otherUserAvatarUrl, radius: 22),
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
  }
}

/// Long-press menu for a chat in the list: Archive / Unarchive, Report,
/// Block, Delete conversation. [onChanged] reloads the list afterwards.
Future<void> showConversationMenu(BuildContext context, ChatConversation c, Future<void> Function() onChanged) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xff141414),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) {
      void run(Future<void> Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  UserAvatar(avatarUrl: c.otherUserAvatarUrl, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.otherUserName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            ListTile(
              leading: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, color: Colors.white),
              title: Text(c.isArchived ? 'Unarchive chat' : 'Archive chat', style: const TextStyle(color: Colors.white)),
              onTap: () => run(() => _toggleArchive(context, c, onChanged)),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.white),
              title: const Text('Report', style: TextStyle(color: Colors.white)),
              onTap: () => run(() => _report(context, c)),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.white),
              title: const Text('Block', style: TextStyle(color: Colors.white)),
              onTap: () => run(() => _block(context, c, onChanged)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete conversation', style: TextStyle(color: Colors.red)),
              onTap: () => run(() => _delete(context, c, onChanged)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

// The messenger is captured BEFORE any await: archiving or deleting removes
// the tile (and its context) from the list, but the messenger stays valid.
void _snack(ScaffoldMessengerState messenger, String message, {SnackBarAction? action}) {
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message), action: action));
}

Future<void> _toggleArchive(BuildContext context, ChatConversation c, Future<void> Function() onChanged) async {
  final messenger = ScaffoldMessenger.of(context);
  final archive = !c.isArchived;
  final ok = await ChatService.setArchived(c.id, archive);
  if (!ok) return _snack(messenger, "Couldn't update. Try again.");
  await onChanged();
  _snack(
    messenger,
    archive ? 'Chat archived' : 'Chat moved back to your chats',
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () async {
        await ChatService.setArchived(c.id, !archive);
        await onChanged();
      },
    ),
  );
}

Future<void> _block(BuildContext context, ChatConversation c, Future<void> Function() onChanged) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xff141414),
      title: Text('Block ${c.otherUserName}?', style: const TextStyle(color: Colors.white)),
      content: const Text(
        "They won't be able to message you, and you won't be able to message them. The chat disappears from your list. You can unblock them any time from their profile.",
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Block', style: TextStyle(color: Colors.red))),
      ],
    ),
  );
  if (confirmed != true) return;
  final ok = await ChatService.blockUser(c.otherUserId);
  if (!ok) return _snack(messenger, "Couldn't block. Try again.");
  await onChanged();
  _snack(messenger, '${c.otherUserName} is blocked.');
}

Future<void> _delete(BuildContext context, ChatConversation c, Future<void> Function() onChanged) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xff141414),
      title: const Text('Delete conversation?', style: TextStyle(color: Colors.white)),
      content: Text(
        "This removes your conversation with ${c.otherUserName} from your list and clears the messages on your side. ${c.otherUserName} still has their copy. This can't be undone.",
        style: const TextStyle(color: Colors.grey),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ),
  );
  if (confirmed != true) return;
  final ok = await ChatService.deleteConversation(c.id);
  if (!ok) return _snack(messenger, "Couldn't delete. Try again.");
  await onChanged();
  _snack(messenger, 'Conversation deleted.');
}

Future<void> _report(BuildContext context, ChatConversation c) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: const Color(0xff141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report ${c.otherUserName}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What happened?',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: const Color(0xff1a1a1a),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel', style: TextStyle(color: Colors.grey)))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Submit Report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  if (reason == null || reason.isEmpty) return;
  final ok = await ChatService.reportUser(reportedUserId: c.otherUserId, conversationId: c.id, reason: reason);
  _snack(messenger, ok ? 'Report submitted. Thank you.' : "Couldn't submit. Please try again.");
}

/// The list behind the "Archived chats" row. Long-press a chat here to
/// unarchive, report, block or delete it.
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  List<ChatConversation> _archived = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await ChatService.fetchConversations();
    if (!mounted) return;
    setState(() {
      _archived = all.where((c) => c.isArchived).toList();
      _loading = false;
    });
    context.read<ChatUnreadProvider>().refresh();
    // Nothing left to show: go back to the main list.
    if (_archived.isEmpty && mounted) Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(backgroundColor: const Color(0xff050505), foregroundColor: Colors.white, title: const Text('Archived chats')),
      body: SafeArea(
        child: _loading
            ? const ListSkeleton()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _archived.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1, indent: 76),
                  itemBuilder: (_, i) => ConversationTile(conversation: _archived[i], onChanged: _load),
                ),
              ),
      ),
    );
  }
}
