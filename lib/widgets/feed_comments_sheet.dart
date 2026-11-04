import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_comment.dart';
import '../models/feed_item.dart';
import '../services/feed_comment_service.dart';
import 'user_actions_sheet.dart';
import 'user_avatar.dart';

/// Opens the comments sheet for [item]. [onCountChanged] is called with
/// the new total whenever a comment is added or deleted so the feed card
/// can update its counter without reloading the whole feed.
Future<void> showFeedCommentsSheet(
  BuildContext context, {
  required FeedItem item,
  required ValueChanged<int> onCountChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff141414),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _CommentsSheet(item: item, onCountChanged: onCountChanged),
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  final FeedItem item;
  final ValueChanged<int> onCountChanged;
  const _CommentsSheet({required this.item, required this.onCountChanged});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<FeedComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  FeedComment? _replyingTo;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await FeedCommentService.fetch(widget.item);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _loading = false;
    });
    widget.onCountChanged(comments.length);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await FeedCommentService.add(widget.item, text, parentId: _replyingTo?.id);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text("Couldn't post your comment. Try again.")));
      return;
    }
    _controller.clear();
    setState(() => _replyingTo = null);
    FocusScope.of(context).unfocus();
    await _load();
  }

  Future<void> _delete(FeedComment c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1f1f1f),
        title: const Text('Delete comment?', style: TextStyle(color: Colors.white)),
        content: const Text('Replies to this comment will be deleted too.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await FeedCommentService.delete(c.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text("Couldn't delete the comment.")));
      return;
    }
    if (_replyingTo?.id == c.id) setState(() => _replyingTo = null);
    await _load();
  }

  void _startReply(FeedComment c) {
    setState(() => _replyingTo = c);
    _focus.requestFocus();
  }

  /// Flat list of (comment, depth) in display order: each top-level
  /// comment followed by every reply beneath it (replies to replies stay
  /// at one indent level and show "Replying to" with the name).
  List<(FeedComment, bool)> _ordered() {
    final byId = {for (final c in _comments) c.id: c};
    String rootOf(FeedComment c) {
      var cur = c;
      var guard = 0;
      while (cur.parentId != null && byId.containsKey(cur.parentId) && guard++ < 50) {
        cur = byId[cur.parentId]!;
      }
      return cur.id;
    }

    final roots = _comments.where((c) => c.parentId == null || !byId.containsKey(c.parentId)).toList();
    final replies = <String, List<FeedComment>>{};
    for (final c in _comments) {
      if (roots.contains(c)) continue;
      replies.putIfAbsent(rootOf(c), () => []).add(c);
    }
    final out = <(FeedComment, bool)>[];
    for (final r in roots) {
      out.add((r, false));
      for (final rep in replies[r.id] ?? const <FeedComment>[]) {
        out.add((rep, true));
      }
    }
    return out;
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Widget _tile(FeedComment c, bool isReply, Map<String, FeedComment> byId) {
    final parent = c.parentId != null ? byId[c.parentId] : null;
    final replyTargetIsRoot = parent != null && parent.parentId == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => showUserActionsSheet(context, userId: c.userId, userName: c.userName, avatarUrl: c.avatarUrl),
            child: UserAvatar(avatarUrl: c.avatarUrl, radius: isReply ? 14 : 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: () => showUserActionsSheet(context, userId: c.userId, userName: c.userName, avatarUrl: c.avatarUrl),
                        child: Text(c.userName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_ago(c.createdAt), style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
                if (isReply && parent != null && !replyTargetIsRoot)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Replying to ${parent.userName}', style: const TextStyle(color: Colors.blue, fontSize: 11)),
                  ),
                const SizedBox(height: 2),
                Text(c.body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _startReply(c),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text('Reply', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (c.userId == _myId) ...[
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () => _delete(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('Delete', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered();
    final byId = {for (final c in _comments) c.id: c};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Comments (${_comments.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1, color: Color(0xff2a2a2a)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                : ordered.isEmpty
                    ? Center(child: Text('No comments yet. Start the conversation!', style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(
                        itemCount: ordered.length,
                        itemBuilder: (_, i) => _tile(ordered[i].$1, ordered[i].$2, byId),
                      ),
          ),
          if (_replyingTo != null)
            Container(
              color: const Color(0xff1f1f1f),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Replying to ${_replyingTo!.userName}', style: const TextStyle(color: Colors.blue, fontSize: 12)),
                  ),
                  InkWell(onTap: () => setState(() => _replyingTo = null), child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _replyingTo == null ? 'Add a comment...' : 'Write a reply...',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        filled: true,
                        fillColor: const Color(0xff1f1f1f),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                        : const Icon(Icons.send, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
