-- Admins can remove profile photos / selfies they moderate (the admin panel
-- deletes the database row with admin_delete_photo(), then the file).
create policy "profile photos: admins can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos' and private.is_admin());

create policy "selfies: admins can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'verification-selfies' and private.is_admin());
