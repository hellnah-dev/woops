-- =============================================================================
-- Amora backend functions
--
-- Everything sensitive (likes, matching, messaging, blocking, reporting) goes
-- through these SECURITY DEFINER functions. Clients have no direct write access
-- to those tables, so likes and matches cannot be forged.
--
-- Errors are raised as `<code>: <human message>` so the app can map the code.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Internal helpers (schema `private` is NOT exposed through the API)
-- -----------------------------------------------------------------------------
create or replace function private.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated: sign in required' using errcode = '28000';
  end if;
  return v_uid;
end;
$$;

create or replace function private.is_active(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
     where id = p_user and status = 'active' and onboarding_completed
  );
$$;

create or replace function private.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
     where (blocker_id = p_a and blocked_id = p_b)
        or (blocker_id = p_b and blocked_id = p_a)
  );
$$;

create or replace function private.is_premium(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.entitlements
     where user_id = p_user
       and entitlement = 'premium'
       and (expires_at is null or expires_at > now())
  );
$$;

create or replace function private.is_conversation_member(p_conversation uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members
     where conversation_id = p_conversation and user_id = p_user
  );
$$;

-- Can `p_viewer` see the photos of `p_owner`? (used by storage policies)
create or replace function private.can_view_photos(p_viewer uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_viewer = p_owner
      or (private.is_active(p_owner) and not private.is_blocked_between(p_viewer, p_owner));
$$;

-- Great-circle distance in km (haversine).
create or replace function private.distance_km(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8
language sql
immutable
set search_path = ''
as $$
  select 6371.0 * 2 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2)
         + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
         ));
$$;

-- Does `p_target`'s discovery preferences accept `p_viewer` (gender + age)?
create or replace function private.target_accepts(p_viewer uuid, p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles v
      join public.discovery_preferences tp on tp.user_id = p_target
     where v.id = p_viewer
       and v.gender = any (tp.genders)
       and private.age_on(v.birthdate) between tp.min_age and tp.max_age
  );
$$;

create or replace function private.daily_like_limit(p_user uuid)
returns int
language sql
stable
set search_path = ''
as $$
  -- null = unlimited
  select case when private.is_premium(p_user) then null else 100 end;
$$;

-- Ordered pair helpers for matches.
create or replace function private.match_between(p_a uuid, p_b uuid)
returns public.matches
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.matches
   where user_low = least(p_a, p_b) and user_high = greatest(p_a, p_b);
$$;

-- -----------------------------------------------------------------------------
-- Profile cards: a safe projection of a profile (age instead of birthdate,
-- no status, no location, no private settings).
-- -----------------------------------------------------------------------------
create or replace view private.profile_cards as
select
  p.id,
  p.display_name,
  private.age_on(p.birthdate) as age,
  p.gender,
  p.bio,
  p.intention,
  p.job_title,
  p.city,
  coalesce((select array_agg(ph.storage_path order by ph.position, ph.created_at)
              from public.profile_photos ph where ph.user_id = p.id), '{}') as photos,
  coalesce((select array_agg(i.name order by i.name)
              from public.profile_interests pi
              join public.interests i on i.id = pi.interest_id
             where pi.user_id = p.id), '{}') as interests,
  coalesce((select jsonb_agg(jsonb_build_object('prompt', pr.prompt, 'answer', pr.answer)
                             order by pr.position)
              from public.profile_prompts pr where pr.user_id = p.id), '[]'::jsonb) as prompts,
  p.status,
  p.onboarding_completed,
  p.last_active_at
from public.profiles p;

-- Client-facing view. Runs with the view owner's rights (it bypasses RLS on
-- the base tables) but only returns profiles the caller has a reason to see:
-- themself, active matches, and people who liked them. Never blocked users.
create or replace view public.public_profiles
with (security_barrier = true)
as
select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
       c.photos, c.interests, c.prompts
  from private.profile_cards c
 where c.status = 'active'
   and c.onboarding_completed
   and auth.uid() is not null
   and (
         c.id = auth.uid()
      or exists (select 1 from public.matches m
                  where m.unmatched_at is null
                    and m.user_low = least(c.id, auth.uid())
                    and m.user_high = greatest(c.id, auth.uid()))
      or exists (select 1 from public.swipes s
                  where s.swiper_id = c.id and s.swipee_id = auth.uid() and s.action = 'like')
   )
   and not private.is_blocked_between(c.id, auth.uid());

-- -----------------------------------------------------------------------------
-- Onboarding / profile RPCs
-- -----------------------------------------------------------------------------
create or replace function public.complete_onboarding()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = v_me) then
    raise exception 'profile_missing: create your profile first' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profile_photos where user_id = v_me) then
    raise exception 'photo_required: add at least one photo' using errcode = 'P0001';
  end if;
  update public.profiles
     set onboarding_completed = true, last_active_at = now()
   where id = v_me;
end;
$$;

create or replace function public.set_my_interests(p_interest_ids smallint[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_ids smallint[] := array(select distinct unnest(coalesce(p_interest_ids, '{}')));
begin
  if cardinality(v_ids) > 10 then
    raise exception 'too_many_interests: pick up to 10 interests' using errcode = 'P0001';
  end if;
  if exists (select 1 from unnest(v_ids) x(id)
              where not exists (select 1 from public.interests i where i.id = x.id)) then
    raise exception 'invalid_interest' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = v_me) then
    raise exception 'profile_missing: create your profile first' using errcode = 'P0001';
  end if;

  delete from public.profile_interests where user_id = v_me and interest_id <> all (v_ids);
  insert into public.profile_interests (user_id, interest_id)
  select v_me, x.id from unnest(v_ids) x(id)
  on conflict do nothing;
end;
$$;

-- Stores an approximate (rounded) location. Exact coordinates are never kept.
create or replace function public.set_my_location(p_lat float8, p_lng float8)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_location' using errcode = 'P0001';
  end if;
  insert into public.profile_locations (user_id, lat, lng, updated_at)
  values (v_me, round(p_lat::numeric, 2)::float8, round(p_lng::numeric, 2)::float8, now())
  on conflict (user_id) do update
    set lat = excluded.lat, lng = excluded.lng, updated_at = now();
end;
$$;

create or replace function public.touch_last_active()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles set last_active_at = now()
   where id = auth.uid() and last_active_at < now() - interval '5 minutes';
$$;

-- -----------------------------------------------------------------------------
-- Discovery
-- -----------------------------------------------------------------------------
create or replace function public.get_discovery_feed(p_limit int default 20)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, distance_km int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := private.require_user();
  v_gender text;
  v_age int;
  v_pref public.discovery_preferences;
  v_lat float8;
  v_lng float8;
  v_lat_delta float8;
  v_lng_delta float8;
begin
  if not private.is_active(v_me) then
    raise exception 'profile_incomplete: finish your profile first' using errcode = 'P0001';
  end if;

  select p.gender, private.age_on(p.birthdate) into v_gender, v_age
    from public.profiles p where p.id = v_me;
  select * into v_pref from public.discovery_preferences dp where dp.user_id = v_me;
  select l.lat, l.lng into v_lat, v_lng from public.profile_locations l where l.user_id = v_me;

  -- Bounding box pre-filter so the distance index can be used.
  if v_lat is not null then
    v_lat_delta := v_pref.max_distance_km / 111.0 + 0.02;
    v_lng_delta := v_pref.max_distance_km / greatest(111.0 * cos(radians(v_lat)), 1.0) + 0.02;
  end if;

  return query
  select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
         c.photos, c.interests, c.prompts,
         case when ps.show_distance and d.km is not null then greatest(1, ceil(d.km))::int end
    from private.profile_cards c
    join public.discovery_preferences tp on tp.user_id = c.id
    join public.privacy_settings ps on ps.user_id = c.id
    left join public.profile_locations tl on tl.user_id = c.id
    cross join lateral (
      select case when v_lat is not null and tl.lat is not null
                  then private.distance_km(v_lat, v_lng, tl.lat, tl.lng) end as km
    ) d
   where c.id <> v_me
     and c.status = 'active'
     and c.onboarding_completed
     and ps.discoverable
     and cardinality(c.photos) > 0
     -- Mutual gender + age preferences
     and c.gender = any (v_pref.genders)
     and v_gender = any (tp.genders)
     and c.age between v_pref.min_age and v_pref.max_age
     and v_age between tp.min_age and tp.max_age
     -- Distance (people without a location are still shown, without distance)
     and (v_lat is null or tl.lat is null or (
             tl.lat between v_lat - v_lat_delta and v_lat + v_lat_delta
         and tl.lng between v_lng - v_lng_delta and v_lng + v_lng_delta
         and d.km <= v_pref.max_distance_km))
     -- Optional filters
     and (cardinality(v_pref.intentions) = 0 or c.intention = any (v_pref.intentions))
     and (cardinality(v_pref.interest_ids) = 0 or exists (
            select 1 from public.profile_interests pi
             where pi.user_id = c.id and pi.interest_id = any (v_pref.interest_ids)))
     -- Not already swiped, not blocked either way
     and not exists (select 1 from public.swipes s where s.swiper_id = v_me and s.swipee_id = c.id)
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = v_me and b.blocked_id = c.id)
                         or (b.blocker_id = c.id and b.blocked_id = v_me))
   order by c.last_active_at desc, c.id
   limit least(greatest(coalesce(p_limit, 20), 1), 50);
end;
$$;

-- -----------------------------------------------------------------------------
-- Swiping & matching
-- -----------------------------------------------------------------------------
create or replace function public.swipe(p_target uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_limit int;
  v_inserted int;
  v_match_id uuid;
  v_conversation_id uuid;
  v_they_liked_me boolean;
begin
  if p_action not in ('like', 'pass') then
    raise exception 'invalid_action' using errcode = 'P0001';
  end if;
  if p_target is null or p_target = v_me then
    raise exception 'invalid_target: you cannot swipe on yourself' using errcode = 'P0001';
  end if;
  if not private.is_active(v_me) then
    raise exception 'profile_incomplete: finish your profile first' using errcode = 'P0001';
  end if;
  if not private.is_active(p_target) or private.is_blocked_between(v_me, p_target) then
    raise exception 'unavailable: this profile is no longer available' using errcode = 'P0001';
  end if;

  v_they_liked_me := exists (select 1 from public.swipes
                              where swiper_id = p_target and swipee_id = v_me and action = 'like');

  if p_action = 'like' then
    -- Respect the target's preferences, unless they already liked us.
    if not v_they_liked_me then
      if not private.target_accepts(v_me, p_target)
         or not exists (select 1 from public.privacy_settings
                         where user_id = p_target and discoverable) then
        raise exception 'unavailable: this profile is no longer available' using errcode = 'P0001';
      end if;
    end if;

    v_limit := private.daily_like_limit(v_me);
    if v_limit is not null and (
         select count(*) from public.swipes
          where swiper_id = v_me and action = 'like' and created_at > now() - interval '24 hours'
       ) >= v_limit then
      raise exception 'rate_limited: you are out of likes for today' using errcode = 'P0001';
    end if;
  end if;

  -- Abuse guard for passes too (scripts hammering the API).
  if (select count(*) from public.swipes
       where swiper_id = v_me and created_at > now() - interval '1 minute') >= 60 then
    raise exception 'rate_limited: slow down a little' using errcode = 'P0001';
  end if;

  insert into public.swipes (swiper_id, swipee_id, action)
  values (v_me, p_target, p_action)
  on conflict (swiper_id, swipee_id) do nothing;
  get diagnostics v_inserted = row_count;

  if p_action <> 'like' or not v_they_liked_me then
    return jsonb_build_object('matched', false);
  end if;
  -- An earlier swipe already existed; only a like can create a match.
  if v_inserted = 0 and not exists (select 1 from public.swipes
                                     where swiper_id = v_me and swipee_id = p_target and action = 'like') then
    return jsonb_build_object('matched', false);
  end if;

  -- Serialise concurrent likes for the same pair so exactly one match is made.
  perform pg_advisory_xact_lock(hashtextextended(least(v_me, p_target)::text || greatest(v_me, p_target)::text, 0));

  insert into public.matches (user_low, user_high)
  values (least(v_me, p_target), greatest(v_me, p_target))
  on conflict (user_low, user_high) do nothing
  returning id into v_match_id;

  if v_match_id is null then
    -- Already matched (or previously unmatched, which must stay unmatched).
    select m.id into v_match_id from public.matches m
     where m.user_low = least(v_me, p_target) and m.user_high = greatest(v_me, p_target)
       and m.unmatched_at is null;
    if v_match_id is null then
      return jsonb_build_object('matched', false);
    end if;
    select cv.id into v_conversation_id from public.conversations cv where cv.match_id = v_match_id;
  else
    insert into public.conversations (match_id) values (v_match_id) returning id into v_conversation_id;
    insert into public.conversation_members (conversation_id, user_id)
    values (v_conversation_id, v_me), (v_conversation_id, p_target);
  end if;

  return jsonb_build_object('matched', true, 'match_id', v_match_id, 'conversation_id', v_conversation_id);
end;
$$;

-- Undo the most recent PASS made in the last 10 minutes. Likes cannot be
-- undone because they may already have created a match.
create or replace function public.undo_last_swipe()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_target uuid;
  v_action text;
begin
  select s.swipee_id, s.action into v_target, v_action
    from public.swipes s
   where s.swiper_id = v_me
   order by s.created_at desc
   limit 1;

  if v_target is null then
    raise exception 'nothing_to_undo' using errcode = 'P0001';
  end if;
  if v_action <> 'pass' then
    raise exception 'cannot_undo_like: likes cannot be undone' using errcode = 'P0001';
  end if;

  delete from public.swipes
   where swiper_id = v_me and swipee_id = v_target
     and created_at > now() - interval '10 minutes';
  if not found then
    raise exception 'nothing_to_undo' using errcode = 'P0001';
  end if;
  return v_target;
end;
$$;

-- People who liked me and whom I have not swiped on yet.
create or replace function public.get_likes_received(p_limit int default 30, p_offset int default 0)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, liked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := private.require_user();
begin
  return query
  select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
         c.photos, c.interests, c.prompts, s.created_at
    from public.swipes s
    join private.profile_cards c on c.id = s.swiper_id
   where s.swipee_id = v_me
     and s.action = 'like'
     and c.status = 'active'
     and c.onboarding_completed
     and not exists (select 1 from public.swipes mine
                      where mine.swiper_id = v_me and mine.swipee_id = s.swiper_id)
     and not private.is_blocked_between(v_me, s.swiper_id)
   order by s.created_at desc
   limit least(greatest(coalesce(p_limit, 30), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.unmatch(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  update public.matches
     set unmatched_at = now(), unmatched_by = v_me
   where id = p_match_id
     and v_me in (user_low, user_high)
     and unmatched_at is null;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Conversations & messages
-- -----------------------------------------------------------------------------

-- All active matches with their conversation and latest message.
-- The app shows matches without messages in "Matches" and the rest in "Chats".
create or replace function public.get_my_conversations(p_limit int default 50, p_offset int default 0)
returns table (
  match_id uuid, conversation_id uuid, matched_at timestamptz,
  other_user_id uuid, other_display_name text, other_photo text,
  last_message_id uuid, last_message_body text, last_message_kind text,
  last_message_sender_id uuid, last_message_at timestamptz, unread_count int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := private.require_user();
begin
  return query
  select m.id, cv.id, m.created_at,
         o.id, o.display_name,
         (select ph.storage_path from public.profile_photos ph
           where ph.user_id = o.id order by ph.position, ph.created_at limit 1),
         lm.id, lm.body, lm.kind, lm.sender_id, lm.created_at,
         coalesce(u.n, 0)::int
    from public.matches m
    join public.conversations cv on cv.match_id = m.id
    join public.conversation_members cm on cm.conversation_id = cv.id and cm.user_id = v_me
    join public.profiles o on o.id = case when m.user_low = v_me then m.user_high else m.user_low end
    left join lateral (
      select msg.id, msg.body, msg.kind, msg.sender_id, msg.created_at
        from public.messages msg
       where msg.conversation_id = cv.id and msg.deleted_at is null
       order by msg.created_at desc, msg.id desc
       limit 1
    ) lm on true
    left join lateral (
      select count(*) as n
        from public.messages msg
       where msg.conversation_id = cv.id
         and msg.sender_id <> v_me
         and msg.deleted_at is null
         and msg.created_at > cm.last_read_at
    ) u on true
   where v_me in (m.user_low, m.user_high)
     and m.unmatched_at is null
     and o.status = 'active'
     and not private.is_blocked_between(v_me, o.id)
   order by coalesce(lm.created_at, m.created_at) desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.send_message(
  p_conversation_id uuid,
  p_body text,
  p_client_id uuid,
  p_kind text default 'text',
  p_media_path text default null
)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_other uuid;
  v_msg public.messages;
begin
  if p_client_id is null then
    raise exception 'invalid_request: client id required' using errcode = 'P0001';
  end if;

  -- Idempotency: a retried request returns the original message.
  select * into v_msg from public.messages where sender_id = v_me and client_id = p_client_id;
  if found then
    return v_msg;
  end if;

  if p_kind <> 'text' then
    raise exception 'unsupported_kind: only text messages are enabled' using errcode = 'P0001';
  end if;
  if p_body is null or char_length(btrim(p_body)) = 0 then
    raise exception 'empty_message' using errcode = 'P0001';
  end if;
  if char_length(p_body) > 2000 then
    raise exception 'message_too_long: keep it under 2000 characters' using errcode = 'P0001';
  end if;
  if not private.is_conversation_member(p_conversation_id, v_me) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  select cm.user_id into v_other
    from public.conversation_members cm
   where cm.conversation_id = p_conversation_id and cm.user_id <> v_me
   limit 1;

  if not exists (select 1 from public.conversations cv
                   join public.matches m on m.id = cv.match_id
                  where cv.id = p_conversation_id and m.unmatched_at is null) then
    raise exception 'conversation_closed: you are no longer matched' using errcode = 'P0001';
  end if;
  if v_other is null or not private.is_active(v_other) or private.is_blocked_between(v_me, v_other) then
    raise exception 'conversation_closed: this person is no longer available' using errcode = 'P0001';
  end if;

  -- Rate limits
  if (select count(*) from public.messages
       where sender_id = v_me and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited: you are sending messages too quickly' using errcode = 'P0001';
  end if;
  if (select count(*) from public.messages
       where sender_id = v_me and created_at > now() - interval '24 hours') >= 1000 then
    raise exception 'rate_limited: daily message limit reached' using errcode = 'P0001';
  end if;

  insert into public.messages (conversation_id, sender_id, client_id, kind, body, media_path)
  values (p_conversation_id, v_me, p_client_id, 'text', p_body, null)
  on conflict (sender_id, client_id) do nothing
  returning * into v_msg;

  if v_msg.id is null then
    select * into v_msg from public.messages where sender_id = v_me and client_id = p_client_id;
  end if;

  -- Sending a message implies you have read the conversation.
  update public.conversation_members
     set last_read_at = v_msg.created_at
   where conversation_id = p_conversation_id and user_id = v_me;

  return v_msg;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_now timestamptz := now();
begin
  update public.conversation_members
     set last_read_at = v_now
   where conversation_id = p_conversation_id and user_id = v_me;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.privacy_settings where user_id = v_me and read_receipts) then
    insert into public.read_receipts (conversation_id, user_id, read_at)
    values (p_conversation_id, v_me, v_now)
    on conflict (conversation_id, user_id) do update set read_at = excluded.read_at;
  else
    delete from public.read_receipts where conversation_id = p_conversation_id and user_id = v_me;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Safety
-- -----------------------------------------------------------------------------
create or replace function public.block_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  if p_target is null or p_target = v_me then
    raise exception 'invalid_target' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_target) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  insert into public.blocks (blocker_id, blocked_id) values (v_me, p_target)
  on conflict do nothing;

  update public.matches
     set unmatched_at = now(), unmatched_by = v_me
   where user_low = least(v_me, p_target) and user_high = greatest(v_me, p_target)
     and unmatched_at is null;
end;
$$;

create or replace function public.unblock_user(p_target uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_target;
$$;

create or replace function public.get_blocked_users()
returns table (id uuid, display_name text, blocked_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, b.created_at
    from public.blocks b
    join public.profiles p on p.id = b.blocked_id
   where b.blocker_id = auth.uid()
   order by b.created_at desc;
$$;

-- Reports never reveal the reporter: the reported user has no read access to
-- the reports table, and nothing about a report is shown to them.
create or replace function public.report_user(
  p_target uuid,
  p_reason text,
  p_details text default null,
  p_message_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_id uuid;
begin
  if p_target is null or p_target = v_me then
    raise exception 'invalid_target' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_target) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if p_reason not in ('inappropriate_photos', 'harassment', 'spam', 'impersonation', 'underage', 'scam', 'other') then
    raise exception 'invalid_reason' using errcode = 'P0001';
  end if;
  if p_details is not null and char_length(p_details) > 1000 then
    raise exception 'details_too_long' using errcode = 'P0001';
  end if;
  -- A referenced message must have been sent by the target in a conversation
  -- the reporter belongs to.
  if p_message_id is not null and not exists (
       select 1 from public.messages msg
        where msg.id = p_message_id
          and msg.sender_id = p_target
          and private.is_conversation_member(msg.conversation_id, v_me)) then
    raise exception 'invalid_message' using errcode = 'P0001';
  end if;
  if (select count(*) from public.reports
       where reporter_id = v_me and created_at > now() - interval '24 hours') >= 20 then
    raise exception 'rate_limited: too many reports today' using errcode = 'P0001';
  end if;

  insert into public.reports (reporter_id, reported_id, reason, details, message_id)
  values (v_me, p_target, p_reason, nullif(btrim(p_details), ''), p_message_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Devices (push notifications)
-- -----------------------------------------------------------------------------
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  if p_platform not in ('ios', 'android') then
    raise exception 'invalid_platform' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = v_me) then
    return; -- token is registered again after onboarding
  end if;
  -- A token belongs to one device; if another account used it, move it.
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, v_me, p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

create or replace function public.is_premium()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_premium(auth.uid());
$$;
