-- Runs the cleanup-proofs Edge Function every day at 03:00 UTC, so ID
-- documents and verification selfies never stay longer than 7 days.
--
-- 1. Deploy:          supabase functions deploy cleanup-proofs --no-verify-jwt
-- 2. Set the secret:  supabase secrets set CLEANUP_SECRET=<random string>
-- 3. Database → Extensions: enable pg_cron and pg_net.
-- 4. Replace <PROJECT_REF> and <CLEANUP_SECRET> below and run this once in the SQL Editor.
select cron.schedule(
  'woops-cleanup-proofs',
  '0 3 * * *',
  $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/cleanup-proofs',
    headers := jsonb_build_object('x-cleanup-secret', '<CLEANUP_SECRET>', 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);
