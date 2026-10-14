-- =============================================================================
-- Storage bucket for profile photos + Realtime publication
-- =============================================================================

-- Private bucket: files are only served to signed-in users allowed by the
-- policies below (never publicly listable or hot-linkable).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Files are stored as "<user_id>/<random>.jpg".
create policy "profile photos: owner can upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "profile photos: owner can update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "profile photos: owner can delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Signed-in users can view photos of active users who have not blocked them
-- (and whom they have not blocked). Paths are random and only handed out via
-- the discovery / profile APIs.
create policy "profile photos: visible to allowed viewers"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'profile-photos'
    and private.can_view_photos(
          (select auth.uid()),
          nullif((storage.foldername(name))[1], '')::uuid)
  );

-- Realtime: Postgres Changes respects RLS, so each user only receives rows
-- they are allowed to select.
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.matches;
alter publication supabase_realtime add table public.read_receipts;
