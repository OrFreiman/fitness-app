# מעקב כושר — Fitness app

Hebrew calorie and macro tracker with logins, built on Supabase and hosted on GitHub Pages.

- **Live:** `index.html` (https://orfreiman.github.io/fitness-app/)
- **Sandbox:** `sandbox/index.html` (https://orfreiman.github.io/fitness-app/sandbox/) — its own Supabase project (`mbfpoghxzcatqvdcleox`, empty), marked "ארגז חול". Every change goes here first, then to `index.html` after approval.
- **Database:** Supabase project `gkttfnwsdhfuknfmwolp` (Frankfurt). Schema in `supabase/migrations/`.
- **Server function:** `supabase/functions/estimate` — Claude estimates and label photos (Claude Haiku, key in the `ANTHROPIC_API_KEY` secret), daily limits, barcode lookup in Open Food Facts.

Limits are editable in the Supabase dashboard (Table Editor): `plan_limits` (per plan, per day) and `app_config` (`global_daily_estimates`). Admins are not limited.

The publishable key in the page is public by design; data is protected by row level security.
