-- Este teste roda contra PRODUCAO (BEGIN/ROLLBACK) e cobra o CHECK de verdade,
-- inserindo a linha que o worker insere. Contrato de catalogo aqui nao bastaria:
-- foi justamente uma prova que nao TOCOU a porta que deixou o defeito passar.

create temporary table pg_temp._tipo_check_res (
  caso text, ok boolean, detalhe text
) on commit drop;

create or replace function pg_temp.checar_tipo_check(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._tipo_check_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_id uuid;
begin
  -- O CORACAO: a linha que o worker `--event sem-roster` insere tem que
  -- ENTRAR. Antes desta migration ela morria com 23514 em producao.
  begin
    insert into public.fabio_notificacoes
      (professor_id, tipo, categoria, canal, corpo, titulo,
       referencia_tipo, referencia_id, status, destinatario_tipo)
    values
      (35, 'registro_sem_roster', 'informativa', 'whatsapp',
       'ensaio: corpo do aviso', 'Aula sem aluno no sistema',
       'fila_audio_sem_roster', 'ensaio-20260815120000', 'processando', 'professor')
    returning id into v_id;
    perform pg_temp.checar_tipo_check(
      'o aviso registro_sem_roster passa pelo CHECK do tipo', v_id is not null, coalesce(v_id::text, '<null>'));
  exception when others then
    perform pg_temp.checar_tipo_check(
      'o aviso registro_sem_roster passa pelo CHECK do tipo', false, sqlstate || ': ' || sqlerrm);
  end;

  -- A allowlist continua sendo allowlist: tipo inventado NAO entra. Sem esta
  -- asercao, trocar o CHECK por `check (true)` passaria batido -- e a guarda
  -- que impede uma familia nova de aviso nascer em silencio some.
  begin
    insert into public.fabio_notificacoes
      (professor_id, tipo, categoria, canal, corpo,
       referencia_tipo, referencia_id, status, destinatario_tipo)
    values
      (35, 'tipo_que_nao_existe', 'informativa', 'whatsapp', 'ensaio',
       'fila_audio_sem_roster', 'ensaio-invalido-20260815120000', 'processando', 'professor');
    perform pg_temp.checar_tipo_check(
      'tipo inventado continua sendo recusado', false, 'entrou, e nao devia');
  exception when check_violation then
    perform pg_temp.checar_tipo_check('tipo inventado continua sendo recusado', true, 'recusado');
  when others then
    perform pg_temp.checar_tipo_check(
      'tipo inventado continua sendo recusado', false, sqlstate || ': ' || sqlerrm);
  end;

  -- Nenhum tipo que ja rodava pode ter caido no caminho.
  perform pg_temp.checar_tipo_check(
    'os tipos que ja rodavam continuam na allowlist',
    (select bool_and(pg_get_constraintdef(c.oid) like '%' || t || '%')
       from pg_constraint c
       join pg_class cl on cl.oid = c.conrelid,
            unnest(array['briefing_matinal','pendencia_registro','devolutiva_pronta',
                         'registro_recibo','feedback_coordenacao','experimental_falta']) as t
      where cl.relname = 'fabio_notificacoes'
        and c.conname = 'fabio_notificacoes_tipo_check'),
    'allowlist');
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._tipo_check_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._tipo_check_res where not ok), '[]'::json)
) as resumo;
