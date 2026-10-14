import 'package:woops/core/supabase/supabase_providers.dart';
import 'package:woops/core/utils/app_exception.dart';
import 'package:woops/features/discovery/application/discovery_controller.dart';
import 'package:woops/features/discovery/data/discovery_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeDiscoveryRepository repo;
  late ProviderContainer container;

  Future<DiscoveryController> start() async {
    container = ProviderContainer(
      overrides: [discoveryRepositoryProvider.overrideWithValue(repo), currentUserIdProvider.overrideWithValue('me')],
    );
    addTearDown(container.dispose);
    container.listen(discoveryControllerProvider, (_, _) {});
    await pumpEventQueue();
    return container.read(discoveryControllerProvider.notifier);
  }

  DiscoveryState state() => container.read(discoveryControllerProvider);

  test('loads the first page', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ]);
    await start();
    expect(state().queue.map((c) => c.id), ['a', 'b']);
    expect(state().isLoading, isFalse);
    expect(state().exhausted, isTrue); // fewer than a full page
  });

  test('a like that matches returns the match and removes the card', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ])..matchOnLike = {'a'};
    final c = await start();

    final result = await c.swipe(state().queue.first, SwipeAction.like);

    expect(result!.matched, isTrue);
    expect(result.conversationId, 'c-a');
    expect(state().queue.map((c) => c.id), ['b']);
    expect(repo.swipes, [('a', SwipeAction.like)]);
  });

  test('double-swiping the same card only sends one request', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ]);
    final c = await start();
    final a = state().queue.first;
    await Future.wait([c.swipe(a, SwipeAction.like), c.swipe(a, SwipeAction.like)]);
    expect(repo.swipes, hasLength(1));
  });

  test('a failed swipe restores the card and reports a friendly error', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ])..swipeError = const PostgrestException(message: 'rate_limited: you are out of likes for today');
    final c = await start();

    await expectLater(
      c.swipe(state().queue.first, SwipeAction.like),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'rate_limited')),
    );
    expect(state().queue.map((c) => c.id), ['a', 'b']);
  });

  test('an unavailable profile is not restored', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ])..swipeError = const PostgrestException(message: 'unavailable: gone');
    final c = await start();
    await expectLater(c.swipe(state().queue.first, SwipeAction.pass), throwsA(isA<AppException>()));
    expect(state().queue.map((c) => c.id), ['b']);
  });

  test('undo brings back the last passed profile', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ])..undoResult = 'a';
    final c = await start();
    await c.swipe(state().queue.first, SwipeAction.pass);
    expect(state().canUndo, isTrue);

    await c.undo();
    expect(state().queue.map((c) => c.id), ['a', 'b']);
    expect(state().canUndo, isFalse);
  });

  test('likes cannot be undone (no undo offered after a like)', () async {
    repo = FakeDiscoveryRepository([
      [card('a'), card('b')],
    ]);
    final c = await start();
    await c.swipe(state().queue.first, SwipeAction.like);
    expect(state().canUndo, isFalse);
  });

  test('prefetch never duplicates profiles already in the queue', () async {
    final full = List.generate(DiscoveryController.pageSize, (i) => card('p$i'));
    repo = FakeDiscoveryRepository([
      full,
      [card('p19'), card('new')], // p19 is still queued
    ]);
    final c = await start();
    // Swipe until the queue drops under the prefetch threshold.
    while (state().queue.length >= DiscoveryController.prefetchThreshold) {
      await c.swipe(state().queue.first, SwipeAction.pass);
    }
    await pumpEventQueue();
    final ids = state().queue.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, contains('new'));
  });
}
