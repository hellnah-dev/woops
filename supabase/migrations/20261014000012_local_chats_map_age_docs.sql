-- =============================================================================
-- v3: chats on the phone, map view, ID-document age review, "ready to date".
--
--  * Messages are no longer kept on the server. `public.messages` becomes a
--    short-lived relay (like WhatsApp): a message waits there only until the
--    recipient's phone downloads it and calls `ack_messages()`, which deletes
--    it. Undelivered messages are purged after 30 days. Chat history lives
--    only on each person's phone. Matches ("connects") stay on the server.
--  * Rate limits use `message_send_log` (sender + time only, no content).
--  * Reports carry a copy of the reported message, since the server no longer has it.
--  * `get_map_people()`: approximate positions (~2 km grid) for the map.
--  * `age_verifications` + private `id-documents` bucket: ID review by admins,
--    using the country's minimum age. Documents are deleted after review.
--  * `private.profile_ready()`: photos, bio, interests and an ID document are
--    required before someone can like or pass (enforced by trigger on swipes).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Message relay
-- -----------------------------------------------------------------------------
create table public.message_send_log (
  sender_id   uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index message_send_log_idx on public.message_send_log (sender_id, created_at desc);
alter table public.message_send_log enable row level security;
revoke all on public.message_send_log from anon, authenticated;

create index if not exists messages_created_idx on public.messages (created_at);

-- Drops undelivered messages older than 30 days and send-log rows older than a day.
create or replace function private.purge_message_relay()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.messages where created_at < now() - interval '30 days';
  delete from public.message_send_log where created_at < now() - interval '1 day';
  return null;
end;
$$;

create trigger messages_purge_relay
  after insert on public.messages
  for each statement execute function private.purge_message_relay();

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

  -- Idempotency while the message is still waiting for delivery. After that
  -- the recipient's phone de-duplicates by client id.
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

  if (select count(*) from public.message_send_log
       where sender_id = v_me and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited: you are sending messages too quickly' using errcode = 'P0001';
  end if;
  if (select count(*) from public.message_send_log
       where sender_id = v_me and created_at > now() - interval '24 hours') >= 1000 then
    raise exception 'rate_limited: daily message limit reached' using errcode = 'P0001';
  end if;

  insert into public.messages (conversation_id, sender_id, client_id, kind, body, media_path)
  values (p_conversation_id, v_me, p_client_id, 'text', p_body, null)
  on conflict (sender_id, client_id) do nothing
  returning * into v_msg;

  if v_msg.id is null then
    select * into v_msg from public.messages where sender_id = v_me and client_id = p_client_id;
  else
    insert into public.message_send_log (sender_id) values (v_me);
  end if;

  update public.conversations set last_message_at = v_msg.created_at where id = p_conversation_id;
  update public.conversation_members
     set last_read_at = v_msg.created_at
   where conversation_id = p_conversation_id and user_id = v_me;

  return v_msg;
end;
$$;

-- Messages waiting for me in any conversation (oldest first).
create or replace function public.get_pending_messages(p_limit int default 500)
returns setof public.messages
language sql
stable
security definer
set search_path = ''
as $$
  select msg.*
    from public.messages msg
    join public.conversation_members cm
      on cm.conversation_id = msg.conversation_id and cm.user_id = (select auth.uid())
   where msg.sender_id <> (select auth.uid())
     and msg.deleted_at is null
   order by msg.created_at, msg.id
   limit least(greatest(coalesce(p_limit, 500), 1), 1000);
$$;

-- My phone has saved these messages: remove them from the relay.
create or replace function public.ack_messages(p_ids uuid[])
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_n int;
begin
  if p_ids is null or cardinality(p_ids) = 0 then return 0; end if;
  if cardinality(p_ids) > 1000 then
    raise exception 'invalid_request: too many ids' using errcode = 'P0001';
  end if;
  delete from public.messages msg
   where msg.id = any (p_ids)
     and msg.sender_id <> v_me
     and private.is_conversation_member(msg.conversation_id, v_me);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Conversations now come from the server without message content; the phone
-- fills in the last message and unread count from its own storage.
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
         null::uuid, null::text, null::text, null::uuid, cv.last_message_at,
         (select count(*) from public.messages msg
           where msg.conversation_id = cv.id and msg.sender_id <> v_me and msg.deleted_at is null)::int
    from public.matches m
    join public.conversations cv on cv.match_id = m.id
    join public.conversation_members cm on cm.conversation_id = cv.id and cm.user_id = v_me
    join public.profiles o on o.id = case when m.user_low = v_me then m.user_high else m.user_low end
   where v_me in (m.user_low, m.user_high)
     and m.unmatched_at is null
     and o.status = 'active'
     and not private.is_blocked_between(v_me, o.id)
   order by coalesce(cv.last_message_at, m.created_at) desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Unmatching or blocking clears anything still waiting in the relay.
create or replace function private.clear_relay_on_unmatch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.unmatched_at is not null and old.unmatched_at is null then
    delete from public.messages msg
     using public.conversations cv
     where cv.match_id = new.id and msg.conversation_id = cv.id;
  end if;
  return new;
end;
$$;

create trigger matches_clear_relay
  after update of unmatched_at on public.matches
  for each row execute function private.clear_relay_on_unmatch();

-- -----------------------------------------------------------------------------
-- Reports: keep a copy of the reported message (the reporter shares it).
-- -----------------------------------------------------------------------------
alter table public.reports add column message_body text
  check (message_body is null or char_length(message_body) <= 2000);

drop function public.report_user(uuid, text, text, uuid);

create function public.report_user(
  p_target uuid,
  p_reason text,
  p_details text default null,
  p_message_body text default null
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
  if p_message_body is not null and char_length(p_message_body) > 2000 then
    raise exception 'invalid_message' using errcode = 'P0001';
  end if;
  if (select count(*) from public.reports
       where reporter_id = v_me and created_at > now() - interval '24 hours') >= 20 then
    raise exception 'rate_limited: too many reports today' using errcode = 'P0001';
  end if;

  insert into public.reports (reporter_id, reported_id, reason, details, message_body)
  values (v_me, p_target, p_reason, nullif(btrim(p_details), ''), nullif(btrim(p_message_body), ''))
  returning id into v_id;
  return v_id;
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
         coalesce(r.message_body, m.body),
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

-- -----------------------------------------------------------------------------
-- Map: people from my discovery feed at an approximate position. Positions are
-- snapped to a ~2.2 km grid (0.02°), and only for people who show distance.
-- -----------------------------------------------------------------------------
create or replace function public.get_map_people(p_limit int default 40)
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

-- My own saved (rounded) position, to centre the map.
create or replace function public.get_my_location()
returns table (lat float8, lng float8, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select l.lat, l.lng, l.updated_at from public.profile_locations l where l.user_id = (select auth.uid());
$$;

-- -----------------------------------------------------------------------------
-- Age verification with an ID document
-- -----------------------------------------------------------------------------
alter table public.profiles add column age_verified boolean not null default false;

create table public.age_verifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  country_code   text not null check (country_code ~ '^[A-Z]{2}$'),
  document_type  text not null check (char_length(document_type) between 2 and 60),
  -- Null once the document has been deleted after review.
  document_path  text check (document_path is null or document_path like user_id::text || '/%'),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reject_reason  text check (reject_reason is null or char_length(reject_reason) <= 300),
  reviewed_by    uuid references auth.users (id) on delete set null,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now()
);

create unique index age_verifications_one_pending on public.age_verifications (user_id) where status = 'pending';
create index age_verifications_status_idx on public.age_verifications (status, created_at);

alter table public.age_verifications enable row level security;
revoke all on public.age_verifications from anon, authenticated;
grant select (id, user_id, country_code, document_type, status, reject_reason, reviewed_at, created_at)
  on public.age_verifications to authenticated;
create policy age_verifications_own_or_admin on public.age_verifications
  for select to authenticated using (user_id = (select auth.uid()) or private.is_admin());

alter publication supabase_realtime add table public.age_verifications;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('id-documents', 'id-documents', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy "id documents: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'id-documents'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "id documents: admins can view"
  on storage.objects for select to authenticated
  using (bucket_id = 'id-documents' and private.is_admin());

create policy "id documents: admins can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'id-documents' and private.is_admin());

create or replace function public.submit_age_verification(p_document_type text, p_document_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_country text;
  v_id uuid;
begin
  select country_code into v_country from public.profiles where id = v_me;
  if v_country is null then
    raise exception 'profile_incomplete: choose your country first' using errcode = 'P0001';
  end if;
  if (select age_verified from public.profiles where id = v_me) then
    raise exception 'already_verified: your age is already confirmed' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.age_verifications where user_id = v_me and status = 'pending') then
    raise exception 'already_pending: your document is being reviewed' using errcode = 'P0001';
  end if;
  if (select count(*) from public.age_verifications
       where user_id = v_me and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'rate_limited: try again tomorrow' using errcode = 'P0001';
  end if;
  insert into public.age_verifications (user_id, country_code, document_type, document_path)
  values (v_me, v_country, btrim(p_document_type), p_document_path)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_list_age_verifications(p_status text default 'pending')
returns table (
  id uuid, user_id uuid, display_name text, birthdate date, age int, country_code text, min_age int,
  document_type text, document_path text, photo text, status text, reject_reason text, created_at timestamptz
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
  select v.id, v.user_id, p.display_name, p.birthdate, private.age_on(p.birthdate), v.country_code,
         private.min_age_for(v.country_code), v.document_type, v.document_path,
         (select ph.storage_path from public.profile_photos ph where ph.user_id = p.id order by ph.position limit 1),
         v.status, v.reject_reason, v.created_at
    from public.age_verifications v
    join public.profiles p on p.id = v.user_id
   where p_status is null or v.status = p_status
   order by v.created_at
   limit 200;
end;
$$;

-- Returns the document path so the admin panel can delete the file.
create or replace function public.admin_review_age_verification(p_request uuid, p_approve boolean, p_reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_path text;
begin
  perform private.require_admin();
  select user_id, document_path into v_user, v_path
    from public.age_verifications where id = p_request and status = 'pending';
  if v_user is null then raise exception 'not_found: already reviewed' using errcode = 'P0001'; end if;
  update public.age_verifications
     set status = case when p_approve then 'approved' else 'rejected' end,
         reject_reason = case when p_approve then null else p_reason end,
         reviewed_by = auth.uid(), reviewed_at = now(), document_path = null
   where id = p_request;
  update public.profiles set age_verified = p_approve where id = v_user;
  perform private.audit(case when p_approve then 'age:approve' else 'age:reject' end,
                        v_user, p_request::text, jsonb_build_object('reason', p_reason));
  return v_path;
end;
$$;

-- -----------------------------------------------------------------------------
-- "Ready to date": a complete profile is required before liking or passing.
-- -----------------------------------------------------------------------------
create or replace function private.profile_ready(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
     where p.id = p_user
       and char_length(btrim(p.bio)) > 0
       and (select count(*) from public.profile_photos ph where ph.user_id = p.id) >= 2
       and (select count(*) from public.profile_interests pi where pi.user_id = p.id) >= 3
       and (p.age_verified or exists (
              select 1 from public.age_verifications v where v.user_id = p.id and v.status = 'pending'))
  );
$$;

create or replace function private.require_profile_ready()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.profile_ready(new.swiper_id) then
    raise exception 'profile_not_ready: complete your profile to start matching' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger swipes_require_profile_ready
  before insert on public.swipes
  for each row execute function private.require_profile_ready();

-- Explicit grants only (a blanket grant would re-open service-role-only
-- functions such as grant_ad_reward).
revoke all on function
  public.send_message(uuid, text, uuid, text, text),
  public.get_pending_messages(int),
  public.ack_messages(uuid[]),
  public.get_my_conversations(int, int),
  public.report_user(uuid, text, text, text),
  public.admin_list_reports(text, int),
  public.get_map_people(int),
  public.get_my_location(),
  public.submit_age_verification(text, text),
  public.admin_list_age_verifications(text),
  public.admin_review_age_verification(uuid, boolean, text)
from public, anon;
grant execute on function
  public.send_message(uuid, text, uuid, text, text),
  public.get_pending_messages(int),
  public.ack_messages(uuid[]),
  public.get_my_conversations(int, int),
  public.report_user(uuid, text, text, text),
  public.admin_list_reports(text, int),
  public.get_map_people(int),
  public.get_my_location(),
  public.submit_age_verification(text, text),
  public.admin_list_age_verifications(text),
  public.admin_review_age_verification(uuid, boolean, text)
to authenticated;

revoke all on function
  private.purge_message_relay(),
  private.clear_relay_on_unmatch(),
  private.profile_ready(uuid),
  private.require_profile_ready()
from public, anon;
grant execute on function private.profile_ready(uuid), private.require_profile_ready() to authenticated, service_role;
