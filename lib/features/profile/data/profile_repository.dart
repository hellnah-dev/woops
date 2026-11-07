import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/image_processing.dart';
import '../domain/profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._client, {ImageProcessor? images}) : _images = images ?? ImageProcessor();
  final SupabaseClient _client;
  final ImageProcessor _images;

  static const photoBucket = 'profile-photos';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Not signed in');
    return id;
  }

  /// The signed-in user's profile, or null if they haven't created one yet.
  Future<MyProfile?> fetchMyProfile() async {
    final row = await _client
        .from('profiles')
        .select(
          '*, profile_photos(id, storage_path, position), profile_interests(interest_id), '
          'profile_prompts(id, prompt, answer, position), '
          'age_verifications(status, reject_reason, created_at), '
          'verification_requests(status, reject_reason, created_at)',
        )
        .eq('id', _uid)
        .maybeSingle();
    return row == null ? null : MyProfile.fromJson(row);
  }

  Future<void> createProfile(ProfileDraft draft) async {
    final uid = _uid;
    // Plain insert (not upsert): birthdate is intentionally not updatable.
    await _client.from('profiles').insert({
      'id': uid,
      'display_name': draft.displayName.trim(),
      'birthdate': DateFormat('yyyy-MM-dd').format(draft.birthdate),
      'gender': draft.gender.value,
      'intention': draft.intention.value,
      'country_code': draft.countryCode,
      'username': draft.username.trim().toLowerCase(),
      if ((draft.city ?? '').trim().isNotEmpty) 'city': draft.city!.trim(),
    });
    await _client
        .from('discovery_preferences')
        .update({'genders': draft.interestedIn.map((g) => g.value).toList()})
        .eq('user_id', uid);
    await setInterests(draft.interestIds);
  }

  Future<void> updateProfile(Map<String, dynamic> fields) => _client.from('profiles').update(fields).eq('id', _uid);

  Future<void> setInterests(Set<int> ids) => _client.rpc('set_my_interests', params: {'p_interest_ids': ids.toList()});

  Future<List<Interest>> fetchInterests() async {
    final rows = await _client.from('interests').select().order('category').order('name');
    return rows.map(Interest.fromJson).toList();
  }

  /// Replaces all prompts with [prompts] (max 3).
  Future<void> savePrompts(List<ProfilePrompt> prompts) async {
    final uid = _uid;
    await _client.from('profile_prompts').delete().eq('user_id', uid);
    if (prompts.isEmpty) return;
    await _client.from('profile_prompts').insert([
      for (var i = 0; i < prompts.length && i < 3; i++)
        {'user_id': uid, 'prompt': prompts[i].prompt, 'answer': prompts[i].answer.trim(), 'position': i},
    ]);
  }

  /// Compresses (WebP, ≤1280 px, ≤350 KB, metadata stripped), uploads the
  /// photo and a 400 px thumbnail, then records it.
  Future<void> uploadPhoto(XFile file, {required int position}) async {
    final uid = _uid;
    final processed = await _images.processProfilePhoto(await file.readAsBytes());
    // 3 MB of media per person in total (profile and moment photos on the server).
    final usage = await mediaUsage();
    final adding = processed.full.lengthInBytes + (processed.thumbnail?.lengthInBytes ?? 0);
    if (usage.used + adding > usage.limit) {
      throw AppException(
        'You’ve used ${formatMb(usage.used)} of your ${formatMb(usage.limit)} media space. '
        'Remove a photo to add a new one.',
        code: 'media_quota',
      );
    }
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.${processed.format.extension}';
    final bucket = _client.storage.from(photoBucket);
    final options = FileOptions(contentType: processed.format.contentType, upsert: false);

    await bucket.uploadBinary(path, processed.full, fileOptions: options);
    if (processed.thumbnail != null) {
      try {
        await bucket.uploadBinary(thumbnailPathFor(path), processed.thumbnail!, fileOptions: options);
      } catch (_) {
        // Not fatal: the app falls back to the full image when a thumbnail is missing.
      }
    }
    try {
      await _client.from('profile_photos').insert({'user_id': uid, 'storage_path': path, 'position': position});
    } catch (_) {
      // Keep storage and database consistent if the row could not be written.
      await bucket.remove([path, thumbnailPathFor(path)]);
      rethrow;
    }
  }

  /// Bytes of my media on the server and the 3 MB allowance.
  Future<({int used, int limit})> mediaUsage() async {
    try {
      final j = Map<String, dynamic>.from(await _client.rpc('get_my_media_usage') as Map);
      return (used: (j['used_bytes'] as num).toInt(), limit: (j['limit_bytes'] as num).toInt());
    } on PostgrestException catch (e) {
      // Database not updated yet: don't block uploads (storage still caps each file).
      if (e.code == 'PGRST202') return (used: 0, limit: 5 * 1024 * 1024);
      rethrow;
    }
  }

  /// Uploads a verification selfie (only admins can view it) and opens a request.
  Future<void> requestVerification(XFile selfie) async {
    final uid = _uid;
    final bytes = await _images.processSelfie(await selfie.readAsBytes());
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage
        .from('verification-selfies')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    await _client.rpc('request_verification', params: {'p_selfie_path': path});
  }

  Future<int> minAgeForCountry(String? countryCode) async {
    if (countryCode == null) return 18;
    return (await _client.rpc('min_age_for_country', params: {'p_country': countryCode}) as num).toInt();
  }

  /// Latest verification request status: null, 'pending', 'approved' or 'rejected'.
  Future<({String status, String? reason})?> latestVerification() async {
    final row = await _client
        .from('verification_requests')
        .select('status, reject_reason')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : (status: row['status'] as String, reason: row['reject_reason'] as String?);
  }

  Future<void> deletePhoto(ProfilePhotoRecord photo) async {
    await _client.from('profile_photos').delete().eq('id', photo.id);
    await _client.storage.from(photoBucket).remove([photo.storagePath, thumbnailPathFor(photo.storagePath)]);
  }

  /// Persists photo order; index in [ordered] becomes the position.
  Future<void> reorderPhotos(List<ProfilePhotoRecord> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].position != i) {
        await _client.from('profile_photos').update({'position': i}).eq('id', ordered[i].id);
      }
    }
  }

  Future<bool> isUsernameAvailable(String username) async =>
      await _client.rpc('is_username_available', params: {'p_username': username.trim()}) as bool;

  Future<void> setLocation({required double lat, required double lng}) =>
      _client.rpc('set_my_location', params: {'p_lat': lat, 'p_lng': lng});

  Future<void> completeOnboarding() => _client.rpc('complete_onboarding');

  Future<void> touchLastActive() => _client.rpc('touch_last_active');

  /// Someone else's profile (only works for matches and people who liked you).
  Future<ProfileCard?> fetchPublicProfile(String userId) async {
    final rows = await _client.rpc('get_public_profile', params: {'p_user': userId}) as List;
    return rows.isEmpty ? null : ProfileCard.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<DiscoveryPreferences> fetchPreferences() async {
    final row = await _client.from('discovery_preferences').select().eq('user_id', _uid).single();
    return DiscoveryPreferences.fromJson(row);
  }

  Future<void> savePreferences(DiscoveryPreferences prefs) =>
      _client.from('discovery_preferences').update(prefs.toJson()).eq('user_id', _uid);
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);
