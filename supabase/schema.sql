-- =====================================================================
-- Dezessete — schema inicial para Supabase
-- =====================================================================
-- Execute no SQL Editor de um projeto NOVO. Idempotente o suficiente para
-- ser reexecutado, mas foi pensado para um banco vazio.
--
-- Modelo:
--   auth.users  -> profiles  (1:1, criado por trigger)
--   profiles    -> calendars (owner)
--   calendars  <-> profiles  (members, com cor por pessoa)
--   calendars  -> events -> rsvps / comments
--   calendars  -> invites (link de convite)
--   profiles   -> notifications (geradas por triggers / RPC)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Schema privado (funcoes que leem membership sem disparar RLS)
-- ---------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 60),
  color text not null default '#E8562A',
  created_at timestamptz not null default now()
);

create table if not exists public.calendars (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 60),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  calendar_id uuid not null references public.calendars(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  color text not null,
  joined_at timestamptz not null default now(),
  via_invite uuid,
  primary key (calendar_id, user_id)
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  calendar_id uuid not null references public.calendars(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  event_date date not null,
  event_time time,
  location text,
  event_type text not null default 'festa'
    check (event_type in ('festa', 'show', 'aniversario', 'reuniao', 'beber')),
  description text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.rsvps (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('yes', 'maybe', 'no')),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 400),
  created_at timestamptz not null default now()
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  calendar_id uuid not null references public.calendars(id) on delete cascade,
  code text not null unique,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  uses integer not null default 0 check (uses >= 0),
  revoked boolean not null default false
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  calendar_id uuid not null references public.calendars(id) on delete cascade,
  kind text not null check (kind in ('join','create','update','move','comment','rsvp','delete')),
  actor_id uuid references public.profiles(id),
  event_id uuid,
  status text,
  created_at timestamptz not null default now(),
  read boolean not null default false
);

-- ---------------------------------------------------------------------
-- 2. Indices (as policies filtram por estas colunas)
-- ---------------------------------------------------------------------
create index if not exists calendars_owner_id_idx on public.calendars (owner_id);
create index if not exists members_user_id_idx on public.members (user_id);
create index if not exists members_calendar_id_idx on public.members (calendar_id);
create index if not exists events_calendar_date_idx on public.events (calendar_id, event_date);
create index if not exists rsvps_user_id_idx on public.rsvps (user_id);
create index if not exists comments_event_id_idx on public.comments (event_id);
create index if not exists invites_calendar_id_idx on public.invites (calendar_id);
create index if not exists notifications_user_cal_idx
  on public.notifications (user_id, calendar_id, created_at desc);

-- ---------------------------------------------------------------------
-- 3. Helpers security definer (quebram a recursao RLS)
-- ---------------------------------------------------------------------

-- IDs dos calendarios dos quais o usuario e membro.
create or replace function private.my_calendar_ids()
returns setof uuid
language sql security definer set search_path = '' stable
as $$
  select m.calendar_id from public.members m where m.user_id = (select auth.uid());
$$;

-- O usuario e membro deste calendario?
create or replace function private.is_calendar_member(p_calendar_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1 from public.members m
    where m.calendar_id = p_calendar_id and m.user_id = (select auth.uid())
  );
$$;

-- O usuario e o dono deste calendario?
create or replace function private.is_calendar_owner(p_calendar_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1 from public.calendars c
    where c.id = p_calendar_id and c.owner_id = (select auth.uid())
  );
$$;

-- O usuario pode acessar este evento?
create or replace function private.can_access_event(p_event_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id
      and (private.is_calendar_member(e.calendar_id)
           or private.is_calendar_owner(e.calendar_id))
  );
$$;

-- Notifica todos os membros exceto o autor da acao.
create or replace function private.notify_members(
  p_calendar_id uuid,
  p_kind text,
  p_actor uuid,
  p_event_id uuid,
  p_status text
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (user_id, calendar_id, kind, actor_id, event_id, status)
  select m.user_id, p_calendar_id, p_kind, p_actor, p_event_id, p_status
  from public.members m
  where m.calendar_id = p_calendar_id
    and m.user_id is distinct from p_actor;
end;
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------------
-- 4. Triggers de sistema
-- ---------------------------------------------------------------------

-- Cria o profile automaticamente quando um usuario se registra.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, color)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''),
             split_part(new.email, '@', 1)),
    coalesce(nullif(new.raw_user_meta_data ->> 'color', ''), '#E8562A')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists events_updated_at on public.events;
create trigger events_updated_at before update on public.events
  for each row execute function public.set_updated_at();

drop trigger if exists rsvps_updated_at on public.rsvps;
create trigger rsvps_updated_at before update on public.rsvps
  for each row execute function public.set_updated_at();

-- Notificacoes automaticas
create or replace function public.on_event_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_kind text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'create';
  elsif (old.event_date, old.event_time) is distinct from (new.event_date, new.event_time) then
    v_kind := 'move';
  else
    v_kind := 'update';
  end if;
  perform private.notify_members(new.calendar_id, v_kind, (select auth.uid()), new.id, null);
  return new;
end;
$$;

drop trigger if exists events_notify on public.events;
create trigger events_notify after insert or update on public.events
  for each row execute function public.on_event_change();

create or replace function public.on_comment_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_cal uuid;
begin
  select e.calendar_id into v_cal from public.events e where e.id = new.event_id;
  perform private.notify_members(v_cal, 'comment', new.author_id, new.event_id, null);
  return new;
end;
$$;

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify after insert on public.comments
  for each row execute function public.on_comment_insert();

create or replace function public.on_rsvp_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_cal uuid;
begin
  select e.calendar_id into v_cal from public.events e where e.id = new.event_id;
  perform private.notify_members(v_cal, 'rsvp', new.user_id, new.event_id, new.status);
  return new;
end;
$$;

drop trigger if exists rsvps_notify on public.rsvps;
create trigger rsvps_notify after insert or update on public.rsvps
  for each row execute function public.on_rsvp_change();

-- ---------------------------------------------------------------------
-- 5. RLS: habilitar, revogar grants padrao, conceder so o necessario
-- ---------------------------------------------------------------------

alter table public.profiles     enable row level security;
alter table public.calendars    enable row level security;
alter table public.members      enable row level security;
alter table public.events       enable row level security;
alter table public.rsvps        enable row level security;
alter table public.comments     enable row level security;
alter table public.invites      enable row level security;
alter table public.notifications enable row level security;

revoke all on table public.profiles, public.calendars, public.members,
  public.events, public.rsvps, public.comments, public.invites,
  public.notifications from anon, authenticated;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.calendars to authenticated;
grant select on table public.members to authenticated; -- escrita so via RPC
grant select, insert, update, delete on table public.events to authenticated;
grant select, insert, update, delete on table public.rsvps to authenticated;
grant select, insert, delete on table public.comments to authenticated; -- sem update
grant select, insert, update, delete on table public.invites to authenticated;
grant select, update on table public.notifications to authenticated; -- escrita via trigger

-- 5.1 profiles
create policy "profiles_select" on public.profiles
  for select to authenticated using (true);

create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "profiles_delete_own" on public.profiles
  for delete to authenticated using ((select auth.uid()) = id);

-- 5.2 calendars
create policy "calendars_select_members" on public.calendars
  for select to authenticated
  using (id in (select private.my_calendar_ids()) or owner_id = (select auth.uid()));

create policy "calendars_insert_own" on public.calendars
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "calendars_update_owner" on public.calendars
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "calendars_delete_owner" on public.calendars
  for delete to authenticated using (owner_id = (select auth.uid()));

-- 5.3 members (leitura; escrita via RPC)
create policy "members_select_visible" on public.members
  for select to authenticated
  using (private.is_calendar_member(calendar_id) or private.is_calendar_owner(calendar_id));

-- 5.4 events
create policy "events_select_members" on public.events
  for select to authenticated using (private.is_calendar_member(calendar_id));

create policy "events_insert_members" on public.events
  for insert to authenticated
  with check (created_by = (select auth.uid()) and private.is_calendar_member(calendar_id));

create policy "events_update_author" on public.events
  for update to authenticated
  using (created_by = (select auth.uid()) and private.is_calendar_member(calendar_id))
  with check (created_by = (select auth.uid()) and private.is_calendar_member(calendar_id));

create policy "events_delete_author" on public.events
  for delete to authenticated
  using (created_by = (select auth.uid()) and private.is_calendar_member(calendar_id));

-- 5.5 rsvps
create policy "rsvps_select_members" on public.rsvps
  for select to authenticated using (private.can_access_event(event_id));

create policy "rsvps_insert_own" on public.rsvps
  for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_access_event(event_id));

create policy "rsvps_update_own" on public.rsvps
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and private.can_access_event(event_id));

create policy "rsvps_delete_own" on public.rsvps
  for delete to authenticated using (user_id = (select auth.uid()));

-- 5.6 comments
create policy "comments_select_members" on public.comments
  for select to authenticated using (private.can_access_event(event_id));

create policy "comments_insert_own" on public.comments
  for insert to authenticated
  with check (author_id = (select auth.uid()) and private.can_access_event(event_id));

create policy "comments_delete_own" on public.comments
  for delete to authenticated using (author_id = (select auth.uid()));

-- 5.7 invites
create policy "invites_select_members" on public.invites
  for select to authenticated
  using (private.is_calendar_member(calendar_id) or private.is_calendar_owner(calendar_id));

create policy "invites_insert_owner" on public.invites
  for insert to authenticated
  with check (created_by = (select auth.uid()) and private.is_calendar_owner(calendar_id));

create policy "invites_update_owner" on public.invites
  for update to authenticated
  using (private.is_calendar_owner(calendar_id))
  with check (private.is_calendar_owner(calendar_id));

create policy "invites_delete_owner" on public.invites
  for delete to authenticated using (private.is_calendar_owner(calendar_id));

-- 5.8 notifications
create policy "notifications_select_own" on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));

create policy "notifications_update_own" on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- 6. RPCs (operacoes que tocam varias tabelas)
-- ---------------------------------------------------------------------

-- Gerador de codigo de convite: ABCD-1234
create or replace function public.gen_invite_code()
returns text language sql volatile set search_path = ''
as $$
  select
    upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4)) || '-' ||
    upper(substr(md5(random()::text || clock_timestamp()::text), 10, 4));
$$;

create or replace function public.create_calendar(
  p_name text,
  p_color text,
  p_with_starter boolean default false
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_colors text[] := array['#E8562A','#D9482B','#D98A00','#B07500','#00865A',
                            '#1F8A5B','#7A5A15','#5E6B12','#B5476E','#C2185B'];
begin
  if char_length(coalesce(trim(p_name), '')) < 2 then
    raise exception 'Nome muito curto.';
  end if;

  insert into public.calendars (name, owner_id)
  values (trim(p_name), (select auth.uid()))
  returning id into v_id;

  insert into public.members (calendar_id, user_id, color)
  values (v_id, (select auth.uid()), coalesce(p_color, v_colors[1]));

  insert into public.invites (calendar_id, code, created_by)
  values (v_id, public.gen_invite_code(), (select auth.uid()));

  if p_with_starter then
    insert into public.events
      (calendar_id, title, event_date, event_time, location, event_type, description, created_by)
    values
      (v_id, 'Dia do Copão', current_date + 2, '19:00', 'Praia de Iracema', 'beber',
       'Cada um leva seu copo e a bebida que quiser. Encontro no calçadão.', (select auth.uid())),
      (v_id, 'Churrasco de domingo', current_date + 5, '13:00', 'A combinar', 'festa',
       'Confirmar presença para calcular a carne.', (select auth.uid())),
      (v_id, 'Cinema com a turma', current_date + 9, '20:00', 'Shopping', 'reuniao',
       'Escolher o filme nos comentários.', (select auth.uid())),
      (v_id, 'Niver da turma', current_date + 14, '19:30', 'Varjota', 'aniversario',
       'Mesa reservada. Chegar pontual.', (select auth.uid())),
      (v_id, 'Show no fim do mês', current_date + 19, '23:00', 'Benfica', 'show',
       'Lineup local. Encontro na porta às 22h40.', (select auth.uid()));
  end if;

  return v_id;
end;
$$;

create or replace function public.join_calendar_by_invite(p_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_inv public.invites;
  v_color text;
  v_colors text[] := array['#E8562A','#D9482B','#D98A00','#B07500','#00865A',
                            '#1F8A5B','#7A5A15','#5E6B12','#B5476E','#C2185B'];
begin
  select * into v_inv
  from public.invites i
  where upper(i.code) = upper(trim(p_code))
  for update;

  if not found then
    raise exception 'Convite não encontrado.';
  end if;
  if v_inv.revoked or (v_inv.expires_at is not null and v_inv.expires_at < now()) then
    raise exception 'Convite indisponível.';
  end if;

  select c into v_color
  from unnest(v_colors) as c
  where c not in (select m.color from public.members m where m.calendar_id = v_inv.calendar_id)
  limit 1;

  v_color := coalesce(v_color, v_colors[1]);

  insert into public.members (calendar_id, user_id, color, via_invite)
  values (v_inv.calendar_id, (select auth.uid()), v_color, v_inv.id)
  on conflict (calendar_id, user_id) do nothing;

  update public.invites i set uses = i.uses + 1 where i.id = v_inv.id;

  perform private.notify_members(v_inv.calendar_id, 'join', (select auth.uid()), null, null);

  return v_inv.calendar_id;
end;
$$;

create or replace function public.leave_calendar(p_calendar_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if private.is_calendar_owner(p_calendar_id) then
    raise exception 'O dono não pode sair. Remova o calendário ou transfira a posse.';
  end if;

  delete from public.rsvps r
  using public.events e
  where e.id = r.event_id and e.calendar_id = p_calendar_id and r.user_id = (select auth.uid());

  delete from public.members m
  where m.calendar_id = p_calendar_id and m.user_id = (select auth.uid());

  delete from public.notifications n
  where n.calendar_id = p_calendar_id and n.user_id = (select auth.uid());
end;
$$;

create or replace function public.remove_calendar(p_calendar_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_count integer;
begin
  if not private.is_calendar_owner(p_calendar_id) then
    raise exception 'Só o dono pode remover o calendário.';
  end if;

  select count(*) into v_count from public.members m where m.calendar_id = p_calendar_id;
  if v_count > 1 then
    raise exception 'Só é possível remover calendários com um único membro.';
  end if;

  delete from public.calendars c where c.id = p_calendar_id;
end;
$$;

-- ATENCAO: o Supabase concede EXECUTE a "anon" por default privileges.
-- Por isso e necessario revogar de public E de anon explicitamente.
revoke all on function public.gen_invite_code() from public, anon;
revoke all on function public.create_calendar(text, text, boolean) from public, anon;
revoke all on function public.join_calendar_by_invite(text) from public, anon;
revoke all on function public.leave_calendar(uuid) from public, anon;
revoke all on function public.remove_calendar(uuid) from public, anon;

grant execute on function public.gen_invite_code() to authenticated;
grant execute on function public.create_calendar(text, text, boolean) to authenticated;
grant execute on function public.join_calendar_by_invite(text) to authenticated;
grant execute on function public.leave_calendar(uuid) to authenticated;
grant execute on function public.remove_calendar(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Realtime (notificacoes e ranking ao vivo)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['events','rsvps','comments','notifications','members','calendars'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Fim
-- ---------------------------------------------------------------------
