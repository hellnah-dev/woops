import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_pacer.dart';
import 'ads_config.dart';
import 'ads_service.dart';

/// Small "Sponsored" label so ads are never mistaken for dating profiles.
class _SponsoredLabel extends StatelessWidget {
  const _SponsoredLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Ad', style: theme.textTheme.labelSmall),
          ),
          const SizedBox(width: 6),
          Text('Sponsored', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Adaptive banner. Renders nothing until an ad has loaded, and nothing at
/// all if ads are off, consent wasn't given, or loading fails.
class BannerAdSlot extends ConsumerStatefulWidget {
  const BannerAdSlot({super.key});

  @override
  ConsumerState<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends ConsumerState<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  Future<void> _load(double width) async {
    final unit = AdsConfig.bannerUnitId;
    if (_requested || unit == null) return;
    _requested = true;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
      Orientation.portrait,
      width.truncate(),
    );
    if (size == null || !mounted) return;
    _ad = BannerAd(
      adUnitId: unit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(adsReadyProvider);
    // Banners only from day [AdsConfig.strongAdsFromDay] of use.
    if (!ready || !AdsConfig.bannersEnabled || !ref.watch(adPacerProvider).strongAdsAllowed) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _load(constraints.maxWidth);
        final ad = _ad;
        if (!_loaded || ad == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SponsoredLabel(),
              SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Native ad using Google's built-in template, inside a clearly labelled
/// "Sponsored" card. Collapses to nothing on failure.
class NativeAdCard extends ConsumerStatefulWidget {
  const NativeAdCard({super.key, this.padding = EdgeInsets.zero});

  /// Space around the card, applied only when an ad is shown (no empty gaps).
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends ConsumerState<NativeAdCard> with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;

  /// Keep a loaded ad when it scrolls out of view, instead of rebuilding the
  /// native view and requesting a new ad every time it comes back.
  @override
  bool get wantKeepAlive => _loaded;

  /// While pacing says "not now" (first minute, or the 5-minute limit is
  /// reached), check again every 30 seconds; the ad loads once it's allowed.
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    _recheck = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_ad != null) {
        _recheck?.cancel();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void _load(BuildContext context) {
    final unit = AdsConfig.nativeUnitId;
    if (_ad != null || unit == null || !ref.read(adPacerProvider.notifier).canShow) return;
    _recheck?.cancel();
    final dark = Theme.of(context).brightness == Brightness.dark;
    _ad = NativeAd(
      adUnitId: unit,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: dark ? const Color(0xFF1C1820) : Colors.white,
        cornerRadius: 12,
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
          updateKeepAlive();
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
        onAdImpression: (_) => ref.read(adPacerProvider.notifier).recordImpression(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive bookkeeping
    final ready = ref.watch(adsReadyProvider);
    if (!ready || !AdsConfig.nativeEnabled) return const SizedBox.shrink();
    _load(context);
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SponsoredLabel(),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
              child: AdWidget(ad: _ad!),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads a native ad for the Discover deck (medium template). Completes with
/// null if ads are off, not allowed right now, or the ad fails to load.
Future<NativeAd?> loadDeckAd({required bool dark, required VoidCallback onImpression}) {
  final unit = AdsConfig.nativeUnitId;
  if (!AdsConfig.deckEnabled || unit == null) return Future.value(null);
  final done = Completer<NativeAd?>();
  NativeAd(
    adUnitId: unit,
    request: const AdRequest(),
    nativeTemplateStyle: NativeTemplateStyle(
      templateType: TemplateType.medium,
      mainBackgroundColor: dark ? const Color(0xFF1C1820) : Colors.white,
      cornerRadius: 16,
    ),
    listener: NativeAdListener(
      onAdLoaded: (ad) => done.isCompleted ? null : done.complete(ad as NativeAd),
      onAdFailedToLoad: (ad, _) {
        ad.dispose();
        if (!done.isCompleted) done.complete(null);
      },
      onAdImpression: (_) => onImpression(),
    ),
  ).load();
  return done.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
}

/// A clearly labelled sponsored card shown between profiles. It is dismissed
/// with a button, not by swiping, so swipes never turn into accidental ad clicks.
class DeckAdCard extends StatelessWidget {
  const DeckAdCard({super.key, required this.ad, required this.onContinue});
  final NativeAd ad;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(top: 8), child: _SponsoredLabel()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 320, maxHeight: 420),
                  child: AdWidget(ad: ad),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.tonalIcon(
              key: const Key('deck-ad-continue'),
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue to profiles'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid split into blocks of [every] items with a paced "Sponsored" card
/// between blocks (never after the last one). Pacing decides whether each
/// card actually shows, so a long list never turns into a wall of ads.
List<Widget> adSpacedGrid({
  required int itemCount,
  required SliverGridDelegate gridDelegate,
  required IndexedWidgetBuilder itemBuilder,
  required EdgeInsets padding,
  int every = 8,
}) {
  final slivers = <Widget>[];
  for (var start = 0; start < itemCount; start += every) {
    final count = (itemCount - start).clamp(0, every);
    final first = start == 0, last = start + count >= itemCount;
    slivers.add(
      SliverPadding(
        padding: padding.copyWith(top: first ? padding.top : 0, bottom: last ? padding.bottom : 12),
        sliver: SliverGrid.builder(
          itemCount: count,
          gridDelegate: gridDelegate,
          itemBuilder: (context, i) => itemBuilder(context, start + i),
        ),
      ),
    );
    if (!last) {
      slivers.add(
        SliverToBoxAdapter(
          child: NativeAdCard(
            key: ValueKey('grid-ad-$start'),
            padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 12),
          ),
        ),
      );
    }
  }
  return slivers;
}

/// A standard banner between items in a list (e.g. every few chats), with
/// the "Sponsored" label. Collapses to nothing if no ad loads.
class InlineBannerAd extends ConsumerStatefulWidget {
  const InlineBannerAd({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<InlineBannerAd> createState() => _InlineBannerAdState();
}

class _InlineBannerAdState extends ConsumerState<InlineBannerAd> with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  bool get wantKeepAlive => _loaded;

  void _load() {
    final unit = AdsConfig.bannerUnitId;
    if (_ad != null || unit == null) return;
    _ad = BannerAd(
      adUnitId: unit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
          updateKeepAlive();
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final allowed =
        ref.watch(adsReadyProvider) && AdsConfig.bannersEnabled && ref.watch(adPacerProvider).strongAdsAllowed;
    if (!allowed) return const SizedBox.shrink();
    _load();
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Column(
        children: [
          const _SponsoredLabel(),
          Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}
