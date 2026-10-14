-- =============================================================================
-- Usernames + hashed ban list
--
--  * profiles.username: unique @handle (lowercase a-z, 0-9, _ and ., 3–20 chars)
--    Uniqueness is enforced by a UNIQUE index, which is exact (no false
--    positives) and O(log n). A Bloom filter is not used here on purpose.
--  * banned_identifiers: SHA-256 hashes of banned users' emails/usernames, so
--    banned people can't sign up again with the same email or take back their
--    username, without keeping those values in plain text after deletion.
--    Uses Postgres's built-in sha256(); no extension required.
-- =============================================================================

alter table public.profiles
  add column username text check (username is null or username ~ '^[a-z0-9_.]{3,20}$');

create unique index profiles_username_key on public.profiles (username);

grant insert (username) on public.profiles to authenticated;
grant update (username) on public.profiles to authenticated;

create table public.banned_identifiers (
  hash        text primary key check (hash ~ '^[0-9a-f]{64}$'),
  kind        text not null check (kind in ('email', 'username')),
  reason      text,
  created_at  timestamptz not null default now()
);

alter table public.banned_identifiers enable row level security;
revoke all on public.banned_identifiers from anon, authenticated;

create or replace function private.identifier_hash(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to('woops:' || lower(btrim(p_value)), 'UTF8')), 'hex');
$$;

create or replace function private.is_reserved_username(p_username text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(p_username) = any (array[
    'admin', 'administrator', 'root', 'support', 'help', 'woops', 'official', 'moderator', 'mod',
    'staff', 'team', 'security', 'system', 'null', 'undefined', 'api', 'www', 'about', 'privacy', 'terms'
  ]);
$$;

-- Runs on profile insert/update: username rules + banned email/username.
create or replace function private.enforce_identity_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  if new.username is not null then
    new.username := lower(new.username);
    if private.is_reserved_username(new.username) then
      raise exception 'username_unavailable: that username is reserved' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.banned_identifiers
                where hash = private.identifier_hash(new.username) and kind = 'username') then
      raise exception 'username_unavailable: that username isn''t available' using errcode = 'P0001';
    end if;
  end if;

  if tg_op = 'INSERT' then
    select email into v_email from auth.users where id = new.id;
    if v_email is not null and exists (select 1 from public.banned_identifiers
                                        where hash = private.identifier_hash(v_email) and kind = 'email') then
      raise exception 'banned: this account can''t use Woops' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_identity_rules
  before insert or update of username on public.profiles
  for each row execute function private.enforce_identity_rules();

-- Live availability check for the username field.
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_username ~ '^[a-zA-Z0-9_.]{3,20}$'
     and not private.is_reserved_username(p_username)
     and not exists (select 1 from public.banned_identifiers
                      where hash = private.identifier_hash(p_username) and kind = 'username')
     and not exists (select 1 from public.profiles
                      where username = lower(p_username) and id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'));
$$;

-- Banning now also records hashed identifiers.
create or replace function public.admin_set_user_status(p_user uuid, p_status text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_username text;
begin
  perform private.require_admin();
  if p_status not in ('active', 'suspended', 'banned') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;
  update public.profiles set status = p_status where id = p_user returning username into v_username;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;

  if p_status = 'banned' then
    select email into v_email from auth.users where id = p_user;
    insert into public.banned_identifiers (hash, kind, reason)
    select h, k, p_reason from (values
      (private.identifier_hash(v_email), 'email'),
      (private.identifier_hash(v_username), 'username')) t(h, k)
    where h is not null
    on conflict (hash) do nothing;
  elsif p_status = 'active' then
    -- Lifting a ban also clears the hashes.
    select email into v_email from auth.users where id = p_user;
    delete from public.banned_identifiers
     where hash in (private.identifier_hash(v_email), private.identifier_hash(v_username));
  end if;
  perform private.audit('set_status:' || p_status, p_user, null, jsonb_build_object('reason', p_reason));
end;
$$;

-- Usernames on profile projections (columns appended).
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
  p.username
from public.profiles p;

create or replace view public.public_profiles
with (security_barrier = true)
as
select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
       c.photos, c.interests, c.prompts, c.country_code, c.is_verified, c.username
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

revoke all on all functions in schema public from public, anon;
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema private to authenticated, service_role;
grant execute on function public.min_age_for_country(text) to anon;
grant execute on function public.log_client_error(text, text, jsonb, text, text) to anon;
