-- 19 Nov 2026: disable/re-enable trainees, names on profiles.
alter table public.profiles add column if not exists disabled boolean not null default false;
alter table public.profiles add column if not exists disabled_at timestamptz;

create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where id = auth.uid() and disabled);
$$;
revoke all on function public.is_active() from public, anon;
grant execute on function public.is_active() to authenticated;

drop policy if exists "own docs" on public.docs;
create policy "own docs" on public.docs for all to authenticated
  using (user_id = auth.uid() and public.is_active())
  with check (user_id = auth.uid() and public.is_active());

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, nullif(trim(new.raw_user_meta_data->>'full_name'), ''))
  on conflict do nothing;
  return new;
end; $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

create or replace function public.admin_set_name(p_user uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update profiles set display_name = nullif(trim(p_name), '') where id = p_user;
end; $$;
revoke all on function public.admin_set_name(uuid, text) from public, anon;
grant execute on function public.admin_set_name(uuid, text) to authenticated;
