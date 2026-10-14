-- =============================================================================
-- Woops core schema
-- Tables, constraints, indexes and integrity triggers.
-- Security (RLS, grants) lives in 20261014000003_security.sql.
-- =============================================================================

create schema if not exists private;

-- -----------------------------------------------------------------------------
-- Generic helpers
-- -----------------------------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.age_on(p_birthdate date, p_on date default current_date)
returns int
language sql
stable
set search_path = ''
as $$
  select extract(year from age(p_on, p_birthdate))::int;
$$;

-- -----------------------------------------------------------------------------
-- Profiles (private: only the owner can read this table directly)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  display_name          text not null check (char_length(btrim(display_name)) between 1 and 40),
  birthdate             date not null,
  gender                text not null check (gender in ('woman', 'man', 'nonbinary')),
  bio                   text not null default '' check (char_length(bio) <= 500),
  intention             text not null default 'figuring_out'
                        check (intention in ('long_term', 'long_term_open', 'short_term_open',
                                             'short_term', 'friends', 'figuring_out')),
  job_title             text check (job_title is null or char_length(job_title) <= 60),
  city                  text check (city is null or char_length(city) <= 80),
  -- Moderation status. Never writable by clients.
  status                text not null default 'active' check (status in ('active', 'suspended', 'banned')),
  onboarding_completed  boolean not null default false,
  last_active_at        timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index profiles_discovery_idx
  on public.profiles (gender, last_active_at desc)
  where status = 'active' and onboarding_completed;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- Users must be 18+. A CHECK constraint cannot use current_date, so use a trigger.
create or replace function private.enforce_adult()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.birthdate > current_date - interval '18 years' then
    raise exception 'underage: users must be at least 18 years old' using errcode = '23514';
  end if;
  if new.birthdate < current_date - interval '120 years' then
    raise exception 'invalid_birthdate' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger profiles_enforce_adult
  before insert or update of birthdate on public.profiles
  for each row execute function private.enforce_adult();

-- -----------------------------------------------------------------------------
-- Approximate location (owner-only; never exposed to other users)
-- Coordinates are rounded to 2 decimals (~1.1 km) before storage.
-- -----------------------------------------------------------------------------
create table public.profile_locations (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  updated_at  timestamptz not null default now()
);

create index profile_locations_lat_lng_idx on public.profile_locations (lat, lng);

-- -----------------------------------------------------------------------------
-- Photos (files live in the private `profile-photos` storage bucket)
-- -----------------------------------------------------------------------------
create table public.profile_photos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  storage_path  text not null unique,
  position      smallint not null default 0 check (position between 0 and 5),
  width         int check (width is null or width > 0),
  height        int check (height is null or height > 0),
  created_at    timestamptz not null default now(),
  -- Path must live in the owner's folder: "<user_id>/<file>"
  constraint profile_photos_path_owner check (storage_path like user_id::text || '/%')
);

create index profile_photos_user_idx on public.profile_photos (user_id, position, created_at);

create or replace function private.enforce_photo_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.profile_photos where user_id = new.user_id) >= 6 then
    raise exception 'photo_limit: a profile can have at most 6 photos' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger profile_photos_limit
  before insert on public.profile_photos
  for each row execute function private.enforce_photo_limit();

-- -----------------------------------------------------------------------------
-- Interests
-- -----------------------------------------------------------------------------
create table public.interests (
  id        smallint generated always as identity primary key,
  name      text not null unique check (char_length(name) between 1 and 40),
  emoji     text,
  category  text not null default 'general'
);

create table public.profile_interests (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  interest_id  smallint not null references public.interests (id) on delete cascade,
  primary key (user_id, interest_id)
);

create index profile_interests_interest_idx on public.profile_interests (interest_id);

-- -----------------------------------------------------------------------------
-- Prompts ("My ideal Sunday is...")
-- -----------------------------------------------------------------------------
create table public.profile_prompts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  prompt      text not null check (char_length(btrim(prompt)) between 1 and 120),
  answer      text not null check (char_length(btrim(answer)) between 1 and 250),
  position    smallint not null default 0 check (position between 0 and 2),
  created_at  timestamptz not null default now(),
  unique (user_id, position)
);

-- -----------------------------------------------------------------------------
-- Discovery preferences, privacy settings, notification preferences
-- (one row each per profile, created automatically)
-- -----------------------------------------------------------------------------
create table public.discovery_preferences (
  user_id          uuid primary key references public.profiles (id) on delete cascade,
  min_age          int not null default 18 check (min_age between 18 and 100),
  max_age          int not null default 99 check (max_age between 18 and 100),
  max_distance_km  int not null default 50 check (max_distance_km between 1 and 500),
  genders          text[] not null default array['woman', 'man', 'nonbinary']
                   check (cardinality(genders) between 1 and 3
                          and genders <@ array['woman', 'man', 'nonbinary']),
  -- Empty array = no filter.
  intentions       text[] not null default '{}'
                   check (intentions <@ array['long_term', 'long_term_open', 'short_term_open',
                                              'short_term', 'friends', 'figuring_out']),
  interest_ids     smallint[] not null default '{}' check (cardinality(interest_ids) <= 10),
  updated_at       timestamptz not null default now(),
  check (min_age <= max_age)
);

create trigger discovery_preferences_updated_at
  before update on public.discovery_preferences
  for each row execute function private.set_updated_at();

create table public.privacy_settings (
  user_id        uuid primary key references public.profiles (id) on delete cascade,
  discoverable   boolean not null default true,   -- false = paused, hidden from discovery
  show_distance  boolean not null default true,
  read_receipts  boolean not null default true,
  updated_at     timestamptz not null default now()
);

create trigger privacy_settings_updated_at
  before update on public.privacy_settings
  for each row execute function private.set_updated_at();

create table public.notification_preferences (
  user_id       uuid primary key references public.profiles (id) on delete cascade,
  new_matches   boolean not null default true,
  new_messages  boolean not null default true,
  new_likes     boolean not null default true,
  updated_at    timestamptz not null default now()
);

create trigger notification_preferences_updated_at
  before update on public.notification_preferences
  for each row execute function private.set_updated_at();

create or replace function private.create_profile_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.discovery_preferences (user_id) values (new.id) on conflict do nothing;
  insert into public.privacy_settings (user_id) values (new.id) on conflict do nothing;
  insert into public.notification_preferences (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger profiles_create_defaults
  after insert on public.profiles
  for each row execute function private.create_profile_defaults();

-- -----------------------------------------------------------------------------
-- Swipes (likes and passes). Written ONLY through public.swipe().
-- -----------------------------------------------------------------------------
create table public.swipes (
  swiper_id   uuid not null references public.profiles (id) on delete cascade,
  swipee_id   uuid not null references public.profiles (id) on delete cascade,
  action      text not null check (action in ('like', 'pass')),
  created_at  timestamptz not null default now(),
  primary key (swiper_id, swipee_id),
  check (swiper_id <> swipee_id)
);

create index swipes_swipee_idx on public.swipes (swipee_id, action, created_at desc);
create index swipes_swiper_recent_idx on public.swipes (swiper_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Matches. The pair is stored ordered (user_low < user_high) so a UNIQUE
-- constraint makes duplicate matches impossible.
-- -----------------------------------------------------------------------------
create table public.matches (
  id            uuid primary key default gen_random_uuid(),
  user_low      uuid not null references public.profiles (id) on delete cascade,
  user_high     uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  unmatched_at  timestamptz,
  unmatched_by  uuid references public.profiles (id) on delete set null,
  check (user_low < user_high),
  unique (user_low, user_high)
);

create index matches_user_high_idx on public.matches (user_high);

-- -----------------------------------------------------------------------------
-- Conversations. Currently 1:1 per match, but members are a separate table so
-- the model can grow (group chats, support threads) without a rewrite.
-- -----------------------------------------------------------------------------
create table public.conversations (
  id               uuid primary key default gen_random_uuid(),
  match_id         uuid unique references public.matches (id) on delete cascade,
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz
);

create table public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  joined_at        timestamptz not null default now(),
  -- Private: used for unread counts. Only visible to the member themself.
  last_read_at     timestamptz not null default '-infinity',
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

-- Public read receipts: only written when the reader has read receipts enabled.
create table public.read_receipts (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  read_at          timestamptz not null,
  primary key (conversation_id, user_id)
);

-- -----------------------------------------------------------------------------
-- Messages. `kind`, `media_path` and `metadata` let us add images, voice notes,
-- GIFs etc. later without changing the table shape.
-- -----------------------------------------------------------------------------
create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  -- Client-generated id that makes retries idempotent (no duplicate messages).
  client_id        uuid not null,
  kind             text not null default 'text' check (kind in ('text', 'image', 'system')),
  body             text check (body is null or char_length(body) <= 2000),
  media_path       text,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (sender_id, client_id),
  check (kind <> 'text' or char_length(btrim(body)) between 1 and 2000),
  check (kind <> 'image' or media_path is not null)
);

create index messages_conversation_created_idx on public.messages (conversation_id, created_at desc, id desc);
create index messages_sender_recent_idx on public.messages (sender_id, created_at desc);

create or replace function private.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id
     and (last_message_at is null or last_message_at < new.created_at);
  return new;
end;
$$;

create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function private.touch_conversation();

-- -----------------------------------------------------------------------------
-- Safety: blocks and reports
-- -----------------------------------------------------------------------------
create table public.blocks (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  -- Set null (not cascade) so moderation history survives account deletion.
  reporter_id  uuid references public.profiles (id) on delete set null,
  reported_id  uuid references public.profiles (id) on delete set null,
  reason       text not null check (reason in ('inappropriate_photos', 'harassment', 'spam',
                                               'impersonation', 'underage', 'scam', 'other')),
  details      text check (details is null or char_length(details) <= 1000),
  message_id   uuid references public.messages (id) on delete set null,
  status       text not null default 'open' check (status in ('open', 'reviewing', 'actioned', 'dismissed')),
  created_at   timestamptz not null default now()
);

create index reports_status_idx on public.reports (status, created_at);
create index reports_reported_idx on public.reports (reported_id);
create index reports_reporter_recent_idx on public.reports (reporter_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Push notification device tokens
-- -----------------------------------------------------------------------------
create table public.device_tokens (
  token       text primary key check (char_length(token) between 10 and 4096),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  platform    text not null check (platform in ('ios', 'android')),
  updated_at  timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

-- -----------------------------------------------------------------------------
-- Entitlements (premium). Written ONLY by the server (service role), e.g. a
-- RevenueCat webhook. A client-side flag is never trusted.
-- -----------------------------------------------------------------------------
create table public.entitlements (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  entitlement  text not null check (entitlement in ('premium')),
  expires_at   timestamptz,
  source       text not null default 'revenuecat',
  updated_at   timestamptz not null default now(),
  primary key (user_id, entitlement)
);
