import 'package:woops/features/chat/domain/chat_models.dart';
import 'package:woops/features/profile/domain/profile_enums.dart';
import 'package:woops/features/profile/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  test('ProfileCard parses the discovery feed row', () {
    final c = ProfileCard.fromJson({
      'id': 'u1',
      'display_name': 'Asha',
      'age': 27,
      'gender': 'woman',
      'bio': 'Mountains',
      'intention': 'long_term',
      'job_title': null,
      'city': 'Kathmandu',
      'photos': ['u1/a.jpg', 'u1/b.jpg'],
      'interests': ['Hiking'],
      'prompts': [
        {'prompt': 'My ideal Sunday is…', 'answer': 'Momos'},
      ],
      'distance_km': 4,
    });
    expect(c.gender, Gender.woman);
    expect(c.intention, Intention.longTerm);
    expect(c.primaryPhoto, 'u1/a.jpg');
    expect(c.prompts.single.answer, 'Momos');
    expect(c.distanceKm, 4);
  });

  test('MyProfile sorts photos by position and computes completeness', () {
    final p = MyProfile.fromJson({
      'id': 'me',
      'display_name': 'Me',
      'birthdate': '1998-05-01',
      'gender': 'man',
      'bio': '',
      'intention': 'friends',
      'onboarding_completed': true,
      'profile_photos': [
        {'id': 'b', 'storage_path': 'me/b.jpg', 'position': 1},
        {'id': 'a', 'storage_path': 'me/a.jpg', 'position': 0},
      ],
      'profile_interests': [
        {'interest_id': 1},
      ],
      'profile_prompts': [],
    });
    expect(p.primaryPhoto, 'me/a.jpg');
    expect(p.interestIds, {1});
    expect(p.completeness, closeTo(0.175, 0.001)); // 2 of 4 photos
    expect(p.missingSteps, [ProfileStep.bio, ProfileStep.interests, ProfileStep.ageCheck]);
    expect(p.isReadyToDate, isFalse);
  });

  test('the 100% checklist adds up and says what each missing item is worth', () {
    final p = MyProfile.fromJson({
      'id': 'me',
      'display_name': 'Me',
      'birthdate': '1998-05-01',
      'gender': 'man',
      'bio': '',
      'intention': 'friends',
      'profile_photos': [],
    });
    expect(p.completionItems.fold<double>(0, (s, i) => s + i.weight), closeTo(1, 1e-9));
    expect(p.completenessPercent, 0);
    expect(p.completionItems.map((i) => i.remainingPercent).reduce((a, b) => a + b), 100);
    expect(
      ProfileCard.fromJson({'id': 'x', 'display_name': 'X', 'age': 30, 'gender': 'man', 'is_repeat': true}).isRepeat,
      isTrue,
    );
  });

  test('a pending ID review counts as ready; a rejected one does not', () {
    Map<String, dynamic> json(String status) => {
      'id': 'me',
      'display_name': 'Me',
      'birthdate': '1998-05-01',
      'gender': 'man',
      'bio': 'Hi',
      'intention': 'friends',
      'profile_photos': [
        {'id': 'a', 'storage_path': 'me/a.jpg', 'position': 0},
        {'id': 'b', 'storage_path': 'me/b.jpg', 'position': 1},
      ],
      'profile_interests': [
        {'interest_id': 1},
        {'interest_id': 2},
        {'interest_id': 3},
      ],
      'age_verifications': [
        {'status': 'rejected', 'reject_reason': 'blurry', 'created_at': '2026-10-01T00:00:00Z'},
        {'status': status, 'reject_reason': null, 'created_at': '2026-10-02T00:00:00Z'},
      ],
    };
    expect(MyProfile.fromJson(json('pending')).isReadyToDate, isTrue);
    final rejected = MyProfile.fromJson(json('rejected'));
    expect(rejected.ageCheck, AgeCheck.rejected);
    expect(rejected.missingSteps, [ProfileStep.ageCheck]);
    expect(MyProfile.fromJson({...json('pending'), 'age_verified': true}).ageCheck, AgeCheck.approved);
  });

  test('ProfileCard reads the random-pick flag (defaults to false)', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
      'id': 'x',
      'display_name': 'X',
      'age': 25,
      'gender': 'woman',
      ...extra,
    };
    expect(ProfileCard.fromJson(json()).isRandom, isFalse);
    expect(ProfileCard.fromJson(json({'is_random': true})).isRandom, isTrue);
  });

  test('DiscoveryPreferences round-trips to the database shape', () {
    const prefs = DiscoveryPreferences(minAge: 25, maxAge: 35, genders: {Gender.man}, intentions: {Intention.friends});
    final back = DiscoveryPreferences.fromJson({...prefs.toJson()});
    expect(back.minAge, 25);
    expect(back.genders, {Gender.man});
    expect(back.intentions, {Intention.friends});
    expect(prefs.toJson()['genders'], ['man']);
  });

  group('mergeMessages', () {
    final t0 = DateTime.utc(2026, 10, 14, 10);

    test('sorts newest first and removes duplicate ids', () {
      final a = msg('a', at: t0);
      final b = msg('b', at: t0.add(const Duration(minutes: 1)));
      final merged = mergeMessages([a], [b, a]);
      expect(merged.map((m) => m.id), ['b', 'a']);
    });

    test('server copy replaces optimistic copy with the same client id', () {
      final optimistic = ChatMessage(
        id: 'cid',
        conversationId: 'c1',
        senderId: 'me',
        clientId: 'cid',
        kind: MessageKind.text,
        body: 'hi',
        createdAt: t0,
        delivery: DeliveryState.sending,
      );
      final server = msg('srv', sender: 'me', clientId: 'cid', at: t0.add(const Duration(seconds: 1)));
      final merged = mergeMessages([optimistic], [server]);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'srv');
      expect(merged.single.delivery, DeliveryState.sent);
    });

    test('a late optimistic copy never overwrites a confirmed message', () {
      final server = msg('srv', sender: 'me', clientId: 'cid', at: t0);
      final optimistic = ChatMessage(
        id: 'cid',
        conversationId: 'c1',
        senderId: 'me',
        clientId: 'cid',
        kind: MessageKind.text,
        body: 'hi',
        createdAt: t0,
        delivery: DeliveryState.sending,
      );
      expect(mergeMessages([server], [optimistic]).single.id, 'srv');
    });
  });

  test('ConversationSummary preview prefixes my own messages', () {
    final c = ConversationSummary.fromJson({
      'match_id': 'm',
      'conversation_id': 'c',
      'matched_at': '2026-10-14T10:00:00Z',
      'other_user_id': 'o',
      'other_display_name': 'Bikash',
      'other_photo': null,
      'last_message_body': 'Hey!',
      'last_message_kind': 'text',
      'last_message_sender_id': 'me',
      'last_message_at': '2026-10-14T10:05:00Z',
      'unread_count': 2,
    });
    expect(c.previewFor('me'), 'You: Hey!');
    expect(c.previewFor('someone-else'), 'Hey!');
    expect(c.hasMessages, isTrue);
    expect(c.unreadCount, 2);
  });
}
