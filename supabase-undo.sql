-- Play Pulse: people can remove their own "coming later" / join (Undo). Busy reports cannot be undone.
-- Run once in SQL Editor, AFTER supabase-guests.sql. Safe to re-run.

drop policy if exists "delete own arrivals" on arrivals;
create policy "delete own arrivals" on arrivals for delete to authenticated using (user_id = auth.uid());

-- Coming-soon list now also says which entry is yours ("mine"), so the app can show "Remove me".
drop function if exists park_arrivals(text, text);
create or replace function park_arrivals(p_slug text, p_sport text)
returns table (who text, arriving_at timestamptz, mine boolean)
language sql security definer set search_path = public as $$
  select case when l.is_guest then btrim(l.reporter_name) || ' (guest)'
              else split_part(btrim(l.reporter_name), ' ', 1)
                   || case when position(' ' in btrim(l.reporter_name)) > 0
                           then ' ' || upper(left(regexp_replace(btrim(l.reporter_name), '^.*\s', ''), 1)) || '.' else '' end end,
         l.arriving_at,
         (l.user_id = auth.uid())
  from (
    select distinct on (user_id) user_id, reporter_name, is_guest, arriving_at
    from arrivals
    where park_slug = p_slug and sport = p_sport
      and created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
    order by user_id, created_at desc
  ) l
  where l.arriving_at > now()
  order by l.arriving_at
  limit 30;
$$;
grant execute on function park_arrivals(text, text) to anon, authenticated;
