-- =============================================================================
-- Discovery never runs dry: when too few people match your filters, the feed
-- is topped up with random people (`is_random = true`).
--
-- The fallback ignores YOUR filters (distance, age range, genders wanted,
-- country, intention, interests) but still respects THEIR preferences about
-- you (private.target_accepts, the same rule swipe() enforces), so every card
-- can be liked. Safety rules are unchanged: never yourself, people you've
-- swiped, blocked pairs, hidden/paused, suspended or photo-less profiles.
-- =============================================================================

drop function public.get_map_people(int);
drop function public.get_discovery_feed(int);

create function public.get_discovery_feed(p_limit int default 20)
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
       -- Their preferences about me (always respected).
       and v_gender = any (tp.genders)
       and v_age between tp.min_age and tp.max_age
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

create function public.get_map_people(p_limit int default 40)
returns table (
  id uuid, display_name text, age int, photo text, distance_km int,
  lat float8, lng float8, is_verified boolean, intention text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  select f.id, f.display_name, f.age, f.photos[1], f.distance_km,
         (round((l.lat / 0.02)::numeric) * 0.02)::float8, (round((l.lng / 0.02)::numeric) * 0.02)::float8,
         f.is_verified, f.intention
    from public.get_discovery_feed(least(greatest(coalesce(p_limit, 40), 1), 50)) f
    join public.profile_locations l on l.user_id = f.id
   where f.distance_km is not null;
end;
$$;

revoke all on function public.get_discovery_feed(int), public.get_map_people(int) from public, anon;
grant execute on function public.get_discovery_feed(int), public.get_map_people(int) to authenticated;
