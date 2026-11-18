-- =====================================================================
-- Renomear calendario (somente o dono)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Nao altera dados sozinho: cria apenas
-- a function que a interface vai chamar quando o usuario salvar.
-- =====================================================================

create or replace function public.rename_calendar(
  p_calendar_id uuid,
  p_name text
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not private.is_calendar_owner(p_calendar_id) then
    raise exception 'Só o dono pode renomear o calendário.';
  end if;

  if char_length(coalesce(trim(p_name), '')) < 2 then
    raise exception 'Nome muito curto.';
  end if;

  if char_length(trim(p_name)) > 60 then
    raise exception 'Nome muito longo.';
  end if;

  update public.calendars
  set name = trim(p_name)
  where id = p_calendar_id;
end;
$$;

revoke all on function public.rename_calendar(uuid, text) from public, anon;
grant execute on function public.rename_calendar(uuid, text) to authenticated;
