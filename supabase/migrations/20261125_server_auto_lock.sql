-- Server-side auto-lock (live since 25 Nov 2026). Runs every 15 minutes via pg_cron.
create or replace function public.auto_lock_days() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  with due as (
    select d.user_id, d.id, d.data, coalesce(s.data, '{}'::jsonb) as st
    from docs d
    left join docs s on s.user_id = d.user_id and s.id = 'settings'
    where d.kind = 'day'
      and (d.data->>'locked') is distinct from 'true'
      and (d.data->'autoLock') is distinct from 'false'::jsonb
      and (d.data->>'date') ~ '^\d{4}-\d{2}-\d{2}$'
      and jsonb_typeof(d.data->'items') = 'array'
      and exists (select 1 from jsonb_array_elements(d.data->'items') i where (i->>'planned') is distinct from 'true')
      and (((d.data->>'date')::date)::timestamp
           + make_interval(mins => coalesce(nullif(nullif(d.data->>'endMin', '')::numeric::int, 0), 1440)))
          at time zone 'Asia/Jerusalem' <= now()
  )
  update docs t set
    data = due.data || jsonb_build_object(
      'items', (select coalesce(jsonb_agg(x.i order by x.ord), '[]'::jsonb)
                from jsonb_array_elements(due.data->'items') with ordinality as x(i, ord)
                where (x.i->>'planned') is distinct from 'true'),
      'locked', true,
      'autoLocked', true,
      'serverLocked', true,
      'lockedAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'timesLocked', coalesce(nullif(due.data->>'timesLocked', '')::numeric::int, 0) + 1,
      'roundAdd', 0,
      'snap', jsonb_build_object(
        'maintenance', coalesce(nullif(due.st->'maintenance', 'null'::jsonb), '2000'::jsonb),
        'calGoal',     coalesce(nullif(due.st->'calGoal', 'null'::jsonb), '1700'::jsonb),
        'proteinGoal', coalesce(nullif(due.st->'proteinGoal', 'null'::jsonb), '120'::jsonb)),
      'sheet', 'off',
      'sheetErr', null,
      'updatedAt', (extract(epoch from now()) * 1000)::bigint),
    updated_at = now()
  from due
  where t.user_id = due.user_id and t.id = due.id;
  get diagnostics n = row_count;
  return n;
end; $$;

revoke all on function public.auto_lock_days() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('auto-lock-days', '*/15 * * * *', 'select public.auto_lock_days()');
