import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends uncaught errors to the `app_errors` table so they show up (grouped)
/// in the admin panel. Size- and rate-limited on the server; never sends
/// message contents or other personal data, only the error and stack trace.
class ErrorReporter {
  ErrorReporter._();

  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static final _recent = <String, DateTime>{};

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      // The full report names the widget and file that caused layout errors
      // ("The relevant error-causing widget was: Column  lib/…:120"), which
      // the one-line message doesn't.
      final full = details.toString();
      report(
        details.exception,
        details.stack,
        context: {'library': details.library ?? '', 'details': full.length > 1500 ? full.substring(0, 1500) : full},
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static Future<void> report(Object error, StackTrace? stack, {Map<String, Object?> context = const {}}) async {
    if (kDebugMode) debugPrint('Reported error: $error');
    final message = error.toString();
    // Don't send the same error more than once a minute from one device.
    final last = _recent[message];
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) return;
    _recent[message] = DateTime.now();
    try {
      await Supabase.instance.client.rpc(
        'log_client_error',
        params: {
          'p_message': message.length > 2000 ? message.substring(0, 2000) : message,
          'p_stack': stack?.toString(),
          'p_context': context,
          'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'p_app_version': appVersion,
        },
      );
    } catch (_) {
      // Never let error reporting crash the app.
    }
  }
}
