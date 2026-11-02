import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation_preview.dart';

class MessagingRepository {
  MessagingRepository(this._client);
  final SupabaseClient _client;

  Future<List<ConversationPreview>> myConversations() async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('Sign in to use Viora messages.');
    }
    final rows = await _client.rpc('list_my_conversations');
    final nicknames = await _nicknames();
    return Future.wait(
      (rows as List).map<Future<ConversationPreview>>((row) async {
        final data = row as Map<String, dynamic>;
        final avatarPath = data['peer_avatar_path'] as String?;
        String? avatarUrl;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          try {
            avatarUrl = await _client.storage
                .from('profile-media')
                .createSignedUrl(avatarPath, 3600);
          } on StorageException {
            // Keep the graceful initials avatar if private media is unavailable.
          }
        }
        return ConversationPreview(
          id: data['conversation_id'] as String,
          title:
              (data['is_group'] != true
                  ? nicknames[data['peer_user_id'] as String?]
                  : null) ??
              data['display_title'] as String? ??
              'Viora conversation',
          isGroup: data['is_group'] as bool? ?? false,
          lastMessage:
              data['last_message'] as String? ?? 'Start a conversation',
          memberCount: (data['member_count'] as num?)?.toInt() ?? 2,
          lastMessageAt: DateTime.tryParse(
            data['last_message_at'] as String? ?? '',
          ),
          attachmentPath: data['last_attachment_path'] as String?,
          peerUserId: data['peer_user_id'] as String?,
          avatarUrl: avatarUrl,
          hasActiveVibe: data['has_active_vibe'] as bool? ?? false,
        );
      }),
    );
  }

  Future<List<Map<String, dynamic>>> searchPeople(String query) async {
    // Search by display name or @username only (never by email).
    final term = query
        .trim()
        .replaceAll(RegExp(r'[%_,()\\]'), ' ')
        .replaceFirst(RegExp(r'^@'), '')
        .trim();
    if (term.isEmpty) return const [];
    final me = _client.auth.currentUser?.id;
    final rows = await _client
        .from('discoverable_profiles')
        .select('id,display_name,username,avatar_path')
        .or('display_name.ilike.%$term%,username.ilike.%$term%')
        .limit(30);
    final people = (rows as List).cast<Map<String, dynamic>>();
    return people.where((p) => p['id'] != me).toList();
  }

  Future<String> openDirectConversation(String otherUserId) async {
    final result = await _client.rpc(
      'open_direct_conversation',
      params: {'other_user_id': otherUserId},
    );
    return result as String;
  }

  /// Names you saved for contacts (like WhatsApp "edit name"). Only you see them.
  Future<Map<String?, String>> _nicknames() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const {};
    try {
      final rows = await _client
          .from('contact_nicknames')
          .select('contact_id,nickname')
          .eq('owner_id', me);
      return {
        for (final r in rows) r['contact_id'] as String?: r['nickname'] as String,
      };
    } catch (_) {
      return const {}; // Run sql/viora_v5_nicknames.sql
    }
  }

  Future<String?> nicknameFor(String contactId) async =>
      (await _nicknames())[contactId];

  /// Saves a name for this contact. An empty name removes it.
  Future<void> setNickname(String contactId, String name) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    final clean = name.trim();
    if (clean.isEmpty) {
      await _client
          .from('contact_nicknames')
          .delete()
          .eq('owner_id', me)
          .eq('contact_id', contactId);
      return;
    }
    await _client.from('contact_nicknames').upsert({
      'owner_id': me,
      'contact_id': contactId,
      'nickname': clean,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> createGroup(String title, List<String> memberIds) async {
    final result = await _client.rpc(
      'create_group_conversation',
      params: {'group_title': title.trim(), 'member_ids': memberIds},
    );
    return result as String;
  }

  Future<void> deleteConversationForMe(String conversationId) async {
    await _client.rpc(
      'hide_conversation_for_me',
      params: {'target_conversation_id': conversationId},
    );
  }

  Future<void> touchPresence() async {
    try {
      await _client.rpc('touch_presence');
    } catch (_) {}
  }

  Future<DateTime?> lastSeen(String userId) async {
    try {
      final r = await _client.rpc('get_last_seen', params: {'p_user_id': userId});
      return r == null ? null : DateTime.tryParse(r as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (_) {}
  }

  /// Members of a chat with real names and avatars.
  Future<List<Map<String, dynamic>>> members(String conversationId) async {
    final rows = await _client.rpc(
      'get_conversation_members',
      params: {'p_conversation_id': conversationId},
    );
    final list = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      var name = (m['display_name'] as String?)?.trim() ?? '';
      if (name.isEmpty) name = '@${m['username'] ?? 'viora_user'}';
      m['name'] = name;
      final path = m['avatar_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          m['avatar_url'] = await _client.storage
              .from('profile-media')
              .createSignedUrl(path, 3600);
        } on StorageException {
          // initials
        }
      }
      list.add(m);
    }
    return list;
  }
}
