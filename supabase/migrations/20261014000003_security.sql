-- =============================================================================
-- Amora security: privileges + Row Level Security
--
-- Principle: deny by default. We revoke everything Supabase grants to the
-- `anon` / `authenticated` roles by default, then grant back only what the app
-- needs. Sensitive writes happen only through functions in 002_functions.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema / function privileges
-- -----------------------------------------------------------------------------
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
-- Helpers are needed inside RLS policies, but `private` is not exposed through
-- the REST API, so clients cannot call them directly.
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
revoke all on all tables in schema private from public, anon, authenticated;

revoke all on all functions in schema public from public, anon;
grant execute on function
  public.complete_onboarding(),
  public.set_my_interests(smallint[]),
  public.set_my_location(float8, float8),
  public.touch_last_active(),
  public.get_discovery_feed(int),
  public.swipe(uuid, text),
  public.undo_last_swipe(),
  public.get_likes_received(int, int),
  public.unmatch(uuid),
  public.get_my_conversations(int, int),
  public.send_message(uuid, text, uuid, text, text),
  public.mark_conversation_read(uuid),
  public.block_user(uuid),
  public.unblock_user(uuid),
  public.get_blocked_users(),
  public.report_user(uuid, text, text, uuid),
  public.register_device_token(text, text),
  public.unregister_device_token(text),
  public.is_premium()
to authenticated;

-- -----------------------------------------------------------------------------
-- Table privileges (column-level where it matters)
-- -----------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

-- profiles: status / onboarding_completed / last_active_at are server-only.
-- birthdate can only be set once (at creation).
grant select on public.profiles to authenticated;
grant insert (id, display_name, birthdate, gender, bio, intention, job_title, city)
  on public.profiles to authenticated;
grant update (display_name, gender, bio, intention, job_title, city)
  on public.profiles to authenticated;

grant select on public.profile_locations to authenticated;

grant select, delete on public.profile_photos to authenticated;
grant insert (user_id, storage_path, position, width, height) on public.profile_photos to authenticated;
grant update (position) on public.profile_photos to authenticated;

grant select on public.interests to authenticated;
grant select on public.profile_interests to authenticated;

grant select, delete on public.profile_prompts to authenticated;
grant insert (user_id, prompt, answer, position) on public.profile_prompts to authenticated;
grant update (prompt, answer, position) on public.profile_prompts to authenticated;

grant select on public.discovery_preferences to authenticated;
grant update (min_age, max_age, max_distance_km, genders, intentions, interest_ids)
  on public.discovery_preferences to authenticated;

grant select on public.privacy_settings to authenticated;
grant update (discoverable, show_distance, read_receipts) on public.privacy_settings to authenticated;

grant select on public.notification_preferences to authenticated;
grant update (new_matches, new_messages, new_likes) on public.notification_preferences to authenticated;

-- Read-only for clients; written by functions.
grant select on public.swipes, public.matches, public.conversations, public.conversation_members,
                public.read_receipts, public.messages, public.blocks, public.reports,
                public.device_tokens, public.entitlements
  to authenticated;

grant select on public.public_profiles to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security: enabled on every table in the public schema.
-- -----------------------------------------------------------------------------
alter table public.profiles                 enable row level security;
alter table public.profile_locations        enable row level security;
alter table public.profile_photos           enable row level security;
alter table public.interests                enable row level security;
alter table public.profile_interests        enable row level security;
alter table public.profile_prompts          enable row level security;
alter table public.discovery_preferences    enable row level security;
alter table public.privacy_settings         enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.swipes                   enable row level security;
alter table public.matches                  enable row level security;
alter table public.conversations            enable row level security;
alter table public.conversation_members     enable row level security;
alter table public.read_receipts            enable row level security;
alter table public.messages                 enable row level security;
alter table public.blocks                   enable row level security;
alter table public.reports                  enable row level security;
alter table public.device_tokens            enable row level security;
alter table public.entitlements             enable row level security;

-- profiles: owner only. Other people's profiles come from public_profiles.
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy profile_locations_select_own on public.profile_locations
  for select to authenticated using (user_id = (select auth.uid()));

create policy profile_photos_select_own on public.profile_photos
  for select to authenticated using (user_id = (select auth.uid()));
create policy profile_photos_insert_own on public.profile_photos
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy profile_photos_update_own on public.profile_photos
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy profile_photos_delete_own on public.profile_photos
  for delete to authenticated using (user_id = (select auth.uid()));

create policy interests_select_all on public.interests
  for select to authenticated using (true);

create policy profile_interests_select_own on public.profile_interests
  for select to authenticated using (user_id = (select auth.uid()));

create policy profile_prompts_select_own on public.profile_prompts
  for select to authenticated using (user_id = (select auth.uid()));
create policy profile_prompts_insert_own on public.profile_prompts
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy profile_prompts_update_own on public.profile_prompts
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy profile_prompts_delete_own on public.profile_prompts
  for delete to authenticated using (user_id = (select auth.uid()));

create policy discovery_preferences_select_own on public.discovery_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy discovery_preferences_update_own on public.discovery_preferences
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy privacy_settings_select_own on public.privacy_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy privacy_settings_update_own on public.privacy_settings
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy notification_preferences_select_own on public.notification_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy notification_preferences_update_own on public.notification_preferences
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Only your own swipes. Who liked you comes from get_likes_received().
create policy swipes_select_own on public.swipes
  for select to authenticated using (swiper_id = (select auth.uid()));

create policy matches_select_participant on public.matches
  for select to authenticated
  using ((select auth.uid()) in (user_low, user_high));

create policy conversations_select_member on public.conversations
  for select to authenticated
  using (private.is_conversation_member(id, (select auth.uid())));

-- Only your own membership row (last_read_at is private).
create policy conversation_members_select_own on public.conversation_members
  for select to authenticated using (user_id = (select auth.uid()));

create policy read_receipts_select_member on public.read_receipts
  for select to authenticated
  using (private.is_conversation_member(conversation_id, (select auth.uid())));

-- Messages: conversation members only, and only while still matched.
create policy messages_select_member on public.messages
  for select to authenticated
  using (
    private.is_conversation_member(conversation_id, (select auth.uid()))
    and exists (
      select 1 from public.conversations cv
        join public.matches m on m.id = cv.match_id
       where cv.id = messages.conversation_id and m.unmatched_at is null
    )
  );

create policy blocks_select_own on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));

-- Reporters can see their own reports. Reported users can never see them.
create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));

create policy device_tokens_select_own on public.device_tokens
  for select to authenticated using (user_id = (select auth.uid()));

create policy entitlements_select_own on public.entitlements
  for select to authenticated using (user_id = (select auth.uid()));
