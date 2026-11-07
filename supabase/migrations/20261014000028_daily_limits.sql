-- =============================================================================
-- Daily limits for free users, extended by rewarded ads.
--
--  * 25 likes a day (was 100).
--  * 100 swipes a day, likes and passes together (new).
--  * Each rewarded ad, verified by Google on the server (admob-ssv), adds
--    REWARD_LIKES likes (10) and 20 swipes; up to 10 such ads a day (was 3),
--    so people who choose to watch more can keep going.
--  * Swipes are counted in `swipe_log`, because a repeat swipe on someone
--    seen before updates the existing row in `swipes` instead of adding one.
-- =============================================================================

create or replace function private.base_daily_likes() returns int language sql immutable as $$ select 25 $$;
create or replace function private.base_daily_swipes() returns int language sql immutable as $$ select 100 $$;
create or replace function private.reward_swipes_per_ad() returns int language sql immutable as $$ select 20 $$;
create or replace function private.max_rewarded_ads_per_day() returns int language sql immutable as $$ select 10 $$;

create table public.swipe_log (
  swiper_id   uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index swipe_log_recent_idx on public.swipe_log (swiper_id, created_at desc);
alter table public.swipe_log enable row level security;
revoke all on public.swipe_log from anon, authenticated;

-- Daily swipe limit = base + 20 per verified ad in the last 24 h (premium = unlimited).
create or replace function private.daily_swipe_limit(p_user uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select case when private.is_premium(p_user) then null
              else private.base_daily_swipes() + private.reward_swipes_per_ad() * (
                     select count(*)::int from public.ad_rewards
                      where user_id = p_user and created_at > now() - interval '24 hours')
         end;
$$;

create or replace function public.swipe(p_target uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_limit int;
  v_swipe_limit int;
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
    -- Random picks can be anyone, so a like no longer has to fit the target's
    -- gender/age preferences. Hidden (paused) profiles still can't be liked.
    if not v_they_liked_me then
      if not exists (select 1 from public.privacy_settings
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

  -- Daily swipes (likes and passes together); verified rewarded ads add more.
  v_swipe_limit := private.daily_swipe_limit(v_me);
  if v_swipe_limit is not null and (
       select count(*) from public.swipe_log
        where swiper_id = v_me and created_at > now() - interval '24 hours'
     ) >= v_swipe_limit then
    raise exception 'rate_limited: you are out of swipes for today' using errcode = 'P0001';
  end if;

  -- Abuse guard for passes too (scripts hammering the API).
  if (select count(*) from public.swipes
       where swiper_id = v_me and created_at > now() - interval '1 minute') >= 60 then
    raise exception 'rate_limited: slow down a little' using errcode = 'P0001';
  end if;

  -- Profiles come back around once the feed runs out, so a new swipe replaces
  -- an older one (e.g. a pass that is now a like).
  insert into public.swipes (swiper_id, swipee_id, action)
  values (v_me, p_target, p_action)
  on conflict (swiper_id, swipee_id) do update
    set action = excluded.action, created_at = now()
    where public.swipes.action <> excluded.action;
  get diagnostics v_inserted = row_count;

  -- Every swipe counts, including a repeat on someone seen before.
  insert into public.swipe_log (swiper_id) values (v_me);
  delete from public.swipe_log where swiper_id = v_me and created_at < now() - interval '2 days';

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

-- What the app shows: likes and swipes left today, and whether a rewarded ad is available.
create or replace function public.get_like_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_limit int := private.daily_like_limit(v_me);
  v_swipe_limit int := private.daily_swipe_limit(v_me);
  v_used int;
  v_swipes int;
  v_ads int;
begin
  select count(*) into v_used from public.swipes
   where swiper_id = v_me and action = 'like' and created_at > now() - interval '24 hours';
  select count(*) into v_swipes from public.swipe_log
   where swiper_id = v_me and created_at > now() - interval '24 hours';
  select count(*) into v_ads from public.ad_rewards
   where user_id = v_me and created_at > now() - interval '24 hours';
  return jsonb_build_object(
    'unlimited', v_limit is null,
    'limit', v_limit,
    'used', v_used,
    'remaining', case when v_limit is null then null else greatest(v_limit - v_used, 0) end,
    'swipe_limit', v_swipe_limit,
    'swipes_used', v_swipes,
    'swipes_remaining', case when v_swipe_limit is null then null else greatest(v_swipe_limit - v_swipes, 0) end,
    'reward_swipes', private.reward_swipes_per_ad(),
    'rewarded_ads_today', v_ads,
    'rewarded_ads_left', greatest(private.max_rewarded_ads_per_day() - v_ads, 0)
  );
end;
$$;

revoke all on function public.swipe(uuid, text), public.get_like_allowance() from public, anon;
grant execute on function public.swipe(uuid, text), public.get_like_allowance() to authenticated;
revoke all on function private.base_daily_swipes(), private.reward_swipes_per_ad(), private.daily_swipe_limit(uuid)
  from public, anon;
grant execute on function private.base_daily_likes(), private.base_daily_swipes(), private.reward_swipes_per_ad(),
  private.daily_swipe_limit(uuid) to authenticated, service_role;
