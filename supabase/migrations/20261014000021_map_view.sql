-- =============================================================================
-- Map in one request: my position, people near me AND my matches.
--
-- Before, the map made 2-3 calls (my location, people, then profiles). Now
-- get_map_view() returns everything as one JSON object. Matches appear on the
-- map with the same privacy as everyone else: position snapped to a ~2 km
-- grid and only if they show their distance.
-- =============================================================================

create or replace function public.get_map_view(p_limit int default 40)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_lat float8;
  v_lng float8;
  v_people jsonb;
  v_matches jsonb;
begin
  select l.lat, l.lng into v_lat, v_lng from public.profile_locations l where l.user_id = v_me;
  if v_lat is null then
    return jsonb_build_object('me', null, 'people', '[]'::jsonb, 'matches', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.distance_km), '[]'::jsonb) into v_people
    from public.get_map_people(p_limit) p;

  select coalesce(jsonb_agg(x order by (x ->> 'distance_km')::int), '[]'::jsonb) into v_matches
    from (
      select jsonb_build_object(
               'id', o.id,
               'display_name', o.display_name,
               'age', private.age_on(o.birthdate),
               'photo', (select ph.storage_path from public.profile_photos ph
                          where ph.user_id = o.id order by ph.position, ph.created_at limit 1),
               'distance_km', greatest(1, ceil(private.distance_km(v_lat, v_lng, l.lat, l.lng)))::int,
               'lat', (round((l.lat / 0.02)::numeric) * 0.02)::float8,
               'lng', (round((l.lng / 0.02)::numeric) * 0.02)::float8,
               'is_verified', o.is_verified,
               'match_id', m.id,
               'conversation_id', cv.id
             ) as x
        from public.matches m
        join public.conversations cv on cv.match_id = m.id
        join public.profiles o on o.id = case when m.user_low = v_me then m.user_high else m.user_low end
        join public.profile_locations l on l.user_id = o.id
        join public.privacy_settings ps on ps.user_id = o.id
       where v_me in (m.user_low, m.user_high)
         and m.unmatched_at is null
         and o.status = 'active'
         and ps.show_distance
         and not private.is_blocked_between(v_me, o.id)
       limit 100
    ) s;

  return jsonb_build_object(
    'me', jsonb_build_object('lat', v_lat, 'lng', v_lng),
    'people', v_people,
    'matches', v_matches
  );
end;
$$;

revoke all on function public.get_map_view(int) from public, anon;
grant execute on function public.get_map_view(int) to authenticated;
