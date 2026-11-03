import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/intro/intro_overlay.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class WoopsApp extends ConsumerWidget {
  const WoopsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Woops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) => IntroOverlay(child: child ?? const SizedBox.shrink()),
      // System widgets (date pickers, dialogs, text selection) follow the
      // phone's language, and right-to-left languages mirror the layout.
      // App text is English for now; see README "Translations".
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: kMaterialSupportedLanguages.map(Locale.new),
    );
  }
}
