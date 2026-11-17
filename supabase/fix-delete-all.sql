-- =====================================================================
-- Correcao definitiva: todas as FKs para profiles / auth.users
-- =====================================================================
-- Diferente do fix-delete-cascade.sql (que usa nomes fixos), este script
-- varre o schema e corrige QUALQUER foreign key que aponte para profiles
-- ou auth.users e ainda nao tenha ON DELETE CASCADE / SET NULL.
--
-- Rode no SQL Editor. Primeiro mostra o diagnostico, depois corrige.
-- =====================================================================

-- 1) Diagnostico: mostra todas as FKs e suas regras de delete
select
  tc.table_name as tabela,
  kcu.column_name as coluna,
  ccu.table_name as referencia,
  rc.delete_rule as regra
from information_schema.table_constraints tc
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
 and rc.constraint_schema = tc.constraint_schema
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
 and kcu.constraint_schema = tc.constraint_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.constraint_schema = tc.constraint_schema
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and ccu.table_name in ('profiles','users')
order by tc.table_name, kcu.column_name;

-- 2) Correcao automatica
do $$
declare
  r record;
  v_nullable boolean;
  v_action text;
begin
  for r in
    select
      tc.table_schema,
      tc.table_name,
      tc.constraint_name,
      kcu.column_name,
      ccu.table_name as ref_table,
      ccu.table_schema as ref_schema,
      rc.delete_rule
    from information_schema.table_constraints tc
    join information_schema.referential_constraints rc
      on rc.constraint_name = tc.constraint_name
     and rc.constraint_schema = tc.constraint_schema
    join information_schema.key_column_usage kcu
      on kcu.constraint_name = tc.constraint_name
     and kcu.constraint_schema = tc.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.constraint_schema = tc.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and ccu.table_name in ('profiles','users')
      and rc.delete_rule not in ('CASCADE','SET NULL')
  loop
    select is_nullable into v_nullable
    from information_schema.columns
    where table_schema = r.table_schema
      and table_name = r.table_name
      and column_name = r.column_name;

    v_action := case when v_nullable then 'SET NULL' else 'CASCADE' end;

    execute format('alter table %I.%I drop constraint %I',
      r.table_schema, r.table_name, r.constraint_name);
    execute format(
      'alter table %I.%I add constraint %I foreign key (%I) references %I.%I(id) on delete %s',
      r.table_schema, r.table_name, r.constraint_name, r.column_name,
      r.ref_schema, r.ref_table, v_action);

    raise notice 'corrigida: %.% (%) -> % on delete %',
      r.table_name, r.column_name, r.constraint_name, r.ref_table, v_action;
  end loop;
end $$;

-- 3) Verificacao final: nao deve aparecer nenhuma linha com regra diferente
-- de CASCADE / SET NULL.
select
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
 and rc.constraint_schema = tc.constraint_schema
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
 and kcu.constraint_schema = tc.constraint_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.constraint_schema = tc.constraint_schema
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and ccu.table_name in ('profiles','users')
  and rc.delete_rule not in ('CASCADE','SET NULL');
