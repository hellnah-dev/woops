import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/image_processing.dart';

/// A 24-hour update that only the author's matches can see.
class Moment {
  const Moment({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.createdAt,
    required this.expiresAt,
    required this.isMine,
    this.avatar,
    this.body,
    this.photoPath,
    this.style = 0,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? avatar;
  final String? body;

  /// In the private `moments` bucket.
  final String? photoPath;

  /// Background of a text-only moment (see [momentStyles]).
  final int style;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isMine;

  bool get hasPhoto => photoPath != null;

  factory Moment.fromJson(Map<String, dynamic> j) => Moment(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    displayName: j['display_name'] as String? ?? '',
    avatar: j['avatar'] as String?,
    body: j['body'] as String?,
    photoPath: j['photo_path'] as String?,
    style: (j['style'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(j['created_at'] as String),
    expiresAt: DateTime.parse(j['expires_at'] as String),
    isMine: j['is_mine'] == true,
  );
}

class MomentsRepository {
  MomentsRepository(this._client, {ImageProcessor? images}) : _images = images ?? ImageProcessor();
  final SupabaseClient _client;
  final ImageProcessor _images;

  static const bucket = 'moments';

  Future<List<Moment>> fetch() async {
    final rows = await _client.rpc('get_moments') as List;
    return [for (final r in rows) Moment.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// Removes my expired moments and their photos (frees media space).
  Future<void> cleanUpExpired() async {
    final paths = (await _client.rpc('claim_my_expired_moments') as List).cast<String>();
    if (paths.isNotEmpty) await _client.storage.from(bucket).remove(paths);
  }

  Future<void> postText(String text, {int style = 0}) =>
      _client.rpc('post_moment', params: {'p_body': text.trim(), 'p_style': style});

  /// Compresses and uploads the photo, then posts it (with an optional caption).
  Future<void> postPhoto(Uint8List original, {String? caption}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppException('Please sign in again.', code: 'not_authenticated');
    final processed = await _images.processProfilePhoto(original);
    final usage = Map<String, dynamic>.from(await _client.rpc('get_my_media_usage') as Map);
    final used = (usage['used_bytes'] as num).toInt(), limit = (usage['limit_bytes'] as num).toInt();
    if (used + processed.full.lengthInBytes > limit) {
      throw AppException(
        'You’ve used ${formatMb(used)} of your ${formatMb(limit)} media space. '
        'Delete a moment or a photo to add a new one.',
        code: 'media_quota',
      );
    }
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.${processed.format.extension}';
    final storage = _client.storage.from(bucket);
    await storage.uploadBinary(
      path,
      processed.full,
      fileOptions: FileOptions(contentType: processed.format.contentType, upsert: false),
    );
    try {
      final text = caption?.trim();
      await _client.rpc(
        'post_moment',
        params: {'p_body': (text == null || text.isEmpty) ? null : text, 'p_photo_path': path},
      );
    } catch (_) {
      await storage.remove([path]).catchError((_) => const <FileObject>[]);
      rethrow;
    }
  }

  Future<void> delete(Moment m) async {
    final path = await _client.rpc('delete_moment', params: {'p_id': m.id}) as String?;
    if (path != null) await _client.storage.from(bucket).remove([path]).catchError((_) => const <FileObject>[]);
  }
}

final momentsRepositoryProvider = Provider<MomentsRepository>(
  (ref) => MomentsRepository(ref.watch(supabaseClientProvider)),
);
