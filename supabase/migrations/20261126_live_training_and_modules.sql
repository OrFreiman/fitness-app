-- Applied to LIVE (gkttfnwsdhfuknfmwolp) on 26 Nov 2026. Same as 20261125_training_and_modules.sql (sandbox),
-- except training is OFF by default: workouts_enabled default false, and new invites default to no training.
-- Backup taken first in schema backup_20261126 (profiles, docs, products, usage).
create policy "admin writes programs and kudos" on public.docs for insert to authenticated
  with check (public.is_admin() and (data->>'kind') in ('program','kudos'));
create policy "admin updates programs and kudos" on public.docs for update to authenticated
  using (public.is_admin() and (data->>'kind') in ('program','kudos'))
  with check (public.is_admin() and (data->>'kind') in ('program','kudos'));
create policy "admin deletes programs and kudos" on public.docs for delete to authenticated
  using (public.is_admin() and (data->>'kind') in ('program','kudos'));
alter table public.profiles add column if not exists food_enabled boolean not null default true;
alter table public.profiles add column if not exists workouts_enabled boolean not null default false;
create or replace function public.admin_set_modules(p_user uuid, p_food boolean, p_workouts boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update profiles set food_enabled = p_food, workouts_enabled = p_workouts where id = p_user;
end; $$;
revoke all on function public.admin_set_modules(uuid, boolean, boolean) from public, anon;
grant execute on function public.admin_set_modules(uuid, boolean, boolean) to authenticated;
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name, food_enabled, workouts_enabled)
  values (new.id, new.email, nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
          coalesce((new.raw_user_meta_data->>'food')::boolean, true),
          coalesce((new.raw_user_meta_data->>'workouts')::boolean, false))
  on conflict do nothing;
  return new;
end; $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
