-- Teste da 083. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- Duas afirmacoes, e as duas so' valem com o par: "aparece quando devia" e
-- "continua NAO aparecendo quando nao devia". Sem o segundo lado, a correcao
-- vira `where true` e o teste aplaude.
--
-- As fixtures montam os 5 casos num horario proprio (minuto :07, pra nao
-- esbarrar em aula real do mesmo professor). Alem delas, dois passos de ISCA
-- medem a PRODUCAO — se a base parar de ter o padrao, o teste avisa em vez de
-- passar de graca. Foi assim que o mutante V7 da 077 sobreviveu: o teste nao
-- tinha o caso que o filtro deveria pegar.

create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof   int;
  v_uni    uuid;
  v_a1     int;   -- aluno da fatia A (plano do Emusys)
  v_a2     int;   -- aluno da fatia B (gemeos discordantes)
  v_t0     timestamptz := date_trunc('hour', now()) - interval '2 days' + interval '7 minutes';
  v_seq    bigint;
  v_n      int;
  v_st     text;
  v_cham   boolean;
  v_plano  boolean;
  v_r      jsonb;
  -- ids das aulas: T=turma (ancora), I=individual (alvo)
  t1 int; i1 int; t2 int; i2 int; t3 int; i3 int; t4 int; i4 int; t5 int; i5 int;
begin
  -- ── ancoras reais, pra nao inventar professor nem unidade ─────────────────
  select ae.professor_id, ae.unidade_id into v_prof, v_uni
    from aulas_emusys ae
   where ae.professor_id is not null and ae.unidade_id is not null
   group by 1,2 order by count(*) desc limit 1;

  select id into v_a1 from alunos where arquivado_em is null order by id limit 1;
  select id into v_a2 from alunos where arquivado_em is null and id <> v_a1 order by id limit 1;

  select coalesce(max(id),0) into v_seq from aula_alunos_emusys;

  -- ── fixtures ──────────────────────────────────────────────────────────────
  -- cada "slot" e' um par (turma, individual) no mesmo instante. A view elege a
  -- TURMA como ancora e a INDIVIDUAL como alvo — o texto do registro mora no
  -- alvo, e e' por isso que as anotacoes abaixo vao na individual.
  insert into aulas_emusys (emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada, anotacoes, anotacoes_fabio)
  values
    -- slot 1 — SO' plano do Emusys no alvo. Antes da 083 sumia; agora e' pendencia.
    (990000101, v_uni, v_prof, v_t0::date,               v_t0,               v_t0 + interval '50 min', 'turma',      'Canto T', '_t83_s1', false, null, null),
    (990000102, v_uni, v_prof, v_t0::date,               v_t0,               v_t0 + interval '50 min', 'individual', 'Canto T', '_t83_s1', false, 'TEMA: EMPOSTACAO. OBJETIVO: ... CONTEUDO PROGRAMATICO: ...', null),
    -- slot 2 — relato de verdade no alvo. Tem que continuar FORA.
    (990000201, v_uni, v_prof, (v_t0+interval '1h')::date, v_t0+interval '1h', v_t0 + interval '1h 50 min', 'turma',      'Canto T', '_t83_s2', false, null, null),
    (990000202, v_uni, v_prof, (v_t0+interval '1h')::date, v_t0+interval '1h', v_t0 + interval '1h 50 min', 'individual', 'Canto T', '_t83_s2', false, 'TEMA: EMPOSTACAO. OBJETIVO: ...', 'AULA — trabalhamos respiracao e o repertorio.'),
    -- slot 3 — gemeos discordam: turma diz falta, individual diz presente.
    (990000301, v_uni, v_prof, (v_t0+interval '2h')::date, v_t0+interval '2h', v_t0 + interval '2h 50 min', 'turma',      'Canto T', '_t83_s3', false, null, null),
    (990000302, v_uni, v_prof, (v_t0+interval '2h')::date, v_t0+interval '2h', v_t0 + interval '2h 50 min', 'individual', 'Canto T', '_t83_s3', false, null, null),
    -- slot 4 — falta de verdade: TODOS os gemeos dizem falta. Fica FORA.
    (990000401, v_uni, v_prof, (v_t0+interval '3h')::date, v_t0+interval '3h', v_t0 + interval '3h 50 min', 'turma',      'Canto T', '_t83_s4', false, null, null),
    (990000402, v_uni, v_prof, (v_t0+interval '3h')::date, v_t0+interval '3h', v_t0 + interval '3h 50 min', 'individual', 'Canto T', '_t83_s4', false, null, null),
    -- slot 5 — chamada nunca lancada. "Nao lancado" nunca foi falta: fica DENTRO.
    (990000501, v_uni, v_prof, (v_t0+interval '4h')::date, v_t0+interval '4h', v_t0 + interval '4h 50 min', 'turma',      'Canto T', '_t83_s5', false, null, null),
    (990000502, v_uni, v_prof, (v_t0+interval '4h')::date, v_t0+interval '4h', v_t0 + interval '4h 50 min', 'individual', 'Canto T', '_t83_s5', false, null, null);

  select id into t1 from aulas_emusys where emusys_id = 990000101;
  select id into i1 from aulas_emusys where emusys_id = 990000102;
  select id into t2 from aulas_emusys where emusys_id = 990000201;
  select id into i2 from aulas_emusys where emusys_id = 990000202;
  select id into t3 from aulas_emusys where emusys_id = 990000301;
  select id into i3 from aulas_emusys where emusys_id = 990000302;
  select id into t4 from aulas_emusys where emusys_id = 990000401;
  select id into i4 from aulas_emusys where emusys_id = 990000402;
  select id into t5 from aulas_emusys where emusys_id = 990000501;
  select id into i5 from aulas_emusys where emusys_id = 990000502;

  insert into aula_alunos_emusys (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
  select v_seq + row_number() over (), x.aula, v_uni, '_t83_'||x.aula, x.aluno,
         (select nome from alunos where id = x.aluno), '_t83'
    from (values (t1,v_a1),(i1,v_a1),(t2,v_a1),(i2,v_a1),
                 (t3,v_a2),(i3,v_a2),(t4,v_a2),(i4,v_a2),
                 (t5,v_a2),(i5,v_a2)) as x(aula, aluno);

  insert into aluno_presenca (aluno_id, professor_id, unidade_id, data_aula, aula_emusys_id, status, status_presenca, respondido_por)
  values
    (v_a1, v_prof, v_uni, v_t0::date,                 t1, 'presente','presente','emusys'),
    (v_a1, v_prof, v_uni, v_t0::date,                 i1, 'presente','presente','emusys'),
    (v_a1, v_prof, v_uni, (v_t0+interval '1h')::date, t2, 'presente','presente','emusys'),
    (v_a1, v_prof, v_uni, (v_t0+interval '1h')::date, i2, 'presente','presente','emusys'),
    -- slot 3: o gemeo da ancora MENTE (falta), o individual afirma presenca
    (v_a2, v_prof, v_uni, (v_t0+interval '2h')::date, t3, 'ausente', 'falta',   'emusys'),
    (v_a2, v_prof, v_uni, (v_t0+interval '2h')::date, i3, 'presente','presente','emusys'),
    -- slot 4: falta em todos
    (v_a2, v_prof, v_uni, (v_t0+interval '3h')::date, t4, 'ausente', 'falta',   'emusys'),
    (v_a2, v_prof, v_uni, (v_t0+interval '3h')::date, i4, 'ausente', 'falta',   'emusys');
  -- slot 5: de proposito, NENHUMA linha de presenca

  -- ── BURACO A ──────────────────────────────────────────────────────────────
  select count(*), bool_or(tem_plano_emusys) into v_n, v_plano
    from vw_registro_pendencia where aula_ancora_id = t1;
  insert into _res values ('plano do Emusys NAO conta como relato: a aula vira pendencia',
    v_n = 1, format('linhas=%s', v_n));
  insert into _res values ('a mesma aula se anuncia como "tem plano no Emusys"',
    coalesce(v_plano,false), format('tem_plano_emusys=%s', v_plano));

  select count(*) into v_n from vw_registro_pendencia where aula_ancora_id = t2;
  insert into _res values ('relato de verdade (anotacoes_fabio) continua fechando a pendencia',
    v_n = 0, format('linhas=%s (esperado 0)', v_n));

  -- ── BURACO B ──────────────────────────────────────────────────────────────
  select count(*), max(status_presenca), bool_and(chamada_feita) into v_n, v_st, v_cham
    from vw_registro_pendencia where aula_ancora_id = t3;
  insert into _res values ('gemeo com falta nao esconde mais a aula (afirmacao vence)',
    v_n = 1, format('linhas=%s', v_n));
  insert into _res values ('a presenca resolvida e a AFIRMADA, nao a da ancora',
    v_st = 'presente' and coalesce(v_cham,false),
    format('status=%s chamada_feita=%s', v_st, v_cham));

  select count(*) into v_n from vw_registro_pendencia where aula_ancora_id = t4;
  insert into _res values ('falta em TODOS os gemeos continua fora (nao ha conteudo)',
    v_n = 0, format('linhas=%s (esperado 0)', v_n));

  -- ── nao lancado nunca foi falta ───────────────────────────────────────────
  select count(*), max(status_presenca), bool_or(chamada_feita) into v_n, v_st, v_cham
    from vw_registro_pendencia where aula_ancora_id = t5;
  insert into _res values ('chamada nunca lancada continua cobravel, e se diz nao lancada',
    v_n = 1 and v_st is null and coalesce(v_cham,true) = false,
    format('linhas=%s status=%s chamada_feita=%s', v_n, v_st, v_cham));

  -- ── a mensagem recebe o numero honesto ────────────────────────────────────
  v_r := fn_pendencias_do_professor(v_prof, true);
  insert into _res values ('fn_pendencias_do_professor conta as aulas com plano no Emusys',
    (v_r ->> 'aulas_com_plano_emusys')::int >= 1,
    format('aulas_com_plano_emusys=%s', v_r ->> 'aulas_com_plano_emusys'));

  -- ── ISCAS: a producao ainda tem os dois padroes? ──────────────────────────
  -- Passo que existe pra o teste NAO passar de graca. Se um dia a base perder o
  -- padrao, e' isto aqui que avisa — e nao um verde silencioso.
  select count(*) into v_n from (
    select 1 from aulas_emusys ae
     where ae.professor_id is not null and coalesce(ae.cancelada,false)=false
       and ae.data_hora_fim < now() and ae.data_aula >= fn_data_corte_cobranca()
       and ae.emusys_id < 990000000
       and nullif(btrim(coalesce(ae.anotacoes_fabio,'')),'') is null
       and nullif(btrim(coalesce(ae.anotacoes,'')),'') is not null
     limit 5) z;
  insert into _res values ('ISCA: a producao tem aula com plano e sem relato (senao o teste e decoracao)',
    v_n >= 1, format('amostras=%s', v_n));

  select count(*) into v_n from (
    select ap.aluno_id
      from aluno_presenca ap join aulas_emusys ae on ae.id = ap.aula_emusys_id
     where ae.data_aula >= '2026-07-01' and coalesce(ae.cancelada,false)=false
       and ae.emusys_id < 990000000
     group by ap.aluno_id, ae.professor_id, ae.data_hora_inicio
    having bool_or(ae.tipo='turma' and ap.status_presenca='falta')
       and bool_or(ae.tipo='individual' and ap.status_presenca='presente')
     limit 5) z;
  insert into _res values ('ISCA: a producao tem gemeos que discordam (senao o teste e decoracao)',
    v_n >= 1, format('amostras=%s', v_n));
end $$;

select json_build_object(
         -- `not coalesce(ok,false)`: assercao que devolve NULL e FALHA, nunca
         -- aprovacao. Com `not ok` puro, um NULL sai do count e o passo some.
         'falhas', (select count(*) from _res where not coalesce(ok, false)),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok',
                                'obtido', coalesce(detalhe,'<assercao devolveu NULL>')))
                                from _res where not coalesce(ok, false)), '[]'::json)
       ) as resumo;
