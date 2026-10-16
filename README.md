# Woops: a modern dating app (Flutter + Supabase)

One Flutter codebase for **Android and iOS**, plus a web **admin panel**, on a secure Supabase backend.

- Sign up with email, Apple or Google. An age gate checks date of birth and country (18+, higher where the law requires).
- Profiles: photos (WebP-compressed, location data stripped), @username, interests, prompts, country, and selfie verification with a blue badge.
- Swipe to discover, with filters for age, distance ("Anywhere"), country, intentions and interests. Undo your last pass.
- Mutual matching, real-time chat with read receipts, push notifications.
- Safety: block, report, unmatch, privacy controls, account deletion, and a hashed ban list that stops re-sign-up.
- Works worldwide: about 250 countries, km or miles by region, local date formats, right-to-left languages.
- Google AdMob (banner, native and rewarded) with GDPR consent and Apple tracking consent.
- **Admin panel** (`admin/`): dashboard, reports, verifications, users, photo review, app errors, age rules, audit log, live alerts.

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Your logo goes in `assets/branding/logo.png` ([how](assets/branding/README.md)).

---

## 1. Install the tools

| Tool | Why | Check |
|---|---|---|
| Flutter 3.41+ | builds the app | `flutter --version` |
| Android Studio + SDK | Android emulator & builds | `flutter doctor` |
| Xcode 16+ and CocoaPods (Mac) | iOS simulator & builds | `xcodebuild -version`, `pod --version` |
| Supabase CLI | sets up the database & server functions | `supabase --version` |

On a Mac: `brew install supabase/tap/supabase cocoapods`. Then run `flutter doctor` and fix anything marked ✗.

## 2. Set up Supabase (the backend)

1. Create a project at <https://supabase.com/dashboard>. Note the **project ref** (the `xxxx` in `https://xxxx.supabase.co`).
2. From this folder, run:
   ```bash
   supabase login
   supabase link --project-ref YOUR_REF
   supabase db push          # tables, security rules, functions, interests, age rules
   ```
3. Dashboard → **Authentication**:
   - *URL Configuration*: add `com.woops.app://login-callback` to **Redirect URLs**.
   - *Providers → Email*: keep "Confirm email" **on** in production.
   - Optional: enable **Google** / **Apple**, then set `ENABLE_GOOGLE_SIGN_IN=true` / `ENABLE_APPLE_SIGN_IN=true` in `.env`.
4. Deploy the server functions:
   ```bash
   supabase functions deploy delete-account
   supabase functions deploy push-notify --no-verify-jwt
   supabase functions deploy admob-ssv --no-verify-jwt
   supabase functions deploy admin-alerts --no-verify-jwt
   ```
5. Make yourself an admin. In Dashboard → **SQL Editor**, run:
   ```sql
   insert into public.admins (user_id) select id from auth.users where email = 'you@example.com';
   ```
   The account must exist first, so sign up in the app, or create the user under Authentication → Users.

## 3. Configure and run the app

```bash
cp .env.example .env     # then set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (Project Settings → API Keys)
flutter pub get
```
The publishable key is safe to ship in an app. **Never** put the service_role or secret key in `.env`, the app, or the admin panel.

| Where | Command |
|---|---|
| Android emulator | Android Studio → Device Manager → start a device, then `flutter run --dart-define-from-file=.env` |
| iOS simulator (Mac) | `open -a Simulator && (cd ios && pod install) && flutter run --dart-define-from-file=.env` |
| Chrome (quick UI testing) | `flutter run -d chrome --dart-define-from-file=.env` |

Chrome is only for testing. Ads, push notifications and some photo compression features are mobile-only.
To test matching and chat, use two accounts on two devices or browsers with preferences that match each other.

## 4. Admin panel

`admin/` is a static website with no build step:
```bash
cp admin/js/config.example.js admin/js/config.js   # add the same URL + publishable key
cd admin && python3 -m http.server 8081            # open http://localhost:8081
```
Sign in with your admin account. For production, upload the `admin/` folder (including `config.js`) to any static host, such as Netlify, Vercel, Cloudflare Pages or GitHub Pages. Every admin action is re-checked on the server against the `admins` table and recorded in the audit log, so the website itself holds no secrets.

| Page | What you can do |
|---|---|
| Dashboard | Users, activity, matches, messages, sign-ups chart, top countries |
| Reports | Review reports (with the reported message), then dismiss, suspend or ban |
| Verifications | Compare a selfie with the profile photos, then approve or reject |
| Users | Search, examine full profiles, activity and history; suspend, ban, reactivate, verify, remove photos |
| Photo review | The newest uploads; remove anything inappropriate |
| App errors | Crashes and errors reported by the app, grouped, with stack traces; mark resolved |
| Age rules | Minimum age per country (can't go below 18) |
| Audit log | Every admin action |

**Alerts:** new reports, verifications and errors pop up live in the panel. Click **Enable alerts** for desktop notifications.
To also get them in **Slack or Discord**:
```bash
supabase secrets set ALERT_WEBHOOK_URL="https://hooks.slack.com/services/..."   # or a Discord webhook URL
supabase secrets set ADMIN_PANEL_URL="https://your-admin-site.example/"
```
Then add Database Webhooks (Dashboard → Database → Webhooks) on **INSERT** into `reports`, `verification_requests` and `app_errors`. Point them at `https://YOUR_REF.supabase.co/functions/v1/admin-alerts` with the header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`.

## 5. Age requirements & legal

- Woops is **adults-only**. The minimum is **18 everywhere**, and higher where a country's age of majority is higher (seeded: KR/DZ 19, TH 20, and 21 in AE, BH, CI, CM, EG, GA, KW, MG, SG, SZ, WS). You can edit these in the admin panel. **Have local counsel confirm the rules for your launch countries.**
- At sign-up people enter their date of birth and country (a neutral age gate). Under-age users can't create an account, and the server rejects a later profile with a different birthday.
- Users must accept the Terms, Privacy Policy and Community Guidelines. Acceptance is stored with a version; bump `LegalDoc.version` and `private.current_legal_version()` to ask again.
- Profiles reported as under 18 by two or more different people are hidden automatically until an admin reviews them.
- Documents: `assets/legal/*.md`, shown in the app and working offline. **They are templates**: fill in `[COMPANY NAME]`, address, country and contact, have a lawyer review them, and publish the same text on your website for the store listings.
- Store ratings: Apple App Store **17+** (dating, unrestricted user content). Google Play: complete the content rating questionnaire and set the target audience to **18+ only**.
- Real ID document checks need a provider (e.g. Persona, Yoti, Stripe Identity). The built-in selfie verification is manual review by your team.

## 6. Ads (Google AdMob)

### How ads behave: minimal at first, slowly more

| Ad | Where | How often |
|---|---|---|
| **Rewarded** | Offered only when someone runs out of likes ("watch an ad for +10 likes") | Only when the user chooses; never counted against the limit below; max 3 a day (server-checked) |
| **Native "Sponsored" card** | In Discover between profiles, closed with a *Continue* button | Paced (below): about every 17 profiles for new users, at most every 5 profiles later |
| **Native "Sponsored" card** | One in Likes, one after the 3rd chat in Chats, one on your Profile | Paced (below) |
| Banner | Supported but off unless you place it | — |

**Pacing** (`lib/features/ads/ad_pacer.dart`), per phone:
- Day 1 (and 2): at most **1 ad per 5 minutes**. Day 3–4: 2. Day 5–6: 3. Day 7: 4. Day 8+: **5 ads per 5 minutes** (the maximum).
- No ads in the **first minute** after opening the app.
- Never in chats, photos, sign-in, onboarding, safety/report screens or settings. No full-screen interstitials and no app-open ads.
- Tune without code changes in `.env`: `ADS_MAX_PER_5MIN`, `ADS_RAMP_DAYS`, `ADS_GRACE_SECONDS`, `ADS_DECK`, `ADS_NATIVE`, `ADS_REWARDED`, `ADS_ENABLED`.

### Setup, step by step

1. **AdMob account**: sign up at https://admob.google.com with the Google account that will receive payments, and add payment + tax details.
2. **Add two apps** in AdMob → Apps → Add app: one **Android** and one **iOS** (choose "not published yet" if needed; link the store listings later).
3. **Create 3 ad units per app** (6 total) in each app → Ad units → Add ad unit:
   - **Rewarded**, name "Extra likes". Reward amount 10, item "likes". Turn on **Server-side verification** with callback URL `https://YOUR_REF.supabase.co/functions/v1/admob-ssv` (extra likes are only granted after Google's signed callback).
   - **Native advanced**, name "Sponsored card".
   - **Banner**, name "Banner" (optional, for later).
4. **App IDs** (look like `ca-app-pub-1234…~5678…`; the app crashes on start without them):
   - Android: add `ADMOB_APP_ID_ANDROID=ca-app-pub-…~…` to `android/gradle.properties`.
   - iOS: put it in `ios/Flutter/AdMob.xcconfig` (`ADMOB_APP_ID_IOS=…`).
5. **Ad unit IDs** (look like `ca-app-pub-1234…/9876…`) go in `.env`:
   ```
   ADMOB_ANDROID_REWARDED_ID=   ADMOB_IOS_REWARDED_ID=
   ADMOB_ANDROID_NATIVE_ID=     ADMOB_IOS_NATIVE_ID=
   ADMOB_ANDROID_BANNER_ID=     ADMOB_IOS_BANNER_ID=
   ```
   Debug builds **always** use Google's test ads, whatever you put here, so you can't accidentally click your own real ads (that gets accounts suspended). Only release builds show real ads.
6. **Consent**: AdMob → Privacy & messaging → create a **GDPR message** (Europe/UK) and, for iOS, an **IDFA explainer** message. The app shows them automatically where required; users can change their choice in Settings → *Ad privacy choices*.
7. **iOS only**: add Google's full `SKAdNetworkItems` list to `ios/Runner/Info.plist` (https://developers.google.com/admob/ios/privacy/skadnetwork).
8. **app-ads.txt**: AdMob → Apps → app-ads.txt gives you a line to put at `https://<your developer website>/app-ads.txt` (the website listed in the store). Without it some advertisers won't bid.
9. Build a release (`flutter build appbundle --release --dart-define-from-file=.env` / iOS archive) and publish. Real ads usually start within a few days of AdMob reviewing the app.

**Testing**: run a debug build. Google's test ads appear (labelled "Test Ad"). To see the ramp quickly, temporarily set `ADS_RAMP_DAYS=1` and `ADS_GRACE_SECONDS=5` in `.env`.

## 7. Push notifications (optional)

1. In a Firebase project, add an Android app and an iOS app (both `com.woops.app`). Copy the IDs and API keys into the `FIREBASE_*` values in `.env`.
2. iOS: upload an APNs key in Firebase → Cloud Messaging. In Xcode, add *Push Notifications* and *Background Modes → Remote notifications*.
3. Firebase → Service accounts → *Generate new private key*, then:
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
   supabase secrets set PUSH_WEBHOOK_SECRET="$(openssl rand -hex 24)"
   ```
4. Add Database Webhooks on **INSERT** into `messages`, `matches` and `swipes`. Point them at `https://YOUR_REF.supabase.co/functions/v1/push-notify` with the header `x-webhook-secret: <secret>`.

## 8. Tests

```bash
flutter analyze
flutter test                         # 49 unit + widget tests, no backend needed
```
**Backend security tests**, using a throwaway local Postgres (132 checks with 12 simulated users). They cover forged likes, outsiders reading chats, age rules, admin-only actions, ban hashes, ad-reward forgery and more:
```bash
brew install postgresql@17 && brew services start postgresql@17
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
./supabase/tests/local/run.sh
```
**On a device**, using a dev project with "Confirm email" off: `flutter test integration_test --dart-define-from-file=.env`

## 9. Your logo & app icon

- In-app logo: save `assets/branding/logo.png` (square, transparent background, at least 512 px). It appears automatically.
- Home-screen icon: use [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) with `image_path: assets/branding/logo.png`.

## 10. Release builds

Before the first release:
- Set your own app ID if `com.woops.app` is taken (Android `applicationId`, iOS bundle ID, the URL scheme and `AUTH_REDIRECT_URL`).
- Add your real AdMob IDs, complete the legal documents, and bump `version:` in `pubspec.yaml` for every upload.

**Google Play**
```bash
keytool -genkey -v -keystore ~/woops-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Create `android/key.properties` (git-ignored) with `storePassword`, `keyPassword`, `keyAlias=upload` and `storeFile=/path/to/woops-upload.jks`. Then:
```bash
flutter build appbundle --release --dart-define-from-file=.env
```
Upload `build/app/outputs/bundle/release/app-release.aab` to Play Console. Fill in **Data safety** (location, photos, messages, ads/advertising ID, account deletion), the **content rating** and the **target audience (18+)**, and declare that the app contains ads.

**Apple App Store**
1. In Xcode, open `ios/Runner.xcworkspace` → Signing & Capabilities and choose your Team.
2. Create the app in App Store Connect with the same bundle ID.
3. Build:
   ```bash
   flutter build ipa --release --dart-define-from-file=.env
   ```
   Upload the IPA with **Transporter**.
4. App Review needs: a demo account, in-app account deletion (included), report and block (included), Sign in with Apple if Google sign-in is offered, App Privacy answers (including tracking, if ATT is used), and an age rating of 17+.

## 11. Status & limitations

| Area | Status |
|---|---|
| Database, security rules, matching, chat, admin RPCs | ✅ 132 automated checks pass locally |
| Flutter app | ✅ analyzer clean, 49 tests pass, web build compiles |
| Android / iOS native builds | ⚠️ **Not yet compiled on the dev machine.** The Gradle download stalled on a slow connection, and Xcode isn't installed. Your first `flutter run` on a device is the first native build |
| Edge Functions (Deno) | ⚠️ written but not type-checked or run locally. Check the function logs after deploying |
| Push, AdMob, Slack/Discord alerts | ⚠️ code complete; need your accounts and credentials |
| Admin panel | ⚠️ code complete; needs a Supabase project to try |
| App text translations | English only for now. Dates, numbers and system dialogs follow the phone's language, and right-to-left layouts work. Translating the app's own text is a next step |
| Premium subscriptions | Not implemented. Server-side entitlement checks are ready |
| Web build | For testing only. On web, photos are not re-compressed by the app |
