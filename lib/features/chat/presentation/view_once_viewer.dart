import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../domain/chat_models.dart';

/// Blocks screenshots/screen recording on Android while view-once media is open.
class SecureScreen {
  SecureScreen._();
  static const _channel = MethodChannel('woops/secure_screen');

  static Future<void> set(bool on) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(on ? 'enable' : 'disable');
    } catch (_) {}
  }
}

/// Opens a chat photo or video at [path] full screen. For view-once media,
/// [onViewed] runs when it closes (the app then deletes the file), but only
/// if it was actually shown: a photo or video that couldn't be opened is
/// kept. Photos from before view-once can be opened again.
Future<void> openViewOnce(
  BuildContext context,
  ChatMessage message, {
  required String path,
  required Future<void> Function() onViewed,
}) async {
  if (!context.mounted) return;
  final once = message.viewOnce;
  final shown = ValueNotifier(false);
  if (once) await SecureScreen.set(true);
  try {
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            _ViewOnceScreen(path: path, isVideo: message.kind == MessageKind.video, once: once, shown: shown),
      ),
    );
  } finally {
    if (once) await SecureScreen.set(false);
    if (once && shown.value) await onViewed();
    shown.dispose();
  }
}

class _ViewOnceScreen extends StatefulWidget {
  const _ViewOnceScreen({required this.path, required this.isVideo, required this.once, required this.shown});
  final String path;
  final bool isVideo;
  final bool once;

  /// Set once the photo or video is actually on screen.
  final ValueNotifier<bool> shown;

  @override
  State<_ViewOnceScreen> createState() => _ViewOnceScreenState();
}

class _ViewOnceScreenState extends State<_ViewOnceScreen> {
  VideoPlayerController? _video;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _video = VideoPlayerController.file(File(widget.path))
        ..initialize().then(
          (_) {
            if (!mounted) return;
            setState(() {});
            widget.shown.value = true;
            _video!.play();
          },
          onError: (Object _) {
            if (mounted) setState(() => _failed = true);
          },
        );
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: widget.once
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.looks_one_outlined, size: 20),
                  SizedBox(width: 6),
                  Text('View once', style: TextStyle(fontSize: 16)),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _failed
                    ? const _CantOpen()
                    : !widget.isVideo
                    ? InteractiveViewer(
                        maxScale: 5,
                        child: Image.file(
                          File(widget.path),
                          errorBuilder: (_, _, _) => const _CantOpen(),
                          frameBuilder: (context, child, frame, _) {
                            if (frame != null) widget.shown.value = true;
                            return child;
                          },
                        ),
                      )
                    : (v == null || !v.value.isInitialized)
                    ? const CircularProgressIndicator(color: Colors.white)
                    : GestureDetector(
                        onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                        child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
                      ),
              ),
            ),
            if (v != null && v.value.isInitialized)
              VideoProgressIndicator(v, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 16)),
            if (widget.once)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This disappears when you close it. Our servers only held it encrypted until it reached you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CantOpen extends StatelessWidget {
  const _CantOpen();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text(
      'This couldn’t be opened on this phone. Ask them to send it again.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white, fontSize: 16),
    ),
  );
}
