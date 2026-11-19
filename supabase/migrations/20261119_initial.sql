-- Fitness app database (applied 19 Nov 2026 to project gkttfnwsdhfuknfmwolp).
-- Re-run this file on a new empty Supabase project (e.g. a separate test project) to get the same setup.

-- Profiles: one per login. role: 'user' | 'admin'. plan: 'free' | 'paid'.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  role text not null default 'user' check (role in ('user','admin')),
  plan text not null default 'free',
  is_test boolean not null default false,
  created_at timestamptz not null default now()
);

-- App documents per user (settings, saved foods, recipes, days).
create table public.docs (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  kind text generated always as (coalesce(data->>'kind', case when id like 'day-%' then 'day' when id = 'settings' then 'settings' else null end)) stored,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index docs_user_kind on public.docs (user_id, kind);

-- Shared barcode products.
create table public.products (
  barcode text primary key,
  name text not null,
  per100 jsonb not null,
  unit_name text,
  unit_grams numeric,
  source text not null default 'user',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Daily estimate limits per plan (null = unlimited) and global settings.
create table public.plan_limits (plan text primary key, daily_estimates integer);
insert into public.plan_limits values ('free', 20), ('paid', null);

create table public.app_config (key text primary key, value integer not null, note text);
insert into public.app_config values ('global_daily_estimates', 300, 'Safety cap for the whole app per day (Israel time). Admins are not limited.');

-- Usage counter per user per day (Israel date). Written only by the server function.
create table public.usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  estimates integer not null default 0,
  primary key (user_id, day)
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email) on conflict do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.bump_usage(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_day date := (now() at time zone 'Asia/Jerusalem')::date;
  v_role text; v_plan text; v_limit integer; v_global integer; v_used integer; v_total integer;
begin
  select role, plan into v_role, v_plan from profiles where id = p_user;
  if v_role = 'admin' then
    insert into usage (user_id, day, estimates) values (p_user, v_day, 1)
      on conflict (user_id, day) do update set estimates = usage.estimates + 1;
    return jsonb_build_object('ok', true);
  end if;
  select daily_estimates into v_limit from plan_limits where plan = coalesce(v_plan, 'free');
  select value into v_global from app_config where key = 'global_daily_estimates';
  select coalesce(sum(estimates), 0) into v_total from usage u join profiles p on p.id = u.user_id where u.day = v_day and p.role <> 'admin';
  select coalesce(estimates, 0) into v_used from usage where user_id = p_user and day = v_day;
  v_used := coalesce(v_used, 0);
  if v_limit is not null and v_used >= v_limit then
    return jsonb_build_object('ok', false, 'error', 'daily_limit', 'limit', v_limit);
  end if;
  if v_global is not null and v_total >= v_global then
    return jsonb_build_object('ok', false, 'error', 'global_limit');
  end if;
  insert into usage (user_id, day, estimates) values (p_user, v_day, 1)
    on conflict (user_id, day) do update set estimates = usage.estimates + 1;
  return jsonb_build_object('ok', true, 'used', v_used + 1, 'limit', v_limit);
end; $$;

create or replace function public.refund_usage(p_user uuid) returns void
language sql security definer set search_path = public as $$
  update usage set estimates = greatest(0, estimates - 1)
  where user_id = p_user and day = (now() at time zone 'Asia/Jerusalem')::date;
$$;

create or replace function public.admin_set_test(p_user uuid, p_test boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update profiles set is_test = p_test where id = p_user;
end; $$;

-- Row level security
alter table public.profiles enable row level security;
alter table public.docs enable row level security;
alter table public.products enable row level security;
alter table public.plan_limits enable row level security;
alter table public.app_config enable row level security;
alter table public.usage enable row level security;

create policy "own profile or admin" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "update own name" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "own docs" on public.docs for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "admin reads docs" on public.docs for select to authenticated using (public.is_admin());
create policy "read products" on public.products for select to authenticated using (true);
create policy "add products" on public.products for insert to authenticated with check (created_by = auth.uid());
create policy "edit own products" on public.products for update to authenticated using (created_by = auth.uid() or public.is_admin());
create policy "read limits" on public.plan_limits for select to authenticated using (true);
create policy "read config" on public.app_config for select to authenticated using (true);
create policy "own usage or admin" on public.usage for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- Grants (auto-grant is off for this project)
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant select, insert, update, delete on public.docs to authenticated;
grant select, insert, update on public.products to authenticated;
grant select on public.plan_limits, public.app_config, public.usage to authenticated;
grant all on all tables in schema public to service_role;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke all on function public.bump_usage(uuid) from public, anon, authenticated;
grant execute on function public.bump_usage(uuid) to service_role;
revoke all on function public.refund_usage(uuid) from public, anon, authenticated;
grant execute on function public.refund_usage(uuid) to service_role;
revoke all on function public.admin_set_test(uuid, boolean) from public, anon;
grant execute on function public.admin_set_test(uuid, boolean) to authenticated;
