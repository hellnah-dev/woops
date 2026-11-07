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
select tests.throws($q$select * from public.get_public_profile('aaaaaaaa-0000-0000-0000-000000000001')$q$, '%permission denied%',
                    'anon cannot look up profiles');
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
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();
select tests.ok((select onboarding_completed from public.profiles), 'onboarding completes with a photo');

select tests.login(:B);
insert into public.profiles (id, display_name, birthdate, gender) values (:B, 'Bikash', current_date - interval '29 years', 'man');
insert into public.profile_photos (user_id, storage_path) values (:B, 'bbbbbbbb-0000-0000-0000-000000000002/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.set_my_location(27.70, 85.30);
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();

select tests.login(:C);
insert into public.profiles (id, display_name, birthdate, gender) values (:C, 'Chris', current_date - interval '31 years', 'man');
insert into public.profile_photos (user_id, storage_path) values (:C, 'cccccccc-0000-0000-0000-000000000003/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();

select tests.login(:D);
insert into public.profiles (id, display_name, birthdate, gender) values (:D, 'Dina', current_date - interval '25 years', 'woman');
insert into public.profile_photos (user_id, storage_path) values (:D, 'dddddddd-0000-0000-0000-000000000004/1.jpg');
update public.discovery_preferences set genders = array['woman'];
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();

-- -----------------------------------------------------------------------------
-- "Ready to date": an incomplete profile cannot like or pass
-- -----------------------------------------------------------------------------
select tests.login(:B);
select tests.throws($q$select public.swipe('aaaaaaaa-0000-0000-0000-000000000001', 'like')$q$,
                    '%profile_not_ready%', 'incomplete profile cannot swipe');
reset role;
select tests.make_ready(u) from unnest(array[:A, :B, :C, :D]::uuid[]) u;
set role authenticated;

-- -----------------------------------------------------------------------------
-- Privacy of private tables
-- -----------------------------------------------------------------------------
select tests.login(:B);
select tests.ok((select count(*) from public.profiles) = 1, 'profiles table only returns own row');
select tests.ok((select count(*) from public.profile_locations) = 1, 'locations table only returns own row');
select tests.ok((select count(*) from public.profile_photos where user_id <> :B) = 0, 'photos table only returns own rows');
select tests.ok(not exists (select 1 from public.discovery_preferences where user_id = :A),
                'cannot read other users'' discovery preferences');
update public.privacy_settings set discoverable = false where user_id = :A;  -- silently affects 0 rows
select tests.throws($q$insert into public.entitlements (user_id, entitlement) values ('bbbbbbbb-0000-0000-0000-000000000002', 'premium')$q$,
                    '%permission denied%', 'cannot grant yourself premium');
select tests.ok(not public.is_premium(), 'is_premium() is false without a server-side entitlement');
select tests.ok(not exists (select 1 from public.get_public_profile(:A)),
                'cannot look up a stranger''s profile');

select tests.login(:A);
select tests.ok((select discoverable from public.privacy_settings), 'another user could not change my privacy settings');

-- -----------------------------------------------------------------------------
-- Discovery respects mutual preferences
-- -----------------------------------------------------------------------------
select tests.login(:A);
select tests.ok((select array_agg(id order by id) from public.get_discovery_feed(20) where not is_random)
                = array[:B::uuid, :C::uuid], 'A (wants men) matches B and C, not D');
select tests.ok((select is_random from public.get_discovery_feed(20) where id = :D),
                'D (outside A''s filters) is shown to A as a random pick');
select tests.ok((select bool_and(not is_random) from public.get_discovery_feed(20) where id in (:B, :C)),
                'matches come first and are not marked random');
select tests.ok((select distance_km from public.get_discovery_feed(20) where id = :B) between 1 and 5,
                'distance is shown rounded in km');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) f
                             where f::text like '%27.7%' or f::text like '%1998%' or f::text like '%birthdate%'),
                'feed exposes no coordinates or birthdate');

select tests.login(:D);
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where not is_random),
                'nobody matches D''s own filters');
select tests.ok((select count(*) from public.get_discovery_feed(20) where is_random and id in (:A, :B, :C)) = 3,
                'instead of an empty feed, D gets random picks: everyone, men included');

select tests.login(:B);
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :A), 'B sees A');
select tests.ok(not (select is_random from public.get_discovery_feed(20) where id = :A), 'A is a real match for B');
select tests.ok((select is_random from public.get_discovery_feed(20) where id = :D),
                'D (wants women only) is not a match for B, but appears as a random pick');
select tests.ok((public.swipe(:D, 'like') ->> 'matched')::boolean = false,
                'B can like a random pick even if it is outside their preferences');

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
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :A and not is_repeat),
                'swiped profiles leave the new-people part of the feed');
select tests.ok((select is_repeat from public.get_discovery_feed(20) where id = :A),
                'when new people run out, swiped profiles come back as repeats');

select tests.login(:A);
select tests.ok(exists (select 1 from public.get_likes_received() where id = :B), 'A sees B in likes received');
select tests.ok(exists (select 1 from public.get_public_profile(:B)), 'A can open B''s profile after B liked her');
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
select tests.ok((select count(*) from public.get_pending_messages()) = 1, 'B downloads the waiting message');
select tests.ok(public.ack_messages(array(select id from public.get_pending_messages())) = 1, 'B acknowledges it');
select tests.ok((select count(*) from public.messages) = 0, 'delivered messages are deleted from the server');
select tests.ok((select unread_count from public.get_my_conversations()) = 0, 'nothing left waiting after delivery');
select tests.ok((select last_message_at from public.get_my_conversations()) is not null,
                'conversation keeps its last activity time');

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
select tests.ok(not exists (select 1 from public.get_public_profile(:A))
                and not exists (select 1 from public.get_public_profile(:B)),
                'C cannot open A''s or B''s profile');

-- End-to-end encryption keys: only matches can read them
select tests.login(:A);
select public.set_my_chat_key('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
select tests.login(:B);
select tests.ok(public.get_chat_key(:A) = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 'a match can fetch your public key');
select tests.throws('select * from public.chat_keys', '%permission denied%', 'the key table is not directly readable');
select tests.login(:C);
select tests.ok(public.get_chat_key(:A) is null, 'strangers cannot fetch your public key');

-- Encrypted text and photo messages
select tests.login(:A);
select tests.ok((public.send_message(current_setting('test.conv')::uuid, repeat('x', 5000), gen_random_uuid(), 'text', null, true)
                 ).metadata ->> 'e2e' = 'true', 'ciphertext may be longer and is flagged e2e');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, repeat('x', 5000), gen_random_uuid())$q$,
                    '%message_too_long%', 'plain text keeps the 2000-character limit');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'k', gen_random_uuid(), 'image',
                       'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/p.bin', true)$q$,
                    '%photos and videos can%', 'photos can no longer be sent in chat');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'k', gen_random_uuid(), 'video',
                       'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/v.bin', true)$q$,
                    '%photos and videos can%', 'videos can no longer be sent in chat');
select tests.ok((public.send_message(current_setting('test.conv')::uuid, 'sealed-gif-link', gen_random_uuid(), 'gif', null, true)
                 ).kind = 'gif', 'GIFs can be sent, encrypted');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'g', gen_random_uuid(), 'gif',
                       'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/g.bin')$q$,
                    '%invalid_media%', 'a GIF is a link, never an uploaded file');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'k', gen_random_uuid(), 'audio', 'x', true)$q$,
                    '%unsupported_kind%', 'unknown media kinds are rejected');
select tests.login(:B);
select public.ack_messages(array(select id from public.get_pending_messages()));

-- Reactions are relayed like messages and don't count as new activity
select tests.login(:A);
select set_config('test.last_at', (select last_message_at::text from public.conversations
                                    where id = current_setting('test.conv')::uuid), false);
select tests.ok((public.send_message(current_setting('test.conv')::uuid, '{"to":"x","e":"❤️"}', gen_random_uuid(),
                 'reaction')).kind = 'reaction', 'reactions can be sent');
select tests.ok((select last_message_at::text from public.conversations where id = current_setting('test.conv')::uuid)
                = current_setting('test.last_at'), 'a reaction does not move the chat to the top');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, ' ', gen_random_uuid(), 'reaction')$q$,
                    '%empty_message%', 'a reaction needs a body');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, 'x', gen_random_uuid(), 'reaction',
                       'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/p.bin')$q$,
                    '%invalid_media%', 'a reaction cannot carry a file');
select tests.throws($q$select public.send_message(current_setting('test.conv')::uuid, repeat('x', 1001), gen_random_uuid(),
                       'reaction', null, true)$q$, '%message_too_long%', 'reactions stay small');
select tests.login(:B);
select tests.ok((select count(*) from public.get_pending_messages() where kind = 'reaction') = 1,
                'B downloads the reaction');
select tests.ok(public.ack_messages(array(select id from public.get_pending_messages())) = 1,
                'and it is deleted from the server once saved');

-- Typing indicator: only the two people in the chat can use its channel
select tests.login(:A);
select set_config('realtime.topic', 'typing:' || current_setting('test.conv'), false);
insert into realtime.messages (topic, extension, event, payload)
values ('typing:' || current_setting('test.conv'), 'broadcast', 'typing', '{"typing":true}');
select tests.ok(true, 'a member can send "typing" in their chat');
select tests.login(:B);
select tests.ok((select count(*) from realtime.messages) = 1, 'the other member receives it');
select tests.login(:C);
select tests.ok((select count(*) from realtime.messages) = 0, 'an outsider cannot listen to typing');
select tests.throws($q$insert into realtime.messages (topic, extension, event, payload)
                       values ('typing:' || current_setting('test.conv'), 'broadcast', 'typing', '{}')$q$,
                    '%row-level security%', 'an outsider cannot send typing');
select set_config('realtime.topic', 'something-else', false);
select tests.login(:A);
select tests.ok((select count(*) from realtime.messages) = 0, 'other topics are not opened by the typing policy');
select set_config('realtime.topic', '', false);
reset role;
delete from realtime.messages;
set role authenticated;

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
-- 3 MB media allowance per person
-- -----------------------------------------------------------------------------
select tests.login(:A);
select tests.ok((public.get_my_media_usage() ->> 'limit_bytes')::int = 3145728, 'the allowance is 3 MB');
insert into storage.objects (bucket_id, name, metadata)
values ('profile-photos', 'aaaaaaaa-0000-0000-0000-000000000001/big.jpg', '{"size": 3200000}');
select tests.ok((public.get_my_media_usage() ->> 'used_bytes')::bigint >= 3200000, 'usage adds up my files');
select tests.throws($q$insert into storage.objects (bucket_id, name, metadata)
                       values ('profile-photos', 'aaaaaaaa-0000-0000-0000-000000000001/more.jpg', '{"size": 1000}')$q$,
                    '%row-level security%', 'uploads stop once 3 MB is used');
select tests.throws($q$insert into storage.objects (bucket_id, name)
                       values ('chat-media', 'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/m.bin')$q$,
                    '%row-level security%', 'chat photos count towards the same 3 MB');
reset role;
delete from storage.objects where name = 'aaaaaaaa-0000-0000-0000-000000000001/big.jpg';
set role authenticated;
select tests.login(:A);
insert into storage.objects (bucket_id, name, metadata)
values ('chat-media', 'aaaaaaaa-0000-0000-0000-000000000001/' || current_setting('test.conv') || '/m.bin', '{"size": 200000}');
select tests.login(:B);
select tests.ok(exists (select 1 from storage.objects where bucket_id = 'chat-media'), 'the recipient can download a chat photo');
delete from storage.objects where bucket_id = 'chat-media';
select tests.ok(not exists (select 1 from storage.objects where bucket_id = 'chat-media'), 'the recipient deletes it after saving');
select tests.login(:C);
select tests.ok(not exists (select 1 from storage.objects where bucket_id = 'chat-media'), 'outsiders cannot see chat photos');
-- A file elsewhere with an odd path never breaks storage queries.
reset role;
insert into storage.objects (bucket_id, name) values ('profile-photos', 'cccccccc-0000-0000-0000-000000000003/not-a-uuid/x.jpg');
set role authenticated;
select tests.login(:A);
select tests.ok((select count(*) from storage.objects) >= 0, 'odd paths in other buckets don''t break chat-media rules');
reset role;
delete from storage.objects where name = 'cccccccc-0000-0000-0000-000000000003/not-a-uuid/x.jpg';
set role authenticated;

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
select tests.ok(public.report_user(:C, 'harassment', null, 'copy of the rude message') is not null,
                'a report can include a copy of the message');
select tests.ok((select count(*) from public.reports) = 2, 'reporter sees own reports');
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
select tests.ok(not exists (select 1 from public.get_public_profile(:B)), 'a blocked profile can no longer be opened');
select tests.ok((select count(*) from public.get_blocked_users()) = 1, 'A sees who she blocked');

reset role;

-- -----------------------------------------------------------------------------
-- Age gate, legal consent, verification flag
-- -----------------------------------------------------------------------------
\set F '''ffffffff-0000-0000-0000-000000000006'''
\set G '''99999999-0000-0000-0000-000000000007'''
\set H '''88888888-0000-0000-0000-000000000008'''
insert into auth.users (id, email, raw_user_meta_data) values
  (:F, 'f@test.dev', '{"birthdate": "2000-01-01"}'),
  (:G, 'g@test.dev', '{}'),
  (:H, 'h@test.dev', '{}');

set role authenticated;
select tests.login(:F);
select tests.throws($q$insert into public.profiles (id, display_name, birthdate, gender)
                       values ('ffffffff-0000-0000-0000-000000000006', 'Fay', '1990-01-01', 'woman')$q$,
                    '%birthdate_mismatch%', 'birthdate must match the sign-up age gate');
insert into public.profiles (id, display_name, birthdate, gender, country_code)
values (:F, 'Fay', '2000-01-01', 'woman', 'NP');
insert into public.profile_photos (user_id, storage_path) values (:F, 'ffffffff-0000-0000-0000-000000000006/1.jpg');
select tests.throws('select public.complete_onboarding()', '%consent_required%', 'onboarding requires accepting terms/privacy/18+');
select tests.throws($q$select public.accept_legal_documents('1999-01-01')$q$, '%outdated_terms%', 'outdated legal version is rejected');
select tests.ok(not public.has_accepted_legal(), 'has_accepted_legal is false before consent');
select public.accept_legal_documents('2026-10-14');
select tests.ok(public.has_accepted_legal(), 'has_accepted_legal is true after consent');
select public.complete_onboarding();
select tests.throws($q$update public.profiles set is_verified = true$q$, '%permission denied%', 'cannot self-verify');
select tests.throws($q$update public.profiles set country_code = 'Nepal'$q$, '%check%', 'country code must be ISO alpha-2');
select tests.throws($q$insert into public.legal_acceptances (user_id, document, version)
                       values ('ffffffff-0000-0000-0000-000000000006', 'terms', 'x')$q$,
                    '%permission denied%', 'consent rows cannot be forged directly');

-- -----------------------------------------------------------------------------
-- Worldwide discovery: countries, "Anywhere", across the 180° meridian
-- -----------------------------------------------------------------------------
select tests.login(:G);  -- Gita in Suva, Fiji (178.4 E)
insert into public.profiles (id, display_name, birthdate, gender, country_code)
values (:G, 'Gita', current_date - interval '28 years', 'woman', 'FJ');
insert into public.profile_photos (user_id, storage_path) values (:G, '99999999-0000-0000-0000-000000000007/1.jpg');
update public.discovery_preferences set genders = array['man'], max_distance_km = 300;
select public.set_my_location(-18.14, 178.44);
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();

select tests.login(:H);  -- Hemi on Taveuni side, just across the meridian (179.9 W)
insert into public.profiles (id, display_name, birthdate, gender, country_code)
values (:H, 'Hemi', current_date - interval '30 years', 'man', 'FJ');
insert into public.profile_photos (user_id, storage_path) values (:H, '88888888-0000-0000-0000-000000000008/1.jpg');
update public.discovery_preferences set genders = array['woman'], max_distance_km = 300;
select public.set_my_location(-16.80, -179.95);
select public.accept_legal_documents('2026-10-14');
select public.complete_onboarding();

select tests.login(:G);
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :H),
                'distance works across the 180° meridian');
select tests.ok((select country_code from public.get_discovery_feed(20) where id = :H) = 'FJ',
                'feed includes country code');
update public.discovery_preferences set country_codes = array['NP'];
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :H and not is_random),
                'country filter excludes other countries from matches');
select tests.ok((select is_random from public.get_discovery_feed(20) where id = :H),
                'people outside the country filter can still appear as random picks');
update public.discovery_preferences set country_codes = array['FJ'];
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :H),
                'country filter includes chosen country');
select tests.throws($q$update public.discovery_preferences set country_codes = array['fiji']$q$,
                    '%check%', 'country filter only accepts ISO codes');

select tests.login(:C);  -- Chris (man, no location) wants women; Anywhere.
update public.discovery_preferences set max_distance_km = 20000;
select tests.ok(exists (select 1 from public.get_discovery_feed(20) where id = :G),
                '"Anywhere" shows people in other countries');

-- -----------------------------------------------------------------------------
-- Two different "under 18" reports hide the profile pending review
-- -----------------------------------------------------------------------------
select tests.login(:B);
select public.report_user(:F, 'underage');
reset role;
select tests.ok((select status from public.profiles where id = :F) = 'active', 'one underage report does not suspend');
set role authenticated;
select tests.login(:C);
select public.report_user(:F, 'underage');
reset role;
select tests.ok((select status from public.profiles where id = :F) = 'suspended',
                'two underage reports from different people suspend the profile');

-- -----------------------------------------------------------------------------
-- Country age rules (floor 18), admin panel permissions, verification, errors
-- -----------------------------------------------------------------------------
\set K '''77777777-0000-0000-0000-000000000009'''
\set Z '''00000000-0000-0000-0000-00000000ad01'''
insert into auth.users (id, email) values (:K, 'kim@test.dev'), (:Z, 'admin@test.dev');
insert into public.admins (user_id) values (:Z);

set role anon;
select tests.login(null);
select tests.ok(public.min_age_for_country('KR') = 19, 'anon can read the minimum age for a country');
select tests.ok(public.min_age_for_country('NP') = 18, 'default minimum age is 18');
select public.log_client_error('Crash on welcome screen', 'stack…', '{"screen":"welcome"}', 'android', '1.0.0');
select tests.throws('select public.admin_stats()', '%permission denied%', 'anon cannot call admin functions');

set role authenticated;
select tests.login(:K);
select tests.throws($q$insert into public.profiles (id, display_name, birthdate, gender, country_code)
                       values ('77777777-0000-0000-0000-000000000009', 'Kim', current_date - interval '18 years 2 months', 'man', 'KR')$q$,
                    '%at least 19%', 'country minimum age (KR 19) is enforced');
insert into public.profiles (id, display_name, birthdate, gender, country_code)
values (:K, 'Kim', current_date - interval '18 years 2 months', 'man', 'NP');
select tests.throws($q$update public.profiles set country_code = 'KR'$q$,
                    '%at least 19%', 'switching country re-checks the age rule');
select public.log_client_error('Null check operator used on a null value', 'at chat_screen.dart:120', '{}', 'ios', '1.0.0');

select tests.throws('select public.admin_stats()', '%forbidden%', 'regular users cannot call admin_stats');
select tests.throws($q$select public.admin_reset_age_check('bbbbbbbb-0000-0000-0000-000000000002')$q$,
                    '%forbidden%', 'regular users cannot reset age checks');
select tests.throws($q$select public.admin_set_user_status('bbbbbbbb-0000-0000-0000-000000000002', 'banned')$q$,
                    '%forbidden%', 'regular users cannot ban people');
select tests.throws($q$select public.admin_upsert_age_rule('NP', 18)$q$, '%forbidden%', 'regular users cannot edit age rules');
select tests.ok((select count(*) from public.app_errors) = 0, 'regular users cannot read error reports');
select tests.ok((select count(*) from public.admin_actions) = 0, 'regular users cannot read the audit log');
select tests.throws($q$insert into public.admins (user_id) values ('77777777-0000-0000-0000-000000000009')$q$,
                    '%permission denied%', 'users cannot make themselves admin');

-- Verification request (B is an active user)
select tests.login(:B);
select tests.throws($q$select public.request_verification('aaaaaaaa-0000-0000-0000-000000000001/selfie.jpg')$q$,
                    '%check%', 'selfie must be in your own folder');
select public.request_verification('bbbbbbbb-0000-0000-0000-000000000002/selfie.jpg');
select tests.throws($q$select public.request_verification('bbbbbbbb-0000-0000-0000-000000000002/selfie2.jpg')$q$,
                    '%already_pending%', 'only one pending verification at a time');
select tests.login(:C);
select tests.ok((select count(*) from public.verification_requests) = 0, 'users cannot see others'' verification requests');

-- Location stays private: only my own position, and no map of anyone else
select tests.login(:G);
update public.discovery_preferences set country_codes = '{}';
select tests.ok((select count(*) from public.get_my_location()) = 1, 'I can read my own saved location');
select tests.ok(not exists (select 1 from pg_proc where proname in ('get_map_people', 'get_map_view')),
                'there is no map of other people''s positions');

-- ID document age review
select tests.login(:F);
select tests.throws($q$select public.submit_age_verification('Passport', 'bbbbbbbb-0000-0000-0000-000000000002/id.jpg')$q$,
                    '%check%', 'ID document must be in your own folder');
select public.submit_age_verification('Citizenship certificate', 'ffffffff-0000-0000-0000-000000000006/id.jpg');
select tests.throws($q$select public.submit_age_verification('Passport', 'ffffffff-0000-0000-0000-000000000006/id2.jpg')$q$,
                    '%already_pending%', 'only one pending ID review at a time');
select tests.throws('select document_path from public.age_verifications', '%permission denied%',
                    'users cannot read the stored document path');
select tests.throws($q$update public.profiles set age_verified = true$q$, '%permission denied%', 'cannot self-confirm age');
select tests.login(:C);
select tests.ok((select count(*) from public.age_verifications) = 0, 'users cannot see others'' ID reviews');

-- Admin
select tests.login(:Z);
select tests.ok((select min_age from public.admin_list_age_verifications() where user_id = :F) = 18,
                'admin sees the country minimum age next to the ID');
select tests.ok(public.admin_review_age_verification(
                  (select id from public.admin_list_age_verifications() where user_id = :F), true)
                like 'ffffffff%', 'review returns the document path so the file can be deleted');
select tests.ok((select document_path is null and status = 'approved' from public.admin_list_age_verifications(null) where user_id = :F),
                'document path is cleared after review');
select tests.ok((public.admin_get_user(:F) -> 'profile' ->> 'age_verified')::boolean, 'approving confirms the user''s age');
select tests.ok((public.admin_get_user(:F) -> 'age_checks' -> 0 ->> 'status') = 'approved', 'admin sees a user''s ID check history');
select tests.ok(not ((public.admin_get_user(:F) -> 'age_checks' -> 0) ? 'document_path'), 'ID history never includes the file path');
select tests.ok((public.admin_get_user(:B) -> 'readiness' ->> 'ready')::boolean, 'admin sees whether a user is ready to match');
select tests.ok((public.admin_stats() ->> 'age_checks_pending') is not null
                and (public.admin_stats() ->> 'users_ready')::int >= 1, 'admin_stats includes ID checks and ready users');
select tests.ok((public.admin_stats() ->> 'messages_24h')::int >= 1, 'messages_24h counts sends even after delivery');
select public.admin_reset_age_check(:F, 'test');
reset role;
select set_config('test.photo', (select id::text from public.profile_photos where user_id = :F limit 1), false);
set role authenticated;
select tests.login(:Z);
select tests.throws($q$select public.admin_delete_photo(current_setting('test.photo')::uuid)$q$,
                    '%reason_required%', 'removing a photo needs a reason');
select public.admin_delete_photo(current_setting('test.photo')::uuid, 'Face not visible');
set role authenticated;
select tests.login(:F);
select tests.ok((select body from public.get_my_notices() limit 1) like '%Face not visible%', 'the user is told why their photo was removed');
select public.mark_notices_read(array(select id from public.get_my_notices()));
select tests.ok(not exists (select 1 from public.get_my_notices()), 'notices can be marked read');
select tests.login(:G);
select tests.ok(not exists (select 1 from public.user_notices), 'users cannot see other people''s notices');
select tests.login(:Z);
select tests.ok(not (public.admin_get_user(:F) -> 'profile' ->> 'age_verified')::boolean, 'admin can reset an age check');
select tests.ok(public.is_admin(), 'admin is recognised');
select tests.ok((public.admin_stats() ->> 'verifications_pending')::int = 1, 'admin_stats counts pending verifications');
select tests.ok((select count(*) from public.admin_search_users('bikash')) = 1, 'admin can search users by name');
select tests.ok((public.admin_get_user(:B) -> 'profile' ->> 'email') = 'b@test.dev', 'admin can examine a user');
select tests.ok((select count(*) from public.admin_list_errors()) = 2, 'admin sees grouped app errors');
select tests.throws($q$select public.admin_review_verification((select id from public.admin_list_verifications() limit 1), false)$q$,
                    '%reason_required%', 'rejecting a verification needs a reason');
select tests.ok(public.admin_review_verification((select id from public.admin_list_verifications() limit 1), true)
                = 'bbbbbbbb-0000-0000-0000-000000000002/selfie.jpg', 'review returns the selfie path so it can be deleted');
select tests.ok((select selfie_path is null from public.admin_list_verifications(null) where user_id = :B),
                'selfie path is cleared after review');
select tests.ok((public.admin_get_user(:B) -> 'profile' ->> 'is_verified')::boolean, 'approving verification marks the user verified');
select tests.ok((select count(*) from public.admin_list_reports('open')) >= 1, 'admin sees open reports');
select public.admin_resolve_report((select id from public.admin_list_reports('open') where reported_id = :C limit 1),
                                   'actioned', 'suspended', 'spam links');
select tests.ok((public.admin_get_user(:C) -> 'profile' ->> 'status') = 'suspended', 'admin can suspend through a report');
select tests.throws($q$select public.admin_upsert_age_rule('NP', 16)$q$, '%never be below 18%', 'age rule can never go below 18');
select public.admin_upsert_age_rule('np', 19, 'test');
select tests.ok(public.min_age_for_country('NP') = 19, 'admin can raise a country''s minimum age');
select public.admin_delete_age_rule('NP');
select tests.ok((select count(*) from public.admin_actions where admin_id = :Z) >= 4, 'admin actions are written to the audit log');
select public.admin_set_user_status(:C, 'active', 'appeal accepted');
reset role;

-- -----------------------------------------------------------------------------
-- Usernames and hashed ban list
-- -----------------------------------------------------------------------------
\set L '''66666666-0000-0000-0000-00000000000a'''
insert into auth.users (id, email) values (:L, 'KIM@Test.dev');  -- same person as K, different casing
set role authenticated;
select tests.login(:A);
update public.profiles set username = 'Asha_K';
select tests.ok((select username from public.profiles) = 'asha_k', 'usernames are stored lowercase');
select tests.login(:B);
select tests.ok(not public.is_username_available('ASHA_K'), 'taken username is unavailable (case-insensitive)');
select tests.ok(public.is_username_available('bikash.np'), 'free username is available');
select tests.ok(not public.is_username_available('admin'), 'reserved usernames are unavailable');
select tests.ok(not public.is_username_available('no spaces!'), 'invalid usernames are unavailable');
select tests.throws($q$update public.profiles set username = 'asha_k'$q$, '%duplicate%', 'duplicate usernames are rejected');
select tests.throws($q$update public.profiles set username = 'support'$q$, '%reserved%', 'reserved usernames are rejected');
select tests.login(:K);
update public.profiles set username = 'kim99';
select tests.login(:Z);
select public.admin_set_user_status(:K, 'banned', 'scam');
reset role;
select tests.ok((select count(*) from public.banned_identifiers) = 2, 'ban stores hashed email + username');
select tests.ok(not exists (select 1 from public.banned_identifiers where hash like '%kim%'), 'ban list holds hashes, not plain text');
set role authenticated;
select tests.throws('select count(*) from public.banned_identifiers', '%permission denied%', 'clients cannot read the ban list');
select tests.login(:L);
select tests.throws($q$insert into public.profiles (id, display_name, birthdate, gender)
                       values ('66666666-0000-0000-0000-00000000000a', 'Kim again', '1995-01-01', 'man')$q$,
                    '%banned%', 'banned email cannot sign up again');
select tests.ok(not public.is_username_available('KIM99'), 'banned username cannot be reused');
reset role;

-- -----------------------------------------------------------------------------
-- Rewarded ads: only the server can grant extra likes
-- -----------------------------------------------------------------------------
set role authenticated;
select tests.login(:A);
select tests.ok((public.get_like_allowance() ->> 'limit')::int = 25, 'base daily like limit is 25');
select tests.ok((public.get_like_allowance() ->> 'swipe_limit')::int = 100, 'base daily swipe limit is 100');
select tests.throws('select count(*) from public.swipe_log', '%permission denied%', 'the swipe log is not readable');
select tests.throws($q$select public.grant_ad_reward('tx-fake', 'aaaaaaaa-0000-0000-0000-000000000001', 50, 'x')$q$,
                    '%permission denied%', 'users cannot grant themselves ad rewards');
select tests.throws($q$insert into public.ad_rewards (transaction_id, user_id, reward_likes) values ('t', 'aaaaaaaa-0000-0000-0000-000000000001', 50)$q$,
                    '%permission denied%', 'users cannot insert ad rewards directly');
set role service_role;
select tests.ok(public.grant_ad_reward('tx-1', :A, 10, 'unit') = 'granted', 'verified reward is granted');
select tests.ok(public.grant_ad_reward('tx-1', :A, 10, 'unit') = 'duplicate', 'same Google transaction is never granted twice');
select public.grant_ad_reward('tx-' || n, :A, 10, 'unit') from generate_series(2, 10) n;
select tests.ok(public.grant_ad_reward('tx-11', :A, 10, 'unit') = 'daily_cap', 'rewarded ads are capped at 10 a day');
set role authenticated;
select tests.login(:A);
select tests.ok((public.get_like_allowance() ->> 'limit')::int = 125, 'rewards raise the daily like limit');
select tests.ok((public.get_like_allowance() ->> 'swipe_limit')::int = 300, 'each reward adds 20 swipes');
select tests.ok((public.get_like_allowance() ->> 'rewarded_ads_left')::int = 0, 'allowance reports no ads left');
reset role;
insert into public.swipe_log (swiper_id) select :A::uuid from generate_series(1, 300);
set role authenticated;
select tests.login(:A);
select tests.throws($q$select public.swipe('dddddddd-0000-0000-0000-000000000004', 'pass')$q$,
                    '%out of swipes%', 'passes stop when the daily swipes are used up');
reset role;
delete from public.swipe_log where swiper_id = :A;

-- -----------------------------------------------------------------------------
-- Zodiac: shared as a sign only, and can be hidden
-- -----------------------------------------------------------------------------
reset role;
select tests.ok(private.zodiac_sign('2000-03-21') = 'aries' and private.zodiac_sign('2000-12-31') = 'capricorn'
                and private.zodiac_sign('2000-01-19') = 'capricorn' and private.zodiac_sign('2000-02-19') = 'pisces'
                and private.zodiac_sign('2000-08-10') = 'leo', 'zodiac signs are computed correctly');
set role authenticated;
select tests.login(:G);
select tests.ok((select zodiac from public.get_discovery_feed(20) where id = :H) is not null, 'feed shows zodiac sign');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) f where f::text ~ '\d{4}-\d{2}-\d{2}'),
                'feed never exposes a birthdate');
select tests.login(:H);
update public.privacy_settings set show_zodiac = false;
select tests.login(:G);
select tests.ok((select zodiac from public.get_discovery_feed(20) where id = :H) is null, 'hidden zodiac is not shared');
reset role;

-- -----------------------------------------------------------------------------
-- Random picks fill an empty feed and can be liked
-- -----------------------------------------------------------------------------
set role authenticated;
select tests.login(:G);
update public.discovery_preferences set country_codes = array['NP'];
select tests.ok((select is_random from public.get_discovery_feed(20) where id = :H), 'H is a random pick for G');
reset role;
select tests.make_ready(:G);
set role authenticated;
select tests.login(:G);
select tests.ok((public.swipe(:H, 'like') ->> 'matched')::boolean = false, 'liking a random pick works');
select tests.ok(not exists (select 1 from public.get_discovery_feed(20) where id = :H and not is_repeat),
                'a liked random pick leaves the new-people part of the feed');
select tests.ok((select is_repeat from public.get_discovery_feed(20) where id = :H), 'and comes back later as a repeat');
select public.swipe(:H, 'pass');
reset role;
select tests.ok((select action from public.swipes where swiper_id = :G and swipee_id = :H) = 'pass',
                'swiping a repeat again replaces the old swipe');

-- -----------------------------------------------------------------------------
-- Proof files never live longer than 7 days
-- -----------------------------------------------------------------------------
insert into public.age_verifications (user_id, country_code, document_type, document_path, created_at)
values (:G, 'FJ', 'Passport', '99999999-0000-0000-0000-000000000007/old.jpg', now() - interval '8 days');
insert into storage.objects (bucket_id, name, created_at) values
  ('id-documents', '99999999-0000-0000-0000-000000000007/old.jpg', now() - interval '8 days'),
  ('id-documents', '99999999-0000-0000-0000-000000000007/new.jpg', now());
set role authenticated;
select tests.login(:G);
select tests.throws('select * from public.admin_claim_expired_proofs()', '%forbidden%', 'users cannot run the proof cleanup');
select tests.throws('select * from public.service_claim_expired_proofs()', '%permission denied%',
                    'only the service role can run the scheduled cleanup');
select tests.login(:Z);
select tests.ok((select array_agg(path) from public.admin_claim_expired_proofs())
                = array['99999999-0000-0000-0000-000000000007/old.jpg'], 'cleanup lists only proof files older than 7 days');
select tests.ok((select status = 'rejected' and document_path is null and reject_reason like 'Not reviewed within 7 days%'
                   from public.admin_list_age_verifications(null) where user_id = :G),
                'a review still pending after 7 days expires, with a reason');
reset role;

-- -----------------------------------------------------------------------------
-- Moments: only you and your matches, only for 24 hours
-- -----------------------------------------------------------------------------
reset role;
insert into auth.users (id, email) values
  ('11111111-0000-4000-8000-000000000001', 'm@test.dev'),
  ('11111111-0000-4000-8000-000000000002', 'n@test.dev'),
  ('11111111-0000-4000-8000-000000000003', 'o@test.dev');
\set M '''11111111-0000-4000-8000-000000000001'''
\set N '''11111111-0000-4000-8000-000000000002'''
\set O '''11111111-0000-4000-8000-000000000003'''
set role authenticated;
select tests.login(:M);
insert into public.profiles (id, display_name, birthdate, gender, intention)
values (:M, 'Maya', current_date - interval '27 years', 'woman', 'long_term');
select tests.login(:N);
insert into public.profiles (id, display_name, birthdate, gender, intention)
values (:N, 'Nabin', current_date - interval '28 years', 'man', 'friends');
select tests.login(:O);
insert into public.profiles (id, display_name, birthdate, gender) values (:O, 'Ojas', current_date - interval '30 years', 'man');
reset role;
update public.profiles set status = 'active', onboarding_completed = true where id in (:M, :N, :O);
insert into public.matches (user_low, user_high) values (least(:M::uuid, :N::uuid), greatest(:M::uuid, :N::uuid));
insert into public.profile_interests (user_id, interest_id)
select u, i.id from (values (:M::uuid), (:N::uuid)) v(u), (select id from public.interests order by id limit 2) i;
insert into public.profile_interests (user_id, interest_id)
select :M::uuid, id from public.interests order by id offset 5 limit 1;
insert into public.profile_locations (user_id, lat, lng) values (:M, 27.7172, 85.3240), (:N, 27.6710, 85.4298);
set role authenticated;

select tests.login(:M);
select tests.throws('select * from public.moments', '%permission denied%', 'the moments table is not directly readable');
select tests.ok((public.post_moment('Sunset hike today ☀️')).body = 'Sunset hike today ☀️', 'I can post a text moment');
select tests.throws($q$select public.post_moment('   ')$q$, '%empty_moment%', 'an empty moment is refused');
select tests.throws($q$select public.post_moment(repeat('x', 201))$q$, '%moment_too_long%', 'moments stay short');
select tests.throws($q$select public.post_moment(null, 'cccccccc-0000-0000-0000-000000000003/x.jpg')$q$,
                    '%invalid_media%', 'a moment photo must be in my own folder');
insert into storage.objects (bucket_id, name, metadata)
values ('moments', '11111111-0000-4000-8000-000000000001/p.jpg', '{"size": 1000}');
select tests.ok((public.post_moment(null, '11111111-0000-4000-8000-000000000001/p.jpg')).photo_path is not null,
                'I can post a photo moment');
select tests.throws($q$insert into storage.objects (bucket_id, name) values ('moments', 'cccccccc-0000-0000-0000-000000000003/x.jpg')$q$,
                    '%row-level security%', 'nobody can upload into someone else''s moments folder');
select tests.ok((select count(*) from public.get_moments() where is_mine) = 2, 'I see my own moments');
select public.post_moment('third');
select tests.throws($q$select public.post_moment('fourth')$q$, '%moment_limit%', 'at most 3 live moments');

select tests.login(:N);
select tests.ok((select count(*) from public.get_moments() where user_id = :M) = 3, 'a match sees my moments');
select tests.ok(exists (select 1 from storage.objects where bucket_id = 'moments' and name like '11111111-0000-4000-8000-000000000001/%'),
                'a match can load the moment photo');
select tests.throws($q$select public.delete_moment((select id from public.get_moments() limit 1))$q$,
                    '%not_found%', 'a match cannot delete my moment');
select tests.ok((select array_length(shared_interests, 1) from public.get_match_insights() where other_user_id = :M) = 2,
                'match insights list the interests we share');
select tests.ok((select intention from public.get_match_insights() where other_user_id = :M) = 'long_term',
                'match insights include their mode');
select tests.ok((select distance_km from public.get_match_insights() where other_user_id = :M) between 10 and 13,
                'match insights include a rounded distance');

select tests.login(:O);
select tests.ok(not exists (select 1 from public.get_moments() where user_id = :M), 'a stranger cannot see my moments');
select tests.ok(not exists (select 1 from storage.objects where bucket_id = 'moments'), 'a stranger cannot load the photo');
select tests.ok(not exists (select 1 from public.get_match_insights()), 'no insights without a match');

select tests.login(:N);
select public.block_user(:M);
select tests.ok(not exists (select 1 from public.get_moments() where user_id = :M), 'blocking hides moments');
select tests.login(:M);
select tests.ok(not exists (select 1 from public.get_match_insights() where other_user_id = :N), 'and insights');

-- Expired: gone from the list, the photo can't be read, and it's cleaned up
reset role;
update public.moments set expires_at = now() - interval '2 hours' where user_id = :M;
update storage.objects set created_at = now() - interval '2 hours' where bucket_id = 'moments';
set role authenticated;
select tests.login(:M);
select tests.ok(not exists (select 1 from public.get_moments()), 'expired moments disappear');
select tests.ok((select array_agg(x) from public.claim_my_expired_moments() x)
                = array['11111111-0000-4000-8000-000000000001/p.jpg'], 'my expired photos are handed back for deletion');
select tests.ok(not exists (select 1 from public.get_moments()), 'and the expired moments are removed');
reset role;
select tests.ok(exists (select 1 from private.claim_expired_proofs() where bucket = 'moments'),
                'the scheduled cleanup also removes moment photos without a live moment');
set role authenticated;

-- No ID document needed: photos, bio and interests are enough
reset role;
insert into public.profile_photos (user_id, storage_path, position)
values (:M, '11111111-0000-4000-8000-000000000001/a.jpg', 0), (:M, '11111111-0000-4000-8000-000000000001/b.jpg', 1);
update public.profiles set bio = 'Hello', age_verified = false where id = :M;
select tests.ok(not exists (select 1 from public.age_verifications where user_id = :M)
                and private.profile_ready(:M), 'a profile with photos, bio and interests is ready without an ID');
set role authenticated;

-- -----------------------------------------------------------------------------
-- Green and red flags: only after chatting, and only you see your counts
-- -----------------------------------------------------------------------------
set role authenticated;
select tests.login(:A);
select tests.ok(public.set_profile_flag(:B, 'green') = 'green', 'someone I chatted with can get a green flag');
select tests.ok(public.get_my_flag_for(:B) = 'green', 'I can see the flag I gave');
select tests.ok(public.set_profile_flag(:B, 'red') = 'red', 'a flag can be changed');
select tests.throws('select * from public.profile_flags', '%permission denied%', 'nobody can read the flag table');
select tests.login(:C);
select tests.throws($q$select public.set_profile_flag('aaaaaaaa-0000-0000-0000-000000000001', 'red')$q$,
                    '%not_allowed%', 'strangers cannot flag anyone');
select tests.login(:B);
select tests.ok((public.get_my_profile_feedback() ->> 'red_flags')::int = 1, 'I see the red flags I received');
select tests.ok((public.get_my_profile_feedback() ->> 'likes')::int >= 1, 'I see how many likes I received');
select tests.throws('select * from public.admin_list_red_flagged()', '%forbidden%', 'only admins see the red-flag list');
select tests.login(:A);
select public.set_profile_flag(:B, null);
select tests.ok(public.get_my_flag_for(:B) is null, 'a flag can be taken back');
select tests.login(:Z);
select tests.ok((select count(*) from public.admin_list_red_flagged()) >= 0, 'admins can open the red-flag list');
reset role;

-- -----------------------------------------------------------------------------
-- No views that run with their owner's rights (Supabase "Security Definer View" lint)
-- -----------------------------------------------------------------------------
reset role;
select tests.ok(not exists (
         select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relkind = 'v'
            and not coalesce(c.reloptions @> array['security_invoker=true'], false)),
       'every view in public runs with the caller''s rights');

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
