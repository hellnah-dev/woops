-- =============================================================================
-- Match insights respect privacy, like the feed, map and likes already do:
--  * no distance for someone who turned off "Show distance";
--  * no insights for suspended, banned or deleted-in-progress profiles.
-- =============================================================================

create or replace function public.get_match_insights()
returns table (other_user_id uuid, intention text, shared_interests text[], distance_km int)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select (select auth.uid()) as id),
  others as (
    select case when m.user_low = me.id then m.user_high else m.user_low end as uid
      from public.matches m, me
     where me.id in (m.user_low, m.user_high) and m.unmatched_at is null
  )
  select o.uid,
         p.intention,
         coalesce((select array_agg(i.name order by i.name)
                     from public.profile_interests a
                     join public.profile_interests b on b.interest_id = a.interest_id and b.user_id = o.uid
                     join public.interests i on i.id = a.interest_id
                    where a.user_id = (select id from me)), '{}'),
         case when coalesce(ps.show_distance, true) then
           (select greatest(1, ceil(private.distance_km(la.lat, la.lng, lb.lat, lb.lng)))::int
              from public.profile_locations la, public.profile_locations lb
             where la.user_id = (select id from me) and lb.user_id = o.uid)
         end
    from others o
    join public.profiles p on p.id = o.uid
    left join public.privacy_settings ps on ps.user_id = o.uid
   where private.is_active(o.uid)
     and not private.is_blocked_between(o.uid, (select id from me))
   limit 1000;
$$;

revoke all on function public.get_match_insights() from public, anon;
grant execute on function public.get_match_insights() to authenticated;
