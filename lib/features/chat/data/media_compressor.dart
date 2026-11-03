import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/utils/app_exception.dart';
import '../../../core/utils/image_processing.dart';

/// Biggest single photo or video after compression (also the server's limit).
const maxChatMediaBytes = 5 * 1024 * 1024;

/// Shrinks chat media on the phone before it is encrypted and sent.
abstract class MediaCompressor {
  /// ≤1280 px, ≤~350 KB, hidden metadata (incl. GPS) removed.
  Future<Uint8List> image(Uint8List original);

  /// Re-encoded to medium quality (~640×480), typically 5–10× smaller.
  Future<Uint8List> video(String path);
}

class DeviceMediaCompressor implements MediaCompressor {
  DeviceMediaCompressor({ImageProcessor? images}) : _images = images ?? ImageProcessor();
  final ImageProcessor _images;

  @override
  Future<Uint8List> image(Uint8List original) async {
    final out = (await _images.processProfilePhoto(original)).full;
    return _checked(out, 'photo');
  }

  @override
  Future<Uint8List> video(String path) async {
    try {
      final info = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.MediumQuality,
        includeAudio: true,
        deleteOrigin: false,
        frameRate: 30,
      );
      final file = info?.file;
      if (file == null) throw const AppException('This video couldn’t be prepared. Try a shorter one.');
      final bytes = await file.readAsBytes();
      await file.delete().catchError((_) => File(''));
      return _checked(bytes, 'video');
    } finally {
      await VideoCompress.deleteAllCache();
    }
  }

  Uint8List _checked(Uint8List bytes, String what) {
    if (bytes.lengthInBytes > maxChatMediaBytes) {
      throw AppException(
        what == 'video'
            ? 'This video is still ${formatMb(bytes.lengthInBytes)} after compressing. Please send a shorter clip (about 30 seconds).'
            : 'This photo is too large to send.',
        code: 'media_too_large',
      );
    }
    return bytes;
  }
}

final mediaCompressorProvider = Provider<MediaCompressor>((ref) => DeviceMediaCompressor());
