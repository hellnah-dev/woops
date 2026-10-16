-- =============================================================================
-- Fixes for chat-media storage rules (migration 017):
--  * The rules cast the second folder of a path to uuid. Postgres doesn't
--    promise to check `bucket_id` first, so a file elsewhere whose second
--    folder isn't a uuid could make storage queries fail. A safe helper now
--    returns null instead of raising.
--  * Admins (the 30-day cleanup in the admin panel) may delete chat photos.
-- =============================================================================

-- '<sender>/<conversation>/<file>' → conversation id, or null if not that shape.
create or replace function private.chat_media_conversation(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
           when (storage.foldername(p_name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then ((storage.foldername(p_name))[2])::uuid
         end;
$$;

drop policy "chat media: sender uploads into own folder" on storage.objects;
drop policy "chat media: conversation members can read" on storage.objects;
drop policy "chat media: conversation members can delete" on storage.objects;

create policy "chat media: sender uploads into own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and coalesce(private.is_conversation_member(private.chat_media_conversation(name), (select auth.uid())), false));

create policy "chat media: conversation members can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-media'
         and coalesce(private.is_conversation_member(private.chat_media_conversation(name), (select auth.uid())), false));

create policy "chat media: conversation members can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media'
         and coalesce(private.is_conversation_member(private.chat_media_conversation(name), (select auth.uid())), false));

-- Expired, undelivered chat photos can be removed by the admin panel's cleanup.
create policy "chat media: admins can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and private.is_admin());

revoke all on function private.chat_media_conversation(text) from public, anon;
grant execute on function private.chat_media_conversation(text) to authenticated, service_role;
