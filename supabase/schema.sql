-- Tagwerk: zentrale Datenbank (SSOT) für iPhone-App und Web-App
-- Einmal im Supabase SQL Editor ausführen. Mehrfaches Ausführen schadet nicht.

create table if not exists public.groups (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null default '',
  sort double precision not null default 0,
  is_expanded boolean not null default true,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.lists (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null default '',
  theme text not null default 'blue',
  sort double precision not null default 0,
  is_default boolean not null default false,
  group_id uuid,
  created_at timestamptz not null default now(),
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_id uuid,
  title text not null default '',
  note text not null default '',
  is_completed boolean not null default false,
  completed_at timestamptz,
  is_important boolean not null default false,
  my_day_date timestamptz,
  my_day_added_at timestamptz,
  due timestamptz,
  reminder timestamptz,
  repeat_raw text,
  spawned_next boolean not null default false,
  created_at timestamptz not null default now(),
  sort double precision not null default 0,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.steps (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid,
  title text not null default '',
  is_completed boolean not null default false,
  sort double precision not null default 0,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Jede Änderung bekommt die Serverzeit. Danach richtet sich der Abgleich ("alles seit ...").
create or replace function public.tagwerk_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['groups', 'lists', 'tasks', 'steps'] loop
    execute format('drop trigger if exists touch on public.%I', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.tagwerk_touch()', t);
    execute format('create index if not exists %I on public.%I (user_id, updated_at)', t || '_sync_idx', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists own_rows on public.%I', t);
    execute format('create policy own_rows on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
