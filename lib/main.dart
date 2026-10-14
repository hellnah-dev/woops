import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/error_reporter.dart';
import 'features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isSupabaseConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  // Dates and numbers use the phone's language/region (e.g. 14/10/2026 vs 10/14/2026).
  await initializeDateFormatting();
  final locale = WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag().replaceAll('-', '_');
  Intl.defaultLocale = Intl.verifiedLocale(locale, DateFormat.localeExists, onFailure: (_) => 'en');

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  ErrorReporter.install();
  await PushService.initializeFirebase();

  runApp(const ProviderScope(child: WoopsApp()));
}

/// Shown when the app is started without `--dart-define-from-file=.env`.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 48),
                const SizedBox(height: 16),
                Text('Configuration missing', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY were not provided.\n\n'
                  '1. Copy .env.example to .env and fill in your Supabase values.\n'
                  '2. Run: flutter run --dart-define-from-file=.env',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
