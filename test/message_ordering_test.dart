import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/models/message_ordering.dart';

void main() {
  test('messages sort newest-first with id as a stable tie-breaker', () {
    final messages = newestMessagesFirst([
      {'id': 'b', 'created_at': '2026-10-28T10:00:00Z'},
      {'id': 'a', 'created_at': '2026-10-28T10:00:00Z'},
      {'id': 'older', 'created_at': '2026-10-27T10:00:00Z'},
    ]);

    expect(messages.map((message) => message['id']), ['b', 'a', 'older']);
  });
}
