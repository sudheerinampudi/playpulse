-- Play Pulse: guests can report how busy it is (sign-in is optional).
-- Run once in SQL Editor, AFTER supabase-guests.sql and supabase-busyness.sql. Safe to re-run.
-- Needs "Allow anonymous sign-ins" ON (already done for guest Join).

alter table reports add column if not exists is_guest boolean not null default false;

-- Guests (anonymous sessions) may now insert their own reports.
drop policy if exists "signed-in insert own report" on reports;
drop policy if exists "insert own report" on reports;
create policy "insert own report" on reports for insert to authenticated with check (user_id = auth.uid());

-- Mark guest reports and limit them: 1 report per park+sport every 15 minutes, 10 per day per guest.
create or replace function check_guest_report() returns trigger language plpgsql as $$
begin
  new.reporter_name := left(btrim(new.reporter_name), 40);
  if length(new.reporter_name) < 1 then raise exception 'Name is required'; end if;
  new.is_guest := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  if new.is_guest then
    if exists (select 1 from reports where user_id = new.user_id and park_slug = new.park_slug and sport = new.sport
               and created_at > now() - interval '15 minutes') then
      raise exception 'You already reported this park a few minutes ago. Please try again later, or sign in.';
    end if;
    if (select count(*) from reports where user_id = new.user_id and created_at > now() - interval '24 hours') >= 10 then
      raise exception 'Guest report limit reached for today. Sign in to report more.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists report_guest_check on reports;
create trigger report_guest_check before insert on reports for each row execute function check_guest_report();

-- Today's updates: guests show as "Sam (guest)", members as "Sam L."
create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, level smallint, playing int, waiting int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select case when r.is_guest then btrim(r.reporter_name) || ' (guest)'
              else split_part(btrim(r.reporter_name), ' ', 1)
                   || case when position(' ' in btrim(r.reporter_name)) > 0
                           then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end end,
         r.level, r.playing, r.waiting, r.created_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport
    and r.created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
  order by r.created_at desc
  limit 50;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;
