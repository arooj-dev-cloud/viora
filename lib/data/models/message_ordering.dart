/// Sorts messages newest-first for a `ListView(reverse: true)`.
/// A unique message id provides a deterministic order for equal timestamps.
List<Map<String, dynamic>> newestMessagesFirst(
  Iterable<Map<String, dynamic>> rows,
) {
  final messages = rows.toList();
  messages.sort((first, second) {
    final firstTime = DateTime.tryParse(first['created_at'] as String? ?? '');
    final secondTime = DateTime.tryParse(second['created_at'] as String? ?? '');
    final byTime = (secondTime ?? DateTime.utc(1970)).compareTo(
      firstTime ?? DateTime.utc(1970),
    );
    if (byTime != 0) return byTime;
    return (second['id'] as String).compareTo(first['id'] as String);
  });
  return messages;
}
