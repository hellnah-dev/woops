# Amora: a modern dating app (Flutter + Supabase)

One Flutter codebase for **Android and iOS** with a secure Supabase backend:
email/Apple/Google sign-in, a profile setup wizard, swipe-to-discover with filters,
mutual matching, real-time chat with read receipts, push notifications,
blocking/reporting and account deletion.

- Architecture, folder structure and database schema: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Your logo goes in `assets/branding/logo.png` (see [assets/branding/README.md](assets/branding/README.md))

---

## 1. What you need installed

| Tool | Why | Check |
|---|---|---|
| Flutter 3.41+ | builds the app | `flutter --version` |
| Android Studio + Android SDK | Android emulator & builds | `flutter doctor` |
| Xcode 16+ and CocoaPods (Mac only) | iOS simulator & builds | `xcodebuild -version`, `pod --version` |
| Supabase CLI | applies the database & deploys functions | `supabase --version` |

Install the Supabase CLI on a Mac with `brew install supabase/tap/supabase`.
Install CocoaPods with `brew install cocoapods`.
Run `flutter doctor` and fix anything marked ✗ before continuing.

## 2. Create and set up Supabase (backend)

1. Create a free project at <https://supabase.com/dashboard>. Note the **project ref** (the `xxxx` in `https://xxxx.supabase.co`).
2. In a terminal, from this folder:
   ```bash
   supabase login                         # opens the browser to log in
   supabase link --project-ref YOUR_REF   # connects this folder to your project
   supabase db push                       # creates tables, security rules, functions & the interest list
   ```
   `db push` runs the files in `supabase/migrations/` in order. Do not edit old migrations; add new ones instead.
3. **Auth settings** (Dashboard → Authentication):
   - *URL Configuration* → add `com.amora.amora://login-callback` to **Redirect URLs**.
   - *Providers → Email*: keep "Confirm email" ON for production. For quick local testing you can turn it off.
   - Optional: enable **Google** and/or **Apple** providers (follow Supabase's guide for each), then set `ENABLE_GOOGLE_SIGN_IN=true` / `ENABLE_APPLE_SIGN_IN=true` in `.env`.
4. Deploy the server functions:
   ```bash
   supabase functions deploy delete-account
   supabase functions deploy push-notify --no-verify-jwt
   ```

## 3. Configure the app

```bash
cp .env.example .env
```
Open `.env` and set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, both from Dashboard → Project Settings → API Keys.
The publishable key is safe to ship in an app. **Never** put the `service_role`/secret key in `.env` or anywhere in the Flutter code.
`.env` is git-ignored.

## 4. Run it

```bash
flutter pub get
```

**Android emulator:** open Android Studio → Device Manager → create a Pixel device, start it, then:
```bash
flutter run --dart-define-from-file=.env
```

**iOS simulator (Mac with Xcode):**
```bash
open -a Simulator
cd ios && pod install && cd ..
flutter run --dart-define-from-file=.env
```

If you forget `--dart-define-from-file=.env`, the app shows a "Configuration missing" screen telling you what to do.

**Try it with two accounts:** run the app on two emulators (or emulator + phone), create two profiles that match each other's preferences, like each other, and chat.

## 5. Push notifications (optional)

1. Create a Firebase project, then add an **Android app** (`com.amora.amora`) and an **iOS app** (`com.amora.amora`).
2. Copy the app IDs/API keys into the `FIREBASE_*` values in `.env`. No `google-services.json` is needed.
3. iOS: in Firebase → Project settings → Cloud Messaging, upload an **APNs auth key** (Apple Developer → Keys). In Xcode → Runner → Signing & Capabilities, add **Push Notifications** and **Background Modes → Remote notifications**.
4. Firebase → Project settings → Service accounts → *Generate new private key*. Then:
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat path/to/service-account.json)"
   supabase secrets set PUSH_WEBHOOK_SECRET="$(openssl rand -hex 24)"
   ```
5. Dashboard → Database → Webhooks → create three webhooks, each one *HTTP POST* to
   `https://YOUR_REF.supabase.co/functions/v1/push-notify` with header
   `x-webhook-secret: <same secret>`:
   - table `messages`, event **Insert**
   - table `matches`, event **Insert**
   - table `swipes`, event **Insert**

Without these steps the app works normally, just without push.

## 6. Tests

```bash
flutter analyze                     # static checks
flutter test                        # 39 unit + widget tests (no backend needed)
```

**Backend security tests** run all migrations against a throwaway local Postgres. They act as five different users and check 71 rules, for example: no forged likes, outsiders can't read chats, blocks hide everything, and reporters stay anonymous.
```bash
brew install postgresql@17 && brew services start postgresql@17
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
./supabase/tests/local/run.sh
```

**On-device end-to-end test**, using a dev Supabase project with email confirmation off:
```bash
flutter test integration_test --dart-define-from-file=.env
```

## 7. Your logo & app icon

- In-app logo: save `assets/branding/logo.png` (square, transparent, ≥512 px). No code changes needed.
- Home-screen icon: replace the images in `android/app/src/main/res/mipmap-*` and
  `ios/Runner/Assets.xcassets/AppIcon.appiconset`, or generate them all with the
  [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) package
  (`image_path: assets/branding/logo.png`).

## 8. Release builds

Before your first release:
- Change the app id `com.amora.amora` to your own: `applicationId` in `android/app/build.gradle.kts`, the bundle id in Xcode, and the URL scheme in `AndroidManifest.xml`, `Info.plist` and `AUTH_REDIRECT_URL`.
- Point `TERMS_URL`, `PRIVACY_URL`, `GUIDELINES_URL` and `SUPPORT_EMAIL` at real pages. The app stores require a privacy policy.
- Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) for every store upload.

### Google Play
```bash
keytool -genkey -v -keystore ~/amora-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Create `android/key.properties` (git-ignored):
```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/Users/you/amora-upload.jks
```
Then:
```bash
flutter build appbundle --release --dart-define-from-file=.env
```
Upload `build/app/outputs/bundle/release/app-release.aab` in Play Console → your app → Testing → Internal testing.
Fill in the Data safety form (location, photos, messages, account deletion) and the content rating, and declare that the app is for adults (18+).

### Apple App Store
1. Join the Apple Developer Program. In Xcode, open `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → choose your Team.
2. Create the app in App Store Connect with the same bundle id.
3. Run:
   ```bash
   flutter build ipa --release --dart-define-from-file=.env
   ```
   Then upload `build/ios/ipa/*.ipa` with the **Transporter** app (or Xcode → Organizer).
4. App Review needs: a demo account, in-app account deletion (included: Settings → Delete account), reporting and blocking (included), and Sign in with Apple if you offer Google sign-in.

## 9. Services & status

| Service | Status |
|---|---|
| Supabase Auth (email) | ✅ implemented; needs your project |
| Apple / Google sign-in | ✅ implemented via Supabase OAuth; enable providers + flags in `.env` |
| Database, RLS, matching, chat | ✅ implemented; 71 security checks pass locally |
| Photo storage | ✅ private bucket, compressed uploads (≤1440 px JPEG) |
| Realtime chat & read receipts | ✅ implemented; needs your project |
| Push notifications (FCM/APNs) | ✅ code complete; **needs Firebase credentials + webhooks** (untested end-to-end) |
| Account deletion | ✅ Edge Function; needs deploying |
| Premium / RevenueCat | ⏳ **not implemented.** The server-side entitlement check exists (premium lifts the daily like limit), but there is no purchase flow or RevenueCat webhook yet |

### Known limitations
- The iOS build has not been compiled on the development machine (Xcode wasn't installed there). Run `pod install` and build on a Mac with Xcode.
- Edge Functions were not type-checked with Deno locally. Deploy them and check the function logs in the dashboard.
- Image messages: the schema supports them (`kind`, `media_path`), but the app sends text only.
- There is no admin moderation dashboard yet. Review the `reports` table in the Supabase Table Editor and set `profiles.status` to `suspended`/`banned` to take action.
- "Who liked you" is free for everyone in this MVP.
