import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bumped whenever a story is viewed so every ring in the app refreshes.
abstract final class VibeSeenStore {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}

class VibeRepository {
  VibeRepository(this._client);
  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  /// Ids of active statuses that the current user has already viewed.
  Future<Set<String>> seenStatusIds() async {
    final me = _me;
    if (me == null) return <String>{};
    try {
      final rows = await _client
          .from('vibe_views')
          .select('status_id')
          .eq('viewer_id', me);
      return rows.map((r) => r['status_id'] as String).toSet();
    } catch (_) {
      // Table missing (migration not applied yet): treat everything as unseen.
      return <String>{};
    }
  }

  /// User ids (other than me) that have at least one unseen active status.
  Future<Set<String>> usersWithUnseenVibes() async {
    final me = _me;
    if (me == null) return <String>{};
    final rows = await _client
        .from('vibes_statuses')
        .select('id,user_id')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());
    final seen = await seenStatusIds();
    final result = <String>{};
    for (final row in rows) {
      final owner = row['user_id'] as String;
      if (owner == me) continue;
      if (!seen.contains(row['id'] as String)) result.add(owner);
    }
    return result;
  }

  Future<void> markSeen(String statusId, String ownerId) async {
    final me = _me;
    if (me == null || ownerId == me) return;
    try {
      await _client.from('vibe_views').upsert(
        {'status_id': statusId, 'viewer_id': me},
        onConflict: 'status_id,viewer_id',
        ignoreDuplicates: true,
      );
      VibeSeenStore.bump();
    } catch (_) {
      // Viewing must still work if the views table is not available.
    }
  }

  /// Active statuses of one person, oldest first, ready for the story viewer.
  Future<List<Map<String, dynamic>>> activeStatusesFor(String userId) async {
    final rows = await _client
        .from('vibes_statuses')
        .select('id,user_id,body,media_path,media_type,created_at,expires_at')
        .eq('user_id', userId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: true);
    if (rows.isEmpty) return const [];
    final profile = await _client
        .from('discoverable_profiles')
        .select('id,display_name,username,avatar_path')
        .eq('id', userId)
        .maybeSingle();
    var name = (profile?['display_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = '@${profile?['username'] ?? 'viora_user'}';
    String? avatarUrl;
    final avatarPath = profile?['avatar_path'] as String?;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      try {
        avatarUrl = await _client.storage
            .from('profile-media')
            .createSignedUrl(avatarPath, 3600);
      } on StorageException {
        // Initials avatar is used instead.
      }
    }
    final seen = await seenStatusIds();
    return rows
        .map(
          (row) => <String, dynamic>{
            ...row,
            'display_name': name,
            'avatar_url': avatarUrl,
            'seen': seen.contains(row['id'] as String),
          },
        )
        .toList();
  }
}
