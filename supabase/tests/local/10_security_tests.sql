-- =============================================================================
-- Security & business-rule tests, run with several simulated accounts.
--
--   A  = Asha   (woman, 27, interested in men)
--   B  = Bikash (man,   29, interested in women)
--   C  = Chris  (man,   31, interested in women)   -> outsider to A/B chat
--   D  = Dina   (woman, 25, interested in women)   -> must never see A/B/C
--   E  = Eve    (signs up, tries to be 16)
-- =============================================================================
\set ON_ERROR_STOP on

\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
\set D '''dddddddd-0000-0000-0000-000000000004'''
\set E '''eeeeeeee-0000-0000-0000-000000000005'''

insert into auth.users (id, email) values
  (:A, 'a@test.dev'), (:B, 'b@test.dev'), (:C, 'c@test.dev'), (:D, 'd@test.dev'), (:E, 'e@test.dev');

-- -----------------------------------------------------------------------------
-- Anonymous visitors get nothing
-- -----------------------------------------------------------------------------
set role anon;
select tests.login(null);
select tests.throws('select * from public.profiles', '%permission denied%', 'anon cannot read profiles');
select tests.throws('select * from public.public_profiles', '%permission denied%', 'anon cannot read public_profiles');
select tests.throws($q$select public.swipe('bbbbbbbb-0000-0000-0000-000000000002', 'like')$q$,
                    '%permission denied%', 'anon cannot call swipe()');
reset role;

-- -----------------------------------------------------------------------------
-- Profile creation (as each user)
-- -----------------------------------------------------------------------------
set role authenticated;

select tests.login(:E);
select tests.throws($q$insert into public.profiles (id, display_name, birthdate, gender)
                       values ('eeeeeeee-0000-0000-0000-000000000005', 'Eve', current_date - interval '16 years', 'woman')$q$,
                    '%underage%', 'under-18 profile is rejected');

select tests.login(:A);
select tests.throws($q$insert into public.profiles (id, display_name, birthdate, gender)
                       values ('bbbbbbbb-0000-0000-0000-000000000002', 'Fake B', '1990-01-01', 'man')$q$,
                    '%row-level security%', 'cannot create a profile for someone else');
insert into public.profiles (id, display_name, birthdate, gender, bio, intention)
values (:A, 'Asha', current_date - interval '27 years', 'woman', 'Mountains and momos', 'long_term');
select tests.throws($q$update public.profiles set status = 'active', onboarding_completed = true$q$,
                    '%permission denied%', 'cannot self-modify status/onboarding flag');
select tests.throws($q$update public.profiles set birthdate = '2015-01-01'$q$,
                    '%permission denied%', 'birthdate cannot be changed after creation');
select tests.throws('select public.complete_onboarding()', '%photo_required%', 'onboarding requires a photo');
select tests.throws($q$insert into public.profile_photos (user_id, storage_path)
                       values ('bbbbbbbb-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000002/x.jpg')$q$,
                    '%row-level security%', 'cannot add photos to another profile');
select tests.throws($q$insert into public.profile_photos (user_id, storage_path)
                       values ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002/x.jpg')$q$,
                    '%profile_photos_path_owner%', 'photo path must be inside own folder');
insert into public.profile_photos (user_id, storage_path) values (:A, 'aaaaaaaa-0000-0000-0000-000000000001/1.jpg');
insert into storage.objects (bucket_id, name) values ('profile-photos', 'aaaaaaaa-0000-0000-0000-000000000001/1.jpg');
select tests.throws($q$insert into storage.objects (bucket_id, name)
                       values ('profile-photos', 'bbbbbbbb-0000-0000-0000-000000000002/evil.jpg')$q$,
                    '%row-level security%', 'cannot upload into another user''s storage folder');
update public.discovery_preferences set genders = array['man'];
select public.set_my_interests(array(select id from public.interests where name in ('Hiking', 'Coffee', 'Travel')));
select public.set_my_location(27.717245, 85.323961);
select tests.ok((select lat = 27.72 and lng = 85.32 from public.profile_locations), 'location is stored rounded (~1 km)');
select public.complete_onboarding();
select tests.ok((select onboarding_completed from public.profiles), 'onboarding completes with a photo');

select tests.login(:B);
insert into public.profiles (id, display_name, birthdate, gender) values (:B, 'Bikash', current_date - interval '29 years', 'man');
insert into public.profile_photos (user_id, storage_path) values (:B, 'bbbbbbbb-0000-0000-0000-000000000002/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.set_my_location(27.70, 85.30);
select public.complete_onboarding();

select tests.login(:C);
insert into public.profiles (id, display_name, birthdate, gender) values (:C, 'Chris', current_date - interval '31 years', 'man');
insert into public.profile_photos (user_id, storage_path) values (:C, 'cccccccc-0000-0000-0000-000000000003/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.complete_onboarding();

select tests.login(:D);
insert into public.profiles (id, display_name, birthdate, gender) values (:D, 'Dina', current_date - interval '25 years', 'woman');
insert into public.profile_photos (user_id, storage_path) values (:D, 'dddddddd-0000-0000-0000-000000000004/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.complete_onboarding();

-- -----------------------------------------------------------------------------
-- Privacy of private tables
-- -----------------------------------------------------------------------------
select tests.login(:B);
select tests.ok((select count(*) from public.profiles) = 1, 'profiles table only returns own row');
select tests.ok((select count(*) from public.profile_locations) = 1, 'locations table only returns own row');
select tests.ok((select count(*) from public.profile_photos) = 1, 'photos table only returns own rows');
select tests.ok(not exists (select 1 from public.discovery_preferences where user_id = :A),
                'cannot read other users'' discovery preferences');
update public.privacy_settings set discoverable = false where user_id = :A;  -- silently affects 0 rows
select tests.throws($q$insert into public.entitlements (user_id, entitlement) values ('bbbbbbbb-0000-0000-0000-000000000002', 'premium')$q$,
                    '%permission denied%', 'cannot grant yourself premium');
select tests.ok(not public.is_premium(), 'is_premium() is false without a server-side entitlement');
select tests.ok(not exists (select 1 from public.public_profiles where id = :A),
                'cannot look up a stranger via public_profiles');

select tests.login(:A);
select tests.ok((select discoverable from public.privacy_settings), 'another user could not change my privacy settings');

-- -----------------------------------------------------------------------------
-- Discovery respects mutual preferences
-- -----------------------------------------------------------------------------
select tests.login(:A);
select tests.ok((select array_agg(id order by id) from public.get_discovery_feed(20))
                = array[:B::uuid, :C::uuid], 'A (wants men) sees B and C, not D');
select tests.ok((select distance_km from public.get_discovery_feed(20) where id = :B) between 1 and 5,
                'distance is shown rounded in km');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) f
                             where f::text like '%27.7%' or f::text like '%1998%' or f::text like '%birthdate%'),
                'feed exposes no coordinates or birthdate');

select tests.login(:D);
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id in (:A, :B, :C)),
                'D (wants women) does not see A (wants men) or the men');

select tests.login(:B);
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :A), 'B sees A');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :D), 'B does not see D (D wants women only)');
select tests.throws($q$select public.swipe('dddddddd-0000-0000-0000-000000000004', 'like')$q$,
                    '%unavailable%', 'cannot like someone whose preferences exclude you');

-- -----------------------------------------------------------------------------
-- Likes cannot be forged; matching is mutual and unique
-- -----------------------------------------------------------------------------
select tests.throws($q$insert into public.swipes (swiper_id, swipee_id, action)
                       values ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'like')$q$,
                    '%permission denied%', 'cannot insert a forged like directly');
select tests.throws($q$insert into public.matches (user_low, user_high)
                       values ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002')$q$,
                    '%permission denied%', 'cannot insert a match directly');
select tests.throws($q$select public.swipe('bbbbbbbb-0000-0000-0000-000000000002', 'like')$q$,
                    '%yourself%', 'cannot swipe on yourself');

select tests.ok((public.swipe(:A, 'like') ->> 'matched')::boolean = false, 'one-sided like does not match');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :A), 'swiped profiles leave the feed');

select tests.login(:A);
select tests.ok(exists (select 1 from public.get_likes_received() where id = :B), 'A sees B in likes received');
select tests.ok(exists (select 1 from public.public_profiles where id = :B), 'A can open B''s profile after B liked her');
select tests.ok((public.swipe(:B, 'like') ->> 'matched')::boolean, 'mutual like creates a match');
select tests.ok((public.swipe(:B, 'like') ->> 'matched')::boolean, 'repeat like is idempotent');
reset role;
select tests.ok((select count(*) from public.matches) = 1, 'exactly one match row exists');
select tests.ok((select count(*) from public.conversations) = 1, 'exactly one conversation exists');
set role authenticated;

select tests.login(:A);
select public.swipe(:C, 'pass');
select tests.ok(public.undo_last_swipe() = :C::uuid, 'undo restores the last pass');
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :C), 'undone pass is back in the feed');

-- -----------------------------------------------------------------------------
-- Messaging: only participants
-- -----------------------------------------------------------------------------
select tests.login(:A);
select tests.ok((select count(*) from public.get_my_conversations()) = 1, 'A has one conversation');
select set_config('test.conv', (select conversation_id::text from public.get_my_conversations() limit 1), false);
select tests.throws($q$insert into public.messages (conversation_id, sender_id, client_id, body)
                       values (current_setting('test.conv')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', gen_random_uuid(), 'hi')$q$,
                    '%permission denied%', 'cannot insert messages directly');
select public.send_message(current_setting('test.conv')::uuid, 'Namaste! 👋', '11111111-1111-1111-1111-111111111111');
select public.send_message(current_setting('test.conv')::uuid, 'Namaste! 👋', '11111111-1111-1111-1111-111111111111');
select tests.ok((select count(*) from public.messages) = 1, 'retried send with same client_id does not duplicate');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, '   ', gen_random_uuid())$q$,
                    '%empty_message%', 'empty messages are rejected');

select tests.login(:B);
select tests.ok((select unread_count from public.get_my_conversations()) = 1, 'B has 1 unread message');
select tests.ok((select count(*) from public.messages) = 1, 'B can read the conversation');
select public.mark_conversation_read(current_setting('test.conv')::uuid);
select tests.ok((select unread_count from public.get_my_conversations()) = 0, 'mark read clears unread count');

select tests.login(:A);
select tests.ok(exists (select 1 from public.read_receipts where user_id = :B), 'A sees B''s read receipt');
select tests.ok(not exists (select 1 from public.conversation_members where user_id = :B),
                'A cannot see B''s private last_read_at');

select tests.login(:C);
select tests.ok((select count(*) from public.messages) = 0, 'outsider C cannot read A/B messages');
select tests.ok((select count(*) from public.conversations) = 0, 'outsider C cannot see the conversation');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'hey', gen_random_uuid())$q$,
                    '%not_found%', 'outsider C cannot post into the conversation');
select tests.throws($q$select public.mark_conversation_read(current_setting('test.conv')::uuid)$q$,
                    '%not_found%', 'outsider C cannot mark it read');
select tests.ok(not exists (select 1 from public.public_profiles where id in (:A, :B)),
                'C cannot browse A/B via public_profiles');

-- Rate limit: 30 messages / minute (B has sent none yet)
select tests.login(:B);
do $$
begin
  for i in 1..30 loop
    perform public.send_message(current_setting('test.conv')::uuid, 'msg ' || i, gen_random_uuid());
  end loop;
end $$;
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'one too many', gen_random_uuid())$q$,
                    '%rate_limited%', 'message rate limit is enforced');

-- -----------------------------------------------------------------------------
-- Storage photo visibility
-- -----------------------------------------------------------------------------
select tests.login(:C);
select tests.ok(exists (select 1 from storage.objects where name like 'aaaaaaaa%'), 'C can load A''s photo');

-- -----------------------------------------------------------------------------
-- Reports never reach the reported user
-- -----------------------------------------------------------------------------
select tests.login(:A);
select tests.ok(public.report_user(:C, 'spam', 'Sends links') is not null, 'A can report C');
select tests.throws($q$select public.report_user('cccccccc-0000-0000-0000-000000000003', 'bad_reason')$q$,
                    '%invalid_reason%', 'report reason is validated');
select tests.throws($q$select public.report_user('cccccccc-0000-0000-0000-000000000003', 'spam', null,
                         (select id from public.messages limit 1))$q$,
                    '%invalid_message%', 'cannot attach a message the target did not send');
select tests.ok((select count(*) from public.reports) = 1, 'reporter sees own report');
select tests.login(:C);
select tests.ok((select count(*) from public.reports) = 0, 'reported user cannot see reports about them');

-- -----------------------------------------------------------------------------
-- Blocking hides everything both ways and closes the chat
-- -----------------------------------------------------------------------------
select tests.login(:A);
select public.block_user(:C);
select tests.login(:C);
select tests.ok(not exists (select 1 from storage.objects where name like 'aaaaaaaa%'), 'blocked C can no longer load A''s photos');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :A), 'blocked C no longer sees A in discovery');
select tests.throws($q$select public.swipe('aaaaaaaa-0000-0000-0000-000000000001', 'like')$q$,
                    '%unavailable%', 'blocked C cannot like A');
select tests.ok(not exists (select 1 from public.blocks), 'C cannot see that A blocked them');

select tests.login(:B);
select public.block_user(:A);
select tests.ok((select count(*) from public.get_my_conversations()) = 0, 'block removes the conversation');
select tests.ok((select count(*) from public.messages) = 0, 'block hides message history');
select tests.login(:A);
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'hello?', gen_random_uuid())$q$,
                    '%conversation_closed%', 'blocked user cannot keep messaging');
select tests.ok(not exists (select 1 from public.public_profiles where id = :B), 'blocked profile disappears from public_profiles');
select tests.ok((select count(*) from public.get_blocked_users()) = 1, 'A sees who she blocked');

reset role;

-- -----------------------------------------------------------------------------
-- Report
-- -----------------------------------------------------------------------------
\echo
select case when passed then 'PASS' else 'FAIL' end as result, name,
       case when not passed then detail end as detail
  from tests.results order by id;
select count(*) filter (where passed) as passed, count(*) filter (where not passed) as failed from tests.results;
do $$ begin
  if exists (select 1 from tests.results where not passed) then raise exception 'security tests failed'; end if;
end $$;
