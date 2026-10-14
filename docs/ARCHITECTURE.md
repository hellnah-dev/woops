# Amora: architecture

## Overview

```
Flutter app (Android + iOS, one codebase)
 ├─ UI (screens/widgets)      ← GoRouter navigation, Material 3 design system
 ├─ application (Riverpod)    ← controllers holding screen state
 └─ data (repositories)       ← the only code that talks to Supabase
            │  HTTPS (publishable key + user JWT)
            ▼
Supabase
 ├─ Auth            email/password, Apple, Google (OAuth)
 ├─ Postgres        tables + Row Level Security + SECURITY DEFINER functions
 ├─ Storage         private `profile-photos` bucket with RLS
 ├─ Realtime        messages, matches, read receipts (RLS-filtered)
 └─ Edge Functions  delete-account, push-notify (service-role key lives ONLY here)
            │
            ▼
Firebase Cloud Messaging → Android / APNs → iOS
```

**Core rule:** the app is never trusted. Every sensitive action (like, pass,
match, message, block, report, undo) is a Postgres function that checks
identity, eligibility, blocks and rate limits itself. Clients have no
INSERT/UPDATE rights on those tables at all.

## Folder structure (feature-first)

```
lib/
  main.dart / app.dart          bootstrap, theme, router
  core/
    config/env.dart             build-time config from .env (public values only)
    router/                     GoRouter + auth/onboarding redirects, bottom-nav shell
    supabase/                   client + auth providers, private photo URL resolver
    theme/                      colours, spacing, radius, light/dark ThemeData
    utils/                      error mapping, validators, time formatting, uuid
    widgets/                    AppLogo, buttons, state views, photos, chips
  features/<feature>/
    data/                       repositories (Supabase calls)
    domain/                     models (fromJson/toJson)
    application/                Riverpod controllers/providers
    presentation/               screens & widgets
  features = auth, onboarding, profile, discovery, likes, matches, chat,
             safety, settings, notifications
supabase/
  migrations/                   001 schema · 002 functions · 003 security · 004 storage+realtime · 005 interests
  functions/                    delete-account, push-notify (Deno)
  tests/local/                  run.sh: migrations + 71 multi-account security tests
test/                           unit + widget tests (fake repositories)
integration_test/               on-device end-to-end smoke test
```

## Database schema

| Table | Purpose | Client access |
|---|---|---|
| `profiles` | name, birthdate, gender, bio, intention, job, city, `status`, `onboarding_completed` | owner: read; insert; update *only* safe columns (not birthdate/status) |
| `profile_locations` | lat/lng **rounded to ~1.1 km** | owner read; write via `set_my_location()` |
| `profile_photos` | storage path + position (max 6, path must be in own folder) | owner CRUD |
| `interests`, `profile_interests` | catalogue + user's picks (max 10) | read catalogue; write via `set_my_interests()` |
| `profile_prompts` | up to 3 prompt answers | owner CRUD |
| `discovery_preferences` | age range, distance, genders wanted, intention/interest filters | owner read/update |
| `privacy_settings` | discoverable (pause), show distance, read receipts | owner read/update |
| `notification_preferences` | matches / messages / likes push toggles | owner read/update |
| `swipes` | like/pass, PK (swiper, swipee) | own rows read-only; write via `swipe()` |
| `matches` | ordered pair `user_low < user_high`, UNIQUE → no duplicates | participants read-only |
| `conversations`, `conversation_members` | chat container + members (future: groups) | members read; `last_read_at` private |
| `read_receipts` | public "read at" only if reader allows it | conversation members read |
| `messages` | `kind` (text/image/system), `body`, `media_path`, `metadata`, `client_id` (idempotency) | members read while matched; write via `send_message()` |
| `blocks` | blocker → blocked | blocker reads own |
| `reports` | reason, details, optional message; reporter hidden | reporter reads own; write via `report_user()` |
| `device_tokens` | FCM tokens | owner read; write via RPC |
| `entitlements` | premium (server-written only, e.g. RevenueCat webhook) | owner read |

Other people's profiles are only reachable through:
- `get_discovery_feed()`: mutual gender + age preferences, distance, filters, excludes swiped/blocked/paused users. Returns **age, not birthdate**, and a distance rounded up to whole km (or null if hidden).
- `public_profiles` view: yourself, your active matches, and people who liked you. Never blocked users.
- `get_likes_received()`, `get_my_conversations()`.

### Backend functions

`complete_onboarding`, `set_my_interests`, `set_my_location`, `touch_last_active`,
`get_discovery_feed`, `swipe`, `undo_last_swipe`, `get_likes_received`, `unmatch`,
`get_my_conversations`, `send_message`, `mark_conversation_read`, `block_user`,
`unblock_user`, `get_blocked_users`, `report_user`, `register_device_token`,
`unregister_device_token`, `is_premium`.

### Rules enforced on the server

- Must be 18+ (trigger), birthdate immutable after creation.
- Can't swipe yourself; can't like someone whose preferences exclude you (unless they liked you first).
- Matches only on mutual like; concurrent likes serialised with an advisory lock; UNIQUE pair.
- Unmatched pairs never re-match. Blocking unmatches and hides both users from each other everywhere (feed, profiles, photos, chat).
- Messages only between active, unblocked, still-matched members; idempotent by `client_id`.
- Rate limits: 100 likes / 24 h (free), 60 swipes / min, 30 messages / min, 1000 messages / day, 20 reports / day.
- Undo: only your most recent **pass**, within 10 minutes.

## Key design decisions

- **Supabase RPCs over Edge Functions for business logic:** transactional, close to the data, testable with plain SQL.
- **Private photo bucket:** photos load with the user's JWT, and storage RLS re-checks blocks on every request.
- **Optimistic UI:** swipes and messages appear instantly. Failures roll back or show "Not sent · Retry". Retries reuse the same `client_id`, so no duplicates.
- **No codegen:** plain Riverpod 2 notifiers and hand-written models keep the build simple for beginners.
- **Monetisation-ready, not monetised:** `entitlements` + `private.is_premium()` already lift the daily like limit server-side. Purchases (RevenueCat) are not implemented yet; see README.

## Development phases & status

| Phase | Status |
|---|---|
| 1 Foundation: structure, design system, env config, Git | ✅ |
| 2 UI: onboarding, auth, discovery, likes, matches, chat, profile, settings | ✅ |
| 3 Backend: schema, RLS, matching/messaging functions, storage | ✅ (tested locally, 71 checks) |
| 4 Integration: all screens wired to Supabase, uploads, realtime, push | ✅ code complete; push needs Firebase credentials |
| 5 Safety: block, report, delete account, privacy controls | ✅ · Premium: ⏳ not started (by design) |
| 6 Testing & release: unit/widget tests, Android build, release docs | ✅ · iOS build needs Xcode on your Mac |
