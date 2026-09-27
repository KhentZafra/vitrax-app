import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_unread_provider.dart';
import '../services/chat_service.dart';

class ChatThreadScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  const ChatThreadScreen({super.key, required this.conversationId, required this.otherUserId, required this.otherUserName});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<ChatMessage>>? _sub;

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _sending = false;
  bool _blockedByMe = false;
  bool _checkingBlockStatus = true;

  @override
  void initState() {
    super.initState();
    _load();
    _checkBlockStatus();
  }

  @override
  void dispose() {
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
    final success = _blockedByMe ? await ChatService.unblockUser(widget.otherUserId) : await ChatService.blockUser(widget.otherUserId);
    if (!mounted) return;
    if (success) {
      setState(() => _blockedByMe = !_blockedByMe);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_blockedByMe ? '${widget.otherUserName} is blocked.' : '${widget.otherUserName} is unblocked.')));
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong, Please try again.')));
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Report submitted. Thank you.' : "Couldn't submit, Please try again.")),
    );
  }

  Future<void> _load() async {
    final initial = await ChatService.fetchMessages(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _messages = initial;
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
      setState(() => _messages = messages);
      if (wasAtBottom) _scrollToBottom();
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
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();
    final success = await ChatService.sendMessage(widget.conversationId, text);
    if (!mounted) return;
    setState(() => _sending = false);

    if (!success) {
      _controller.text = text; // give it back so they don't lose what they typed
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send, Please check your connection and try again.")));
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
        title: Text(widget.otherUserName),
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
                          itemCount: _messages.length,
                          itemBuilder: (context, index) => _MessageBubble(message: _messages[index]),
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
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.blue),
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
