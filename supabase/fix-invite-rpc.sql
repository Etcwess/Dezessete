-- =====================================================================
-- RPC publica para validar convite antes do login
-- =====================================================================
-- Um visitante sem conta nao pode ler calendars/invites por causa do RLS.
-- Esta function security definer valida o codigo e devolve so o necessario
-- para mostrar o banner "Convite para X" na tela de cadastro.
-- Nao expoe membros, eventos nem dados sensiveis.
-- =====================================================================

create or replace function public.check_invite(p_code text)
returns table (calendar_id uuid, calendar_name text, member_count integer, valid boolean, reason text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_inv public.invites;
begin
  select * into v_inv
  from public.invites i
  where upper(i.code) = upper(trim(coalesce(p_code,'')));

  if not found then
    return query select null::uuid, null::text, 0, false, 'not_found'::text;
    return;
  end if;

  if v_inv.revoked then
    return query select null::uuid, null::text, 0, false, 'revoked'::text;
    return;
  end if;

  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    return query select null::uuid, null::text, 0, false, 'expired'::text;
    return;
  end if;

  return query
    select c.id, c.name, count(m.user_id)::integer, true, null::text
    from public.calendars c
    left join public.members m on m.calendar_id = c.id
    where c.id = v_inv.calendar_id
    group by c.id, c.name;
end;
$$;

revoke all on function public.check_invite(text) from public;
grant execute on function public.check_invite(text) to anon, authenticated;
