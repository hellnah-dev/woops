-- =============================================================================
-- Remove the map. Showing people as points on a map, even on a ~2 km grid,
-- reveals which neighbourhood they are in. Woops now shows only how far
-- away someone is ("Less than 2 km away", "12 km away"), like Tinder, and
-- never where. Distances still respect "Show distance".
-- =============================================================================

drop function if exists public.get_map_view(int);
drop function if exists public.get_map_people(int);
