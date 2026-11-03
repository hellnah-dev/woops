import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woops/features/moments/application/moments_controller.dart';
import 'package:woops/features/moments/data/moments_repository.dart';

class _FakeMoments extends MomentsController {
  @override
  Future<List<Moment>> build() async => [
    Moment(
      id: 'm1',
      userId: 'u',
      displayName: 'Ana',
      createdAt: DateTime.utc(2026, 10, 22),
      expiresAt: DateTime.utc(2026, 10, 23),
      isMine: false,
      body: 'hi',
    ),
  ];
}

void main() {
  test('seen moments are remembered on the phone across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [momentsProvider.overrideWith(_FakeMoments.new)]);
    addTearDown(c.dispose);
    await c.read(momentsProvider.future);
    await c.read(seenMomentsProvider.notifier).markSeen('m1');
    expect(c.read(seenMomentsProvider), {'m1'});
    expect((await SharedPreferences.getInstance()).getStringList('moments_seen'), ['m1']);

    // A fresh start loads them back.
    final again = ProviderContainer(overrides: [momentsProvider.overrideWith(_FakeMoments.new)]);
    addTearDown(again.dispose);
    again.read(seenMomentsProvider);
    await pumpEventQueue();
    expect(again.read(seenMomentsProvider), {'m1'});
  });
}
