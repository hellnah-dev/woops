-- Make someone an admin of the Woops admin panel.
-- 1. They must first have an account (sign up in the app with this email).
-- 2. Replace the email below, paste into Supabase → SQL Editor → New query → Run.
-- 3. The result should say "1 row". "0 rows" = no account with that email yet.
insert into public.admins (user_id)
select id from auth.users where email = 'you@example.com'
on conflict do nothing;

-- See all admins:
-- select u.email, a.created_at from public.admins a join auth.users u on u.id = a.user_id;

-- Remove an admin:
-- delete from public.admins where user_id = (select id from auth.users where email = 'old-admin@example.com');
