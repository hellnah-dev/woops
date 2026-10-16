-- =============================================================================
-- Random picks show everyone (men included), not only people whose
-- preferences include you.
--
--  * Matches (top of the feed) stay mutual: your filters AND theirs.
--  * Random picks fill the rest from all active, discoverable people with a
--    photo, whatever either side's gender/age/distance preferences are.
--  * swipe() therefore no longer rejects a like that is outside the target's
--    preferences (it still rejects hidden, blocked or inactive profiles).
-- =============================================================================

create or replace function public.get_discovery_feed(p_limit int default 20)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, distance_km int,
  country_code text, is_verified boolean, zodiac text, is_random boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := private.require_user();
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_gender text;
  v_age int;
  v_pref public.discovery_preferences;
  v_lat float8;
  v_lng float8;
  v_lat_delta float8;
  v_lng_delta float8;
  v_anywhere boolean;
begin
  if not private.is_active(v_me) then
    raise exception 'profile_incomplete: finish your profile first' using errcode = 'P0001';
  end if;

  select p.gender, private.age_on(p.birthdate) into v_gender, v_age
    from public.profiles p where p.id = v_me;
  select * into v_pref from public.discovery_preferences dp where dp.user_id = v_me;
  select l.lat, l.lng into v_lat, v_lng from public.profile_locations l where l.user_id = v_me;

  v_anywhere := v_pref.max_distance_km >= 20000;
  if v_lat is not null then
    v_lat_delta := v_pref.max_distance_km / 111.0 + 0.02;
    v_lng_delta := least(v_pref.max_distance_km / greatest(111.0 * cos(radians(v_lat)), 1.0) + 0.02, 180.0);
  end if;

  return query
  with eligible as (
    -- Everyone I could ever be shown, with distance. No preference filters yet.
    select c.*, tp.genders as t_genders, tp.min_age as t_min_age, tp.max_age as t_max_age,
           ps.show_distance, tl.lat as t_lat, tl.lng as t_lng, d.km
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
       and not exists (select 1 from public.swipes s where s.swiper_id = v_me and s.swipee_id = c.id)
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_me and b.blocked_id = c.id)
                           or (b.blocker_id = c.id and b.blocked_id = v_me))
  ),
  strict as (
    select e.*, row_number() over (order by e.km nulls last, e.last_active_at desc, e.id) as rk
      from eligible e
     where e.gender = any (v_pref.genders)
       and e.age between v_pref.min_age and v_pref.max_age
       -- Matches are mutual: they must also be looking for someone like me.
       and v_gender = any (e.t_genders)
       and v_age between e.t_min_age and e.t_max_age
       and (v_anywhere or v_lat is null or e.t_lat is null or (
               e.t_lat between v_lat - v_lat_delta and v_lat + v_lat_delta
           and (abs(e.t_lng - v_lng) <= v_lng_delta or 360 - abs(e.t_lng - v_lng) <= v_lng_delta)
           and e.km <= v_pref.max_distance_km))
       and (cardinality(v_pref.country_codes) = 0 or e.country_code = any (v_pref.country_codes))
       and (cardinality(v_pref.intentions) = 0 or e.intention = any (v_pref.intentions))
       and (cardinality(v_pref.interest_ids) = 0 or exists (
              select 1 from public.profile_interests pi
               where pi.user_id = e.id and pi.interest_id = any (v_pref.interest_ids)))
     order by rk
     limit v_limit
  ),
  fallback as (
    select e.*, row_number() over (order by random()) as rk
      from eligible e
     where not exists (select 1 from strict s where s.id = e.id)
     order by rk
     limit greatest(v_limit - (select count(*) from strict), 0)
  ),
  combined as (
    select s.*, false as random_pick from strict s
    union all
    select f.*, true from fallback f
  )
  select x.id, x.display_name, x.age, x.gender, x.bio, x.intention, x.job_title, x.city,
         x.photos, x.interests, x.prompts,
         case when x.show_distance and x.km is not null then greatest(1, ceil(x.km))::int end,
         x.country_code, x.is_verified, x.zodiac, x.random_pick
    from combined x
   order by x.random_pick, x.rk;
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

revoke all on function public.get_discovery_feed(int), public.swipe(uuid, text) from public, anon;
grant execute on function public.get_discovery_feed(int), public.swipe(uuid, text) to authenticated;
