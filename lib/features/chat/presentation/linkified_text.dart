import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A piece of message text: plain, or a link.
class TextPart {
  const TextPart(this.text, {this.uri});
  final String text;
  final Uri? uri;
  bool get isLink => uri != null;
}

final _linkPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>]+|\b[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:com|net|org|io|me|app|dev|co|info|in|np|uk|us|ai|gg|ly|xyz|link|site|online)(?:\/[^\s<>]*)?)',
  caseSensitive: false,
);

/// Splits [text] into plain parts and links. Trailing punctuation such as
/// "." or ")" is not part of a link. Only http(s) links are produced.
List<TextPart> parseLinks(String text) {
  final parts = <TextPart>[];
  var last = 0;
  for (final m in _linkPattern.allMatches(text)) {
    var raw = m.group(0)!;
    var end = m.end;
    while (raw.isNotEmpty && '.,!?;:)\'"]'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
      end--;
    }
    // Skip things like "a.b" inside an email address.
    if (m.start > 0 && text[m.start - 1] == '@') continue;
    final uri = Uri.tryParse(raw.toLowerCase().startsWith('http') ? raw : 'https://$raw');
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) continue;
    if (m.start > last) parts.add(TextPart(text.substring(last, m.start)));
    parts.add(TextPart(text.substring(m.start, end), uri: uri));
    last = end;
  }
  if (last < text.length) parts.add(TextPart(text.substring(last)));
  return parts;
}

/// Message text with tappable links. Tapping asks first and shows the real
/// domain, so a disguised link can't open by surprise.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style, this.linkColor});
  final String text;
  final TextStyle? style;
  final Color? linkColor;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.link_rounded),
        title: const Text('Open link?'),
        content: Text(
          'This opens ${uri.host} in your browser. Only open links from people you trust, '
          'and never share passwords or payment details.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final parts = parseLinks(widget.text);
    if (parts.every((p) => !p.isLink)) return Text(widget.text, style: widget.style);
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final p in parts)
            if (!p.isLink)
              TextSpan(text: p.text)
            else
              TextSpan(
                text: p.text,
                style: TextStyle(
                  color: widget.linkColor,
                  decoration: TextDecoration.underline,
                  decorationColor: widget.linkColor,
                  fontWeight: FontWeight.w700,
                ),
                recognizer: (TapGestureRecognizer()..onTap = () => _open(p.uri!)).also(_recognizers.add),
              ),
        ],
      ),
    );
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
