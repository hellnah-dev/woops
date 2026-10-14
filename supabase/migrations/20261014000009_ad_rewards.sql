-- =============================================================================
-- Rewarded ads: extra likes, granted ONLY by the server
--
-- Flow: the app shows an AdMob rewarded ad with the user's id attached →
-- Google calls our `admob-ssv` Edge Function (server-side verification) →
-- the function verifies Google's signature and inserts a row here →
-- the daily like limit grows. The app can never grant itself a reward.
-- =============================================================================

create table public.ad_rewards (
  transaction_id  text primary key,                 -- from Google: makes callbacks idempotent
  user_id         uuid not null references public.profiles (id) on delete cascade,
  reward_likes    int not null check (reward_likes between 1 and 50),
  ad_unit         text,
  created_at      timestamptz not null default now()
);

create index ad_rewards_user_recent_idx on public.ad_rewards (user_id, created_at desc);

alter table public.ad_rewards enable row level security;
revoke all on public.ad_rewards from anon, authenticated;
grant select on public.ad_rewards to authenticated;
create policy ad_rewards_select_own on public.ad_rewards
  for select to authenticated using (user_id = (select auth.uid()));

-- Tunables (change here; the Edge Function reads the same values via RPC-free SQL).
create or replace function private.base_daily_likes() returns int language sql immutable as $$ select 100 $$;
create or replace function private.max_rewarded_ads_per_day() returns int language sql immutable as $$ select 3 $$;

create or replace function private.reward_likes_today(p_user uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(reward_likes), 0)::int from public.ad_rewards
   where user_id = p_user and created_at > now() - interval '24 hours';
$$;

-- Daily like limit = base + verified ad rewards in the last 24 h (premium = unlimited).
create or replace function private.daily_like_limit(p_user uuid)
returns int
language sql
stable
set search_path = ''
as $$
  select case when private.is_premium(p_user) then null
              else private.base_daily_likes() + private.reward_likes_today(p_user) end;
$$;

-- Used by the Edge Function (service role) to record a verified reward.
create or replace function public.grant_ad_reward(p_transaction_id text, p_user uuid, p_reward_likes int, p_ad_unit text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_user) then
    return 'unknown_user';
  end if;
  if exists (select 1 from public.ad_rewards where transaction_id = p_transaction_id) then
    return 'duplicate';
  end if;
  if (select count(*) from public.ad_rewards
       where user_id = p_user and created_at > now() - interval '24 hours') >= private.max_rewarded_ads_per_day() then
    return 'daily_cap';
  end if;
  insert into public.ad_rewards (transaction_id, user_id, reward_likes, ad_unit)
  values (p_transaction_id, p_user, p_reward_likes, p_ad_unit)
  on conflict (transaction_id) do nothing;
  return 'granted';
end;
$$;

revoke all on function public.grant_ad_reward(text, uuid, int, text) from public, anon, authenticated;
grant execute on function public.grant_ad_reward(text, uuid, int, text) to service_role;

-- What the app shows: likes left today and whether a rewarded ad is available.
create or replace function public.get_like_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.require_user();
  v_limit int := private.daily_like_limit(v_me);
  v_used int;
  v_ads int;
begin
  select count(*) into v_used from public.swipes
   where swiper_id = v_me and action = 'like' and created_at > now() - interval '24 hours';
  select count(*) into v_ads from public.ad_rewards
   where user_id = v_me and created_at > now() - interval '24 hours';
  return jsonb_build_object(
    'unlimited', v_limit is null,
    'limit', v_limit,
    'used', v_used,
    'remaining', case when v_limit is null then null else greatest(v_limit - v_used, 0) end,
    'rewarded_ads_today', v_ads,
    'rewarded_ads_left', greatest(private.max_rewarded_ads_per_day() - v_ads, 0)
  );
end;
$$;

revoke all on function public.get_like_allowance() from public, anon;
grant execute on function public.get_like_allowance() to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
