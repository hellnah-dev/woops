# Woops Admin Panel

A separate website for your moderation team. It is **not** part of the app and
is never shipped to users. It talks to the same Supabase project, and every
action is re-checked on the server against the `admins` table.

## Run it on your computer

```bash
cd admin
./make_config.sh                 # creates js/config.js from ../.env (URL + publishable key)
python3 -m http.server 8081      # then open http://localhost:8081
```

## Become an admin

1. Sign up in the Woops app with your email and a password.
2. In Supabase → **SQL Editor** → **New query**, run `supabase/make_admin.sql`
   with your email filled in (it should say "1 row").
3. Sign in at http://localhost:8081 with that same email and password.

If you sign in before step 2, the panel shows the exact SQL to copy.

## Put it online (its own website)

Upload this `admin/` folder, including `js/config.js`, to any static host:
Netlify Drop (drag the folder onto https://app.netlify.com/drop), Vercel,
Cloudflare Pages or GitHub Pages. Use a separate domain or subdomain, such as
`admin.yourdomain.com`. You can also move this folder into its own Git
repository; it has no dependencies on the app code.

Never put the Supabase service_role/secret key in this website.
