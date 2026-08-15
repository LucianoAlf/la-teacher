-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. Confere que as tabelas/view/triggers existem e que as
-- portas estao fechadas (service_role sem UPDATE/DELETE; anon/authenticated sem
-- nada). O bloco Docker no fim fica comentado de proposito e o mutante o extrai
-- para um PostgreSQL efemero, onde a prova por DML roda de verdade.

create temporary table pg_temp._participacao_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_schema(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._participacao_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_ocorr   oid := to_regclass('public.fabio_participacao_ocorrencias');
  v_eventos oid := to_regclass('public.fabio_participacao_ocorrencia_eventos');
  v_view    oid := to_regclass('public.vw_fabio_participacao_ocorrencia_estado');
begin
  perform pg_temp.checar_schema('a tabela de ocorrencias existe', v_ocorr is not null, coalesce(v_ocorr::text, '<ausente>'));
  perform pg_temp.checar_schema('a tabela de eventos existe', v_eventos is not null, coalesce(v_eventos::text, '<ausente>'));
  perform pg_temp.checar_schema('a view de estado existe', v_view is not null, coalesce(v_view::text, '<ausente>'));

  perform pg_temp.checar_schema(
    'o trigger append-only da ocorrencia existe',
    exists (select 1 from pg_trigger where tgname = 'trg_participacao_ocorrencias_append_only' and not tgisinternal),
    'pg_trigger');
  perform pg_temp.checar_schema(
    'o trigger append-only dos eventos existe',
    exists (select 1 from pg_trigger where tgname = 'trg_participacao_eventos_append_only' and not tgisinternal),
    'pg_trigger');
  perform pg_temp.checar_schema(
    'o trigger de supersede coerente existe',
    exists (select 1 from pg_trigger where tgname = 'trg_participacao_supersede_coerente' and not tgisinternal),
    'pg_trigger');

  if v_ocorr is not null then
    perform pg_temp.checar_schema(
      'service_role insere e le a ocorrencia',
      has_table_privilege('service_role', v_ocorr, 'INSERT')
      and has_table_privilege('service_role', v_ocorr, 'SELECT'),
      'grant service_role');
    perform pg_temp.checar_schema(
      'service_role NAO atualiza nem apaga a ocorrencia (append-only por grant)',
      not has_table_privilege('service_role', v_ocorr, 'UPDATE')
      and not has_table_privilege('service_role', v_ocorr, 'DELETE'),
      'grant service_role');
    perform pg_temp.checar_schema(
      'anon/authenticated nao alcancam a ocorrencia',
      not has_table_privilege('anon', v_ocorr, 'SELECT')
      and not has_table_privilege('anon', v_ocorr, 'INSERT')
      and not has_table_privilege('authenticated', v_ocorr, 'SELECT')
      and not has_table_privilege('authenticated', v_ocorr, 'INSERT'),
      'grant publico');
  end if;

  if v_eventos is not null then
    perform pg_temp.checar_schema(
      'service_role NAO atualiza nem apaga os eventos (append-only por grant)',
      not has_table_privilege('service_role', v_eventos, 'UPDATE')
      and not has_table_privilege('service_role', v_eventos, 'DELETE'),
      'grant service_role');
    perform pg_temp.checar_schema(
      'anon/authenticated nao alcancam os eventos',
      not has_table_privilege('anon', v_eventos, 'SELECT')
      and not has_table_privilege('authenticated', v_eventos, 'SELECT'),
      'grant publico');
  end if;

  if v_view is not null then
    perform pg_temp.checar_schema(
      'anon/authenticated nao leem a view de estado',
      not has_table_privilege('anon', v_view, 'SELECT')
      and not has_table_privilege('authenticated', v_view, 'SELECT'),
      'grant publico');
  end if;
end
$function$;

-- Resumo do contrato de catalogo (execucao remota). O bloco Docker abaixo
-- fecha com o SEU proprio resumo: sem isso, o mutante leria este resumo aqui,
-- calculado ANTES das asercoes DML, e um mutante vivo passaria por morto.
select json_build_object(
  'falhas', (select count(*) from pg_temp._participacao_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._participacao_res where not ok
  ), '[]'::json)
) as resumo;

/* PARTICIPACAO-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante: aqui a insercao acontece de verdade
-- contra as tabelas reais, e cada mutante do schema precisa matar um caso.

do $docker$
declare
  v_id     uuid;
  v_del    uuid;
  v_estado text;
begin
  -- Fato principal + evento registrada (usado no estado e nos supersedes).
  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_nome, confianca, metodo_extracao, origem, origem_message_id)
  values (1, 1, 10, 793, 'Juliana', 'media', 'deterministico', 'whatsapp', 'wa:1')
  returning id into v_id;
  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo)
  values (v_id, 'registrada', 'sistema');

  -- Estado = candidata (registrada->candidata).
  select estado_atual into v_estado
    from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = v_id;
  perform pg_temp.checar_schema('registrada aparece como candidata na view',
    v_estado = 'candidata', coalesce(v_estado, '<nulo>'));

  -- Fato descartavel so pros testes destrutivos de append-only: apagar este nao
  -- desmonta o v_id de que o supersede depende adiante.
  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_nome, confianca, metodo_extracao, origem, origem_message_id)
  values (1, 1, 10, 793, 'Juliana', 'media', 'deterministico', 'whatsapp', 'wa:del')
  returning id into v_del;

  -- append-only: UPDATE estoura.
  begin
    update public.fabio_participacao_ocorrencias set confianca = 'alta' where id = v_del;
    perform pg_temp.checar_schema('UPDATE no fato e bloqueado pelo trigger', false, 'passou, e nao devia');
  exception when others then
    perform pg_temp.checar_schema('UPDATE no fato e bloqueado pelo trigger', true, sqlerrm);
  end;
  -- append-only: DELETE estoura.
  begin
    delete from public.fabio_participacao_ocorrencias where id = v_del;
    perform pg_temp.checar_schema('DELETE no fato e bloqueado pelo trigger', false, 'passou, e nao devia');
  exception when others then
    perform pg_temp.checar_schema('DELETE no fato e bloqueado pelo trigger', true, sqlerrm);
  end;

  -- origem whatsapp sem message_id: recusado pelo CHECK.
  begin
    insert into public.fabio_participacao_ocorrencias
      (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
       participante_real_nome, confianca, metodo_extracao, origem)
    values (1, 1, 10, 793, 'Juliana', 'media', 'deterministico', 'whatsapp');
    perform pg_temp.checar_schema('whatsapp sem message_id e recusado', false, 'entrou, e nao devia');
  exception when check_violation then
    perform pg_temp.checar_schema('whatsapp sem message_id e recusado', true, 'recusado');
  end;

  -- supersede incoerente (outra aula) estoura.
  begin
    insert into public.fabio_participacao_ocorrencias
      (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
       participante_real_nome, confianca, metodo_extracao, origem, origem_message_id,
       supersede_ocorrencia_id)
    values (999, 999, 10, 793, 'Marina', 'media', 'deterministico', 'whatsapp', 'wa:2', v_id);
    perform pg_temp.checar_schema('supersede de outra aula e recusado', false, 'entrou, e nao devia');
  exception when others then
    perform pg_temp.checar_schema('supersede de outra aula e recusado', true, sqlerrm);
  end;

  -- supersede coerente carimba 'corrigida' na antiga.
  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_nome, confianca, metodo_extracao, origem, origem_message_id,
     supersede_ocorrencia_id)
  values (1, 1, 10, 793, 'Marina', 'media', 'deterministico', 'whatsapp', 'wa:3', v_id);
  perform pg_temp.checar_schema('supersede coerente carimba corrigida na antiga',
    exists (select 1 from public.fabio_participacao_ocorrencia_eventos
             where ocorrencia_id = v_id and evento = 'corrigida'), '');
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._participacao_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._participacao_res where not ok
  ), '[]'::json)
) as resumo;
PARTICIPACAO-DOCKER-DML-TESTS-FIM */
