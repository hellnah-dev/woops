import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../settings/domain/settings_models.dart';

enum ReportReason {
  inappropriatePhotos('inappropriate_photos', 'Inappropriate photos'),
  harassment('harassment', 'Harassment or hateful behaviour'),
  spam('spam', 'Spam or advertising'),
  scam('scam', 'Scam or asking for money'),
  impersonation('impersonation', 'Fake profile / impersonation'),
  underage('underage', 'May be under 18'),
  other('other', 'Something else');

  const ReportReason(this.value, this.label);
  final String value;
  final String label;
}

class SafetyRepository {
  SafetyRepository(this._client);
  final SupabaseClient _client;

  Future<void> block(String userId) => _client.rpc('block_user', params: {'p_target': userId});

  Future<void> unblock(String userId) => _client.rpc('unblock_user', params: {'p_target': userId});

  Future<void> report(String userId, ReportReason reason, {String? details, String? messageId}) => _client.rpc(
    'report_user',
    params: {'p_target': userId, 'p_reason': reason.value, 'p_details': details, 'p_message_id': messageId},
  );

  Future<List<BlockedUser>> blockedUsers() async {
    final rows = await _client.rpc('get_blocked_users') as List;
    return rows.map((r) => BlockedUser.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }
}

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(ref.watch(supabaseClientProvider)),
);
