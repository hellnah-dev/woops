-- =============================================================================
-- No ID documents, like Tinder.
--
-- Age is checked at sign-up from the date of birth (the country's minimum
-- age is enforced by the existing triggers; someone under it never gets an
-- account). An ID photo is no longer needed to start matching: being ready
-- means 2 photos, a bio and 3 interests. The optional selfie check (the
-- verified badge) stays. Old review data is left untouched.
-- =============================================================================

create or replace function private.profile_ready(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
     where p.id = p_user
       and char_length(btrim(p.bio)) > 0
       and (select count(*) from public.profile_photos ph where ph.user_id = p.id) >= 2
       and (select count(*) from public.profile_interests pi where pi.user_id = p.id) >= 3
  );
$$;
