-- =============================================================================
-- Admin & moderation
--
--  * country_age_rules: minimum age per country (never below 18)
--  * admins + admin_actions (audit log of every admin action)
--  * verification_requests: selfie verification reviewed by an admin
--  * app_errors: crash / error reports from the app, shown in the admin panel
--  * admin_* RPCs: every one checks private.is_admin() on the server
--
-- Make someone an admin (run once in the SQL editor):
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'you@example.com';
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Minimum age per country. The global floor of 18 can never be lowered.
-- -----------------------------------------------------------------------------
create table public.country_age_rules (
  country_code  text primary key check (country_code ~ '^[A-Z]{2}$'),
  min_age       int not null check (min_age between 18 and 25),
  note          text,
  updated_at    timestamptz not null default now()
);

-- Countries whose age of majority is above 18. Have local counsel confirm these
-- for your launch markets; admins can edit them in the admin panel.
insert into public.country_age_rules (country_code, min_age, note) values
  ('KR', 19, 'Age of majority 19'),
  ('DZ', 19, 'Age of majority 19'),
  ('TH', 20, 'Age of majority 20'),
  ('BH', 21, 'Age of majority 21'),
  ('CM', 21, 'Age of majority 21'),
  ('CI', 21, 'Age of majority 21'),
  ('EG', 21, 'Age of majority 21'),
  ('GA', 21, 'Age of majority 21'),
  ('KW', 21, 'Age of majority 21'),
  ('MG', 21, 'Age of majority 21'),
  ('SG', 21, 'Age of majority 21'),
  ('SZ', 21, 'Age of majority 21'),
  ('WS', 21, 'Age of majority 21'),
  ('AE', 21, 'Age of majority 21')
on conflict (country_code) do nothing;

alter table public.country_age_rules enable row level security;
revoke all on public.country_age_rules from anon, authenticated;
grant select on public.country_age_rules to anon, authenticated;
create policy country_age_rules_read on public.country_age_rules for select to anon, authenticated using (true);

create or replace function private.min_age_for(p_country text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(18, coalesce((select min_age from public.country_age_rules
                                 where country_code = upper(p_country)), 18));
$$;

-- Callable before sign-in so the age gate can show the right limit.
create or replace function public.min_age_for_country(p_country text)
returns int
language sql
stable
security definer
set search_path = ''
as $$ select private.min_age_for(p_country) $$;

-- Replace the fixed 18+ check with the per-country rule.
create or replace function private.enforce_adult()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_min int := private.min_age_for(new.country_code);
begin
  if private.age_on(new.birthdate) < v_min then
    raise exception 'underage: you must be at least % to use this app in your country', v_min using errcode = '23514';
  end if;
  if new.birthdate < current_date - interval '120 years' then
    raise exception 'invalid_birthdate' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger profiles_enforce_adult on public.profiles;
create trigger profiles_enforce_adult
  before insert or update of birthdate, country_code on public.profiles
  for each row execute function private.enforce_adult();

-- -----------------------------------------------------------------------------
-- Admins & audit log
-- -----------------------------------------------------------------------------
create table public.admins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.admin_actions (
  id          bigint generated always as identity primary key,
  admin_id    uuid references auth.users (id) on delete set null,
  action      text not null,
  target_user uuid,
  target_id   text,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index admin_actions_created_idx on public.admin_actions (created_at desc);

create or replace function private.is_admin(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from public.admins where user_id = p_user) $$;

create or replace function private.require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not private.is_admin(v_uid) then
    raise exception 'forbidden: admin only' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

create or replace function private.audit(p_action text, p_target_user uuid, p_target_id text, p_details jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.admin_actions (admin_id, action, target_user, target_id, details)
  values (auth.uid(), p_action, p_target_user, p_target_id, coalesce(p_details, '{}'::jsonb));
$$;

alter table public.admins enable row level security;
alter table public.admin_actions enable row level security;
revoke all on public.admins, public.admin_actions from anon, authenticated;
grant select on public.admins, public.admin_actions to authenticated;
create policy admins_read on public.admins for select to authenticated using (private.is_admin());
create policy admin_actions_read on public.admin_actions for select to authenticated using (private.is_admin());

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_admin(auth.uid()) $$;

-- Admins can read reports in realtime (reporters still only see their own).
create policy reports_admin_read on public.reports for select to authenticated using (private.is_admin());

-- -----------------------------------------------------------------------------
-- Selfie verification
-- -----------------------------------------------------------------------------
create table public.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  selfie_path   text not null check (selfie_path like user_id::text || '/%'),
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reject_reason text check (reject_reason is null or char_length(reject_reason) <= 300),
  reviewed_by   uuid references auth.users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

create unique index verification_one_pending on public.verification_requests (user_id) where status = 'pending';
create index verification_status_idx on public.verification_requests (status, created_at);

alter table public.verification_requests enable row level security;
revoke all on public.verification_requests from anon, authenticated;
grant select on public.verification_requests to authenticated;
create policy verification_own_or_admin on public.verification_requests
  for select to authenticated using (user_id = (select auth.uid()) or private.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-selfies', 'verification-selfies', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy "selfies: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-selfies'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Only admins can view selfies (not even other users).
create policy "selfies: admins can view"
  on storage.objects for select to authenticated
  using (bucket_id = 'verification-selfies' and private.is_admin());

-- Admins can view any profile photo (including suspended users) for moderation.
create policy "profile photos: admins can view"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos' and private.is_admin());

create or replace function public.request_verification(p_selfie_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_id uuid;
begin
  if not private.is_active(v_me) then
    raise exception 'profile_incomplete: finish your profile first' using errcode = 'P0001';
  end if;
  if (select is_verified from public.profiles where id = v_me) then
    raise exception 'already_verified: you are already verified' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.verification_requests where user_id = v_me and status = 'pending') then
    raise exception 'already_pending: your verification is being reviewed' using errcode = 'P0001';
  end if;
  if (select count(*) from public.verification_requests
       where user_id = v_me and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'rate_limited: try again tomorrow' using errcode = 'P0001';
  end if;
  insert into public.verification_requests (user_id, selfie_path)
  values (v_me, p_selfie_path)
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- App error reports
-- -----------------------------------------------------------------------------
create table public.app_errors (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users (id) on delete set null,
  message      text not null check (char_length(message) <= 2000),
  stack        text check (stack is null or char_length(stack) <= 8000),
  context      jsonb not null default '{}'::jsonb,
  platform     text check (platform is null or char_length(platform) <= 40),
  app_version  text check (app_version is null or char_length(app_version) <= 40),
  fingerprint  text not null,
  resolved     boolean not null default false,
  created_at   timestamptz not null default now()
);

create index app_errors_created_idx on public.app_errors (created_at desc);
create index app_errors_fingerprint_idx on public.app_errors (fingerprint, created_at desc);

alter table public.app_errors enable row level security;
revoke all on public.app_errors from anon, authenticated;
grant select on public.app_errors to authenticated;
create policy app_errors_admin_read on public.app_errors for select to authenticated using (private.is_admin());

-- Anyone (even signed out, e.g. a crash on the welcome screen) can report an
-- error, with size and rate limits.
create or replace function public.log_client_error(
  p_message text,
  p_stack text default null,
  p_context jsonb default '{}'::jsonb,
  p_platform text default null,
  p_app_version text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if p_message is null or btrim(p_message) = '' then return; end if;
  if v_uid is not null then
    if (select count(*) from public.app_errors
         where user_id = v_uid and created_at > now() - interval '1 hour') >= 30 then
      return;
    end if;
  elsif (select count(*) from public.app_errors
          where user_id is null and created_at > now() - interval '1 minute') >= 60 then
    return;
  end if;
  insert into public.app_errors (user_id, message, stack, context, platform, app_version, fingerprint)
  values (v_uid, left(p_message, 2000), left(p_stack, 8000),
          case when pg_column_size(p_context) <= 4000 then coalesce(p_context, '{}'::jsonb) else '{}'::jsonb end,
          left(p_platform, 40), left(p_app_version, 40),
          md5(left(p_message, 200) || coalesce(left(p_stack, 300), '')));
end;
$$;

-- -----------------------------------------------------------------------------
-- Admin RPCs
-- -----------------------------------------------------------------------------
create or replace function public.admin_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return jsonb_build_object(
    'users_total',          (select count(*) from public.profiles),
    'users_new_24h',        (select count(*) from public.profiles where created_at > now() - interval '24 hours'),
    'users_active_24h',     (select count(*) from public.profiles where last_active_at > now() - interval '24 hours'),
    'users_suspended',      (select count(*) from public.profiles where status = 'suspended'),
    'users_banned',         (select count(*) from public.profiles where status = 'banned'),
    'users_verified',       (select count(*) from public.profiles where is_verified),
    'matches_24h',          (select count(*) from public.matches where created_at > now() - interval '24 hours'),
    'messages_24h',         (select count(*) from public.messages where created_at > now() - interval '24 hours'),
    'likes_24h',            (select count(*) from public.swipes where action = 'like' and created_at > now() - interval '24 hours'),
    'reports_open',         (select count(*) from public.reports where status in ('open', 'reviewing')),
    'verifications_pending',(select count(*) from public.verification_requests where status = 'pending'),
    'errors_24h',           (select count(*) from public.app_errors where created_at > now() - interval '24 hours'),
    'errors_unresolved',    (select count(distinct fingerprint) from public.app_errors where not resolved),
    'signups_by_day', coalesce((
        select jsonb_agg(jsonb_build_object('day', d, 'count', n) order by d)
          from (select date_trunc('day', created_at)::date d, count(*) n
                  from public.profiles where created_at > now() - interval '14 days' group by 1) s), '[]'::jsonb),
    'users_by_country', coalesce((
        select jsonb_agg(jsonb_build_object('country', c, 'count', n) order by n desc)
          from (select coalesce(country_code, '??') c, count(*) n from public.profiles group by 1
                order by 2 desc limit 15) s), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_search_users(p_query text default '', p_status text default null, p_limit int default 50, p_offset int default 0)
returns table (
  id uuid, email text, display_name text, age int, gender text, country_code text, city text,
  status text, is_verified boolean, onboarding_completed boolean, photo text,
  reports_against bigint, created_at timestamptz, last_active_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_q text := '%' || coalesce(btrim(p_query), '') || '%';
begin
  perform private.require_admin();
  return query
  select p.id, u.email::text, p.display_name, private.age_on(p.birthdate), p.gender, p.country_code, p.city,
         p.status, p.is_verified, p.onboarding_completed,
         (select ph.storage_path from public.profile_photos ph where ph.user_id = p.id order by ph.position limit 1),
         (select count(*) from public.reports r where r.reported_id = p.id),
         p.created_at, p.last_active_at
    from public.profiles p
    join auth.users u on u.id = p.id
   where (p_status is null or p.status = p_status)
     and (coalesce(btrim(p_query), '') = ''
          or p.display_name ilike v_q or u.email ilike v_q or p.id::text = btrim(p_query))
   order by p.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_get_user(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return (
    select jsonb_build_object(
      'profile', to_jsonb(p) || jsonb_build_object('email', u.email, 'age', private.age_on(p.birthdate),
                                                   'last_sign_in_at', u.last_sign_in_at),
      'photos', coalesce((select jsonb_agg(to_jsonb(ph) order by ph.position)
                            from public.profile_photos ph where ph.user_id = p.id), '[]'::jsonb),
      'interests', coalesce((select jsonb_agg(i.name order by i.name) from public.profile_interests pi
                               join public.interests i on i.id = pi.interest_id where pi.user_id = p.id), '[]'::jsonb),
      'prompts', coalesce((select jsonb_agg(to_jsonb(pr) order by pr.position)
                             from public.profile_prompts pr where pr.user_id = p.id), '[]'::jsonb),
      'reports_against', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                     from public.reports r where r.reported_id = p.id), '[]'::jsonb),
      'reports_made', (select count(*) from public.reports r where r.reporter_id = p.id),
      'verifications', coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc)
                                   from public.verification_requests v where v.user_id = p.id), '[]'::jsonb),
      'counts', jsonb_build_object(
          'likes_sent', (select count(*) from public.swipes s where s.swiper_id = p.id and s.action = 'like'),
          'likes_received', (select count(*) from public.swipes s where s.swipee_id = p.id and s.action = 'like'),
          'matches', (select count(*) from public.matches m where p.id in (m.user_low, m.user_high)),
          'messages_sent', (select count(*) from public.messages m where m.sender_id = p.id),
          'blocked_by', (select count(*) from public.blocks b where b.blocked_id = p.id)),
      'admin_actions', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc)
                                   from public.admin_actions a where a.target_user = p.id), '[]'::jsonb)
    )
    from public.profiles p join auth.users u on u.id = p.id
   where p.id = p_user
  );
end;
$$;

create or replace function public.admin_set_user_status(p_user uuid, p_status text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if p_status not in ('active', 'suspended', 'banned') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;
  update public.profiles set status = p_status where id = p_user;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  perform private.audit('set_status:' || p_status, p_user, null, jsonb_build_object('reason', p_reason));
end;
$$;

create or replace function public.admin_set_verified(p_user uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  update public.profiles set is_verified = p_verified where id = p_user;
  perform private.audit(case when p_verified then 'verify' else 'unverify' end, p_user, null, '{}');
end;
$$;

create or replace function public.admin_list_reports(p_status text default 'open', p_limit int default 100)
returns table (
  id uuid, reason text, details text, status text, created_at timestamptz,
  reporter_id uuid, reporter_name text,
  reported_id uuid, reported_name text, reported_status text, reported_photo text,
  message_body text, open_reports_against bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_admin();
  return query
  select r.id, r.reason, r.details, r.status, r.created_at,
         r.reporter_id, rp.display_name,
         r.reported_id, tp.display_name, tp.status,
         (select ph.storage_path from public.profile_photos ph where ph.user_id = r.reported_id order by ph.position limit 1),
         m.body,
         (select count(*) from public.reports o where o.reported_id = r.reported_id and o.status in ('open', 'reviewing'))
    from public.reports r
    left join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles tp on tp.id = r.reported_id
    left join public.messages m on m.id = r.message_id
   where p_status is null or r.status = p_status
   order by r.created_at desc
   limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- Resolve a report; optionally act on the reported user at the same time.
create or replace function public.admin_resolve_report(p_report uuid, p_status text, p_user_action text default null, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reported uuid;
begin
  perform private.require_admin();
  if p_status not in ('reviewing', 'actioned', 'dismissed') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;
  update public.reports set status = p_status where id = p_report returning reported_id into v_reported;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_user_action is not null and v_reported is not null then
    perform public.admin_set_user_status(v_reported, p_user_action, p_note);
  end if;
  perform private.audit('report:' || p_status, v_reported, p_report::text,
                        jsonb_build_object('user_action', p_user_action, 'note', p_note));
end;
$$;

create or replace function public.admin_list_verifications(p_status text default 'pending')
returns table (
  id uuid, user_id uuid, display_name text, age int, country_code text, selfie_path text,
  photos text[], status text, reject_reason text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_admin();
  return query
  select v.id, v.user_id, p.display_name, private.age_on(p.birthdate), p.country_code, v.selfie_path,
         coalesce((select array_agg(ph.storage_path order by ph.position)
                     from public.profile_photos ph where ph.user_id = p.id), '{}'),
         v.status, v.reject_reason, v.created_at
    from public.verification_requests v
    join public.profiles p on p.id = v.user_id
   where p_status is null or v.status = p_status
   order by v.created_at
   limit 200;
end;
$$;

create or replace function public.admin_review_verification(p_request uuid, p_approve boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  perform private.require_admin();
  update public.verification_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         reject_reason = case when p_approve then null else p_reason end,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request and status = 'pending'
  returning user_id into v_user;
  if v_user is null then raise exception 'not_found: already reviewed' using errcode = 'P0001'; end if;
  if p_approve then
    update public.profiles set is_verified = true where id = v_user;
  end if;
  perform private.audit(case when p_approve then 'verification:approve' else 'verification:reject' end,
                        v_user, p_request::text, jsonb_build_object('reason', p_reason));
end;
$$;

-- Remove an inappropriate photo (the file is removed by the admin panel through Storage).
create or replace function public.admin_delete_photo(p_photo uuid, p_reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path text;
  v_user uuid;
begin
  perform private.require_admin();
  delete from public.profile_photos where id = p_photo returning storage_path, user_id into v_path, v_user;
  if v_path is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  perform private.audit('photo:delete', v_user, v_path, jsonb_build_object('reason', p_reason));
  return v_path;
end;
$$;

create or replace function public.admin_recent_photos(p_limit int default 60, p_before timestamptz default null)
returns table (id uuid, user_id uuid, display_name text, status text, storage_path text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_admin();
  return query
  select ph.id, ph.user_id, p.display_name, p.status, ph.storage_path, ph.created_at
    from public.profile_photos ph join public.profiles p on p.id = ph.user_id
   where p_before is null or ph.created_at < p_before
   order by ph.created_at desc
   limit least(greatest(coalesce(p_limit, 60), 1), 200);
end;
$$;

create or replace function public.admin_list_errors(p_include_resolved boolean default false)
returns table (
  fingerprint text, message text, stack text, platform text, app_version text,
  occurrences bigint, users bigint, first_seen timestamptz, last_seen timestamptz, resolved boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_admin();
  return query
  select e.fingerprint,
         (array_agg(e.message order by e.created_at desc))[1],
         (array_agg(e.stack order by e.created_at desc))[1],
         (array_agg(e.platform order by e.created_at desc))[1],
         (array_agg(e.app_version order by e.created_at desc))[1],
         count(*), count(distinct e.user_id), min(e.created_at), max(e.created_at), bool_and(e.resolved)
    from public.app_errors e
   where p_include_resolved or not e.resolved
   group by e.fingerprint
   order by max(e.created_at) desc
   limit 200;
end;
$$;

create or replace function public.admin_resolve_error(p_fingerprint text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  update public.app_errors set resolved = true where fingerprint = p_fingerprint;
  perform private.audit('error:resolve', null, p_fingerprint, '{}');
end;
$$;

create or replace function public.admin_upsert_age_rule(p_country text, p_min_age int, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if p_min_age < 18 then
    raise exception 'invalid_age: the minimum age can never be below 18' using errcode = 'P0001';
  end if;
  insert into public.country_age_rules (country_code, min_age, note, updated_at)
  values (upper(p_country), p_min_age, p_note, now())
  on conflict (country_code) do update set min_age = excluded.min_age, note = excluded.note, updated_at = now();
  perform private.audit('age_rule:set', null, upper(p_country), jsonb_build_object('min_age', p_min_age));
end;
$$;

create or replace function public.admin_delete_age_rule(p_country text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  delete from public.country_age_rules where country_code = upper(p_country);
  perform private.audit('age_rule:delete', null, upper(p_country), '{}');
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke all on all functions in schema public from public, anon;
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema private to authenticated, service_role;
-- Callable before signing in:
grant execute on function public.min_age_for_country(text) to anon;
grant execute on function public.log_client_error(text, text, jsonb, text, text) to anon;

-- Realtime for the admin panel (RLS limits these to admins).
alter publication supabase_realtime add table public.reports;
alter publication supabase_realtime add table public.app_errors;
alter publication supabase_realtime add table public.verification_requests;
