-- =====================================================================
-- Correcao de grants das RPCs
-- =====================================================================
-- O Supabase concede EXECUTE a "anon" por default privileges em funcoes
-- novas do schema public. O REVOKE ... FROM PUBLIC do schema.sql nao
-- remove esse grant explicito. Esta correcaoencilha as funcoes para que
-- so "authenticated" possa chamalas.
--
-- Cole e execute no SQL Editor. Pode reexecutar quantas vezes quiser.
-- =====================================================================

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

-- Mesma correcao para os helpers privados (defesa em profundidade).
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Verificacao: as consultas abaixo devem retornar ZERO linhas para anon.
-- (Se aparecer alguma linha, o grant ainda esta solto.)
select distinct p.proname, r.rolname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as a
join pg_roles r on r.oid = a.grantee
where n.nspname in ('public','private')
  and p.proname in ('gen_invite_code','create_calendar','join_calendar_by_invite',
                    'leave_calendar','remove_calendar','my_calendar_ids',
                    'is_calendar_member','is_calendar_owner','can_access_event','notify_members')
  and r.rolname = 'anon'
  and a.privilege_type = 'EXECUTE';
