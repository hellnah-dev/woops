-- =============================================================================
-- Simple astrology: Western zodiac sign derived from the birthdate.
-- Only the sign is ever shared (never the birthdate), and users can hide it
-- with privacy_settings.show_zodiac.
-- =============================================================================

create or replace function private.zodiac_sign(p_birthdate date)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when md between 321 and 419  then 'aries'
    when md between 420 and 520  then 'taurus'
    when md between 521 and 620  then 'gemini'
    when md between 621 and 722  then 'cancer'
    when md between 723 and 822  then 'leo'
    when md between 823 and 922  then 'virgo'
    when md between 923 and 1022 then 'libra'
    when md between 1023 and 1121 then 'scorpio'
    when md between 1122 and 1221 then 'sagittarius'
    when md >= 1222 or md <= 119 then 'capricorn'
    when md between 120 and 218  then 'aquarius'
    else 'pisces'
  end
  from (select extract(month from p_birthdate)::int * 100 + extract(day from p_birthdate)::int as md) x;
$$;

alter table public.privacy_settings add column show_zodiac boolean not null default true;
grant update (show_zodiac) on public.privacy_settings to authenticated;

-- Profile projections gain `zodiac` (null when hidden).
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
  p.last_active_at,
  p.country_code,
  p.is_verified,
  p.username,
  case when coalesce((select ps.show_zodiac from public.privacy_settings ps where ps.user_id = p.id), true)
       then private.zodiac_sign(p.birthdate) end as zodiac
from public.profiles p;

create or replace view public.public_profiles
with (security_barrier = true)
as
select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
       c.photos, c.interests, c.prompts, c.country_code, c.is_verified, c.username, c.zodiac
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

-- Feed + likes return zodiac too (return type changes → drop & recreate).
drop function public.get_discovery_feed(int);

create function public.get_discovery_feed(p_limit int default 20)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, distance_km int,
  country_code text, is_verified boolean, zodiac text
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
  select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
         c.photos, c.interests, c.prompts,
         case when ps.show_distance and d.km is not null then greatest(1, ceil(d.km))::int end,
         c.country_code, c.is_verified, c.zodiac
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
     and c.gender = any (v_pref.genders)
     and v_gender = any (tp.genders)
     and c.age between v_pref.min_age and v_pref.max_age
     and v_age between tp.min_age and tp.max_age
     and (v_anywhere or v_lat is null or tl.lat is null or (
             tl.lat between v_lat - v_lat_delta and v_lat + v_lat_delta
         and (abs(tl.lng - v_lng) <= v_lng_delta or 360 - abs(tl.lng - v_lng) <= v_lng_delta)
         and d.km <= v_pref.max_distance_km))
     and (cardinality(v_pref.country_codes) = 0 or c.country_code = any (v_pref.country_codes))
     and (cardinality(v_pref.intentions) = 0 or c.intention = any (v_pref.intentions))
     and (cardinality(v_pref.interest_ids) = 0 or exists (
            select 1 from public.profile_interests pi
             where pi.user_id = c.id and pi.interest_id = any (v_pref.interest_ids)))
     and not exists (select 1 from public.swipes s where s.swiper_id = v_me and s.swipee_id = c.id)
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = v_me and b.blocked_id = c.id)
                         or (b.blocker_id = c.id and b.blocked_id = v_me))
   order by d.km nulls last, c.last_active_at desc, c.id
   limit least(greatest(coalesce(p_limit, 20), 1), 50);
end;
$$;

drop function public.get_likes_received(int, int);

create function public.get_likes_received(p_limit int default 30, p_offset int default 0)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, liked_at timestamptz,
  country_code text, is_verified boolean, zodiac text
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
         c.photos, c.interests, c.prompts, s.created_at, c.country_code, c.is_verified, c.zodiac
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

revoke all on function public.get_discovery_feed(int), public.get_likes_received(int, int) from public, anon;
grant execute on function public.get_discovery_feed(int), public.get_likes_received(int, int) to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
