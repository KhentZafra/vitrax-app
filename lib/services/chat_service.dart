import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';

class ChatService {
  static final _supabase = Supabase.instance.client;

  /// Finds or creates a 1:1 conversation with [otherUserId] and returns
  /// its id. All the atomicity (creating the conversation + adding both
  /// participants) happens server-side in start_or_get_conversation() —
  /// see 014_chat.sql for why that needs to run with elevated privilege.
  static Future<String?> startOrGetConversation(String otherUserId) async {
    try {
      final result = await _supabase.rpc('start_or_get_conversation', params: {'other_user_id': otherUserId});
      return result as String;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.startOrGetConversation failed: $e');
      return null;
    }
  }

  /// All conversations the current user is part of, each with the other
  /// participant's name and a preview of the most recent message,
  /// sorted most-recently-active first. Conversations with someone
  /// you've blocked are excluded — blocking hides them from your list,
  /// it doesn't just prevent new messages.
  static Future<List<ChatConversation>> fetchConversations() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return [];

    try {
      final participantRows = await _supabase
          .from('conversation_participants')
          .select('conversation_id, last_read_at, archived_at, deleted_at')
          .eq('user_id', currentUserId);

      final myRows = (participantRows as List).cast<Map<String, dynamic>>();
      final conversationIds = myRows.map((r) => r['conversation_id'] as String).toList();
      if (conversationIds.isEmpty) return [];

      // My own "last opened this conversation" timestamp, per conversation
      // — null means never opened (a brand-new conversation someone just
      // started with you), which should count as unread the moment it has
      // a message, same as any other unread one.
      final myLastReadAt = <String, DateTime?>{
        for (final row in myRows)
          row['conversation_id'] as String: row['last_read_at'] != null ? DateTime.parse(row['last_read_at'] as String) : null,
      };

      final archivedIds = <String>{
        for (final row in myRows)
          if (row['archived_at'] != null) row['conversation_id'] as String,
      };
      // When I deleted a conversation: older messages are hidden from me.
      final myDeletedAt = <String, DateTime>{
        for (final row in myRows)
          if (row['deleted_at'] != null) row['conversation_id'] as String: DateTime.parse(row['deleted_at'] as String),
      };

      final blockedIds = await _fetchMyBlockedIds();

      final otherParticipantRows = await _supabase
          .from('conversation_participants')
          .select('conversation_id, user_id, profiles(first_name, last_name, avatar_url)')
          .inFilter('conversation_id', conversationIds)
          .neq('user_id', currentUserId);

      final otherByConversation = <String, Map<String, dynamic>>{};
      for (final row in (otherParticipantRows as List).cast<Map<String, dynamic>>()) {
        final otherUserId = row['user_id'] as String;
        if (blockedIds.contains(otherUserId)) continue; // hide blocked conversations entirely
        otherByConversation[row['conversation_id'] as String] = row;
      }

      final messageRows = await _supabase
          .from('messages')
          .select('conversation_id, sender_id, body, created_at')
          .inFilter('conversation_id', otherByConversation.keys.toList())
          .order('created_at', ascending: false);

      final lastMessageByConversation = <String, Map<String, dynamic>>{};
      for (final row in (messageRows as List).cast<Map<String, dynamic>>()) {
        final deletedAt = myDeletedAt[row['conversation_id'] as String];
        if (deletedAt != null && !DateTime.parse(row['created_at'] as String).isAfter(deletedAt)) continue;
        // First hit per conversation_id is the newest, since we ordered
        // by created_at descending above.
        lastMessageByConversation.putIfAbsent(row['conversation_id'] as String, () => row);
      }

      final conversations = otherByConversation.entries.where((entry) {
        // A deleted conversation stays hidden until a newer message arrives.
        return !myDeletedAt.containsKey(entry.key) || lastMessageByConversation.containsKey(entry.key);
      }).map((entry) {
        final id = entry.key;
        final other = entry.value;
        final profile = other['profiles'] as Map<String, dynamic>?;
        final first = profile?['first_name'] as String? ?? '';
        final last = profile?['last_name'] as String? ?? '';
        final name = ('$first $last').trim();
        final lastMessage = lastMessageByConversation[id];
        final lastMessageAt = lastMessage != null ? DateTime.parse(lastMessage['created_at'] as String).toLocal() : null;

        // Unread only if the last message is actually from THEM — you
        // sending the last message is never "unread" for you, no matter
        // how long ago you opened the thread.
        final lastSenderId = lastMessage?['sender_id'] as String?;
        final readAt = myLastReadAt[id];
        final isUnread = lastMessageAt != null && lastSenderId != currentUserId && (readAt == null || lastMessageAt.isAfter(readAt));

        return ChatConversation(
          id: id,
          otherUserId: other['user_id'] as String? ?? '',
          otherUserName: name.isEmpty ? 'A Vitrax user' : name,
          otherUserAvatarUrl: profile?['avatar_url'] as String?,
          lastMessageBody: lastMessage?['body'] as String?,
          lastMessageAt: lastMessageAt,
          isUnread: isUnread,
          isArchived: archivedIds.contains(id),
        );
      }).toList();

      // Most-recently-active conversation first (standard messaging-app
      // order) — a conversation with no messages yet (lastMessageAt ==
      // null) has no activity to sort by, so it's treated as "oldest"
      // and placed at the very bottom.
      conversations.sort((a, b) {
        if (a.lastMessageAt == null && b.lastMessageAt == null) return 0;
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });

      return conversations;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.fetchConversations failed: $e');
      return [];
    }
  }

  /// Total number of conversations with something unread — what the
  /// chat badge (e.g. on the bottom nav or the "Chat" tab) shows. Reuses
  /// fetchConversations()'s own unread logic so the two can never
  /// disagree with each other.
  static Future<int> fetchUnreadConversationCount() async {
    final conversations = await fetchConversations();
    return conversations.where((c) => c.isUnread && !c.isArchived).length;
  }

  /// Call when the user opens [conversationId] — marks it read as of
  /// right now, so it drops off the unread badge/list styling until a
  /// NEW message arrives after this point.
  static Future<void> markConversationRead(String conversationId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase
          .from('conversation_participants')
          .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id);
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.markConversationRead failed: $e');
    }
  }

  static Future<Set<String>> _fetchMyBlockedIds() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return {};
    try {
      final rows = await _supabase.from('blocked_users').select('blocked_id').eq('blocker_id', currentUserId);
      return (rows as List).cast<Map<String, dynamic>>().map((r) => r['blocked_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// When I deleted [conversationId], or null if I never did. Messages from
  /// before that moment stay hidden from me.
  static Future<DateTime?> _myDeletedAt(String conversationId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _supabase
          .from('conversation_participants')
          .select('deleted_at')
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id)
          .maybeSingle();
      final raw = row?['deleted_at'] as String?;
      return raw == null ? null : DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id ?? '';
    try {
      final cutoff = await _myDeletedAt(conversationId);
      final rows = await _supabase.from('messages').select().eq('conversation_id', conversationId).order('created_at', ascending: true);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map((r) => ChatMessage.fromMap(r, currentUserId: currentUserId))
          .where((m) => cutoff == null || m.createdAt.isAfter(cutoff))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.fetchMessages failed: $e');
      return [];
    }
  }

  /// Live stream of every message in [conversationId], via Supabase
  /// Realtime — new messages appear immediately without polling. Emits
  /// the full current list on every change (Supabase's stream() API
  /// re-emits the whole result set, not just diffs), which is simple to
  /// reason about and fine at chat-history scale.
  static Stream<List<ChatMessage>> streamMessages(String conversationId) async* {
    final currentUserId = _supabase.auth.currentUser?.id ?? '';
    final cutoff = await _myDeletedAt(conversationId);
    yield* _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        // Must be explicit: unlike a one-time .select() query, Supabase's
        // realtime .stream().order() defaults to DESCENDING (newest
        // first) when ascending isn't given — that mismatch with
        // fetchMessages() above (which defaults correctly) is exactly
        // what caused messages to flip to newest-on-top a moment after
        // the initial correct load.
        .order('created_at', ascending: true)
        .map((rows) => rows
            .map((r) => ChatMessage.fromMap(r, currentUserId: currentUserId))
            .where((m) => cutoff == null || m.createdAt.isAfter(cutoff))
            .toList());
  }

  static Future<bool> sendMessage(String conversationId, String body) async {
    final user = _supabase.auth.currentUser;
    if (user == null || body.trim().isEmpty) return false;
    try {
      await _supabase.from('messages').insert({'conversation_id': conversationId, 'sender_id': user.id, 'body': body.trim()});
      // Writing in an archived chat brings it back to the main list.
      try {
        await setArchived(conversationId, false);
      } catch (_) {}
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.sendMessage failed: $e');
      return false;
    }
  }

  /// True if either you've blocked [otherUserId] or they've blocked you —
  /// either direction prevents messaging, so the UI treats both the same
  /// (shows a "can't message this person" state instead of the input).
  static Future<bool> isBlocked(String otherUserId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return false;
    try {
      // Only rows where you're the blocker are visible to you (RLS), so
      // this only reliably detects "I blocked them" — the "they blocked
      // me" case surfaces naturally when sendMessage() fails instead,
      // since that's enforced server-side regardless of what this
      // client can see.
      final rows = await _supabase.from('blocked_users').select('id').eq('blocker_id', currentUserId).eq('blocked_id', otherUserId).maybeSingle();
      return rows != null;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.isBlocked failed: $e');
      return false;
    }
  }

  static Future<bool> blockUser(String otherUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('blocked_users').insert({'blocker_id': user.id, 'blocked_id': otherUserId});
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.blockUser failed: $e');
      return false;
    }
  }

  static Future<bool> unblockUser(String otherUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('blocked_users').delete().eq('blocker_id', user.id).eq('blocked_id', otherUserId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.unblockUser failed: $e');
      return false;
    }
  }

  /// Moves a chat into (or out of) "Archived chats". Only affects me.
  static Future<bool> setArchived(String conversationId, bool archived) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase
          .from('conversation_participants')
          .update({'archived_at': archived ? DateTime.now().toUtc().toIso8601String() : null})
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.setArchived failed: $e');
      return false;
    }
  }

  /// Deletes the conversation for me only: hides everything up to now and
  /// takes it out of my list. The other person keeps their copy. A new
  /// message from them brings the chat back with only the newer messages.
  static Future<bool> deleteConversation(String conversationId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase
          .from('conversation_participants')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'archived_at': null})
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.deleteConversation failed: $e');
      return false;
    }
  }

  static Future<bool> reportUser({required String reportedUserId, String? conversationId, required String reason}) async {
    final user = _supabase.auth.currentUser;
    if (user == null || reason.trim().isEmpty) return false;
    try {
      await _supabase.from('chat_reports').insert({
        'reporter_id': user.id,
        'reported_user_id': reportedUserId,
        'conversation_id': conversationId,
        'reason': reason.trim(),
      });
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.reportUser failed: $e');
      return false;
    }
  }

  /// A user's profile photo URL (null if none), for the chat header.
  static Future<String?> fetchAvatarUrl(String userId) async {
    try {
      final row = await _supabase.from('profiles').select('avatar_url').eq('id', userId).maybeSingle();
      return row?['avatar_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// People I have blocked, with names, for the "Blocked users" list.
  static Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await _supabase.from('blocked_users').select('blocked_id').eq('blocker_id', me);
      final ids = (rows as List).map((r) => (r as Map)['blocked_id'] as String).toList();
      if (ids.isEmpty) return [];
      final profiles = await _supabase.from('profiles').select('id, first_name, last_name, avatar_url').inFilter('id', ids);
      final byId = {for (final p in (profiles as List)) (p as Map)['id'] as String: p};
      return [
        for (final id in ids)
          {
            'id': id,
            'name': ('${byId[id]?['first_name'] ?? ''} ${byId[id]?['last_name'] ?? ''}').trim().isEmpty
                ? 'Unknown user'
                : ('${byId[id]?['first_name'] ?? ''} ${byId[id]?['last_name'] ?? ''}').trim(),
            'avatar': byId[id]?['avatar_url'],
          },
      ];
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.fetchBlockedUsers failed: $e');
      return [];
    }
  }

  /// Reports I have sent, newest first (if the database lets me read them).
  static Future<List<Map<String, dynamic>>> fetchMyReports() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await _supabase.from('chat_reports').select().eq('reporter_id', me);
      final list = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      final ids = list.map((r) => r['reported_user_id']).whereType<String>().toSet().toList();
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final profiles = await _supabase.from('profiles').select('id, first_name, last_name').inFilter('id', ids);
        for (final p in (profiles as List)) {
          final m = p as Map;
          names[m['id'] as String] = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
        }
      }
      for (final r in list) {
        final n = names[r['reported_user_id']];
        r['name'] = (n == null || n.isEmpty) ? 'Unknown user' : n;
      }
      list.sort((a, b) => '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
      return list;
    } catch (e) {
      // ignore: avoid_print
      print('ChatService.fetchMyReports failed: $e');
      return [];
    }
  }
}
