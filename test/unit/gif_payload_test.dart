import 'package:flutter_test/flutter_test.dart';
import 'package:woops/features/chat/domain/chat_models.dart';

void main() {
  test('a GIF message round-trips its link and size', () {
    const gif = GifPayload(url: 'https://media2.giphy.com/media/abc/200w.webp', width: 200, height: 150, title: 'Hi');
    final back = GifPayload.tryParse(gif.encode())!;
    expect(back.url, gif.url);
    expect(back.aspectRatio, closeTo(200 / 150, 1e-9));
  });

  test('only https links from GIPHY are ever shown', () {
    expect(GifPayload.tryParse('{"url":"http://media.giphy.com/x.gif"}'), isNull);
    expect(GifPayload.tryParse('{"url":"https://evil.example.com/x.gif"}'), isNull);
    expect(GifPayload.tryParse('{"url":"https://giphy.com.evil.example/x.gif"}'), isNull);
    expect(GifPayload.tryParse('not json'), isNull);
    expect(GifPayload.tryParse('{"url":"https://i.giphy.com/x.webp"}'), isNotNull);
  });

  test('chat list previews say GIF, not the link', () {
    final c = ConversationSummary(
      matchId: 'm',
      conversationId: 'c',
      matchedAt: DateTime.utc(2026),
      otherUserId: 'o',
      otherDisplayName: 'O',
      unreadCount: 0,
      lastMessageBody: '{"url":"https://i.giphy.com/x.webp"}',
      lastMessageKind: MessageKind.gif,
      lastMessageSenderId: 'o',
      lastMessageAt: DateTime.utc(2026),
    );
    expect(c.previewFor('me'), 'GIF');
  });
}
