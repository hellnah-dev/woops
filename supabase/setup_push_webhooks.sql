-- =============================================================================
-- Push notification webhooks (same as Dashboard → Database Webhooks, as SQL).
--
-- Sends each new message / match / like, and each ID or selfie review result,
-- to the push-notify Edge Function, which delivers the push through Firebase.
--
-- Run once in Supabase → SQL Editor. Safe to run again (it replaces itself).
-- The webhook secret is kept encrypted in Supabase Vault, not in this file:
-- put it in the line marked ⬇ (the generated local copy already has it).
-- =============================================================================

create extension if not exists pg_net;

-- ⬇ The PUSH_WEBHOOK_SECRET (same value as the Edge Function secret).
do $$
declare
  v_secret text := 'PASTE_PUSH_WEBHOOK_SECRET_HERE';
  v_id uuid;
begin
  if v_secret = 'PASTE_PUSH_WEBHOOK_SECRET_HERE' then
    raise exception 'Paste the webhook secret into this script first.';
  end if;
  select id into v_id from vault.secrets where name = 'push_webhook_secret';
  if v_id is null then
    perform vault.create_secret(v_secret, 'push_webhook_secret', 'Woops push-notify webhook secret');
  else
    perform vault.update_secret(v_id, v_secret);
  end if;
end $$;

-- Posts the change to push-notify in the same shape as a Supabase Database Webhook.
create or replace function private.push_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if v_secret is null then
    return null; -- not configured: never block the app's write
  end if;
  perform net.http_post(
    url := 'https://brvwwznmrtnjcvtitrrx.supabase.co/functions/v1/push-notify',
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
      'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
    ),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    timeout_milliseconds := 5000
  );
  return null;
exception when others then
  -- A push problem must never stop a message, match or like from saving.
  raise warning 'push webhook failed: %', sqlerrm;
  return null;
end;
$$;

revoke all on function private.push_webhook() from public, anon, authenticated;

-- The 5 webhooks. Tables that don't exist yet (migrations not applied) are skipped.
do $$
declare
  w record;
begin
  for w in
    select * from (values
      ('push_messages',  'messages',              'insert'),
      ('push_matches',   'matches',               'insert'),
      ('push_likes',     'swipes',                'insert'),
      ('push_age_check', 'age_verifications',     'update'),
      ('push_verified',  'verification_requests', 'update')
    ) as t(name, tbl, evt)
  loop
    if to_regclass('public.' || w.tbl) is null then
      raise notice 'skipped % (table public.% not found: apply the migrations first)', w.name, w.tbl;
      continue;
    end if;
    execute format('drop trigger if exists %I on public.%I', w.name, w.tbl);
    execute format(
      'create trigger %I after %s on public.%I for each row execute function private.push_webhook()',
      w.name, w.evt, w.tbl);
    raise notice 'created %', w.name;
  end loop;
end $$;

-- Check: should list the 5 triggers.
select tgname as webhook, tgrelid::regclass as table_name
  from pg_trigger
 where tgname in ('push_messages', 'push_matches', 'push_likes', 'push_age_check', 'push_verified')
 order by tgname;
