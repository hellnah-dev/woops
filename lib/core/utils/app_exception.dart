import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A user-presentable error. Backend functions raise errors as
/// `"<code>: <message>"`; [AppException.from] maps them to friendly text.
class AppException implements Exception {
  const AppException(this.message, {this.code, this.isNetwork = false});

  final String message;
  final String? code;
  final bool isNetwork;

  static const _friendly = <String, String>{
    'not_authenticated': 'Please sign in again.',
    'profile_incomplete': 'Finish setting up your profile first.',
    'profile_missing': 'Finish setting up your profile first.',
    'photo_required': 'Add at least one photo to continue.',
    'photo_limit': 'You can have up to 6 photos.',
    'underage': 'You must be at least 18 to use Woops.',
    'unavailable': 'This profile is no longer available.',
    'rate_limited': "You're going a little fast. Try again later.",
    'nothing_to_undo': 'There is nothing to undo.',
    'cannot_undo_like': 'Likes can’t be undone. Only your last pass can be.',
    'conversation_closed': 'This conversation is no longer available.',
    'not_found': 'We couldn’t find that. It may have been removed.',
    'empty_message': 'Type a message first.',
    'message_too_long': 'That message is too long.',
    'too_many_interests': 'Pick up to 10 interests.',
    'invalid_location': 'We couldn’t read your location.',
    'username_unavailable': 'That username isn’t available.',
    'birthdate_mismatch': 'Your birthday must match the one you entered when signing up.',
    'consent_required': 'Please accept the Terms and Privacy Policy to continue.',
    'banned': 'This account can’t use Woops.',
    'already_pending': 'Your verification is already being reviewed.',
    'already_verified': 'You’re already verified.',
  };

  factory AppException.from(Object error) {
    if (error is AppException) return error;
    if (error is SocketException || error is TimeoutException || error is HttpException) {
      return const AppException('You appear to be offline. Check your connection and try again.', isNetwork: true);
    }
    if (error is AuthException) {
      return AppException(_authMessage(error), code: error.code);
    }
    if (error is PostgrestException) {
      final raw = error.message;
      final sep = raw.indexOf(':');
      final code = sep > 0 ? raw.substring(0, sep).trim() : raw.trim();
      final detail = sep > 0 ? raw.substring(sep + 1).trim() : null;
      if (_friendly.containsKey(code)) {
        // Prefer the server's specific wording when it gives one.
        return AppException(detail?.isNotEmpty == true ? _capitalize(detail!) : _friendly[code]!, code: code);
      }
      if (error.code == '42501') {
        return const AppException('You don’t have permission to do that.', code: 'forbidden');
      }
      return const AppException('Something went wrong. Please try again.');
    }
    if (error is StorageException) {
      return AppException('Upload failed: ${error.message}', code: 'storage');
    }
    if (error is FunctionException) {
      return const AppException('The server couldn’t complete that request. Please try again.');
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException')) {
      return const AppException('You appear to be offline. Check your connection and try again.', isNetwork: true);
    }
    return const AppException('Something went wrong. Please try again.');
  }

  static String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Email or password is incorrect.';
    if (m.contains('email not confirmed')) return 'Please confirm your email first. Check your inbox.';
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (m.contains('password')) return _capitalize(e.message);
    if (m.contains('rate limit')) return 'Too many attempts. Please wait a moment and try again.';
    return _capitalize(e.message);
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  String toString() => message;
}
