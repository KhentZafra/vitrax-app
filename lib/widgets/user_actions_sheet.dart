import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/chat_thread_screen.dart';
import '../screens/user_profile_screen.dart';
import '../services/chat_service.dart';
import 'confirm_unblock.dart';
import 'user_avatar.dart';

/// The menu that opens when you tap another member's name or photo
/// (e.g. on a Community Feed post): View profile, Message, Block / Unblock,
/// Report. Tapping your own name does nothing.
///
/// [includeViewProfile] is false when this is opened from that member's own
/// profile screen, where "View profile" would just reopen the same page.
Future<void> showUserActionsSheet(
  BuildContext context, {
  required String userId,
  required String userName,
  String? avatarUrl,
  bool includeViewProfile = true,
}) async {
  final me = Supabase.instance.client.auth.currentUser?.id;
  if (me == null || me == userId) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xff141414),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _UserActionsSheet(
      parentContext: context,
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
      includeViewProfile: includeViewProfile,
    ),
  );
}

class _UserActionsSheet extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final bool includeViewProfile;

  const _UserActionsSheet({
    required this.parentContext,
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.includeViewProfile,
  });

  @override
  State<_UserActionsSheet> createState() => _UserActionsSheetState();
}

class _UserActionsSheetState extends State<_UserActionsSheet> {
  bool _blocked = false;
  bool _checkingBlock = true;

  @override
  void initState() {
    super.initState();
    ChatService.isBlocked(widget.userId).then((value) {
      if (!mounted) return;
      setState(() {
        _blocked = value;
        _checkingBlock = false;
      });
    });
  }

  // The sheet closes before each action runs, so everything after that uses
  // the screen that opened it (parentContext), not this sheet's own context.
  BuildContext get _ctx => widget.parentContext;

  void _snack(String message) {
    if (!_ctx.mounted) return;
    ScaffoldMessenger.of(_ctx).clearSnackBars();
    ScaffoldMessenger.of(_ctx).showSnackBar(SnackBar(content: Text(message)));
  }

  void _viewProfile() {
    Navigator.pop(context);
    Navigator.push(
      _ctx,
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: widget.userId, fallbackName: widget.userName, fallbackAvatarUrl: widget.avatarUrl)),
    );
  }

  Future<void> _message() async {
    final ctx = _ctx;
    Navigator.pop(context);
    _snack('Opening chat…');
    final conversationId = await ChatService.startOrGetConversation(widget.userId);
    if (conversationId == null) {
      _snack("Couldn't open the chat. Try again.");
      return;
    }
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).clearSnackBars();
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: conversationId, otherUserId: widget.userId, otherUserName: widget.userName)),
    );
  }

  Future<void> _toggleBlock() async {
    final wasBlocked = _blocked;
    Navigator.pop(context);

    if (!wasBlocked) {
      final confirmed = await showDialog<bool>(
        context: _ctx,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xff141414),
          title: Text('Block ${widget.userName}?', style: const TextStyle(color: Colors.white)),
          content: const Text(
            "They won't be able to message you, and you won't be able to message them. You can unblock them any time.",
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Block', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (wasBlocked) {
      if (!_ctx.mounted) return;
      if (!await confirmUnblock(_ctx, widget.userName)) return;
      if (!_ctx.mounted) return;
    }
    final ok = wasBlocked ? await ChatService.unblockUser(widget.userId) : await ChatService.blockUser(widget.userId);
    _snack(ok ? (wasBlocked ? '${widget.userName} is unblocked.' : '${widget.userName} is blocked.') : "Couldn't update. Try again.");
  }

  Future<void> _report() async {
    Navigator.pop(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: _ctx,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xff141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report ${widget.userName}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
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

    final ok = await ChatService.reportUser(reportedUserId: widget.userId, reason: reason);
    _snack(ok ? 'Report submitted. Thank you.' : "Couldn't submit. Please try again.");
  }

  @override
  Widget build(BuildContext context) {
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
                UserAvatar(avatarUrl: widget.avatarUrl, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          if (widget.includeViewProfile)
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.white),
              title: const Text('View profile', style: TextStyle(color: Colors.white)),
              onTap: _viewProfile,
            ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            title: const Text('Message', style: TextStyle(color: Colors.white)),
            onTap: _message,
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.white),
            title: Text(_blocked ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.white)),
            enabled: !_checkingBlock,
            onTap: _toggleBlock,
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text('Report', style: TextStyle(color: Colors.red)),
            onTap: _report,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
