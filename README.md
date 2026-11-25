# מעקב כושר — Fitness app

Hebrew calorie and macro tracker with logins, built on Supabase and hosted on GitHub Pages.

- **Live:** `index.html` (https://orfreiman.github.io/fitness-app/)
- **Sandbox:** `sandbox/index.html` (https://orfreiman.github.io/fitness-app/sandbox/) — its own Supabase project (`mbfpoghxzcatqvdcleox`, empty), marked "ארגז חול". Every change goes here first, then to `index.html` after approval.
- **Database:** Supabase project `gkttfnwsdhfuknfmwolp` (Frankfurt). Schema in `supabase/migrations/`.
- **Server function:** `supabase/functions/estimate` — Claude estimates and label photos (Claude Haiku, key in the `ANTHROPIC_API_KEY` secret), daily limits, barcode lookup in Open Food Facts.

Limits are editable in the Supabase dashboard (Table Editor): `plan_limits` (per plan, per day) and `app_config` (`global_daily_estimates`). Admins are not limited.

The publishable key in the page is public by design; data is protected by row level security.

## Live since 26 Nov 2026
- Training section, coach training tools and the תזונה / תוכנית אימון switch are live, but **training is turned off for every user** (owner's choice for now). Turn it on per trainee in their page ("ניהול"), or for yourself in "מה אני רואה באפליקציה" on the מתאמנים screen.
- Live migration: `supabase/migrations/20261126_live_training_and_modules.sql` (training default off). Backup before it: schema `backup_20261126`.
- Server function `estimate` v4 deployed to live (passes food/workouts in invites).
- `exercises.json` at the root and in `sandbox/`: index of the public-domain exercise library github.com/yuhonas/free-exercise-db (images load from that repo).
- `index.html` (live) and `sandbox/index.html` differ only in title, icon paths, badge, Supabase URL/key and `INVITE_TRAIN_DEFAULT`.
