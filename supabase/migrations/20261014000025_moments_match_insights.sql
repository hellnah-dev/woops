-- =============================================================================
-- Moments (24-hour updates for your matches) and match insights.
--
--  * A moment is a short line of text or a photo. Only the author and their
--    active matches can see it, never anyone blocked either way, and only for
--    24 hours. Photos live in the private `moments` bucket, count toward the
--    5 MB media allowance, and are deleted once the moment expires.
--  * There is no public feed and no "seen" tracking on the server: the phone
--    remembers which moments it has shown.
--  * `get_match_insights()`: for each active match, their mode (intention),
--    the interests you share, and a rounded distance, for the Matches tab.
-- =============================================================================

create table public.moments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  body        text check (body is null or char_length(body) between 1 and 200),
  photo_path  text,
  -- Background colour of a text-only moment (index into the app's palette).
  style       smallint not null default 0 check (style between 0 and 5),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours',
  check (btrim(coalesce(body, '')) <> '' or photo_path is not null)
);
create index moments_user_active_idx on public.moments (user_id, expires_at desc);
create index moments_photo_idx on public.moments (photo_path) where photo_path is not null;

-- Only through the functions below.
alter table public.moments enable row level security;
revoke all on public.moments from anon, authenticated;

-- May `p_viewer` see `p_author`'s moments? Themself, or an active,
-- unblocked match.
create or replace function private.can_see_moments(p_author uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_viewer is not null and (
    p_author = p_viewer
    or (exists (select 1 from public.matches m
                 where m.user_low = least(p_author, p_viewer)
                   and m.user_high = greatest(p_author, p_viewer)
                   and m.unmatched_at is null)
        and private.is_active(p_author)
        and not private.is_blocked_between(p_author, p_viewer))
  );
$$;
revoke all on function private.can_see_moments(uuid, uuid) from public, anon;
grant execute on function private.can_see_moments(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Storage: private `moments` bucket, `<author>/<file>`
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('moments', 'moments', false, 1048576, array['image/jpeg', 'image/webp', 'image/png'])
on conflict (id) do nothing;

create policy "moments: author uploads into own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'moments' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Is `p_name` the photo of a live moment that `p_viewer` may see? (Security
-- definer: storage policies run as the caller, who can't read the table.)
create or replace function private.moment_photo_visible(p_name text, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.moments mo
                  where mo.photo_path = p_name
                    and mo.expires_at > now()
                    and private.can_see_moments(mo.user_id, p_viewer));
$$;
revoke all on function private.moment_photo_visible(text, uuid) from public, anon;
grant execute on function private.moment_photo_visible(text, uuid) to authenticated;

-- A photo can be read only while its moment is live, by people who may see it.
create policy "moments: visible while live"
  on storage.objects for select to authenticated
  using (bucket_id = 'moments'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or private.moment_photo_visible(name, (select auth.uid()))));

create policy "moments: author deletes own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'moments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "moments: admins can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'moments' and private.is_admin());

-- Moments photos count toward the same 5 MB per person.
create or replace function private.media_bytes(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(coalesce((o.metadata ->> 'size')::bigint, 0)), 0)::bigint
    from storage.objects o
   where o.bucket_id in ('profile-photos', 'chat-media', 'moments')
     and (storage.foldername(o.name))[1] = p_user::text;
$$;

drop policy "media allowance: 5 MB per person" on storage.objects;
create policy "media allowance: 5 MB per person"
  on storage.objects as restrictive for insert to authenticated
  with check (bucket_id not in ('profile-photos', 'chat-media', 'moments')
              or private.media_bytes((select auth.uid())) < 5242880);

-- Scheduled/admin cleanup also removes expired moment photos and leftovers
-- of deleted accounts in the moments bucket.
create or replace function private.claim_expired_proofs()
returns table (bucket text, path text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.age_verifications
     set status = 'rejected', document_path = null, reviewed_at = now(),
         reject_reason = 'Not reviewed within 7 days. Please send your ID again.'
   where status = 'pending' and created_at < now() - interval '7 days';
  update public.verification_requests
     set status = 'rejected', selfie_path = null, reviewed_at = now(),
         reject_reason = 'Not reviewed within 7 days. Please take a new selfie.'
   where status = 'pending' and created_at < now() - interval '7 days';
  delete from public.moments where expires_at < now() - interval '1 hour';

  return query
  select o.bucket_id::text, o.name::text
    from storage.objects o
   where (o.bucket_id in ('id-documents', 'verification-selfies') and o.created_at < now() - interval '7 days')
      or (o.bucket_id = 'chat-media' and o.created_at < now() - interval '30 days')
      -- A moment photo with no live moment (expired, deleted, or never posted).
      or (o.bucket_id = 'moments' and o.created_at < now() - interval '1 hour'
          and not exists (select 1 from public.moments mo where mo.photo_path = o.name and mo.expires_at > now()))
      -- Leftovers of deleted accounts (older than an hour, so uploads in progress are safe).
      or (o.bucket_id in ('profile-photos', 'chat-media', 'id-documents', 'verification-selfies')
          and o.created_at < now() - interval '1 hour'
          and not exists (select 1 from public.profiles p
                           where p.id::text = (storage.foldername(o.name))[1]))
   order by o.created_at
   limit 1000;
end;
$$;
revoke all on function private.claim_expired_proofs() from public, anon;

-- -----------------------------------------------------------------------------
-- Moments API
-- -----------------------------------------------------------------------------
create or replace function public.post_moment(p_body text default null, p_photo_path text default null,
                                              p_style int default 0)
returns public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_row public.moments;
begin
  if not private.is_active(v_me) then
    raise exception 'forbidden: your account can''t post right now' using errcode = 'P0001';
  end if;
  if v_body is null and p_photo_path is null then
    raise exception 'empty_moment: add a photo or a few words' using errcode = 'P0001';
  end if;
  if char_length(coalesce(v_body, '')) > 200 then
    raise exception 'moment_too_long: keep it under 200 characters' using errcode = 'P0001';
  end if;
  if p_photo_path is not null and (p_photo_path not like v_me::text || '/%' or p_photo_path like '%..%') then
    raise exception 'invalid_media' using errcode = 'P0001';
  end if;
  if (select count(*) from public.moments where user_id = v_me and expires_at > now()) >= 3 then
    raise exception 'moment_limit: you can have 3 moments at a time. Delete one to add another.' using errcode = 'P0001';
  end if;
  if (select count(*) from public.moments where user_id = v_me and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'rate_limited: that''s enough moments for today' using errcode = 'P0001';
  end if;

  insert into public.moments (user_id, body, photo_path, style)
  values (v_me, v_body, p_photo_path, least(greatest(coalesce(p_style, 0), 0), 5))
  returning * into v_row;
  return v_row;
end;
$$;

-- Live moments I can see: mine first, then my matches' (newest first).
create or replace function public.get_moments()
returns table (
  id uuid, user_id uuid, display_name text, avatar text, body text, photo_path text, style int,
  created_at timestamptz, expires_at timestamptz, is_mine boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select mo.id, mo.user_id, p.display_name,
         (select ph.storage_path from public.profile_photos ph
           where ph.user_id = mo.user_id order by ph.position limit 1),
         mo.body, mo.photo_path, mo.style::int, mo.created_at, mo.expires_at,
         mo.user_id = (select auth.uid())
    from public.moments mo
    join public.profiles p on p.id = mo.user_id
   where mo.expires_at > now()
     and private.can_see_moments(mo.user_id, (select auth.uid()))
   order by (mo.user_id = (select auth.uid())) desc, mo.created_at desc
   limit 300;
$$;

-- Deletes one of my moments; returns its photo path so the phone removes the file.
create or replace function public.delete_moment(p_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path text;
begin
  delete from public.moments where id = p_id and user_id = private.require_user()
  returning photo_path into v_path;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return v_path;
end;
$$;

-- My expired moments: removed, with their photo paths returned so the phone
-- deletes the files (freeing media space straight away).
create or replace function public.claim_my_expired_moments()
returns setof text
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from public.moments
     where user_id = (select auth.uid()) and expires_at <= now()
    returning photo_path
  )
  select photo_path from gone where photo_path is not null;
$$;

-- -----------------------------------------------------------------------------
-- Match insights: mode, shared interests, distance
-- -----------------------------------------------------------------------------
create or replace function public.get_match_insights()
returns table (other_user_id uuid, intention text, shared_interests text[], distance_km int)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select (select auth.uid()) as id),
  others as (
    select case when m.user_low = me.id then m.user_high else m.user_low end as uid
      from public.matches m, me
     where me.id in (m.user_low, m.user_high) and m.unmatched_at is null
  )
  select o.uid,
         p.intention,
         coalesce((select array_agg(i.name order by i.name)
                     from public.profile_interests a
                     join public.profile_interests b on b.interest_id = a.interest_id and b.user_id = o.uid
                     join public.interests i on i.id = a.interest_id
                    where a.user_id = (select id from me)), '{}'),
         (select greatest(1, ceil(private.distance_km(la.lat, la.lng, lb.lat, lb.lng)))::int
            from public.profile_locations la, public.profile_locations lb
           where la.user_id = (select id from me) and lb.user_id = o.uid)
    from others o
    join public.profiles p on p.id = o.uid
   where not private.is_blocked_between(o.uid, (select id from me))
   limit 1000;
$$;

revoke all on function
  public.post_moment(text, text, int), public.get_moments(), public.delete_moment(uuid),
  public.claim_my_expired_moments(), public.get_match_insights()
from public, anon;
grant execute on function
  public.post_moment(text, text, int), public.get_moments(), public.delete_moment(uuid),
  public.claim_my_expired_moments(), public.get_match_insights()
to authenticated;
