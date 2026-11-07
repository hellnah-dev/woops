import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/chat_models.dart';

/// Picks a GIF from GIPHY (trending, or search). Returns null if cancelled.
/// Only PG-13 GIFs are offered, which suits a dating app.
Future<GifPayload?> pickGif(BuildContext context) async {
  if (Env.giphyApiKey.isEmpty) {
    showSnack(context, 'GIFs aren’t set up yet.', isError: true);
    return null;
  }
  return showModalBottomSheet<GifPayload>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _GifSheet(),
  );
}

class _GifSheet extends StatefulWidget {
  const _GifSheet();

  @override
  State<_GifSheet> createState() => _GifSheetState();
}

class _GifSheetState extends State<_GifSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<GifPayload> _gifs = const [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(q.trim()));
  }

  Future<void> _load(String q) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.https('api.giphy.com', q.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search', {
        'api_key': Env.giphyApiKey,
        if (q.isNotEmpty) 'q': q,
        'limit': '30',
        'rating': 'pg-13',
        'bundle': 'messaging_non_clips',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('GIPHY ${res.statusCode}');
      final data = (jsonDecode(res.body) as Map)['data'] as List;
      final gifs = <GifPayload>[];
      for (final g in data) {
        final img = ((g as Map)['images'] as Map?)?['fixed_width'] as Map?;
        final url = (img?['webp'] ?? img?['url']) as String?;
        if (url == null) continue;
        gifs.add(
          GifPayload(
            url: url,
            width: int.tryParse('${img!['width']}') ?? 0,
            height: int.tryParse('${img['height']}') ?? 0,
            title: g['title'] as String? ?? '',
          ),
        );
      }
      if (!mounted || request != _request) return;
      setState(() {
        _gifs = gifs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load GIFs. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 8),
              child: TextField(
                key: const Key('gif-search'),
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search GIFs',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading && _gifs.isEmpty
                  ? const LoadingView()
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _gifs.isEmpty
                  ? const Center(child: Text('No GIFs found. Try another word.'))
                  : GridView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (context, i) {
                        final gif = _gifs[i];
                        return Semantics(
                          button: true,
                          label: gif.title.isEmpty ? 'GIF' : gif.title,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context, gif),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: gif.url,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                                errorWidget: (_, _, _) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // GIPHY's terms require this credit wherever their GIFs are offered.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Powered by GIPHY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
