import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woops/core/i18n/countries.dart';
import 'package:woops/core/i18n/units.dart';
import 'package:woops/core/utils/app_exception.dart';
import 'package:woops/core/utils/image_processing.dart';
import 'package:woops/core/utils/validators.dart';

void main() {
  group('countries', () {
    test('list is complete, unique and valid ISO codes', () {
      expect(allCountries.length, greaterThan(240));
      final codes = allCountries.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes.every(RegExp(r'^[A-Z]{2}$').hasMatch), isTrue);
    });

    test('flags are built from the code', () {
      expect(countryByCode('np')!.flag, '🇳🇵');
      expect(countryByCode('US')!.name, 'United States');
      expect(countryByCode('ZZ'), isNull);
    });
  });

  group('distance units', () {
    test('km for most regions, miles for US/GB/LR/MM', () {
      expect(DistanceUnits.away(5, regionCode: 'NP'), '5 km away');
      expect(DistanceUnits.away(5, regionCode: 'US'), '4 mi away');
      expect(DistanceUnits.away(1, regionCode: 'GB'), 'Less than 2 mi away');
      expect(DistanceUnits.away(2, regionCode: 'NP'), 'Less than 2 km away');
      expect(DistanceUnits.away(3, regionCode: 'NP'), '3 km away');
    });

    test('limit labels include Anywhere', () {
      expect(DistanceUnits.limit(50, regionCode: 'IN'), '50 km');
      expect(DistanceUnits.limit(DistanceUnits.anywhereKm, regionCode: 'IN'), 'Anywhere');
    });
  });

  group('image processing', () {
    test('thumbnail paths', () {
      expect(thumbnailPathFor('u/123.webp'), 'u/123_thumb.webp');
      expect(thumbnailPathFor('u/123.jpg'), 'u/123_thumb.jpg');
      expect(thumbnailPathFor('u.v/123'), 'u.v/123_thumb');
    });

    test('steps quality down until the file is small enough, prefers WebP', () async {
      final calls = <(int, int, ImageFormat)>[];
      final processor = ImageProcessor(
        isWeb: false,
        encoder: (input, {required size, required quality, required format}) async {
          calls.add((size, quality, format));
          // Pretend quality 60 is the first that fits the limit.
          final bytes = size == ImageProcessor.thumbSize ? 20000 : (quality > 60 ? 500 * 1024 : 300 * 1024);
          return Uint8List(bytes);
        },
      );
      final out = await processor.processProfilePhoto(Uint8List(10));
      expect(out.format, ImageFormat.webp);
      expect(out.full.lengthInBytes, lessThanOrEqualTo(ImageProcessor.maxFullBytes));
      expect(out.thumbnail!.lengthInBytes, 20000);
      expect(calls.where((c) => c.$1 == ImageProcessor.fullSize).map((c) => c.$2), [80, 70, 60]);
    });

    test('falls back to JPEG when WebP encoding fails', () async {
      final processor = ImageProcessor(
        isWeb: false,
        encoder: (input, {required size, required quality, required format}) async {
          if (format == ImageFormat.webp) throw UnsupportedError('no webp');
          return Uint8List(1000);
        },
      );
      expect((await processor.processProfilePhoto(Uint8List(10))).format, ImageFormat.jpeg);
    });

    test('never uploads an unprocessed original (metadata could leak)', () async {
      final processor = ImageProcessor(
        isWeb: false,
        encoder: (input, {required size, required quality, required format}) async => throw Exception('bad'),
      );
      expect(processor.processProfilePhoto(Uint8List(10)), throwsA(isA<AppException>()));
    });
  });

  test('username validator mirrors the database rule', () {
    expect(Validators.username('ab'), isNotNull);
    expect(Validators.username('has space'), isNotNull);
    expect(Validators.username('a' * 21), isNotNull);
    expect(Validators.username('asha_k.99'), isNull);
  });

  test('names in any script are accepted', () {
    expect(Validators.displayName('आशा'), isNull);
    expect(Validators.displayName('محمد'), isNull);
    expect(Validators.displayName('美咲'), isNull);
  });
}
