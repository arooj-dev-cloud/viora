import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/services/gallery_service.dart';
import '../../core/theme/viora_theme.dart';
import '../../data/models/conversation_preview.dart';
import '../../data/models/vibe_story_grouping.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/vibe_repository.dart';
import '../stories/story_viewer_screen.dart';
import '../messaging/call_screen.dart';
import '../messaging/calls_tab.dart';
import '../messaging/chat_screen.dart';
import '../messaging/create_group_screen.dart';
import '../notifications/notification_service.dart';
import '../notifications/push_service.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/welcome_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _chatsTab = 0;
  static const _callsTab = 1;
  static const _discoverTab = 2;
  static const _vibesTab = 3;

  int tab = 0;
  final titles = ['Chats', 'Calls', 'Discover', 'Vibes', 'Profile'];
  VioraNotificationService? _notifications;
  RealtimeChannel? _incomingCallChannel;
  RealtimeChannel? _incomingMediaChannel;
  bool _galleryWarned = false;
  String? _presentingCallId;
  Timer? _callPoll;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    if (AppConfig.supabaseConfigured) {
      _notifications = VioraNotificationService(Supabase.instance.client);
      unawaited(_notifications!.start());
      unawaited(PushService.register(Supabase.instance.client));
      final repo = MessagingRepository(Supabase.instance.client);
      unawaited(repo.touchPresence());
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 45),
            (_) => unawaited(repo.touchPresence()),
      );
      _subscribeToIncomingCalls();
      _subscribeToIncomingMedia();
      // Fallback in case a realtime event is missed: check every 3 seconds.
      _callPoll = Timer.periodic(
        const Duration(seconds: 3),
            (_) => unawaited(_pollIncomingCalls()),
      );
    }
  }

  Future<void> _pollIncomingCalls() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null ||
        !mounted ||
        _presentingCallId != null ||
        CallScreen.isCallActive) {
      return;
    }
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 40))
          .toIso8601String();
      final rows = await Supabase.instance.client
          .from('call_sessions')
          .select('id')
          .eq('callee_id', userId)
          .eq('status', 'ringing')
          .gt('created_at', since)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        unawaited(_presentIncomingCall({'id': rows.first['id']}));
      }
    } catch (_) {
      // Realtime remains the primary path.
    }
  }

  @override
  void dispose() {
    _callPoll?.cancel();
    _presenceTimer?.cancel();
    final service = _notifications;
    if (service != null) unawaited(service.stop());
    final incomingChannel = _incomingCallChannel;
    if (incomingChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(incomingChannel));
    }
    final mediaChannel = _incomingMediaChannel;
    if (mediaChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(mediaChannel));
    }
    super.dispose();
  }

  /// Like WhatsApp: photos and videos that other people send are copied to
  /// the phone gallery as soon as they arrive, even if the chat is closed.
  void _subscribeToIncomingMedia() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _incomingMediaChannel = Supabase.instance.client
        .channel('viora-incoming-media-$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) =>
          unawaited(_saveIncomingMedia(payload.newRecord)),
    )
        .subscribe();
  }

  Future<void> _saveIncomingMedia(Map<String, dynamic> message) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final path = message['attachment_path'] as String?;
    if (me == null || path == null || message['sender_id'] == me) return;
    if (!GalleryService.isImage(path) && !GalleryService.isVideo(path)) return;
    final saved = await GalleryService.saveAttachment(path);
    if (!saved &&
        GalleryService.lastError != null &&
        !_galleryWarned &&
        mounted) {
      _galleryWarned = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save a received photo or video to your gallery. '
                'Allow photo access for Viora in your phone settings.',
          ),
        ),
      );
    }
  }

  void _subscribeToIncomingCalls() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _incomingCallChannel = Supabase.instance.client
        .channel('viora-incoming-calls-$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'callee_id',
        value: userId,
      ),
      callback: (payload) =>
          unawaited(_presentIncomingCall(payload.newRecord)),
    )
        .subscribe();
  }

  Future<void> _presentIncomingCall(Map<String, dynamic> call) async {
    final callId = call['id'] as String?;
    if (!mounted ||
        callId == null ||
        _presentingCallId != null ||
        CallScreen.isCallActive) {
      return;
    }
    _presentingCallId = callId;
    try {
      final liveCall = await Supabase.instance.client
          .from('call_sessions')
          .select('caller_id,media_type,status')
          .eq('id', callId)
          .maybeSingle();
      if (!mounted || liveCall == null || liveCall['status'] != 'ringing') {
        return;
      }
      var callerName = 'Viora user';
      String? avatarUrl;
      final profile = await Supabase.instance.client
          .from('discoverable_profiles')
          .select('display_name,username,avatar_path')
          .eq('id', liveCall['caller_id'] as String)
          .maybeSingle();
      if (profile != null) {
        final name = (profile['display_name'] as String?)?.trim();
        if (name?.isNotEmpty == true) {
          callerName = name!;
        } else if ((profile['username'] as String?)?.isNotEmpty == true) {
          callerName = '@${profile['username']}';
        }
        final path = profile['avatar_path'] as String?;
        if (path != null && path.isNotEmpty) {
          try {
            avatarUrl = await Supabase.instance.client.storage
                .from('profile-media')
                .createSignedUrl(path, 3600);
          } on Object {
            // Initial letter is shown when the photo cannot be loaded.
          }
        }
      }
      if (!mounted) return;
      // Full-screen ringing page (accept / decline live inside CallScreen).
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            callId: callId,
            incoming: true,
            participantName: callerName,
            avatarUrl: avatarUrl,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('Incoming call could not open: $error');
    } finally {
      if (_presentingCallId == callId) _presentingCallId = null;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(titles[tab]),
      actions: [
        if (tab == _chatsTab)
          IconButton(
            tooltip: 'New group',
            onPressed: !AppConfig.supabaseConfigured
                ? null
                : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreateGroupScreen(),
              ),
            ),
            icon: const Icon(Icons.group_add_outlined),
          ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          icon: const Icon(Icons.notifications_none),
        ),
      ],
    ),
    body: IndexedStack(
      index: tab,
      children: [
        _Chats(onOpenVibes: (_) => setState(() => tab = _vibesTab)),
        CallsTab(active: tab == _callsTab),
        const _Discover(),
        const _Vibes(),
        const _Profile(),
      ],
    ),
    bottomNavigationBar: _VioraBottomNavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() => tab = index),
    ),
    floatingActionButton: tab == _chatsTab
        ? FloatingActionButton(
      onPressed: () => setState(() => tab = _discoverTab),
      backgroundColor: VioraColors.mauve,
      child: const Icon(Icons.edit),
    )
        : null,
  );
}

class _VioraBottomNavigationBar extends StatelessWidget {
  const _VioraBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    _NavDestination(Icons.chat_bubble_outline, Icons.chat_bubble, 'Chats'),
    _NavDestination(Icons.call_outlined, Icons.call, 'Calls'),
    _NavDestination(Icons.explore_outlined, Icons.explore, 'Discover'),
    _NavDestination(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Vibes'),
    _NavDestination(Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF281238), Color(0xFF190925)],
          ),
          border: Border.all(color: VioraColors.blush.withValues(alpha: .13)),
          boxShadow: [
            BoxShadow(
              color: VioraColors.plum.withValues(alpha: .30),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index++)
              Expanded(
                child: _NavigationDestinationButton(
                  destination: _destinations[index],
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NavigationDestinationButton extends StatelessWidget {
  const _NavigationDestinationButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: destination.label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              color: selected
                  ? VioraColors.mauve.withValues(alpha: .52)
                  : Colors.transparent,
              boxShadow: selected
                  ? [
                BoxShadow(
                  color: const Color(0xFFE586F2).withValues(alpha: .20),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
                  : const [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.activeIcon : destination.icon,
                  size: 21,
                  color: selected ? VioraColors.blush : VioraColors.silver,
                ),
                const SizedBox(height: 3),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? VioraColors.blush : VioraColors.silver,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NavDestination {
  const _NavDestination(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _Chats extends StatefulWidget {
  const _Chats({required this.onOpenVibes});
  final ValueChanged<String> onOpenVibes;
  @override
  State<_Chats> createState() => _ChatsState();
}

class _ChatsState extends State<_Chats> {
  late Future<List<ConversationPreview>> _conversations;
  RealtimeChannel? _messageChannel;
  RealtimeChannel? _vibeChannel;
  Timer? _refreshTimer;
  Set<String> _unseenVibeUsers = <String>{};
  Set<String> _pinned = <String>{};
  String _chatFilter = '';
  String _chatTab = 'All';
  final _chatSearch = TextEditingController();

  Future<void> _loadPinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('viora_pinned_chats') ?? const [];
      if (mounted) setState(() => _pinned = saved.toSet());
    } catch (_) {}
  }

  Future<void> _togglePin(String id) async {
    setState(() {
      if (!_pinned.remove(id)) _pinned.add(id);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('viora_pinned_chats', _pinned.toList());
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _conversations = _load();
    _subscribeToMessages();
    _loadUnseenVibes();
    VibeSeenStore.version.addListener(_loadUnseenVibes);
    final userId = AppConfig.supabaseConfigured
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    if (userId != null) {
      _vibeChannel = Supabase.instance.client
          .channel('viora-chat-ring-$userId')
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'vibes_statuses',
        callback: (_) {
          _loadUnseenVibes();
          if (mounted) _reload();
        },
      )
          .subscribe();
    }
  }

  Future<void> _loadUnseenVibes() async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    try {
      final ids = await VibeRepository(
        Supabase.instance.client,
      ).usersWithUnseenVibes();
      if (mounted) setState(() => _unseenVibeUsers = ids);
    } catch (_) {
      // Rings fall back to the previous state.
    }
  }

  Future<void> _openPersonVibes(String userId) async {
    try {
      final stories = await VibeRepository(
        Supabase.instance.client,
      ).activeStatusesFor(userId);
      if (!mounted || stories.isEmpty) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StoryViewerScreen(stories: stories),
        ),
      );
      _loadUnseenVibes();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story could not be opened.')),
        );
      }
    }
  }

  void _subscribeToMessages() {
    if (!AppConfig.supabaseConfigured) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _messageChannel = Supabase.instance.client
        .channel('viora-chat-list-$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      callback: (_) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _reload();
        });
      },
    )
        .subscribe();
  }

  @override
  void dispose() {
    _chatSearch.dispose();
    VibeSeenStore.version.removeListener(_loadUnseenVibes);
    _refreshTimer?.cancel();
    final channel = _messageChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    final vibeChannel = _vibeChannel;
    if (vibeChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(vibeChannel));
    }
    super.dispose();
  }

  Future<List<ConversationPreview>> _load() {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return Future.value(const []);
    }
    return MessagingRepository(Supabase.instance.client).myConversations();
  }

  void _reload() {
    final next = _load();
    setState(() {
      _conversations = next;
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _conversations = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the connection error.
    }
  }

  Future<void> _deleteConversation(ConversationPreview item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '“${item.title}” will be removed from your chat list. The other person keeps their chat, and a new message can make it appear here again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete chat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MessagingRepository(
        Supabase.instance.client,
      ).deleteConversationForMe(item.id);
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat deleted from your list.')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete chat: $error')),
        );
      }
    }
  }

  Future<void> _showConversationActions(ConversationPreview item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _pinned.contains(item.id)
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
              ),
              title: Text(
                _pinned.contains(item.id) ? 'Unpin chat' : 'Pin chat',
              ),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.pinkAccent,
              ),
              title: const Text('Delete chat for me'),
              subtitle: const Text('The other person keeps their messages.'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'pin' && mounted) await _togglePin(item.id);
    if (action == 'delete' && mounted) await _deleteConversation(item);
  }

  Widget _chatTile(ConversationPreview item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 12,
        ),
        leading: GestureDetector(
          onTap:
          item.hasActiveVibe &&
              !item.isGroup &&
              item.peerUserId != null
              ? () => _openPersonVibes(item.peerUserId!)
              : null,
          child: Container(
            padding: EdgeInsets.all(item.hasActiveVibe ? 2.5 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.hasActiveVibe &&
                  !_unseenVibeUsers.contains(item.peerUserId)
                  ? Colors.white24
                  : null,
              gradient: item.hasActiveVibe &&
                  _unseenVibeUsers.contains(item.peerUserId)
                  ? const LinearGradient(
                colors: [Color(0xFF9BFFC1), Color(0xFF20C66B)],
              )
                  : null,
            ),
            child: CircleAvatar(
              radius: item.hasActiveVibe ? 22.5 : 25,
              backgroundColor: VioraColors.mauve,
              backgroundImage: item.avatarUrl == null
                  ? null
                  : NetworkImage(item.avatarUrl!),
              child: item.avatarUrl == null
                  ? Icon(
                item.isGroup
                    ? Icons.groups_2_outlined
                    : Icons.person_outline,
              )
                  : null,
            ),
          ),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          item.previewText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_pinned.contains(item.id))
              const Icon(
                Icons.push_pin,
                size: 13,
                color: VioraColors.silver,
              ),
            if (item.lastMessageAt != null)
              Text(
                _chatListTime(item.lastMessageAt!),
                style: const TextStyle(
                  color: VioraColors.silver,
                  fontSize: 11,
                ),
              ),
            if (item.isGroup)
              Text(
                '${item.memberCount} members',
                style: const TextStyle(
                  color: VioraColors.silver,
                  fontSize: 10,
                ),
              ),
          ],
        ),
        onLongPress: () => _showConversationActions(item),
        onTap: () =>
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  conversationId: item.id,
                  title: item.title,
                  isGroup: item.isGroup,
                  memberCount: item.memberCount,
                ),
              ),
            ).then((_) {
              if (mounted) _reload();
            }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<ConversationPreview>>(
        future: _conversations,
        builder: (context, snapshot) {
          if (!AppConfig.supabaseConfigured ||
              Supabase.instance.client.auth.currentUser == null) {
            return const _EmptyState(
              icon: Icons.lock_outline,
              title: 'Sign in to see your chats',
              detail: 'Your conversations will appear here after you sign in.',
            );
          }
          if (snapshot.hasError) {
            return _EmptyState(
              icon: Icons.wifi_off_outlined,
              title: 'Chats could not load',
              detail: 'Check your connection and Supabase setup.',
              action: TextButton(
                onPressed: _reload,
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allConversations = snapshot.data!;
          final needle = _chatFilter.toLowerCase();
          final conversations = [
            ...allConversations.where(
                  (c) =>
              (needle.isEmpty || c.title.toLowerCase().contains(needle)) &&
                  switch (_chatTab) {
                    'Groups' => c.isGroup,
                    'Direct' => !c.isGroup,
                    'Pinned' => _pinned.contains(c.id),
                    _ => true,
                  },
            ),
          ]..sort((a, b) {
            final pa = _pinned.contains(a.id) ? 0 : 1;
            final pb = _pinned.contains(b.id) ? 0 : 1;
            return pa.compareTo(pb);
          });
          if (allConversations.isEmpty) {
            return const _EmptyState(
              icon: Icons.forum_outlined,
              title: 'Your conversations start here',
              detail: 'Discover people and send your first message.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              itemCount: conversations.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _chatSearch,
                      onChanged: (v) => setState(() => _chatFilter = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search chats',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _chatFilter.isEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _chatSearch.clear();
                            setState(() => _chatFilter = '');
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .06),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }
                if (index == 1) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final label in const [
                              'All',
                              'Direct',
                              'Groups',
                              'Pinned',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(label),
                                  selected: _chatTab == label,
                                  onSelected: (_) =>
                                      setState(() => _chatTab = label),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (conversations.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              _chatTab == 'All'
                                  ? 'No chats match your search.'
                                  : 'No $_chatTab chats yet.',
                              style: const TextStyle(color: VioraColors.silver),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return _chatTile(conversations[index - 2]);
              },
            ),
          );
        },
      );
}

String _chatListTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
  if (now.difference(local).inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[local.weekday - 1];
  }
  return '${local.month}/${local.day}/${local.year}';
}

class _Discover extends StatefulWidget {
  const _Discover();
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  final _search = TextEditingController();
  Future<List<Map<String, dynamic>>>? _people;
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openChat(Map<String, dynamic> person) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final repository = MessagingRepository(Supabase.instance.client);
      final id = await repository.openDirectConversation(
        person['id'] as String,
      );
      if (!mounted) return;
      final displayName = (person['display_name'] as String?)?.trim();
      final username = person['username'] as String?;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id,
            title: displayName?.isNotEmpty == true
                ? displayName!
                : '@${username ?? 'viora_user'}',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError('Could not open this conversation. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return const _EmptyState(
        icon: Icons.people_outline,
        title: 'Find your people',
        detail: 'Sign in to find people on Viora by name.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _search,
          onChanged: (query) => setState(() {
            _people = query.trim().isEmpty
                ? null
                : MessagingRepository(
              Supabase.instance.client,
            ).searchPeople(query);
          }),
          decoration: const InputDecoration(
            hintText: 'Search people by name...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (_people == null)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: Text(
              'Type a name or @username to find people.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VioraColors.silver),
            ),
          )
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _people,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('People could not be loaded. Try again.');
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Text('No Viora users matched that search.');
              }
              return Column(
                children: [
                  for (final person in snapshot.data!)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: VioraColors.mauve,
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        (person['display_name'] as String?)
                            ?.trim()
                            .isNotEmpty ==
                            true
                            ? person['display_name'] as String
                            : 'Viora user',
                      ),
                      subtitle: Text('@${person['username'] ?? 'viora_user'}'),
                      trailing: IconButton(
                        onPressed: _opening ? null : () => _openChat(person),
                        icon: _opening
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.chat_bubble_outline),
                      ),
                      onTap: () => _openChat(person),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: VioraColors.blush.withValues(alpha: .8)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'serif', fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VioraColors.silver),
          ),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

class _Vibes extends StatefulWidget {
  const _Vibes();
  @override
  State<_Vibes> createState() => _VibesState();
}

class _VibesState extends State<_Vibes> {
  late Future<List<Map<String, dynamic>>> _statuses;
  bool _posting = false;
  final _picker = ImagePicker();
  RealtimeChannel? _statusChannel;
  Timer? _statusRefreshTimer;

  @override
  void initState() {
    super.initState();
    _statuses = _loadStatuses();
    _subscribeToStatuses();
    VibeSeenStore.version.addListener(_onSeenChanged);
  }

  void _onSeenChanged() {
    if (mounted) _reloadStatuses();
  }

  Future<void> _openStories(String ownerId) async {
    final all = await _statuses;
    final seenIds = all.where((s) => s['seen'] == true).map((s) => s['id']);
    final mine = all
        .where((s) => s['user_id'] == ownerId)
        .map((s) => {...s, 'seen': seenIds.contains(s['id'])})
        .toList()
        .reversed
        .toList();
    if (mine.isEmpty || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StoryViewerScreen(stories: mine),
      ),
    );
    if (mounted) _reloadStatuses();
  }

  void _subscribeToStatuses() {
    if (!AppConfig.supabaseConfigured) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _statusChannel = Supabase.instance.client
        .channel('viora-vibes-feed-$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vibes_statuses',
      callback: (_) {
        _statusRefreshTimer?.cancel();
        _statusRefreshTimer = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _reloadStatuses();
        });
      },
    )
        .subscribe();
  }

  @override
  void dispose() {
    VibeSeenStore.version.removeListener(_onSeenChanged);
    _statusRefreshTimer?.cancel();
    final channel = _statusChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadStatuses() async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return const [];
    }
    final client = Supabase.instance.client;
    final rows = await client
        .from('vibes_statuses')
        .select('id,user_id,body,media_path,media_type,created_at,expires_at')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    final userIds = rows
        .map((row) => row['user_id'] as String)
        .toSet()
        .toList();
    if (userIds.isEmpty) return const [];
    List<Map<String, dynamic>> people = const [];
    try {
      people = (await client
          .from('discoverable_profiles')
          .select('id,display_name,username,avatar_path')
          .inFilter('id', userIds))
          .cast<Map<String, dynamic>>();
    } catch (_) {
      // Stories still show (with a generic name) if profiles cannot load.
    }
    final profiles = <String, Map<String, dynamic>>{};
    for (final person in people) {
      final name = (person['display_name'] as String?)?.trim();
      profiles[person['id'] as String] = {
        ...person,
        'display_name': name?.isNotEmpty == true
            ? name!
            : '@${person['username'] ?? 'viora_user'}',
      };
    }
    await Future.wait(
      profiles.values.map((profile) async {
        final path = profile['avatar_path'] as String?;
        if (path == null) return;
        try {
          profile['avatar_url'] = await client.storage
              .from('profile-media')
              .createSignedUrl(path, 3600);
        } on StorageException {
          // Keep the initials avatar if private media is unavailable.
        }
      }),
    );
    final seenIds = await VibeRepository(client).seenStatusIds();
    return rows.map((row) {
      final profile = profiles[row['user_id']] ?? const <String, dynamic>{};
      return {
        ...row,
        'display_name': profile['display_name'] ?? 'Viora user',
        'avatar_url': profile['avatar_url'],
        'seen': seenIds.contains(row['id']),
      };
    }).toList();
  }

  void _reloadStatuses() {
    final nextStatuses = _loadStatuses();
    setState(() {
      _statuses = nextStatuses;
    });
  }

  Future<void> _refreshStatuses() async {
    final nextStatuses = _loadStatuses();
    setState(() {
      _statuses = nextStatuses;
    });
    try {
      await nextStatuses;
    } catch (_) {
      // FutureBuilder shows the load error and its retry action.
    }
  }

  Future<void> _compose() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Share a Vibe')),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Text update'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video (up to 30 seconds)'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == 'image' || kind == 'video') {
      await _shareMediaStatus(kind);
      return;
    }
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share a Vibe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 280,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'What’s on your mind?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to share a Vibe.')));
      return;
    }
    setState(() => _posting = true);
    try {
      await Supabase.instance.client.from('vibes_statuses').insert({
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'body': text,
      });
      if (mounted) _reloadStatuses();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your Vibe could not be shared. Check your connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _shareMediaStatus(String mediaType) async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to share a Vibe.')));
      return;
    }
    XFile? file;
    if (mediaType == 'video') {
      file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
    } else {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 25 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose media smaller than 25 MB.')),
      );
      return;
    }
    final extension = file.name.split('.').last.toLowerCase();
    const imageTypes = {'jpg', 'jpeg', 'png', 'webp'};
    if ((mediaType == 'image' && !imageTypes.contains(extension)) ||
        (mediaType == 'video' && extension != 'mp4')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mediaType == 'video'
                ? 'Choose an MP4 video.'
                : 'Choose a JPG, PNG, or WebP image.',
          ),
        ),
      );
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final path = '$userId/${const Uuid().v4()}.$extension';
    String? uploadedPath;
    setState(() => _posting = true);
    try {
      final mimeType = mediaType == 'video'
          ? 'video/mp4'
          : extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      await Supabase.instance.client.storage
          .from('status-media')
          .uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType),
      );
      uploadedPath = path;
      await Supabase.instance.client.from('vibes_statuses').insert({
        'user_id': userId,
        'body': mediaType == 'video' ? 'Shared a video' : 'Shared a photo',
        'media_path': path,
        'media_type': mediaType,
      });
      uploadedPath = null;
      if (mounted) _reloadStatuses();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share media: $error')),
        );
      }
    } finally {
      if (uploadedPath != null) {
        try {
          await Supabase.instance.client.storage.from('status-media').remove([
            uploadedPath,
          ]);
        } catch (_) {}
      }
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(
      BuildContext context,
      ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _statuses,
    builder: (context, snapshot) {
      final statuses = snapshot.data ?? const <Map<String, dynamic>>[];
      final userId = AppConfig.supabaseConfigured
          ? Supabase.instance.client.auth.currentUser?.id
          : null;
      final myStatus = statuses
          .where((status) => status['user_id'] == userId)
          .toList();
      final others = statuses
          .where((status) => status['user_id'] != userId)
          .toList();
      final peopleWithVibes = uniqueVibePeople(others);
      final unseenOwners = others
          .where((status) => status['seen'] != true)
          .map((status) => status['user_id'] as String)
          .toSet();
      return RefreshIndicator(
        onRefresh: _refreshStatuses,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          InkWell(
                            onTap: _posting
                                ? null
                                : (myStatus.isNotEmpty && userId != null
                                ? () => _openStories(userId)
                                : _compose),
                            borderRadius: BorderRadius.circular(40),
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: myStatus.isNotEmpty
                                    ? const LinearGradient(
                                  colors: [Color(0xFFE68CFF), Color(0xFF7B5CFF)],
                                )
                                    : null,
                              ),
                              child: CircleAvatar(
                                radius: 29,
                                backgroundColor: VioraColors.charcoal,
                                backgroundImage:
                                myStatus.isNotEmpty &&
                                    myStatus.first['avatar_url'] is String
                                    ? NetworkImage(
                                  myStatus.first['avatar_url'] as String,
                                )
                                    : null,
                                child: _posting
                                    ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : (myStatus.isNotEmpty &&
                                    myStatus.first['avatar_url']
                                    is String
                                    ? null
                                    : const Icon(Icons.person_outline)),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: GestureDetector(
                              onTap: _posting ? null : _compose,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: VioraColors.mauve,
                                  border: Border.all(
                                    color: VioraColors.midnight,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(Icons.add, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        myStatus.isEmpty ? 'Add story' : 'Your Story',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  for (final person in peopleWithVibes)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(40),
                        onTap: () => _openStories(person['user_id'] as String),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: unseenOwners.contains(person['user_id'])
                                    ? null
                                    : Colors.white24,
                                gradient:
                                unseenOwners.contains(person['user_id'])
                                    ? const LinearGradient(
                                  colors: [
                                    Color(0xFF9BFFC1),
                                    Color(0xFF20C66B),
                                  ],
                                )
                                    : null,
                              ),
                              child: CircleAvatar(
                                radius: 27,
                                backgroundColor: VioraColors.mauve,
                                backgroundImage: person['avatar_url'] is String
                                    ? NetworkImage(
                                  person['avatar_url'] as String,
                                )
                                    : null,
                                child: person['avatar_url'] is String
                                    ? null
                                    : Text(
                                  (person['display_name'] as String)
                                      .characters
                                      .first
                                      .toUpperCase(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 60,
                              child: Text(
                                person['display_name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (userId != null && myStatus.isNotEmpty)
              _MyStoryCard(
                stories: myStatus,
                onOpen: () => _openStories(userId),
              ),
            if (userId != null && myStatus.isEmpty && snapshot.hasData)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: InkWell(
                  onTap: _compose,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_circle_outline, color: VioraColors.blush),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text('Share a Vibe — it stays for 24 hours.'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!AppConfig.supabaseConfigured || userId == null)
              const _EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'Share your little moments',
                detail: 'Sign in to post a Vibe for people you chat with.',
              ),
            if (snapshot.hasError)
              _EmptyState(
                icon: Icons.wifi_off_outlined,
                title: 'Vibes could not load',
                detail:
                'Check your connection and make sure the status migration is applied.',
                action: TextButton(
                  onPressed: _reloadStatuses,
                  child: const Text('Retry'),
                ),
              ),
            if (!snapshot.hasData && !snapshot.hasError && userId != null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  Future<Map<String, dynamic>?>? _profile;

  Future<Map<String, dynamic>?> _loadProfile() async {
    final client = Supabase.instance.client;
    final id = client.auth.currentUser?.id;
    if (id == null) return null;
    final row = await client
        .from('profiles')
        .select('display_name,username,bio,avatar_path')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final path = row['avatar_path'] as String?;
    return {
      ...row,
      'avatar_url': path == null
          ? null
          : await client.storage
          .from('profile-media')
          .createSignedUrl(path, 3600),
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = AppConfig.supabaseConfigured
        ? Supabase.instance.client.auth.currentUser
        : null;
    if (user != null) _profile ??= _loadProfile();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = (profile?['display_name'] as String?)?.trim();
        final avatarUrl = profile?['avatar_url'] as String?;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            Center(
              child: CircleAvatar(
                radius: 58,
                backgroundColor: VioraColors.mauve,
                backgroundImage: avatarUrl == null
                    ? null
                    : NetworkImage(avatarUrl),
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 52)
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              displayName?.isNotEmpty == true ? displayName! : 'Your Profile',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 5),
            Text(
              profile?['username'] == null
                  ? (user?.email ?? 'Sign in to view your profile')
                  : '@${profile!['username']}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: VioraColors.silver),
            ),
            if ((profile?['bio'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(profile!['bio'] as String, textAlign: TextAlign.center),
            ],
            if (snapshot.hasError)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Profile details could not be loaded.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VioraColors.silver),
                ),
              ),
            const SizedBox(height: 25),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: user == null
                  ? null
                  : () =>
                  Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ).then((changed) {
                    if (changed == true && mounted) {
                      final nextProfile = _loadProfile();
                      setState(() {
                        _profile = nextProfile;
                      });
                    }
                  }),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy & Safety'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacySafetyScreen()),
              ),
            ),
            if (user != null)
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.pinkAccent),
                title: const Text(
                  'Log Out',
                  style: TextStyle(color: Colors.pinkAccent),
                ),
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                          (route) => false,
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }
}


/// Shows that your own story is live: count, time left and viewers.
class _MyStoryCard extends StatelessWidget {
  const _MyStoryCard({required this.stories, required this.onOpen});
  final List<Map<String, dynamic>> stories;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final latest = DateTime.tryParse(stories.first['created_at'] as String? ?? '');
    final expires = DateTime.tryParse(stories.first['expires_at'] as String? ?? '');
    String ago = '';
    if (latest != null) {
      final d = DateTime.now().difference(latest.toLocal());
      ago = d.inMinutes < 1
          ? 'just now'
          : d.inMinutes < 60
          ? '${d.inMinutes} min ago'
          : '${d.inHours} h ago';
    }
    String left = '';
    if (expires != null) {
      final d = expires.toLocal().difference(DateTime.now());
      if (d.inMinutes > 0) left = ' · ${d.inHours}h ${d.inMinutes % 60}m left';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A1650), Color(0xFF2A1240)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your story is live',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${stories.length} ${stories.length == 1 ? 'update' : 'updates'} · $ago$left',
                      style: const TextStyle(color: VioraColors.silver, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}