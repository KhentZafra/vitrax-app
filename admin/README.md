# VITRAX Admin website

A static website (no build step) for managing the VITRAX app: users,
activities, feed posts, comments, hazards (with map), challenges and
user reports.

It uses only the **public anon key**. All permissions are enforced in
Supabase by row-level security (`supabase/018_admin.sql`), so only an
account with `profiles.is_admin = true` can see or change anything.

## One-time setup
1. Supabase SQL Editor -> run `supabase/018_admin.sql`.
2. Make yourself the first admin (use the email you sign in with):
   `update public.profiles set is_admin = true where email = 'you@example.com';`
3. `admin/config.js` already holds your project URL and anon key (it is
   gitignored). On a new machine, copy `config.example.js` to `config.js`.

## Run it on your computer
In a terminal, from the project folder:

    cd admin
    npx serve .

(or `python -m http.server 8080`) and open the address it prints.
Opening `index.html` by double-click can also work, but a local server
is more reliable.

## Put it online (later, with your domain)
Upload the contents of `admin/` (including your local `config.js`) to any
static host: Netlify, Vercel, Cloudflare Pages, GitHub Pages or your
RackNerd VPS (nginx). Then in Supabase -> Authentication -> URL
Configuration, add the site's address. Use HTTPS only.

## Safety notes
* Never put the `service_role` key in these files.
* Everything users typed is HTML-escaped before display.
* The site does not show private chat messages - only the reports people
  file. Suspending a user blocks them in the app (they are signed out when
  the app opens).
