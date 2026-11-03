import 'package:flutter_test/flutter_test.dart';
import 'package:woops/features/matches/application/match_insights.dart';
import 'package:woops/features/moments/application/moments_controller.dart';
import 'package:woops/features/moments/data/moments_repository.dart';
import 'package:woops/features/profile/domain/profile_enums.dart';

Moment moment(String id, String user, int minutesAgo, {bool mine = false}) {
  final at = DateTime.utc(2026, 10, 22, 12).subtract(Duration(minutes: minutesAgo));
  return Moment(
    id: id,
    userId: user,
    displayName: user,
    createdAt: at,
    expiresAt: at.add(const Duration(hours: 24)),
    isMine: mine,
    body: 'hi',
  );
}

void main() {
  group('moments', () {
    test('one group per person, played oldest first', () {
      final groups = groupMoments([moment('a2', 'ana', 5), moment('a1', 'ana', 50)], const {});
      expect(groups, hasLength(1));
      expect(groups.single.moments.map((m) => m.id), ['a1', 'a2']);
    });

    test('mine first, then people with something new, then newest', () {
      final groups = groupMoments(
        [moment('old-unseen', 'bo', 120), moment('new-seen', 'cy', 1), moment('mine', 'me', 300, mine: true)],
        {'new-seen'},
      );
      expect(groups.map((g) => g.userId), ['me', 'bo', 'cy']);
      expect(groups[1].hasUnseen({'new-seen'}), isTrue);
      expect(groups[2].hasUnseen({'new-seen'}), isFalse);
    });

    test('reads the server row', () {
      final m = Moment.fromJson({
        'id': 'x',
        'user_id': 'u',
        'display_name': 'Ana',
        'avatar': 'u/1.webp',
        'body': null,
        'photo_path': 'u/p.webp',
        'style': 3,
        'created_at': '2026-10-22T12:00:00Z',
        'expires_at': '2026-10-23T12:00:00Z',
        'is_mine': false,
      });
      expect(m.hasPhoto, isTrue);
      expect(m.style, 3);
    });
  });

  group('match modes and insights', () {
    test('every intention has a mode', () {
      expect(MatchMode.of(Intention.longTermOpen), MatchMode.longTerm);
      expect(MatchMode.of(Intention.shortTerm), MatchMode.dating);
      expect(MatchMode.of(Intention.friends), MatchMode.friends);
      expect(MatchMode.of(Intention.figuringOut), MatchMode.open);
    });

    test('why you matched reads naturally', () {
      final i = MatchInsight.fromJson({
        'intention': 'friends',
        'shared_interests': ['Hiking', 'Coffee', 'Music'],
        'distance_km': 12,
      });
      expect(i.summary, '3 in common · 12 km');
      expect(i.mode, MatchMode.friends);
      expect(const MatchInsight(intention: Intention.longTerm).summary, isNull);
      expect(const MatchInsight(intention: Intention.longTerm, distanceKm: 4).summary, '4 km');
    });
  });
}
