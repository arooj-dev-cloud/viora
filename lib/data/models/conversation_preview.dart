class ConversationPreview {
  const ConversationPreview({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.lastMessage,
    required this.memberCount,
    this.lastMessageAt,
    this.attachmentPath,
    this.peerUserId,
    this.avatarUrl,
    this.hasActiveVibe = false,
  });

  final String id;
  final String title;
  final bool isGroup;
  final String lastMessage;
  final int memberCount;
  final DateTime? lastMessageAt;
  final String? attachmentPath;
  final String? peerUserId;
  final String? avatarUrl;
  final bool hasActiveVibe;

  String get previewText {
    if (attachmentPath == null) return lastMessage;
    final extension = attachmentPath!.split('.').last.toLowerCase();
    if (const {'mp4', 'mov', 'm4v', 'webm'}.contains(extension)) {
      return 'Video';
    }
    if (const {'m4a', 'aac', 'ogg'}.contains(extension)) {
      return 'Voice message';
    }
    if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
      return 'Photo';
    }
    return lastMessage.isEmpty ? 'Attachment' : lastMessage;
  }
}
