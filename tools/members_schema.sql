-- Lap swim membership check (run once in the Supabase SQL editor; safe to run again).
--
-- The member list lives in a table the public "anon" key can NOT read. The signup page only
-- calls check_member(), which answers true/false, so names are never sent to the browser.
-- Load or refresh the names with tools/update_members.py (it writes a SQL file that includes
-- this schema plus the names).

create extension if not exists fuzzystrmatch with schema extensions;

create table if not exists public.members (
  first_names text[] not null,   -- first + middle names, lowercase, e.g. {maria,elena}
  last_names  text[] not null    -- last name words, lowercase, e.g. {garcia,lopez}
);
alter table public.members enable row level security;   -- no policies: nobody can read it via the API
revoke all on table public.members from anon, authenticated;

-- 0..1 similarity: 1 = identical, 0.5 = about half the letters line up.
create or replace function public.lap_name_sim(a text, b text)
returns double precision language sql immutable set search_path = public, extensions as $$
  select case when coalesce(a, '') = '' or coalesce(b, '') = '' then 0
              else 1 - extensions.levenshtein(a, b)::double precision / greatest(length(a), length(b)) end;
$$;

-- Same first name, a small typo (1 letter; 2 for long names), or a short form ("chris" / "christopher").
create or replace function public.lap_first_close(a text, b text)
returns boolean language sql immutable set search_path = public, extensions as $$
  select a = b
      or (least(length(a), length(b)) >= 3 and (left(a, length(b)) = b or left(b, length(a)) = a))
      or (least(length(a), length(b)) >= 4
          and extensions.levenshtein(a, b) <= case when greatest(length(a), length(b)) >= 8 then 2 else 1 end);
$$;

-- tokens: the swimmer's name as lowercase words, first name first (the page prepares this).
-- Accepts first name close + last name close (typos, missing middle name, part of a two-part
-- last name, last/first swapped), and as a backup an exact first name with a last name that
-- is at least half similar (e.g. "jensen" vs "jansson").
create or replace function public.check_member(tokens text[])
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare
  n int := coalesce(array_length(tokens, 1), 0);
  m record; k int; f text; rest text[]; ex boolean; ok boolean; score double precision; g text; r text; l text;
begin
  if n < 2 or n > 8 then return false; end if;
  for k in 1..n loop
    if tokens[k] is null or tokens[k] !~ '^[a-z]{1,40}$' then return false; end if;
  end loop;
  for m in select first_names, last_names from public.members loop
    for k in 1..2 loop
      if k = 1 then f := tokens[1]; rest := tokens[2:n]; else f := tokens[n]; rest := tokens[1:n-1]; end if;
      ex := f = any(m.first_names);
      ok := ex;
      if not ok then
        foreach g in array m.first_names loop
          if public.lap_first_close(g, f) then ok := true; exit; end if;
        end loop;
      end if;
      continue when not ok;
      score := public.lap_name_sim(array_to_string(rest, ''), array_to_string(m.last_names, ''));
      foreach r in array rest loop
        foreach l in array m.last_names loop
          score := greatest(score, public.lap_name_sim(r, l));
        end loop;
      end loop;
      if score >= 0.75 or (ex and score >= 0.5) then return true; end if;
    end loop;
  end loop;
  return false;
end $$;

revoke all on function public.check_member(text[]) from public;
grant execute on function public.check_member(text[]) to anon, authenticated;
