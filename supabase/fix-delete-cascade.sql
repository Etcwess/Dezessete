-- =====================================================================
-- Correcao: permitir exclusao de usuarios
-- =====================================================================
-- O delete no Supabase Auth apaga o auth.users e, por cascade, o profile.
-- Mas as tabelas abaixo tinham FK para profiles SEM ON DELETE CASCADE,
-- entao sobravam registros orphan e o delete era abortado com
-- "Database error deleting user".
--
-- Rode no SQL Editor. Idempotente: remove a constraint antiga e recria.
-- =====================================================================

alter table public.events
  drop constraint if exists events_created_by_fkey;
alter table public.events
  add constraint events_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete cascade;

alter table public.comments
  drop constraint if exists comments_author_id_fkey;
alter table public.comments
  add constraint comments_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete cascade;

alter table public.invites
  drop constraint if exists invites_created_by_fkey;
alter table public.invites
  add constraint invites_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete cascade;

alter table public.notifications
  drop constraint if exists notifications_actor_id_fkey;
alter table public.notifications
  add constraint notifications_actor_id_fkey
  foreign key (actor_id) references public.profiles(id) on delete set null;

-- Verificacao: todas as FKs para profiles devem ter delete_action CASCADE
-- (ou SET NULL no caso de actor_id).
select
  tc.table_name,
  tc.constraint_name,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
order by tc.table_name, tc.constraint_name;
