-- =============================================================================
-- Delete test users from Supabase (permanent).
--
-- Paste into Supabase → SQL Editor → New query. Run it in 3 steps:
--
--   STEP 1  Put the test accounts' emails in the list below, then run only the
--           PREVIEW query (select it and press Run). Check the list carefully.
--   STEP 2  Run the DELETE block. It removes those accounts and, automatically,
--           their profile, photos list, likes, matches, chats waiting on the
--           relay, reports they made (kept anonymously), ID checks, etc.
--   STEP 3  Nothing to do: their photo/ID files are removed automatically the
--           next time an admin signs in to the admin panel (files of deleted
--           accounts are cleaned up after 1 hour).
--
-- Admins are never deleted by this script, even if listed.
-- =============================================================================

-- ---- Which accounts? ---------------------------------------------------------
-- Option A (recommended): exact emails.
create temporary table test_users_to_delete as
select u.id, u.email, p.display_name, p.created_at as joined_at
  from auth.users u
  left join public.profiles p on p.id = u.id
 where lower(u.email) in (
         'test1@example.com',          -- ← replace with your test emails
         'test2@example.com'
       )
   -- Option B: also every email that looks like a test account. Remove the
   -- two dashes at the start of the next line to include them.
   -- or u.email ilike '%test%' or u.email ilike '%@example.%'
   and not exists (select 1 from public.admins a where a.user_id = u.id);

-- ---- STEP 1: PREVIEW (nothing is deleted yet) ----------------------------------
select email, display_name, joined_at from test_users_to_delete order by joined_at;

-- ---- STEP 2: DELETE ------------------------------------------------------------
begin;
  delete from auth.users where id in (select id from test_users_to_delete);
  -- Should match the number of rows in the preview:
  select count(*) as deleted_accounts from test_users_to_delete;
commit;

drop table test_users_to_delete;
