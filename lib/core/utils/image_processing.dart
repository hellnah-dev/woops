import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'app_exception.dart';

enum ImageFormat {
  webp('webp', 'image/webp', CompressFormat.webp),
  jpeg('jpg', 'image/jpeg', CompressFormat.jpeg);

  const ImageFormat(this.extension, this.contentType, this.compressFormat);
  final String extension;
  final String contentType;
  final CompressFormat compressFormat;
}

/// Re-encodes [input] so its shorter side is at most [size] px.
typedef ImageEncoder =
    Future<Uint8List> Function(Uint8List input, {required int size, required int quality, required ImageFormat format});

class ProcessedPhoto {
  const ProcessedPhoto({required this.full, required this.format, this.thumbnail});
  final Uint8List full;
  final Uint8List? thumbnail;
  final ImageFormat format;
}

/// Compresses photos before upload:
///  * WebP (≈25–35% smaller than JPEG at the same quality), JPEG fallback
///  * full image: shorter side ≤ 1280 px, quality stepped down until ≤ 350 KB
///  * thumbnail: shorter side ≤ 400 px (used in grids/avatars to save data)
///  * metadata (EXIF, including GPS location) is always removed by re-encoding
///
/// If an image can't be re-encoded it is rejected instead of being uploaded
/// as-is, so hidden location data never leaves the phone.
class ImageProcessor {
  ImageProcessor({ImageEncoder? encoder, this.isWeb = kIsWeb}) : _encode = encoder ?? _nativeEncode;

  static const fullSize = 1280;
  static const thumbSize = 400;
  static const maxFullBytes = 350 * 1024;
  static const qualityLadder = [80, 70, 60, 50];

  /// Largest single file picked (before compression); media also has a 3 MB total per person.
  static const maxUploadBytes = 5 * 1024 * 1024;

  /// Rejects files over 5 MB before any work is done.
  static void checkUploadSize(int bytes) {
    if (bytes > maxUploadBytes) {
      throw AppException(
        'This photo is ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB. Please choose one that is 5 MB or smaller.',
        code: 'photo_too_large',
      );
    }
  }

  final ImageEncoder _encode;
  final bool isWeb;

  static Future<Uint8List> _nativeEncode(
    Uint8List input, {
    required int size,
    required int quality,
    required ImageFormat format,
  }) => FlutterImageCompress.compressWithList(
    input,
    minWidth: size,
    minHeight: size,
    quality: quality,
    format: format.compressFormat,
    keepExif: false,
  );

  Future<ProcessedPhoto> processProfilePhoto(Uint8List input) async {
    // On the web the browser's image picker already re-encodes and resizes
    // (see pickImage maxWidth/imageQuality). Web is a testing target only.
    if (isWeb) return ProcessedPhoto(full: input, format: ImageFormat.jpeg);
    for (final format in ImageFormat.values) {
      try {
        Uint8List? best;
        for (final quality in qualityLadder) {
          best = await _encode(input, size: fullSize, quality: quality, format: format);
          if (best.lengthInBytes <= maxFullBytes) break;
        }
        final thumb = await _encode(input, size: thumbSize, quality: 65, format: format);
        if (best!.isEmpty) continue;
        return ProcessedPhoto(full: best, thumbnail: thumb, format: format);
      } catch (_) {
        // Try the next format (WebP isn't available on every device).
      }
    }
    throw const AppException(
      'This photo format isn’t supported. Please choose a JPEG, PNG or HEIC photo.',
      code: 'unsupported_image',
    );
  }

  /// ID documents keep more detail so the date of birth stays readable.
  Future<Uint8List> processDocument(Uint8List input) async {
    if (isWeb) return input;
    try {
      return await _encode(input, size: 1600, quality: 85, format: ImageFormat.jpeg);
    } catch (_) {
      throw const AppException('We couldn’t process that photo. Please try again.', code: 'unsupported_image');
    }
  }

  Future<Uint8List> processSelfie(Uint8List input) async {
    if (isWeb) return input;
    try {
      return await _encode(input, size: 1080, quality: 80, format: ImageFormat.jpeg);
    } catch (_) {
      throw const AppException('We couldn’t process that photo. Please try again.', code: 'unsupported_image');
    }
  }
}

/// `abc/123.jpg` → `abc/123_thumb.jpg`
String thumbnailPathFor(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (dot <= slash) return '${path}_thumb';
  return '${path.substring(0, dot)}_thumb${path.substring(dot)}';
}

/// 1536000 → "1.5 MB".
String formatMb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
