-- Contrato de catalogo na execucao remota; o bloco Docker no fim e extraido
-- pelo mutante e roda as DUAS portas de verdade, contra linhas reais.

create temporary table pg_temp._fabio_20260815090000_res (
  caso text, ok boolean, detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815090000(
  p_caso text, p_ok boolean, p_detalhe text
) returns void language plpgsql as $function$
begin
  insert into pg_temp._fabio_20260815090000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_tick regprocedure := to_regprocedure('public.fn_reconciliar_experimental_tick(integer,integer)');
  v_velha regprocedure := to_regprocedure('public.fn_reconciliar_experimental_aulas(integer,integer)');
  v_nova  regprocedure := to_regprocedure('public.fn_reconciliar_experimental_por_lead(integer,integer,integer)');
  v_t text; v_v text; v_n text;
begin
  perform pg_temp.checar_20260815090000('o tick existe', v_tick is not null, coalesce(v_tick::text,'<ausente>'));
  if v_tick is null or v_velha is null or v_nova is null then return; end if;

  v_t := lower(regexp_replace(pg_get_functiondef(v_tick),  '\s+', ' ', 'g'));
  v_v := lower(regexp_replace(pg_get_functiondef(v_velha), '\s+', ' ', 'g'));
  v_n := lower(regexp_replace(pg_get_functiondef(v_nova),  '\s+', ' ', 'g'));

  -- O tick chama as duas portas, e a NOVA vem primeiro. A ordem e o conserto:
  -- quem chega primeiro num lead sem vinculo e quem carimba a procedencia.
  perform pg_temp.checar_20260815090000(
    'o tick chama as duas portas',
    v_t like '%fn_reconciliar_experimental_por_lead%' and v_t like '%fn_reconciliar_experimental_aulas%',
    substring(v_t from 1 for 700)
  );

  perform pg_temp.checar_20260815090000(
    'a porta nova roda ANTES da chave natural',
    position('fn_reconciliar_experimental_por_lead' in v_t)
      < position('fn_reconciliar_experimental_aulas' in v_t),
    substring(v_t from 1 for 700)
  );

  -- A porta nova e a adicao; ela nao pode derrubar a porta que ja funciona.
  perform pg_temp.checar_20260815090000(
    'se a porta nova falhar, a chave natural ainda roda',
    v_t like '%exception%',
    substring(v_t from 1 for 700)
  );

  -- O CORACAO: a chave natural nao tem autoridade pra desfazer o casamento
  -- feito pelo id que o proprio Emusys manda. Quem confere um vinculo e a
  -- MESMA chave que o criou.
  perform pg_temp.checar_20260815090000(
    'a chave natural reconhece o vinculo casado pelo id do lead',
    v_v like '%casado_por = ''emusys_lead_id''%',
    substring(v_v from 1 for 700)
  );

  perform pg_temp.checar_20260815090000(
    'o vinculo soberano e conferido PELO ID DO LEAD, nao pela chave natural',
    v_v like '%r.emusys_lead_id = v_lead.emusys_lead_id%',
    substring(v_v from 1 for 700)
  );

  perform pg_temp.checar_20260815090000(
    'a porta nova promove pendente em vez de so inserir',
    v_n like '%pendente%' and v_n like '%update public.lead_experimental_aulas%',
    substring(v_n from 1 for 700)
  );
end
$function$;

-- Estado do agendamento: o cron tem que estar chamando o tick. Em Docker nao
-- existe schema `cron`, entao a assercao so se aplica onde ele existe --
-- na execucao remota, que e onde a pergunta faz sentido.
do $function$
begin
  if to_regclass('cron.job') is not null then
    perform pg_temp.checar_20260815090000(
      'o cron chama o tick (e nao mais so a chave natural)',
      exists (select 1 from cron.job
               where jobname = 'reconciliar-experimental-aulas'
                 and active
                 and command like '%fn_reconciliar_experimental_tick%'),
      coalesce((select command from cron.job where jobname='reconciliar-experimental-aulas'), '<sem job>')
    );
  end if;
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815090000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815090000_res where not ok), '[]'::json)
) as resumo;

/* 20260815090000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unid uuid := gen_random_uuid();
  v_p1 integer := 900;   -- o professor que o LEAD diz
  v_p2 integer := 901;   -- o professor que a AULA tem (trocou)
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_a integer; v_b integer; v_c integer; v_d integer; v_f integer;
  v_vinc_b bigint; v_vinc_f bigint;
  v_r jsonb;
  v_id_depois bigint;
begin
  insert into public.unidades(id, nome) values (v_unid,'U');
  insert into public.professores(id, nome) values (v_p1,'P1'), (v_p2,'P2');

  -- CASO A: o professor trocou. A chave natural NAO alcanca; o id do lead sim.
  -- Este e o caso que a Fase 1 existe pra resolver -- e que a chave natural
  -- desfazia no mesmo tick, logo depois de criado.
  insert into public.lead_experimentais(unidade_id, data_experimental, horario_experimental, professor_experimental_id, emusys_lead_id)
  values (v_unid, v_hoje, time '10:00', v_p1, 111) returning id into v_a;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (5001, v_p2, v_unid, 'experimental', (v_hoje::timestamp + time '14:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id, emusys_lead_id)
  values (5001, v_unid, null, 111);

  -- CASO B: remarcacao DE VERDADE. O vinculo pelo id do lead ja existe, mas a
  -- aula dele nao casa mais nem pelo id (a data do lead mudou). Soberania nao
  -- e imunidade: tem que sair de vigencia.
  insert into public.lead_experimentais(unidade_id, data_experimental, horario_experimental, professor_experimental_id, emusys_lead_id)
  values (v_unid, v_hoje + 3, time '10:00', v_p1, 222) returning id into v_b;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (5002, v_p1, v_unid, 'experimental', (v_hoje::timestamp + time '10:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id, emusys_lead_id)
  values (5002, v_unid, null, 222);
  insert into public.lead_experimental_aulas
    (lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
  values (v_b, 5002, 'vinculado', 'emusys_lead_id', now(), 'reconciliador_lead')
  returning id into v_vinc_b;

  -- CASO C: lead legado, sem id do lead (junho). So a chave natural alcanca.
  insert into public.lead_experimentais(unidade_id, data_experimental, horario_experimental, professor_experimental_id, emusys_lead_id)
  values (v_unid, v_hoje, time '16:00', v_p1, null) returning id into v_c;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (5003, v_p1, v_unid, 'experimental', (v_hoje::timestamp + time '16:00') at time zone 'America/Sao_Paulo');

  -- CASO D: as DUAS portas alcancam a mesma aula. Quem carimba revela a ordem.
  insert into public.lead_experimentais(unidade_id, data_experimental, horario_experimental, professor_experimental_id, emusys_lead_id)
  values (v_unid, v_hoje, time '18:00', v_p1, 444) returning id into v_d;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (5004, v_p1, v_unid, 'experimental', (v_hoje::timestamp + time '18:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id, emusys_lead_id)
  values (5004, v_unid, null, 444);

  -- CASO F: a aula chegou DEPOIS. A chave natural ja carimbou 'pendente/sem_par'
  -- e o indice de vigencia trancava a porta nova pra sempre. Tem que PROMOVER a
  -- mesma linha -- linha nova quebraria o link que o app ja abriu.
  insert into public.lead_experimentais(unidade_id, data_experimental, horario_experimental, professor_experimental_id, emusys_lead_id)
  values (v_unid, v_hoje, time '09:00', v_p1, 555) returning id into v_f;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio)
  values (5005, v_p2, v_unid, 'experimental', (v_hoje::timestamp + time '11:00') at time zone 'America/Sao_Paulo');
  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id, emusys_lead_id)
  values (5005, v_unid, null, 555);
  insert into public.lead_experimental_aulas
    (lead_experimental_id, estado, motivo_pendencia)
  values (v_f, 'pendente', 'sem_par') returning id into v_vinc_f;

  v_r := public.fn_reconciliar_experimental_tick(7, 200);

  perform pg_temp.checar_20260815090000(
    'A) professor trocado: o vinculo pelo id do lead SOBREVIVE ao tick',
    (select count(*) = 1 from public.lead_experimental_aulas
      where lead_experimental_id = v_a and aula_local_id = 5001
        and casado_por = 'emusys_lead_id' and estado = 'vinculado'
        and substituido_em is null),
    v_r::text
  );

  perform pg_temp.checar_20260815090000(
    'B) remarcacao de verdade: o vinculo que nem pelo id casa mais sai de vigencia',
    (select substituido_em is not null from public.lead_experimental_aulas where id = v_vinc_b),
    coalesce((select substituido_em::text from public.lead_experimental_aulas where id = v_vinc_b), '<null>')
  );

  perform pg_temp.checar_20260815090000(
    'C) a chave natural continua casando o legado sem id do lead',
    (select count(*) = 1 from public.lead_experimental_aulas
      where lead_experimental_id = v_c and aula_local_id = 5003
        and casado_por = 'chave_natural' and substituido_em is null),
    v_r::text
  );

  perform pg_temp.checar_20260815090000(
    'D) quando as duas alcancam, quem casa e o id do lead (a nova roda antes)',
    (select casado_por = 'emusys_lead_id' from public.lead_experimental_aulas
      where lead_experimental_id = v_d and substituido_em is null),
    coalesce((select casado_por from public.lead_experimental_aulas
               where lead_experimental_id = v_d and substituido_em is null), '<sem vinculo>')
  );

  perform pg_temp.checar_20260815090000(
    'F) pendente vira vinculado NA MESMA LINHA (o link do app nao troca)',
    (select id = v_vinc_f and estado = 'vinculado' and aula_local_id = 5005
            and casado_por = 'emusys_lead_id' and motivo_pendencia is null
       from public.lead_experimental_aulas
      where lead_experimental_id = v_f and substituido_em is null),
    coalesce((select id || '/' || estado || '/' || coalesce(aula_local_id::text,'-') || '/' || coalesce(casado_por,'-')
                from public.lead_experimental_aulas
               where lead_experimental_id = v_f and substituido_em is null), '<sem vinculo>')
  );

  -- Sem esta assercao, um tick que engole unique_violation no `exception when
  -- others` da porta velha passaria por verde: o vinculo sobrevive e o erro
  -- vira uma linha de warning que ninguem le.
  perform pg_temp.checar_20260815090000(
    'o tick nao gera erro silencioso na porta velha',
    (v_r -> 'chave_natural' ->> 'erros')::int = 0,
    v_r::text
  );

  -- Segunda rodada: o vinculo soberano nao pode trocar de id a cada 15 min --
  -- o app navega por esse id e o registro da experimental aponta pra ele.
  select id into v_id_depois from public.lead_experimental_aulas
   where lead_experimental_id = v_a and substituido_em is null;
  v_r := public.fn_reconciliar_experimental_tick(7, 200);

  perform pg_temp.checar_20260815090000(
    'o segundo tick nao troca o id do vinculo (nada de churn a cada rodada)',
    (select id = v_id_depois from public.lead_experimental_aulas
      where lead_experimental_id = v_a and substituido_em is null),
    coalesce((select id::text from public.lead_experimental_aulas
               where lead_experimental_id = v_a and substituido_em is null), '<sumiu>')
    || ' era ' || coalesce(v_id_depois::text,'<null>')
  );

  perform pg_temp.checar_20260815090000(
    'o segundo tick tambem nao gera erro',
    (v_r -> 'chave_natural' ->> 'erros')::int = 0,
    v_r::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815090000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815090000_res where not ok), '[]'::json)
) as resumo;
20260815090000-DOCKER-DML-TESTS-FIM */
