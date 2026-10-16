-- =============================================================================
-- The automatic cleanup (admin panel on sign-in + cleanup-proofs function)
-- also removes files left behind by deleted accounts: anything in a user
-- folder whose account no longer exists (e.g. after deleting test users).
-- =============================================================================
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
