-- O aviso ao comercial cabe no índice -- provado PLANEJANDO, não lendo texto.
--
-- O passo que vale é o `explain`: ele força o planejador a inferir o índice
-- árbitro de verdade. Conferir o texto da função só diz que a string mudou;
-- o `42P10` nasce no planejamento, e é lá que ele tem que morrer.

create temporary table _aviso_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_aviso(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _aviso_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare
  v_erro text;
begin
  -- 1) O INSERT do aviso comercial PLANEJA. Antes do fix isto explodia 42P10.
  begin
    execute $q$
      explain insert into public.fabio_notificacoes
        (professor_id, destinatario_tipo, destinatario_whatsapp, tipo, categoria, corpo,
         canal, status, tentativas, referencia_tipo, referencia_id)
      values (null,'comercial','0','experimental_registrada','informativa','x',
              'whatsapp','processando',1,'lead_experimental_registro','x')
      on conflict (referencia_tipo, referencia_id, canal)
        where referencia_tipo is not null and referencia_id is not null
          and tipo <> 'registro_recibo'
      do nothing
    $q$;
    v_erro := null;
  exception when others then
    v_erro := sqlstate || ': ' || sqlerrm;
  end;
  perform pg_temp.checar_aviso(
    'o ON CONFLICT do aviso infere o indice parcial (planeja sem 42P10)',
    v_erro is null, coalesce(v_erro,'planejou'));

  -- 2) O predicado ANTIGO tem que continuar falhando -- se ele passasse, o
  --    indice teria mudado por baixo e este conserto estaria consertando nada.
  begin
    execute $q$
      explain insert into public.fabio_notificacoes
        (professor_id, destinatario_tipo, destinatario_whatsapp, tipo, categoria, corpo,
         canal, status, tentativas, referencia_tipo, referencia_id)
      values (null,'comercial','0','experimental_registrada','informativa','x',
              'whatsapp','processando',1,'lead_experimental_registro','x')
      on conflict (referencia_tipo, referencia_id, canal)
        where referencia_tipo is not null and referencia_id is not null
      do nothing
    $q$;
    v_erro := null;
  exception when others then
    v_erro := sqlstate;
  end;
  perform pg_temp.checar_aviso(
    'o predicado incompleto continua sendo recusado (42P10)',
    v_erro = '42P10', coalesce(v_erro,'planejou -- nao devia'));

  -- 3) As DUAS funcoes carregam a condicao que faltava.
  perform pg_temp.checar_aviso(
    'fabio_claim_aviso_comercial carrega tipo <> registro_recibo',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fabio_claim_aviso_comercial')
      ilike '%and tipo <> ''registro_recibo''%',
    'a cláusula tem que estar nas duas ocorrencias');

  perform pg_temp.checar_aviso(
    'fabio_claim_aviso_falta_experimental carrega tipo <> registro_recibo',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fabio_claim_aviso_falta_experimental')
      ilike '%and tipo <> ''registro_recibo''%',
    'a cláusula tem que estar nas duas ocorrencias');

  -- 4) NENHUMA ocorrencia pode ter ficado para tras: se sobrar uma antiga, a
  --    funcao explode na hora exata em que aquele ramo for usado.
  perform pg_temp.checar_aviso(
    'nao sobrou nenhum ON CONFLICT com o predicado incompleto',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and pg_get_functiondef(p.oid) ~
             'on conflict \(referencia_tipo, referencia_id, canal\)\s*where referencia_tipo is not null and referencia_id is not null\s*do'),
    (select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and pg_get_functiondef(p.oid) ~
            'on conflict \(referencia_tipo, referencia_id, canal\)\s*where referencia_tipo is not null and referencia_id is not null\s*do'));

  -- 5) O bloco family-safe nao pode ter sido perdido no patch de texto.
  perform pg_temp.checar_aviso(
    'a hierarquia family-safe segue intacta na mensagem do comercial',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fabio_claim_aviso_comercial')
      like '%Leitura de conversão%uso interno, não encaminhar%',
    'a leitura de conversao fica por ULTIMO, depois da regua e marcada');
end $$;

select json_build_object(
  'teste', '20260813250000-o-aviso-ao-comercial-volta-a-caber-no-indice',
  'falhas', (select count(*) from _aviso_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _aviso_res where not ok), '[]'::json)
) as resumo;
