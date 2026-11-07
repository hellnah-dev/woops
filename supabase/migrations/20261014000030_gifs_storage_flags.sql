-- =============================================================================
-- GIFs instead of photos in chat, a smaller media allowance, and private
-- green/red flags.
--
--  * Chats are GIF-only, like Tinder: a GIF message carries the GIF's GIPHY
--    link (end-to-end encrypted like text). New photo/video messages are
--    refused; ones already on phones still open.
--  * Media allowance per person: 3 MB (was 5): profile and moment photos.
--  * Flags: someone you matched with and exchanged at least one message with
--    can give you a green or a red flag (one each way, changeable). Only you
--    see your own counts; 3+ red flags in 30 days put you on a moderator list.
-- =============================================================================

alter table public.messages drop constraint messages_kind_check;
alter table public.messages
  add constraint messages_kind_check check (kind in ('text', 'image', 'video', 'gif', 'reaction', 'system'));

create or replace function public.send_message(
  p_conversation_id uuid,
  p_body text,
  p_client_id uuid,
  p_kind text default 'text',
  p_media_path text default null,
  p_encrypted boolean default false
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

  select * into v_msg from public.messages where sender_id = v_me and client_id = p_client_id;
  if found then
    return v_msg;
  end if;

  -- Chats are GIF-only now, like Tinder: no new photos or videos.
  if p_kind in ('image', 'video') then
    raise exception 'unsupported_kind: photos and videos can''t be sent in chat. Try a GIF' using errcode = 'P0001';
  end if;
  if p_kind not in ('text', 'gif', 'reaction') then
    raise exception 'unsupported_kind' using errcode = 'P0001';
  end if;
  if p_kind in ('text', 'gif', 'reaction') and (p_body is null or char_length(btrim(p_body)) = 0) then
    raise exception 'empty_message' using errcode = 'P0001';
  end if;
  -- Plain text keeps the 2000-character limit; ciphertext is a bit longer.
  -- A reaction is only a message id and an emoji.
  if char_length(coalesce(p_body, '')) > (case when p_kind in ('reaction', 'gif') then 1000
                                               when p_encrypted then 12000 else 2000 end) then
    raise exception 'message_too_long: keep it under 2000 characters' using errcode = 'P0001';
  end if;
  if p_kind in ('image', 'video') and (p_media_path is null
       or p_media_path not like v_me::text || '/' || p_conversation_id::text || '/%') then
    raise exception 'invalid_media' using errcode = 'P0001';
  end if;
  if p_kind not in ('image', 'video') and p_media_path is not null then
    raise exception 'invalid_media' using errcode = 'P0001';
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

  insert into public.messages (conversation_id, sender_id, client_id, kind, body, media_path, metadata)
  values (p_conversation_id, v_me, p_client_id, p_kind, p_body, p_media_path,
          jsonb_build_object('e2e', coalesce(p_encrypted, false)))
  on conflict (sender_id, client_id) do nothing
  returning * into v_msg;

  if v_msg.id is null then
    select * into v_msg from public.messages where sender_id = v_me and client_id = p_client_id;
  else
    insert into public.message_send_log (sender_id) values (v_me);
  end if;

  -- A reaction doesn't move the chat to the top or count as new activity.
  if p_kind <> 'reaction' then
    update public.conversations set last_message_at = v_msg.created_at where id = p_conversation_id;
    update public.conversation_members
       set last_read_at = v_msg.created_at
     where conversation_id = p_conversation_id and user_id = v_me;
  end if;

  return v_msg;
end;
$$;

revoke all on function public.send_message(uuid, text, uuid, text, text, boolean) from public, anon;
grant execute on function public.send_message(uuid, text, uuid, text, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 3 MB media allowance
-- -----------------------------------------------------------------------------
create or replace function private.media_limit_bytes() returns bigint language sql immutable as $$ select 3145728::bigint $$;

create or replace function public.get_my_media_usage()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('used_bytes', private.media_bytes((select auth.uid())),
                            'limit_bytes', private.media_limit_bytes());
$$;

drop policy "media allowance: 5 MB per person" on storage.objects;
create policy "media allowance per person"
  on storage.objects as restrictive for insert to authenticated
  with check (bucket_id not in ('profile-photos', 'chat-media', 'moments')
              or private.media_bytes((select auth.uid())) < private.media_limit_bytes());

grant execute on function private.media_limit_bytes() to authenticated;

-- -----------------------------------------------------------------------------
-- Green and red flags
-- -----------------------------------------------------------------------------
create table public.profile_flags (
  giver_id     uuid not null references public.profiles (id) on delete cascade,
  receiver_id  uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('green', 'red')),
  created_at   timestamptz not null default now(),
  primary key (giver_id, receiver_id),
  check (giver_id <> receiver_id)
);
create index profile_flags_receiver_idx on public.profile_flags (receiver_id, kind, created_at desc);
alter table public.profile_flags enable row level security;
revoke all on public.profile_flags from anon, authenticated;

-- Matched (now or before) and at least one message was sent in their chat.
create or replace function private.have_chatted(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
      join public.conversations cv on cv.match_id = m.id
     where m.user_low = least(p_a, p_b) and m.user_high = greatest(p_a, p_b)
       and cv.last_message_at is not null
  );
$$;

-- Give (or change) a flag; null removes mine.
create or replace function public.set_profile_flag(p_target uuid, p_kind text)
returns text
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
  if p_kind is null then
    delete from public.profile_flags where giver_id = v_me and receiver_id = p_target;
    return null;
  end if;
  if p_kind not in ('green', 'red') then
    raise exception 'invalid_flag' using errcode = 'P0001';
  end if;
  if not private.have_chatted(v_me, p_target) then
    raise exception 'not_allowed: you can flag someone after you have matched and chatted' using errcode = 'P0001';
  end if;
  insert into public.profile_flags (giver_id, receiver_id, kind) values (v_me, p_target, p_kind)
  on conflict (giver_id, receiver_id) do update set kind = excluded.kind, created_at = now();
  return p_kind;
end;
$$;

-- The flag I gave someone (to show in the chat menu).
create or replace function public.get_my_flag_for(p_target uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select kind from public.profile_flags where giver_id = (select auth.uid()) and receiver_id = p_target;
$$;

-- My own counts: only I see them.
create or replace function public.get_my_profile_feedback()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'green_flags', (select count(*) from public.profile_flags where receiver_id = (select auth.uid()) and kind = 'green'),
    'red_flags', (select count(*) from public.profile_flags where receiver_id = (select auth.uid()) and kind = 'red'),
    'likes', (select count(*) from public.swipes where swipee_id = (select auth.uid()) and action = 'like')
  );
$$;

-- Moderators: people with 3 or more red flags in the last 30 days.
create or replace function public.admin_list_red_flagged()
returns table (user_id uuid, display_name text, red_flags int, green_flags int, last_flag_at timestamptz, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select p.id, p.display_name,
         count(*) filter (where f.kind = 'red' and f.created_at > now() - interval '30 days')::int,
         count(*) filter (where f.kind = 'green')::int,
         max(f.created_at), p.status
    from public.profile_flags f
    join public.profiles p on p.id = f.receiver_id
   group by p.id, p.display_name, p.status
  having count(*) filter (where f.kind = 'red' and f.created_at > now() - interval '30 days') >= 3
   order by 3 desc, 5 desc
   limit 200;
end;
$$;

revoke all on function
  public.set_profile_flag(uuid, text), public.get_my_flag_for(uuid), public.get_my_profile_feedback(),
  public.admin_list_red_flagged(), private.have_chatted(uuid, uuid)
from public, anon;
grant execute on function
  public.set_profile_flag(uuid, text), public.get_my_flag_for(uuid), public.get_my_profile_feedback(),
  public.admin_list_red_flagged()
to authenticated;
