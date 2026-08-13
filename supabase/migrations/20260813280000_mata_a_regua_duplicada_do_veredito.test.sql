-- A duplicata morreu e a régua canônica continua sendo a mesma pra todo mundo.

create temporary table _mata_regua(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_mr(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _mata_regua values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare v_consumidores int;
begin
  perform pg_temp.checar_mr(
    'a regua duplicada nao existe mais',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.proname='fn_presenca_e_resposta'),
    'fn_presenca_e_resposta');

  perform pg_temp.checar_mr(
    'a canonica que fica esta la, e continua sendo sql IMMUTABLE (inlinavel)',
    (select p.provolatile = 'i' and l.lanname = 'sql'
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       join pg_language l on l.oid=p.prolang
      where n.nspname='public' and p.proname='fn_presenca_fecha_chamada'),
    'fn_presenca_fecha_chamada');

  -- O ganho legitimo fica: o idioma do coalesce com nome.
  perform pg_temp.checar_mr(
    'fn_presenca_status_efetivo sobreviveu e faz o coalesce',
    public.fn_presenca_status_efetivo(null, 'presente') = 'presente'
      and public.fn_presenca_status_efetivo(null, 'ausente') = 'falta'
      and public.fn_presenca_status_efetivo('falta_justificada', 'ausente') = 'falta_justificada',
    'o idioma continua nomeado');

  -- NINGUEM pode ter ficado apontando pra funcao morta.
  perform pg_temp.checar_mr(
    'nenhuma view ou funcao referencia a regua apagada',
    not exists (select 1 from pg_views
                 where schemaname='public' and definition ilike '%fn_presenca_e_resposta%')
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                     where n.nspname='public'
                       and pg_get_functiondef(p.oid) ilike '%fn_presenca_e_resposta%'),
    'referencia orfa derruba o consumidor em runtime, nao aqui');

  -- A canonica segue com os SEIS consumidores -- se cair, alguem trocou a
  -- regua de lugar e este arquivo precisa ser relido.
  select count(*) into v_consumidores from (
    select viewname as nome from pg_views
     where schemaname='public' and definition ilike '%fn_presenca_fecha_chamada%'
    union all
    select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname <> 'fn_presenca_fecha_chamada'
       and pg_get_functiondef(p.oid) ilike '%fn_presenca_fecha_chamada%') x;
  perform pg_temp.checar_mr(
    'a regua canonica continua com os 6 consumidores',
    v_consumidores >= 6, format('%s consumidores', v_consumidores));

  -- E a decisao do Alf continua valendo na canonica.
  perform pg_temp.checar_mr(
    'Emusys presente CONTA / Emusys ausente NAO -- na canonica',
    public.fn_presenca_fecha_chamada('presente','emusys')
      and not public.fn_presenca_fecha_chamada(null,'emusys')
      and public.fn_presenca_fecha_chamada('falta','agenda_secretaria'),
    'decisao do Alf, 13/08/2026');
end $$;

select json_build_object(
  'teste', '20260813280000-mata-a-regua-duplicada-do-veredito',
  'falhas', (select count(*) from _mata_regua where not coalesce(ok,false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _mata_regua where not coalesce(ok,false)), '[]'::json)
) as resumo;
