import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/settings_models.dart';

class SettingsRepository {
  SettingsRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<PrivacySettings> fetchPrivacy() async =>
      PrivacySettings.fromJson(await _client.from('privacy_settings').select().eq('user_id', _uid).single());

  Future<void> savePrivacy(PrivacySettings s) =>
      _client.from('privacy_settings').update(s.toJson()).eq('user_id', _uid);

  Future<NotificationPreferences> fetchNotifications() async => NotificationPreferences.fromJson(
      await _client.from('notification_preferences').select().eq('user_id', _uid).single());

  Future<void> saveNotifications(NotificationPreferences p) =>
      _client.from('notification_preferences').update(p.toJson()).eq('user_id', _uid);

  /// Permanently deletes the account, photos and all personal data.
  /// Runs in the `delete-account` Edge Function because it needs the
  /// service-role key, which must never be in the app.
  Future<void> deleteAccount() async {
    final res = await _client.functions.invoke('delete-account', method: HttpMethod.post);
    if (res.status != 200) {
      throw FunctionException(status: res.status, details: res.data);
    }
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseClientProvider)),
);
