-- Teste da 086. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- Três fixtures, cada uma provando uma coisa que a outra não prova:
--  · fixture 1 — fn_registrar_presencas_core PROPAGA pro gêmeo em tempo real,
--    E não apaga resposta humana forte já existente no gêmeo (o guard);
--  · fixture 2 — fn_sincronizar_gemeos_presenca() sozinha CONSERTA histórico
--    (o caso do BACKFILL, sem passar pela chamada);
--  · fixture 3 — o parâmetro de ESCOPO de verdade escopa: chamado pra outra
--    aula não toca aqui, chamado pra esta aula toca.
-- Sem a 3, um `fn_sincronizar_gemeos_presenca(p_aula_ancora_id)` que ignorasse
-- o parâmetro e sempre varresse tudo passaria pelas fixtures 1 e 2 do mesmo
-- jeito — só a 3 mostra a diferença.

create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof int;
  v_uni  uuid;
  v_a1 int; v_a2 int; v_a3 int; v_a4 int; v_a5 int;
  v_t0 timestamptz := date_trunc('hour', now()) - interval '3 days' + interval '11 minutes';
  v_seq bigint;
  t1 int; i1 int; i2 int; i3 int;   -- fixture 1: turma + 3 individuais
  t2 int; i4 int;                   -- fixture 2: backfill direto
  t3 int; i5 int;                   -- fixture 3: escopo
  v_r jsonb;
  v_st text; v_resp text;
  v_n int;
begin
  select ae.professor_id, ae.unidade_id into v_prof, v_uni
    from aulas_emusys ae
   where ae.professor_id is not null and ae.unidade_id is not null
   group by 1,2 order by count(*) desc limit 1;

  select id into v_a1 from alunos where arquivado_em is null order by id offset 0 limit 1;
  select id into v_a2 from alunos where arquivado_em is null order by id offset 1 limit 1;
  select id into v_a3 from alunos where arquivado_em is null order by id offset 2 limit 1;
  select id into v_a4 from alunos where arquivado_em is null order by id offset 3 limit 1;
  select id into v_a5 from alunos where arquivado_em is null order by id offset 4 limit 1;

  select coalesce(max(id),0) into v_seq from aula_alunos_emusys;

  -- ══ FIXTURE 1 — propagação em tempo real + guard ══════════════════════════
  insert into aulas_emusys (emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values
    (990010101, v_uni, v_prof, v_t0::date, v_t0, v_t0 + interval '50 min', 'turma',      'Canto T', '_t86_f1', false),
    (990010102, v_uni, v_prof, v_t0::date, v_t0, v_t0 + interval '50 min', 'individual', 'Canto T', '_t86_f1', false),
    (990010103, v_uni, v_prof, v_t0::date, v_t0, v_t0 + interval '50 min', 'individual', 'Canto T', '_t86_f1', false),
    (990010104, v_uni, v_prof, v_t0::date, v_t0, v_t0 + interval '50 min', 'individual', 'Canto T', '_t86_f1', false);
  select id into t1 from aulas_emusys where emusys_id=990010101;
  select id into i1 from aulas_emusys where emusys_id=990010102;
  select id into i2 from aulas_emusys where emusys_id=990010103;
  select id into i3 from aulas_emusys where emusys_id=990010104;

  insert into aula_alunos_emusys (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
  select v_seq + row_number() over (), x.aula, v_uni, '_t86_'||x.aula||'_'||x.aluno, x.aluno,
         (select nome from alunos where id=x.aluno), '_t86'
    from (values (t1,v_a1),(t1,v_a2),(t1,v_a3),(i1,v_a1),(i2,v_a2),(i3,v_a3)) as x(aula, aluno);

  -- gêmeos CONTAMINADOS pelo Emusys — o oposto do que a chamada vai dizer
  insert into aluno_presenca (aluno_id, professor_id, unidade_id, data_aula, aula_emusys_id, status, status_presenca, respondido_por)
  values
    (v_a1, v_prof, v_uni, v_t0::date, i1, 'ausente', 'falta',    'emusys'),
    (v_a2, v_prof, v_uni, v_t0::date, i2, 'presente','presente', 'emusys'),
    -- a3: resposta HUMANA já existe no gêmeo, e é diferente do que a chamada dirá
    (v_a3, v_prof, v_uni, v_t0::date, i3, 'ausente', 'falta',    'manual');

  v_r := fn_registrar_presencas_core(t1, v_prof, array[v_a2]);  -- a2 falta; a1 e a3 presentes

  insert into _res values ('fixture1: a1 (contaminado falta) SINCRONIZA pro gemeo como presente',
    (select status_presenca from aluno_presenca where aula_emusys_id=i1 and aluno_id=v_a1) = 'presente',
    format('i1=%s', (select status_presenca from aluno_presenca where aula_emusys_id=i1 and aluno_id=v_a1)));

  insert into _res values ('fixture1: a2 (contaminado presente) SINCRONIZA pro gemeo como falta',
    (select status_presenca from aluno_presenca where aula_emusys_id=i2 and aluno_id=v_a2) = 'falta',
    format('i2=%s', (select status_presenca from aluno_presenca where aula_emusys_id=i2 and aluno_id=v_a2)));

  select status_presenca, respondido_por into v_st, v_resp from aluno_presenca where aula_emusys_id=i3 and aluno_id=v_a3;
  insert into _res values ('fixture1: a3 tem resposta HUMANA no gemeo (manual) — NAO e sobrescrita',
    v_st is not distinct from 'falta' and v_resp is not distinct from 'manual',
    format('i3 status=%s respondido_por=%s', v_st, v_resp));

  insert into _res values ('fixture1: o retorno conta 2 gemeos sincronizados (nao 3 — o guard segurou o 3o)',
    (v_r ->> 'gemeos_sincronizados')::int = 2,
    format('gemeos_sincronizados=%s', v_r ->> 'gemeos_sincronizados'));

  insert into _res values ('fixture1: a ancora continua gravando normalmente (aplicado=true)',
    (v_r ->> 'aplicado')::boolean is true, v_r::text);

  -- ══ FIXTURE 2 — fn_sincronizar_gemeos_presenca() conserta HISTÓRICO ═══════
  -- Simula o estado de ANTES da 086: escrita forte só na ancora, gemeo
  -- contaminado, sem passar pela RPC (é exatamente como os dados de produção
  -- ficaram órfãos até agora).
  insert into aulas_emusys (emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values
    (990010201, v_uni, v_prof, (v_t0+interval '1h')::date, v_t0+interval '1h', v_t0+interval '1h 50 min', 'turma',      'Canto T', '_t86_f2', false),
    (990010202, v_uni, v_prof, (v_t0+interval '1h')::date, v_t0+interval '1h', v_t0+interval '1h 50 min', 'individual', 'Canto T', '_t86_f2', false);
  select id into t2 from aulas_emusys where emusys_id=990010201;
  select id into i4 from aulas_emusys where emusys_id=990010202;

  insert into aula_alunos_emusys (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
  values (v_seq+100, t2, v_uni, '_t86_'||t2, v_a4, (select nome from alunos where id=v_a4), '_t86'),
         (v_seq+101, i4, v_uni, '_t86_'||i4, v_a4, (select nome from alunos where id=v_a4), '_t86');

  insert into aluno_presenca (aluno_id, professor_id, unidade_id, data_aula, aula_emusys_id, status, status_presenca, respondido_por)
  values (v_a4, v_prof, v_uni, (v_t0+interval '1h')::date, t2, 'presente', 'presente', 'fabio_audio'),  -- historico, so na ancora
         (v_a4, v_prof, v_uni, (v_t0+interval '1h')::date, i4, 'ausente',  'falta',    'emusys');       -- gemeo contaminado

  perform fn_sincronizar_gemeos_presenca();  -- SEM escopo — o modo backfill

  select status_presenca, respondido_por into v_st, v_resp from aluno_presenca where aula_emusys_id=i4 and aluno_id=v_a4;
  insert into _res values ('fixture2: backfill sem escopo conserta escrita historica orfa',
    v_st = 'presente' and v_resp = 'fabio_audio', format('i4 status=%s respondido_por=%s', v_st, v_resp));

  -- ══ FIXTURE 3 — o parâmetro de ESCOPO realmente escopa ════════════════════
  insert into aulas_emusys (emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values
    (990010301, v_uni, v_prof, (v_t0+interval '2h')::date, v_t0+interval '2h', v_t0+interval '2h 50 min', 'turma',      'Canto T', '_t86_f3', false),
    (990010302, v_uni, v_prof, (v_t0+interval '2h')::date, v_t0+interval '2h', v_t0+interval '2h 50 min', 'individual', 'Canto T', '_t86_f3', false);
  select id into t3 from aulas_emusys where emusys_id=990010301;
  select id into i5 from aulas_emusys where emusys_id=990010302;

  insert into aula_alunos_emusys (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
  values (v_seq+200, t3, v_uni, '_t86_'||t3, v_a5, (select nome from alunos where id=v_a5), '_t86'),
         (v_seq+201, i5, v_uni, '_t86_'||i5, v_a5, (select nome from alunos where id=v_a5), '_t86');

  insert into aluno_presenca (aluno_id, professor_id, unidade_id, data_aula, aula_emusys_id, status, status_presenca, respondido_por)
  values (v_a5, v_prof, v_uni, (v_t0+interval '2h')::date, t3, 'ausente',  'falta',    'manual'),
         (v_a5, v_prof, v_uni, (v_t0+interval '2h')::date, i5, 'presente', 'presente', 'emusys');  -- contaminado

  -- escopado pra OUTRA aula (t1, da fixture 1) — nao pode tocar em i5
  perform fn_sincronizar_gemeos_presenca(t1);
  select status_presenca into v_st from aluno_presenca where aula_emusys_id=i5 and aluno_id=v_a5;
  insert into _res values ('fixture3: escopo errado NAO toca no par (prova que o parametro escopa de verdade)',
    v_st = 'presente', format('i5 status=%s (esperado presente = ainda contaminado)', v_st));

  -- agora escopado pra t3 de verdade — tem que sincronizar
  perform fn_sincronizar_gemeos_presenca(t3);
  select status_presenca, respondido_por into v_st, v_resp from aluno_presenca where aula_emusys_id=i5 and aluno_id=v_a5;
  insert into _res values ('fixture3: escopo certo sincroniza o par',
    v_st = 'falta' and v_resp = 'manual', format('i5 status=%s respondido_por=%s', v_st, v_resp));
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not coalesce(ok, false)),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok',
                                'obtido', coalesce(detalhe,'<assercao devolveu NULL>')))
                                from _res where not coalesce(ok, false)), '[]'::json)
       ) as resumo;
