import 'package:flutter_test/flutter_test.dart';
import 'package:woops/features/chat/presentation/linkified_text.dart';

void main() {
  List<String> links(String t) => [
    for (final p in parseLinks(t))
      if (p.isLink) p.uri.toString(),
  ];

  test('finds http(s), www and bare domains, and keeps the rest as text', () {
    expect(links('see https://kamaucha.me/rammy24d and www.example.com or woops.app/help'), [
      'https://kamaucha.me/rammy24d',
      'https://www.example.com',
      'https://woops.app/help',
    ]);
    final parts = parseLinks('hi https://a.com bye');
    expect(parts.map((p) => p.text).join(), 'hi https://a.com bye');
  });

  test('trailing punctuation is not part of the link', () {
    expect(links('Go to https://example.com/path.'), ['https://example.com/path']);
    expect(links('(www.example.org)'), ['https://www.example.org']);
  });

  test('plain text, emails and decimals are not links', () {
    expect(links('see you at 5.30 tonight'), isEmpty);
    expect(links('mail me at rammy@example.com'), isEmpty);
    expect(links('just words'), isEmpty);
  });
}
