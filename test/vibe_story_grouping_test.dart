import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/models/vibe_story_grouping.dart';

void main() {
  test('story bubbles show each person once, even with multiple Vibes', () {
    final people = uniqueVibePeople([
      {'user_id': 'rooj', 'id': 'vibe-1'},
      {'user_id': 'rooj', 'id': 'vibe-2'},
      {'user_id': 'areej', 'id': 'vibe-3'},
    ]);

    expect(people.map((person) => person['user_id']), ['rooj', 'areej']);
  });
}
