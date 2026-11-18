# Supabase setup

The site now uses Supabase Auth and Storage instead of browser-local account
records. The publishable key in `supabase-client.js` is intended for browser
use; never put a `service_role` or secret key in this site.

## 1. Create the shared profile schema

In Supabase, open **SQL Editor**, create a query, paste in `supabase-setup.sql`,
and run it.

## 2. Configure email confirmation redirects

Open **Authentication → URL Configuration**:

- Set **Site URL** to `https://relaxed-lamington-c660d4.netlify.app`.
- Add `https://relaxed-lamington-c660d4.netlify.app/**` to the redirect URLs.

If you test on a local server, also add its exact origin, for example
`http://127.0.0.1:8765/**`.

## 3. Assign an administrator

Register an account through the site and confirm its email first. In the SQL
Editor, run the final commented `INSERT` from `supabase-setup.sql`, replacing
`ADMIN_EMAIL` with that account's email. The admin page now signs in through
Supabase Auth and requires this database role.

## 4. Publish the updated site

Deploy the complete website folder to Netlify, including `supabase-client.js`,
`supabase-setup.sql`, `SUPABASE_SETUP.md`, and the `vendor` folder. Then test
registration, email confirmation, login, and a QR scan from another device.

Profiles are not exposed until the account email is confirmed. QR profiles
publicly show name, photo, email, gender, country, city, and address. Phone
number is kept out of the QR profile.

Accounts previously saved in this browser's `localStorage` are not migrated;
they must register again to use shared Supabase login and profiles. This
deployment does not erase those old browser-local records.
