-- =============================================================================
-- WhatsApp-style chats, photos in chat, and a 5 MB media allowance.
--
--  * End-to-end encryption: every phone has an X25519 key pair; the private
--    key never leaves the phone (Keychain / Android Keystore). Only public
--    keys are stored here (`chat_keys`), readable by your matches. Messages
--    and photo keys are encrypted on the phone with AES-256-GCM, so the relay
--    only ever holds ciphertext (`messages.metadata->>'e2e' = 'true'`).
--  * Chat photos: encrypted on the phone, uploaded to the private
--    `chat-media` bucket at <sender>/<conversation>/<file>, downloaded and
--    decrypted by the recipient, saved on their phone, then deleted from the
--    server. Undelivered files are removed after 30 days.
--  * 5 MB per person in total: profile photos + chat photos still on the
--    server. `get_my_media_usage()` lets the app check before uploading, and a
--    restrictive storage policy blocks uploads once the allowance is used.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Public keys
-- -----------------------------------------------------------------------------
create table public.chat_keys (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  public_key  text not null check (char_length(public_key) between 40 and 64),
  updated_at  timestamptz not null default now()
);
alter table public.chat_keys enable row level security;
revoke all on public.chat_keys from anon, authenticated;

create or replace function public.set_my_chat_key(p_public_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
begin
  insert into public.chat_keys (user_id, public_key) values (v_me, p_public_key)
  on conflict (user_id) do update set public_key = excluded.public_key, updated_at = now();
end;
$$;

-- Only people you are matched with can fetch your public key.
create or replace function public.get_chat_key(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select k.public_key
    from public.chat_keys k
   where k.user_id = p_user
     and (p_user = (select auth.uid()) or exists (
           select 1 from public.matches m
            where m.user_low = least(p_user, (select auth.uid()))
              and m.user_high = greatest(p_user, (select auth.uid()))
              and m.unmatched_at is null))
     and not private.is_blocked_between(p_user, (select auth.uid()));
$$;

-- -----------------------------------------------------------------------------
-- Messages: room for ciphertext, and photo messages
-- -----------------------------------------------------------------------------
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.messages'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ~ '(2000|media_path)'
  loop
    execute format('alter table public.messages drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.messages
  add constraint messages_body_size check (body is null or char_length(body) <= 12000),
  add constraint messages_text_has_body check (kind <> 'text' or char_length(btrim(body)) >= 1),
  add constraint messages_image_has_media check (kind <> 'image' or media_path is not null);

drop function public.send_message(uuid, text, uuid, text, text);

create function public.send_message(
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

  if p_kind not in ('text', 'image') then
    raise exception 'unsupported_kind' using errcode = 'P0001';
  end if;
  if p_kind = 'text' and (p_body is null or char_length(btrim(p_body)) = 0) then
    raise exception 'empty_message' using errcode = 'P0001';
  end if;
  -- Plain text keeps the 2000-character limit; ciphertext is a bit longer.
  if char_length(coalesce(p_body, '')) > (case when p_encrypted then 12000 else 2000 end) then
    raise exception 'message_too_long: keep it under 2000 characters' using errcode = 'P0001';
  end if;
  if p_kind = 'image' and (p_media_path is null
       or p_media_path not like v_me::text || '/' || p_conversation_id::text || '/%') then
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

  update public.conversations set last_message_at = v_msg.created_at where id = p_conversation_id;
  update public.conversation_members
     set last_read_at = v_msg.created_at
   where conversation_id = p_conversation_id and user_id = v_me;

  return v_msg;
end;
$$;

-- -----------------------------------------------------------------------------
-- Chat photo relay bucket: <sender>/<conversation>/<file>
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 5242880, array['application/octet-stream'])
on conflict (id) do nothing;

create policy "chat media: sender uploads into own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and private.is_conversation_member(((storage.foldername(name))[2])::uuid, (select auth.uid())));

create policy "chat media: conversation members can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-media'
         and private.is_conversation_member(((storage.foldername(name))[2])::uuid, (select auth.uid())));

-- The recipient deletes the file once it is saved on their phone.
create policy "chat media: conversation members can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media'
         and private.is_conversation_member(((storage.foldername(name))[2])::uuid, (select auth.uid())));

-- -----------------------------------------------------------------------------
-- 5 MB media allowance
-- -----------------------------------------------------------------------------
create or replace function private.media_bytes(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(coalesce((o.metadata ->> 'size')::bigint, 0)), 0)::bigint
    from storage.objects o
   where o.bucket_id in ('profile-photos', 'chat-media')
     and (storage.foldername(o.name))[1] = p_user::text;
$$;

create or replace function public.get_my_media_usage()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('used_bytes', private.media_bytes((select auth.uid())), 'limit_bytes', 5242880);
$$;

-- Restrictive: applies on top of the bucket's own insert policies.
create policy "media allowance: 5 MB per person"
  on storage.objects as restrictive for insert to authenticated
  with check (bucket_id not in ('profile-photos', 'chat-media')
              or private.media_bytes((select auth.uid())) < 5242880);

-- -----------------------------------------------------------------------------
-- Cleanup: undelivered chat photos after 30 days (with the 7-day proof files)
-- -----------------------------------------------------------------------------
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

  return query
  select o.bucket_id::text, o.name::text
    from storage.objects o
   where (o.bucket_id in ('id-documents', 'verification-selfies') and o.created_at < now() - interval '7 days')
      or (o.bucket_id = 'chat-media' and o.created_at < now() - interval '30 days')
   order by o.created_at
   limit 1000;
end;
$$;

revoke all on function
  public.set_my_chat_key(text), public.get_chat_key(uuid),
  public.send_message(uuid, text, uuid, text, text, boolean), public.get_my_media_usage(),
  private.media_bytes(uuid), private.claim_expired_proofs()
from public, anon;
grant execute on function
  public.set_my_chat_key(text), public.get_chat_key(uuid),
  public.send_message(uuid, text, uuid, text, text, boolean), public.get_my_media_usage()
to authenticated;
grant execute on function private.media_bytes(uuid) to authenticated;
