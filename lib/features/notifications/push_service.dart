import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/router/app_router.dart';
import '../../core/supabase/supabase_providers.dart';
import '../chat/application/chat_controllers.dart';
import '../profile/application/profile_providers.dart';
import 'notification_center.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Notifications with a `notification` payload are shown by the OS; nothing to do.
}

/// Firebase Cloud Messaging (Android) / APNs via FCM (iOS).
///
/// Push stays disabled unless the FIREBASE_* values are present in `.env`, so
/// the app runs fine without Firebase. Messages are sent by the `push-notify`
/// Supabase Edge Function.
class PushService {
  PushService(this._client);
  final SupabaseClient _client;

  static bool _firebaseReady = false;
  static bool get isEnabled => _firebaseReady;

  StreamSubscription<String>? _tokenSub;
  bool _listenersAttached = false;

  static FirebaseOptions? _options() {
    if (kIsWeb || Env.firebaseProjectId.isEmpty || Env.firebaseMessagingSenderId.isEmpty) return null;
    if (Platform.isAndroid && Env.firebaseAndroidApiKey.isNotEmpty && Env.firebaseAndroidAppId.isNotEmpty) {
      return FirebaseOptions(
        apiKey: Env.firebaseAndroidApiKey,
        appId: Env.firebaseAndroidAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
      );
    }
    if (Platform.isIOS && Env.firebaseIosApiKey.isNotEmpty && Env.firebaseIosAppId.isNotEmpty) {
      return FirebaseOptions(
        apiKey: Env.firebaseIosApiKey,
        appId: Env.firebaseIosAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
        iosBundleId: Env.firebaseIosBundleId,
      );
    }
    return null;
  }

  static Future<void> initializeFirebase() async {
    final options = _options();
    if (options == null) {
      debugPrint('Push notifications disabled: Firebase is not configured in .env');
      return;
    }
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase initialisation failed, push disabled: $e');
    }
  }

  /// Shows the system notification prompt (from the permissions screen or
  /// Settings). Returns true if notifications are allowed.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (_firebaseReady) {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final ok =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (ok) await registerForCurrentUser();
      return ok;
    }
    final status = await Permission.notification.request();
    return status.isGranted || status.isProvisional;
  }

  Future<bool> get isAllowed async {
    if (kIsWeb) return false;
    final status = await Permission.notification.status;
    return status.isGranted || status.isProvisional;
  }

  /// Registers this device for pushes if the user already allowed them.
  /// Never prompts: asking happens once, on the permissions screen.
  Future<void> registerForCurrentUser() async {
    if (!_firebaseReady || _client.auth.currentUser == null) return;
    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await messaging.getToken();
      if (token != null) await _register(token);
      _tokenSub ??= messaging.onTokenRefresh.listen(_register);
      _attachListeners();
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _register(String token) => _client.rpc(
    'register_device_token',
    params: {'p_token': token, 'p_platform': Platform.isIOS ? 'ios' : 'android'},
  );

  /// Call before signing out so this device stops receiving the user's pushes.
  Future<void> unregister() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _client.rpc('unregister_device_token', params: {'p_token': token});
      await _tokenSub?.cancel();
      _tokenSub = null;
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    // Foreground: matches and messages arrive through the inbox, which shows
    // its own top banner; everything else is announced here.
    FirebaseMessaging.onMessage.listen((message) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      final container = ProviderScope.containerOf(navContext, listen: false);
      final type = message.data['type'];
      if (type == 'message' || type == 'match') {
        container.read(inboxProvider.notifier).refresh();
        return;
      }
      if (type == 'age_check' || type == 'verification') {
        container.read(myProfileProvider.notifier).refresh();
        return;
      }
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null && body == null) return;
      container
          .read(notificationCenterProvider.notifier)
          .add(
            ActivityItem(
              id: message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
              type: type == 'like' ? ActivityType.like : ActivityType.system,
              title: title ?? 'Woops',
              body: body ?? '',
              at: DateTime.now(),
              route: type == 'like' ? Routes.likes : null,
            ),
          );
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _open(m);
    });
  }

  void _open(RemoteMessage message) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final router = ProviderScope.containerOf(context, listen: false).read(routerProvider);
    final conversationId = message.data['conversation_id'] as String?;
    switch (message.data['type']) {
      case 'message' when conversationId != null:
        router.push(Routes.chat(conversationId));
      case 'match':
        router.go(Routes.matches);
      case 'like':
        router.go(Routes.likes);
      case 'age_check':
        router.push(Routes.ageCheck);
      case 'verification':
        router.push(Routes.verify);
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(supabaseClientProvider)));
