-- =============================================================================
-- Replace the `public_profiles` view with `get_public_profile()`.
--
-- The view ran with its owner's rights (Supabase lint: "Security Definer
-- View"): correct, but all of its protection lived in one WHERE clause that
-- anyone could later loosen by accident, and it could be filtered freely by
-- the client. A function states its access rule explicitly and returns one
-- profile, like the rest of the API (get_discovery_feed, get_map_view, ...).
--
-- Who you can see is unchanged: yourself, active matches, and people who
-- liked you, never anyone blocked either way, never when signed out.
-- =============================================================================

create function public.get_public_profile(p_user uuid)
returns table (
  id uuid, display_name text, age int, gender text, bio text, intention text,
  job_title text, city text, photos text[], interests text[], prompts jsonb,
  country_code text, is_verified boolean, username text, zodiac text
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.display_name, c.age, c.gender, c.bio, c.intention, c.job_title, c.city,
         c.photos, c.interests, c.prompts, c.country_code, c.is_verified, c.username, c.zodiac
    from private.profile_cards c
   where c.id = p_user
     and c.status = 'active'
     and c.onboarding_completed
     and (select auth.uid()) is not null
     and (
           c.id = (select auth.uid())
        or exists (select 1 from public.matches m
                    where m.unmatched_at is null
                      and m.user_low = least(c.id, (select auth.uid()))
                      and m.user_high = greatest(c.id, (select auth.uid())))
        or exists (select 1 from public.swipes s
                    where s.swiper_id = c.id and s.swipee_id = (select auth.uid()) and s.action = 'like')
     )
     and not private.is_blocked_between(c.id, (select auth.uid()));
$$;

revoke all on function public.get_public_profile(uuid) from public, anon;
grant execute on function public.get_public_profile(uuid) to authenticated;

drop view public.public_profiles;
