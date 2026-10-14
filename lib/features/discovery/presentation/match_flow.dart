import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../chat/application/chat_controllers.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/profile_models.dart';
import '../data/discovery_repository.dart';
import 'match_overlay.dart';

/// After a swipe that produced a match: celebrate, refresh the inbox, and
/// optionally jump straight into the new conversation.
Future<void> celebrateMatch(BuildContext context, WidgetRef ref, SwipeResult result, ProfileCard card) async {
  if (!result.matched) return;
  ref.read(inboxProvider.notifier).refresh();
  final myPhoto = ref.read(myProfileProvider).valueOrNull?.primaryPhoto;
  final message = await showMatchOverlay(
    context,
    myPhoto: myPhoto,
    theirPhoto: card.primaryPhoto,
    theirName: card.displayName,
  );
  if (message == true && result.conversationId != null && result.matchId != null && context.mounted) {
    context.push(
      Routes.chat(result.conversationId!),
      extra: ChatRouteArgs(
        matchId: result.matchId!,
        otherUserId: card.id,
        otherName: card.displayName,
        otherPhoto: card.primaryPhoto,
      ),
    );
  }
}
