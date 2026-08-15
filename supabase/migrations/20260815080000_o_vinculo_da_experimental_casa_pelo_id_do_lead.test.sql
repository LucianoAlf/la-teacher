-- Contrato de catalogo na execucao remota; o bloco Docker no fim e extraido
-- pelo mutante e roda a conciliacao de verdade contra linhas reais.

create temporary table pg_temp._fabio_20260815080000_res (
  caso text, ok boolean, detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815080000(
  p_caso text, p_ok boolean, p_detalhe text
) returns void language plpgsql as $function$
begin
  insert into pg_temp._fabio_20260815080000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_fn regprocedure := to_regprocedure('public.fn_reconciliar_experimental_por_lead(integer,integer,integer)');
  v_norm text;
begin
  perform pg_temp.checar_20260815080000('a porta nova existe', v_fn is not null, coalesce(v_fn::text,'<ausente>'));
  if v_fn is null then return; end if;
  v_norm := lower(regexp_replace(pg_get_functiondef(v_fn), '\s+', ' ', 'g'));

  perform pg_temp.checar_20260815080000(
    'casa pelo id do lead que o Emusys manda',
    v_norm like '%r.emusys_lead_id = v_lead.emusys_lead_id%',
    substring(v_norm from 1 for 700)
  );

  -- O CORACAO: sem a data, a remarcacao pendura na tentativa errada.
  perform pg_temp.checar_20260815080000(
    'a DATA faz parte da chave (desempata remarcacao)',
    v_norm like '%= v_lead.data_experimental%',
    substring(v_norm from 1 for 700)
  );

  -- O vocabulario de `casado_por` e fechado por CHECK. Se a migration nao o
  -- alargar, a funcao existe e estoura no primeiro insert -- foi o que um
  -- ensaio a seco contra producao mostrou.
  perform pg_temp.checar_20260815080000(
    'o CHECK de casado_por aceita o valor novo',
    (select pg_get_constraintdef(oid) like '%emusys_lead_id%'
       from pg_constraint
      where conrelid = 'public.lead_experimental_aulas'::regclass
        and conname = 'lead_experimental_aulas_casado_por_check'),
    coalesce((select pg_get_constraintdef(oid) from pg_constraint
               where conrelid = 'public.lead_experimental_aulas'::regclass
                 and conname = 'lead_experimental_aulas_casado_por_check'), '<ausente>')
  );

  perform pg_temp.checar_20260815080000(
    'carimba a procedencia do casamento',
    v_norm like '%''emusys_lead_id''%',
    substring(v_norm from 1 for 700)
  );

  perform pg_temp.checar_20260815080000(
    'nao toca em quem ja tem vinculo vigente',
    v_norm like '%not exists%' and v_norm like '%substituido_em is null%',
    substring(v_norm from 1 for 700)
  );

  perform pg_temp.checar_20260815080000(
    'nao escolhe no chute quando ha mais de um par',
    v_norm like '%v_qtd_par > 1%',
    substring(v_norm from 1 for 700)
  );

  perform pg_temp.checar_20260815080000(
    'aula ja ocupada nao vira erro',
    v_norm like '%unique_violation%',
    substring(v_norm from 1 for 700)
  );

  -- Nao pode ter virado uma funcao que escreve sem controle.
  perform pg_temp.checar_20260815080000(
    'nao mexe em aulas_emusys nem em lead_experimentais',
    v_norm not like '%update public.aulas_emusys%'
      and v_norm not like '%update public.lead_experimentais%'
      and v_norm not like '%delete from%',
    substring(v_norm from 1 for 700)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815080000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815080000_res where not ok), '[]'::json)
) as resumo;

/* 20260815080000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unid uuid := gen_random_uuid();
  v_prof integer := 900;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_lead_a integer; v_lead_b integer; v_lead_c integer; v_lead_d integer;
  v_aula_a integer := 5001; v_aula_b integer := 5002;
  v_aula_c integer := 5003; v_aula_d integer := 5004;
  v_r jsonb;
begin
  insert into public.unidades(id, nome) values (v_unid,'U');
  insert into public.professores(id, nome) values (v_prof,'P');

  -- CASO 1: um lead, uma aula, mesma data. Tem que casar.
  insert into public.lead_experimentais(unidade_id, data_experimental, emusys_lead_id)
  values (v_unid, v_hoje, 111) returning id into v_lead_a;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (v_aula_a, v_prof, v_unid, 'experimental', (v_hoje::timestamp + time '10:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id, emusys_lead_id)
  values (v_aula_a, null, 111);

  -- CASO 2: REMARCACAO — o MESMO lead com duas experimentais em datas
  -- diferentes, e duas aulas. Cada uma tem que ir pra sua data. Sem a data na
  -- chave, as duas disputariam a mesma aula.
  insert into public.lead_experimentais(unidade_id, data_experimental, emusys_lead_id)
  values (v_unid, v_hoje, 222) returning id into v_lead_b;
  insert into public.lead_experimentais(unidade_id, data_experimental, emusys_lead_id)
  values (v_unid, v_hoje + 1, 222) returning id into v_lead_c;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (v_aula_b, v_prof, v_unid, 'experimental', (v_hoje::timestamp + time '14:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id, emusys_lead_id)
  values (v_aula_b, null, 222);
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (v_aula_c, v_prof, v_unid, 'experimental', ((v_hoje+1)::timestamp + time '14:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id, emusys_lead_id)
  values (v_aula_c, null, 222);

  -- CASO 3: lead SEM emusys_lead_id (legado de junho). Nao e assunto desta
  -- porta; a chave natural da funcao antiga que cuida.
  insert into public.lead_experimentais(unidade_id, data_experimental, emusys_lead_id)
  values (v_unid, v_hoje, null) returning id into v_lead_d;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (v_aula_d, v_prof, v_unid, 'experimental', (v_hoje::timestamp + time '16:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id, emusys_lead_id)
  values (v_aula_d, null, null);

  v_r := public.fn_reconciliar_experimental_por_lead(2, 7, 100);

  perform pg_temp.checar_20260815080000(
    'lead com aula na mesma data foi vinculado',
    (select count(*) = 1 from public.lead_experimental_aulas
      where lead_experimental_id = v_lead_a and aula_local_id = v_aula_a
        and casado_por = 'emusys_lead_id' and estado = 'vinculado'),
    v_r::text
  );

  -- O caso que prova a DATA na chave.
  perform pg_temp.checar_20260815080000(
    'remarcacao: cada tentativa do MESMO lead foi pra sua propria data',
    (select count(*) = 1 from public.lead_experimental_aulas
      where lead_experimental_id = v_lead_b and aula_local_id = v_aula_b)
    and (select count(*) = 1 from public.lead_experimental_aulas
      where lead_experimental_id = v_lead_c and aula_local_id = v_aula_c),
    (select coalesce(string_agg(lead_experimental_id || '->' || aula_local_id, ','), '<vazio>')
       from public.lead_experimental_aulas where lead_experimental_id in (v_lead_b, v_lead_c))
  );

  perform pg_temp.checar_20260815080000(
    'lead legado sem emusys_lead_id NAO e tocado por esta porta',
    (select count(*) = 0 from public.lead_experimental_aulas where lead_experimental_id = v_lead_d),
    v_r::text
  );

  -- Idempotencia: rodar de novo nao duplica nem estoura.
  v_r := public.fn_reconciliar_experimental_por_lead(2, 7, 100);
  perform pg_temp.checar_20260815080000(
    'rodar de novo nao duplica vinculo (idempotente)',
    (select count(*) = 3 from public.lead_experimental_aulas),
    (select count(*)::text from public.lead_experimental_aulas) || ' | ' || v_r::text
  );

  perform pg_temp.checar_20260815080000(
    'a segunda rodada nao vincula nada de novo',
    (v_r ->> 'vinculados')::int = 0,
    v_r::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815080000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815080000_res where not ok), '[]'::json)
) as resumo;
20260815080000-DOCKER-DML-TESTS-FIM */
