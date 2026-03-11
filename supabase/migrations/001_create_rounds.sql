-- Enable realtime (run once per project)
begin;
drop publication if exists supabase_realtime;
create publication supabase_realtime;
commit;

-- Conflict resolution: discard updates with an older timestamp
create or replace function discard_older_updates()
returns trigger as $$
begin
  if new.updated_at <= old.updated_at then
    return null;
  end if;
  return new;
end;
$$ language plpgsql;

-- Rounds table (mirrors the local Drift schema)
create table if not exists rounds (
  id          text        not null,
  user_id     uuid        references auth.users(id) on delete cascade,
  updated_at  timestamptz not null,
  deleted     boolean     not null default false,

  player_name     text    not null,
  player_handicap float   not null default 0,
  course_id       text    not null,
  course_name     text    not null,
  date            timestamptz not null, -- round start date
  status          text    not null default 'in_progress',
  data            text    not null default '{}',  -- JSON holePlays

  primary key (id)
);

create trigger rounds_handle_conflicts
  before update on rounds
  for each row execute function discard_older_updates();

alter publication supabase_realtime add table rounds;

-- Optional: Row-Level Security (enable once auth is fully wired)
-- alter table rounds enable row level security;
-- create policy "Users can access their own rounds"
--   on public.rounds for all
--   using (auth.uid() = user_id);
