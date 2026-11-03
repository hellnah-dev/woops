-- =============================================================================
-- Message reactions and typing indicator.
--
--  * Reactions are relayed like messages (kind 'reaction'): the body says which
--    message and which emoji, end-to-end encrypted when both phones have keys.
--    The phone attaches it to that message in its own storage and acks it, so
--    the relay row is deleted like any other message. Removing a reaction is
--    sent unencrypted with an empty emoji (it only names a random message id).
--  * "Typing…" uses Realtime broadcast on the private topic
--    `typing:<conversation id>`. Nothing is written to any table; only the two
--    members of the conversation may join or send on that topic.
-- =============================================================================

alter table public.messages drop constraint messages_kind_check;
alter table public.messages
  add constraint messages_kind_check check (kind in ('text', 'image', 'video', 'reaction', 'system')),
  add constraint messages_reaction_has_body check (kind <> 'reaction' or body is not null);

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

  if p_kind not in ('text', 'image', 'video', 'reaction') then
    raise exception 'unsupported_kind' using errcode = 'P0001';
  end if;
  if p_kind in ('text', 'reaction') and (p_body is null or char_length(btrim(p_body)) = 0) then
    raise exception 'empty_message' using errcode = 'P0001';
  end if;
  -- Plain text keeps the 2000-character limit; ciphertext is a bit longer.
  -- A reaction is only a message id and an emoji.
  if char_length(coalesce(p_body, '')) > (case when p_kind = 'reaction' then 1000
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

-- The insert trigger also keeps last activity: reactions don't count.
create or replace function private.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'reaction' then return new; end if;
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id
     and (last_message_at is null or last_message_at < new.created_at);
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Typing indicator: private broadcast topic per conversation.
-- -----------------------------------------------------------------------------
-- `typing:<uuid>` → the conversation id, or null for any other topic.
create or replace function private.typing_conversation(p_topic text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_topic ~ '^typing:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then substring(p_topic from 8)::uuid
  end;
$$;
grant execute on function private.typing_conversation(text) to authenticated;

drop policy if exists "conversation members receive typing" on realtime.messages;
create policy "conversation members receive typing" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and private.is_conversation_member(private.typing_conversation((select realtime.topic())), (select auth.uid()))
  );

drop policy if exists "conversation members send typing" on realtime.messages;
create policy "conversation members send typing" on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'broadcast'
    and private.is_conversation_member(private.typing_conversation((select realtime.topic())), (select auth.uid()))
  );
