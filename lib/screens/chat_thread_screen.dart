import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../providers/chat_unread_provider.dart';
import '../services/chat_service.dart';
import '../widgets/confirm_unblock.dart';
import '../widgets/user_avatar.dart';

class ChatThreadScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  const ChatThreadScreen({super.key, required this.conversationId, required this.otherUserId, required this.otherUserName, this.otherUserAvatarUrl});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<ChatMessage>>? _sub;

  List<ChatMessage> _messages = [];
  bool _isLoading = true;

  // Messages I just sent that the server has not echoed back yet. They show
  // instantly (like Messenger) and are replaced by the real message.
  final List<ChatMessage> _pending = [];
  // Messages that should play the pop-in animation (new ones only).
  final Set<String> _seenIds = {};
  final Set<String> _animateIds = {};
  RealtimeChannel? _typingChannel;
  Timer? _typingHideTimer;
  DateTime? _lastTypingSentAt;
  bool _otherTyping = false;
  bool _blockedByMe = false;
  bool _checkingBlockStatus = true;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.otherUserAvatarUrl;
    if (_avatarUrl == null) {
      ChatService.fetchAvatarUrl(widget.otherUserId).then((url) {
        if (mounted && url != null) setState(() => _avatarUrl = url);
      });
    }
    _load();
    _checkBlockStatus();
    _typingChannel = ChatService.openTypingChannel(widget.conversationId, (userId) {
      if (userId != widget.otherUserId || !mounted) return;
      final wasAtBottom = _isNearBottom();
      setState(() => _otherTyping = true);
      if (wasAtBottom) _scrollToBottom();
      _typingHideTimer?.cancel();
      _typingHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _otherTyping = false);
      });
    });
  }

  void _onTextChanged(String text) {
    final channel = _typingChannel;
    if (channel == null || text.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSentAt != null && now.difference(_lastTypingSentAt!) < const Duration(seconds: 2)) return;
    _lastTypingSentAt = now;
    ChatService.sendTyping(channel);
  }

  @override
  void dispose() {
    _typingHideTimer?.cancel();
    final channel = _typingChannel;
    if (channel != null) ChatService.closeTypingChannel(channel);
    _controller.dispose();
    _scrollController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _checkBlockStatus() async {
    final blocked = await ChatService.isBlocked(widget.otherUserId);
    if (!mounted) return;
    setState(() {
      _blockedByMe = blocked;
      _checkingBlockStatus = false;
    });
  }

  Future<void> _toggleBlock() async {
    if (_blockedByMe && !await confirmUnblock(context, widget.otherUserName)) return;
    if (!mounted) return;
    final success = _blockedByMe ? await ChatService.unblockUser(widget.otherUserId) : await ChatService.blockUser(widget.otherUserId);
    if (!mounted) return;
    if (success) {
      setState(() => _blockedByMe = !_blockedByMe);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(content: Text(_blockedByMe ? '${widget.otherUserName} is blocked.' : '${widget.otherUserName} is unblocked.')));
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('Something went wrong, Please try again.')));
    }
  }

  Future<void> _openReportDialog() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xff141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report ${widget.otherUserName}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
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
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel', style: TextStyle(color: Colors.grey)))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text.trim()),
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

    if (reason == null || reason.isEmpty || !mounted) return;

    final success = await ChatService.reportUser(reportedUserId: widget.otherUserId, conversationId: widget.conversationId, reason: reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
      SnackBar(content: Text(success ? 'Report submitted. Thank you.' : "Couldn't submit, Please try again.")),
    );
  }

  Future<void> _load() async {
    final initial = await ChatService.fetchMessages(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _messages = initial;
      _seenIds.addAll(initial.map((m) => m.id));
      _isLoading = false;
    });
    _scrollToBottom();

    // Opening the thread is what counts as "reading" it — mark it read
    // right away (not just on the messages you can already see, but as
    // of now, so anything that streams in while you're actively viewing
    // this screen counts as read too — see the stream listener below).
    // Refresh the app-wide badge afterward so it drops immediately
    // instead of waiting for the next time something else calls it.
    unawaited(ChatService.markConversationRead(widget.conversationId).then((_) {
      if (mounted) context.read<ChatUnreadProvider>().refresh();
    }));

    // Switch to the live stream after the initial load — new messages
    // (yours or theirs) appear instantly via Supabase Realtime, no
    // polling or manual refresh needed.
    _sub = ChatService.streamMessages(widget.conversationId).listen((messages) {
      if (!mounted) return;
      final wasAtBottom = _isNearBottom();
      final fresh = messages.where((m) => !_seenIds.contains(m.id)).toList();
      setState(() {
        _messages = messages;
        for (final m in fresh) {
          _seenIds.add(m.id);
          _animateIds.add(m.id);
          Timer(const Duration(milliseconds: 700), () => _animateIds.remove(m.id));
          // Their message arrived: they are no longer "typing".
          if (!m.isMine) _otherTyping = false;
        }
        // The server has echoed my message: drop its temporary copy.
        _pending.removeWhere((p) => messages.any((m) => m.isMine && m.body == p.body && m.createdAt.isAfter(p.createdAt.subtract(const Duration(seconds: 15)))));
      });
      if (wasAtBottom || fresh.any((m) => m.isMine)) _scrollToBottom();
      // A message that streams in while this screen is open was just
      // seen by the user — keep it marked read rather than letting it
      // silently go stale until they leave and come back.
      unawaited(ChatService.markConversationRead(widget.conversationId));
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 80;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    // Show it right away, before the network answers.
    final temp = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: widget.conversationId,
      senderId: Supabase.instance.client.auth.currentUser?.id ?? '',
      body: text,
      createdAt: DateTime.now(),
      isMine: true,
    );
    setState(() {
      _pending.add(temp);
      _animateIds.add(temp.id);
    });
    Timer(const Duration(milliseconds: 700), () => _animateIds.remove(temp.id));
    _scrollToBottom();

    final success = await ChatService.sendMessage(widget.conversationId, text);
    if (!mounted) return;

    if (!success) {
      setState(() => _pending.removeWhere((p) => p.id == temp.id));
      _controller.text = text; // give it back so they don't lose what they typed
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text("Couldn't send, Please check your connection and try again.")));
    }
    // On success, the realtime stream (not this call) is what updates
    // _messages — keeps a single source of truth for what's on screen.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(avatarUrl: _avatarUrl, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xff1a1a1a),
            onSelected: (value) {
              if (value == 'block') _toggleBlock();
              if (value == 'report') _openReportDialog();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'block',
                child: Text(_blockedByMe ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(value: 'report', child: Text('Report', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                  : _messages.isEmpty
                      ? Center(child: Text('Say hello 👋', style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + _pending.length + (_otherTyping ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _messages.length + _pending.length) {
                              final isPending = index >= _messages.length;
                              final m = isPending ? _pending[index - _messages.length] : _messages[index];
                              return _PopIn(
                                key: ValueKey(m.id),
                                animate: _animateIds.contains(m.id),
                                fromRight: m.isMine,
                                child: Opacity(opacity: isPending ? 0.7 : 1, child: _MessageBubble(message: m)),
                              );
                            }
                            return const _PopIn(animate: true, fromRight: false, child: _TypingBubble());
                          },
                        ),
            ),
            if (_checkingBlockStatus)
              const SizedBox.shrink()
            else if (_blockedByMe)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.grey.shade500, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('You\'ve blocked ${widget.otherUserName}.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
                    TextButton(onPressed: _toggleBlock, child: const Text('Unblock')),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xff141414),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, color: Colors.blue),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: message.isMine ? Colors.blue : const Color(0xff1a1a1a),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isMine ? 16 : 4),
            bottomRight: Radius.circular(message.isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3)),
            const SizedBox(height: 3),
            Text(DateFormat.jm().format(message.createdAt), style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}


/// Pop-in for a message that just appeared (fade + slide up + slight scale),
/// like Messenger. Messages that were already there are shown as they are.
class _PopIn extends StatelessWidget {
  final Widget child;
  final bool animate;
  final bool fromRight;
  const _PopIn({super.key, required this.child, required this.animate, required this.fromRight});

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: Transform.scale(scale: 0.88 + 0.12 * v, alignment: fromRight ? Alignment.bottomRight : Alignment.bottomLeft, child: child),
        ),
      ),
    );
  }
}

/// The three bouncing dots shown while the other person is typing.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xff1a1a1a),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16)),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_c.value - i * 0.18) % 1.0;
              final bounce = t < 0.5 ? (1 - (t - 0.25).abs() * 4).clamp(0.0, 1.0) : 0.0;
              return Container(
                margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                width: 8,
                height: 8,
                transform: Matrix4.translationValues(0, -4 * bounce, 0),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .45 + .4 * bounce)),
              );
            }),
          ),
        ),
      ),
    );
  }
}
