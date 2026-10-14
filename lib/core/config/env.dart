/// Build-time configuration.
///
/// Values come from `--dart-define-from-file=.env` (see `.env.example`).
/// Only PUBLIC values belong here: the Supabase publishable key is designed to be
/// shipped in apps and is protected by Row Level Security. Never put the
/// service-role key or any other secret in this file or in `.env`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The public "publishable" key (Settings → API Keys). A legacy `anon` key also works.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// Deep link used by email confirmation, password reset and OAuth sign-in.
  /// Must also be added to Supabase → Authentication → URL Configuration.
  static const authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'com.woops.app://login-callback',
  );

  static const enableGoogleSignIn = bool.fromEnvironment('ENABLE_GOOGLE_SIGN_IN');
  static const enableAppleSignIn = bool.fromEnvironment('ENABLE_APPLE_SIGN_IN');

  // Firebase (push notifications). Leave empty to disable push.
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseAndroidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const firebaseAndroidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const firebaseIosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseIosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'com.woops.app');

  // Legal / support links shown in the app.
  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: 'https://example.com/terms');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://example.com/privacy');
  static const guidelinesUrl = String.fromEnvironment('GUIDELINES_URL', defaultValue: 'https://example.com/guidelines');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@example.com');

  static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
