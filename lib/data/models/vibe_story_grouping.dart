/// Returns one story-ring entry per person while leaving every Vibe post in
/// the feed itself.
List<Map<String, dynamic>> uniqueVibePeople(
  Iterable<Map<String, dynamic>> statuses,
) {
  final people = <String, Map<String, dynamic>>{};
  for (final status in statuses) {
    people.putIfAbsent(status['user_id'] as String, () => status);
  }
  return people.values.toList();
}
