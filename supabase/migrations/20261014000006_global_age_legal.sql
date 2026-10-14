-- =============================================================================
-- Worldwide support, age assurance and legal consent
--
--  * profiles.country_code (ISO 3166-1 alpha-2) + discovery country filter
--  * "Anywhere" distance (max_distance_km = 20000)
--  * Distance pre-filter that works across the 180° meridian (Fiji, NZ, Alaska…)
--  * Legal consent records (terms, privacy, guidelines, 18+), required to finish onboarding
--  * Birthdate must match the one given at the sign-up age gate
--  * Profiles reported as under 18 by 2+ different people are hidden pending review
--  * is_verified flag, written only by the server (ID-verification provider webhook)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Country
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  add column is_verified boolean not null default false;

grant insert (country_code) on public.profiles to authenticated;
grant update (country_code) on public.profiles to authenticated;

alter table public.discovery_preferences
  add column country_codes text[] not null default '{}'
    check (cardinality(country_codes) <= 30
           and array_to_string(country_codes, ',') ~ '^([A-Z]{2}(,[A-Z]{2})*)?$');

-- 20000 km ≈ half the Earth's circumference = "Anywhere".
alter table public.discovery_preferences
  drop constraint discovery_preferences_max_distance_km_check,
  add constraint discovery_preferences_max_distance_km_check check (max_distance_km between 1 and 20000);

grant update (country_codes) on public.discovery_preferences to authenticated;

-- -----------------------------------------------------------------------------
-- Legal consent
-- -----------------------------------------------------------------------------
create table public.legal_acceptances (
  user_id      uuid not null references auth.users (id) on delete cascade,
  document     text not null check (document in ('terms', 'privacy', 'guidelines', 'age_18')),
  version      text not null,
  accepted_at  timestamptz not null default now(),
  primary key (user_id, document, version)
);

alter table public.legal_acceptances enable row level security;
revoke all on public.legal_acceptances from anon, authenticated;
grant select on public.legal_acceptances to authenticated;
create policy legal_acceptances_select_own on public.legal_acceptances
  for select to authenticated using (user_id = (select auth.uid()));

-- Bump this (and the app's LegalDocs.version) whenever the documents change;
-- users are then asked to accept again.
create or replace function private.current_legal_version()
returns text
language sql
immutable
set search_path = ''
as $$ select '2026-10-14' $$;

create or replace function public.accept_legal_documents(p_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  if p_version is distinct from private.current_legal_version() then
    raise exception 'outdated_terms: please update the app' using errcode = 'P0001';
  end if;
  insert into public.legal_acceptances (user_id, document, version)
  select v_me, d, p_version from unnest(array['terms', 'privacy', 'guidelines', 'age_18']) d
  on conflict do nothing;
end;
$$;

create or replace function public.has_accepted_legal()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) = 4 from public.legal_acceptances
   where user_id = auth.uid() and version = private.current_legal_version();
$$;

-- -----------------------------------------------------------------------------
-- Age gate consistency: the birthdate entered at sign-up (stored in the auth
-- user's metadata) must match the profile birthdate, so someone turned away
-- at the gate can't simply type a different date later.
-- -----------------------------------------------------------------------------
create or replace function private.enforce_gate_birthdate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gate text;
begin
  select u.raw_user_meta_data ->> 'birthdate' into v_gate from auth.users u where u.id = new.id;
  if v_gate is not null and v_gate <> '' and v_gate::date <> new.birthdate then
    raise exception 'birthdate_mismatch: birthday must match the one you entered when signing up'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger profiles_gate_birthdate
  before insert on public.profiles
  for each row execute function private.enforce_gate_birthdate();

-- Onboarding now also requires accepted legal documents.
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
  if (select count(*) from public.legal_acceptances
       where user_id = v_me and version = private.current_legal_version()) < 4 then
    raise exception 'consent_required: please accept the terms, privacy policy and guidelines'
      using errcode = 'P0001';
  end if;
  update public.profiles
     set onboarding_completed = true, last_active_at = now()
   where id = v_me;
end;
$$;

-- -----------------------------------------------------------------------------
-- Underage reports: 2+ distinct reporters → profile suspended pending review.
-- -----------------------------------------------------------------------------
create or replace function private.auto_suspend_underage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reason = 'underage' and new.reported_id is not null and (
       select count(distinct r.reporter_id) from public.reports r
        where r.reported_id = new.reported_id and r.reason = 'underage' and r.status = 'open'
     ) >= 2 then
    update public.profiles set status = 'suspended'
     where id = new.reported_id and status = 'active';
  end if;
  return new;
end;
$$;

create trigger reports_auto_suspend_underage
  after insert on public.reports
  for each row execute function private.auto_suspend_underage();

-- -----------------------------------------------------------------------------
-- Profile projections gain country + verification (columns appended).
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
  p.last_active_at,
  p.country_code,
  p.is_verified
from public.profiles p;

create or replace view public.public_profiles
with (security_barrier = true)
as
select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
       c.photos, c.interests, c.prompts, c.country_code, c.is_verified
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
-- Discovery feed v2: country filter, "Anywhere", antimeridian-safe box.
-- -----------------------------------------------------------------------------
drop function public.get_discovery_feed(int);

create function public.get_discovery_feed(p_limit int default 20)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb, distance_km int,
  country_code text, is_verified boolean
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
         c.country_code, c.is_verified
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
  country_code text, is_verified boolean
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
         c.photos, c.interests, c.prompts, s.created_at, c.country_code, c.is_verified
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

-- Privileges for new / recreated functions (Supabase grants new functions to
-- anon by default; revoke that again).
revoke all on function
  public.get_discovery_feed(int),
  public.get_likes_received(int, int),
  public.accept_legal_documents(text),
  public.has_accepted_legal(),
  public.complete_onboarding()
from public, anon;
grant execute on function
  public.get_discovery_feed(int),
  public.get_likes_received(int, int),
  public.accept_legal_documents(text),
  public.has_accepted_legal(),
  public.complete_onboarding()
to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
