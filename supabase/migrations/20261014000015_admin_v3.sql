-- =============================================================================
-- Admin panel catch-up for v3: ID-document age checks, profile readiness and
-- on-phone chats.
--  * admin_stats(): pending age checks, confirmed ages, ready profiles,
--    messages waiting in the relay; messages_24h now counts sends (the relay
--    deletes delivered messages, so counting `messages` would read ~0).
--  * admin_get_user(): age-check history, readiness checklist, message counts.
--  * admin_reset_age_check(): withdraw a confirmed age (e.g. after a report),
--    so the user must send an ID again before matching.
-- =============================================================================

create or replace function public.admin_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return jsonb_build_object(
    'users_total',          (select count(*) from public.profiles),
    'users_new_24h',        (select count(*) from public.profiles where created_at > now() - interval '24 hours'),
    'users_active_24h',     (select count(*) from public.profiles where last_active_at > now() - interval '24 hours'),
    'users_suspended',      (select count(*) from public.profiles where status = 'suspended'),
    'users_banned',         (select count(*) from public.profiles where status = 'banned'),
    'users_verified',       (select count(*) from public.profiles where is_verified),
    'matches_24h',          (select count(*) from public.matches where created_at > now() - interval '24 hours'),
    -- Chats live on phones now: count sends from the content-free send log.
    'messages_24h',         (select count(*) from public.message_send_log where created_at > now() - interval '24 hours'),
    'messages_waiting',     (select count(*) from public.messages),
    'age_checks_pending',   (select count(*) from public.age_verifications where status = 'pending'),
    'users_age_confirmed',  (select count(*) from public.profiles where age_verified),
    'users_ready',          (select count(*) from public.profiles p where p.status = 'active' and private.profile_ready(p.id)),
    'likes_24h',            (select count(*) from public.swipes where action = 'like' and created_at > now() - interval '24 hours'),
    'reports_open',         (select count(*) from public.reports where status in ('open', 'reviewing')),
    'verifications_pending',(select count(*) from public.verification_requests where status = 'pending'),
    'errors_24h',           (select count(*) from public.app_errors where created_at > now() - interval '24 hours'),
    'errors_unresolved',    (select count(distinct fingerprint) from public.app_errors where not resolved),
    'signups_by_day', coalesce((
        select jsonb_agg(jsonb_build_object('day', d, 'count', n) order by d)
          from (select date_trunc('day', created_at)::date d, count(*) n
                  from public.profiles where created_at > now() - interval '14 days' group by 1) s), '[]'::jsonb),
    'users_by_country', coalesce((
        select jsonb_agg(jsonb_build_object('country', c, 'count', n) order by n desc)
          from (select coalesce(country_code, '??') c, count(*) n from public.profiles group by 1
                order by 2 desc limit 15) s), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_get_user(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return (
    select jsonb_build_object(
      'profile', to_jsonb(p) || jsonb_build_object('email', u.email, 'age', private.age_on(p.birthdate),
                                                   'last_sign_in_at', u.last_sign_in_at),
      'photos', coalesce((select jsonb_agg(to_jsonb(ph) order by ph.position)
                            from public.profile_photos ph where ph.user_id = p.id), '[]'::jsonb),
      'interests', coalesce((select jsonb_agg(i.name order by i.name) from public.profile_interests pi
                               join public.interests i on i.id = pi.interest_id where pi.user_id = p.id), '[]'::jsonb),
      'prompts', coalesce((select jsonb_agg(to_jsonb(pr) order by pr.position)
                             from public.profile_prompts pr where pr.user_id = p.id), '[]'::jsonb),
      'reports_against', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                     from public.reports r where r.reported_id = p.id), '[]'::jsonb),
      'reports_made', (select count(*) from public.reports r where r.reporter_id = p.id),
      'age_checks', coalesce((select jsonb_agg(jsonb_build_object(
                                     'id', v.id, 'document_type', v.document_type, 'country_code', v.country_code,
                                     'status', v.status, 'reject_reason', v.reject_reason,
                                     'reviewed_at', v.reviewed_at, 'created_at', v.created_at) order by v.created_at desc)
                                   from public.age_verifications v where v.user_id = p.id), '[]'::jsonb),
      'readiness', jsonb_build_object(
          'ready', private.profile_ready(p.id),
          'photos', (select count(*) from public.profile_photos ph where ph.user_id = p.id),
          'has_bio', char_length(btrim(p.bio)) > 0,
          'interests', (select count(*) from public.profile_interests pi where pi.user_id = p.id),
          'min_age', private.min_age_for(p.country_code)),
      'verifications', coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc)
                                   from public.verification_requests v where v.user_id = p.id), '[]'::jsonb),
      'counts', jsonb_build_object(
          'likes_sent', (select count(*) from public.swipes s where s.swiper_id = p.id and s.action = 'like'),
          'likes_received', (select count(*) from public.swipes s where s.swipee_id = p.id and s.action = 'like'),
          'matches', (select count(*) from public.matches m where p.id in (m.user_low, m.user_high)),
          'messages_sent_24h', (select count(*) from public.message_send_log l
                                 where l.sender_id = p.id and l.created_at > now() - interval '24 hours'),
          'messages_waiting_for_them', (select count(*) from public.messages m
                                         join public.conversation_members cm on cm.conversation_id = m.conversation_id
                                        where cm.user_id = p.id and m.sender_id <> p.id),
          'blocked_by', (select count(*) from public.blocks b where b.blocked_id = p.id)),
      'admin_actions', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc)
                                   from public.admin_actions a where a.target_user = p.id), '[]'::jsonb)
    )
    from public.profiles p join auth.users u on u.id = p.id
   where p.id = p_user
  );
end;
$$;

create or replace function public.admin_reset_age_check(p_user uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  update public.profiles set age_verified = false where id = p_user;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  perform private.audit('age:reset', p_user, null, jsonb_build_object('reason', p_reason));
end;
$$;

revoke all on function public.admin_stats(), public.admin_get_user(uuid), public.admin_reset_age_check(uuid, text)
  from public, anon;
grant execute on function public.admin_stats(), public.admin_get_user(uuid), public.admin_reset_age_check(uuid, text)
  to authenticated;
