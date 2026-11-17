-- Correcao minima: apenas REVOKE/GRANT. Sem queries de verificacao.
-- Cole e execute no SQL Editor.

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

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;
