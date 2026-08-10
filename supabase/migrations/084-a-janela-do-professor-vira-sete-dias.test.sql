-- Teste da 084. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- O que precisa ser provado nao e "7 > 3". E' que os QUATRO lugares que tinham
-- o numero na mao passaram a ler o MESMO dono — chamada, gravacao, escalacao e
-- o proprio contrato. Um teste que so' checasse `fn_janela_registro_dias() = 7`
-- passaria com as funcoes ainda em 3 dias, que e' exatamente o defeito.
--
-- Por isso cada prazo e testado pelo COMPORTAMENTO (5 dias entra, 10 dias e
-- recusado) e nao pelo texto do corpo da funcao.
--
-- ⚠️ Os passos de "continua recusada" usam `is not distinct from`, nao `=`. Com
-- `=`, um mutante que trocasse `raise exception` por `raise notice` deixaria
-- `v_erro` NULO, a assercao devolveria NULL, e `count(*) where not ok` NAO
-- contaria a linha: o mutante sobreviveria imprimindo verde. Aconteceu aqui
-- (V5/V6/V8 sobreviveram na primeira rodada) e ja tinha acontecido na 076. O
-- resumo no fim tambem passou a tratar `ok IS NULL` como FALHA — assercao que
-- nao sabe responder nao pode ser lida como aprovacao.

create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof  int;
  v_auth  uuid;
  v_uni   uuid;
  v_a1    int;
  v_seq   bigint;
  v_dias  int;
  v_r     jsonb;
  v_erro  text;
  a5 int; a8 int; afut int;   -- aulas: 5 dias atras, 10 dias atras, futura
begin
  select p.id, u.auth_user_id into v_prof, v_auth
    from professores p join usuarios u on u.id = p.usuario_id
   where p.ativo and u.auth_user_id is not null
   order by p.id limit 1;

  select ae.unidade_id into v_uni
    from aulas_emusys ae where ae.professor_id = v_prof and ae.unidade_id is not null
   group by 1 order by count(*) desc limit 1;

  select id into v_a1 from alunos where arquivado_em is null order by id limit 1;
  select coalesce(max(id),0) into v_seq from aula_alunos_emusys;

  v_dias := public.fn_janela_registro_dias();

  -- ── o contrato ────────────────────────────────────────────────────────────
  insert into _res values ('a janela tem um dono unico e ele diz 7',
    v_dias = 7, format('fn_janela_registro_dias()=%s', v_dias));

  -- ── fixtures ──────────────────────────────────────────────────────────────
  -- 5 dias atras: DENTRO da janela nova, FORA da antiga. E' a aula que a
  -- professora nao conseguiu lancar em 08/08.
  -- 10 dias atras: fora das duas, e com `dias_em_atraso` folgado acima de 7.
  --   (a primeira versao usava 8 dias e o passo da escalacao falhava: o
  --    `dias_em_atraso` e' FLOOR do intervalo, entao uma aula que comecou ha 8
  --    dias e terminou 50 min depois da o inteiro 7, e `7 > 7` e' falso. O
  --    defeito estava na fixture, nao na 084 — mas so' apareceu porque o passo
  --    existia.)
  insert into aulas_emusys (emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values
    (990000801, v_uni, v_prof, (now() - interval '5 days')::date, now() - interval '5 days', now() - interval '5 days' + interval '50 min', 'individual', 'Canto T', '_t84_d5',  false),
    (990000802, v_uni, v_prof, (now() - interval '10 days')::date, now() - interval '10 days', now() - interval '10 days' + interval '50 min', 'individual', 'Canto T', '_t84_d10', false),
    (990000803, v_uni, v_prof, (now() + interval '2 days')::date, now() + interval '2 days', now() + interval '2 days' + interval '50 min', 'individual', 'Canto T', '_t84_fut', false);

  select id into a5   from aulas_emusys where emusys_id = 990000801;
  select id into a8   from aulas_emusys where emusys_id = 990000802;
  select id into afut from aulas_emusys where emusys_id = 990000803;

  insert into aula_alunos_emusys (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
  select v_seq + row_number() over (), x.aula, v_uni, '_t84_'||x.aula, v_a1,
         (select nome from alunos where id = v_a1), '_t84'
    from (values (a5),(a8),(afut)) as x(aula);

  -- ── CHAMADA ───────────────────────────────────────────────────────────────
  begin
    v_r := public.fn_registrar_presencas_core(a5, v_prof);
    insert into _res values ('chamada de 5 dias atras ENTRA (a janela antiga recusava)',
      coalesce((v_r ->> 'aplicado')::boolean, false), v_r::text);
  exception when others then
    insert into _res values ('chamada de 5 dias atras ENTRA (a janela antiga recusava)',
      false, 'levantou: ' || sqlerrm);
  end;

  v_erro := null;
  begin
    perform public.fn_registrar_presencas_core(a8, v_prof);
  exception when others then v_erro := sqlerrm;
  end;
  insert into _res values ('chamada de 10 dias atras continua RECUSADA',
    v_erro is not distinct from 'janela_de_chamada_encerrada', format('erro=%s', coalesce(v_erro,'NENHUM')));

  v_erro := null;
  begin
    perform public.fn_registrar_presencas_core(afut, v_prof);
  exception when others then v_erro := sqlerrm;
  end;
  insert into _res values ('aula futura continua recusada (a outra guarda ficou de pe)',
    v_erro is not distinct from 'chamada_ainda_nao_disponivel', format('erro=%s', coalesce(v_erro,'NENHUM')));

  -- ── GRAVACAO DO AUDIO ─────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  begin
    v_r := public.app_enfileirar_audio(a5, 'teste/084/d5.m4a', 30);
    insert into _res values ('audio de 5 dias atras ENTRA na fila (a janela antiga recusava)',
      (v_r ->> 'audio_id') is not null, v_r::text);
  exception when others then
    insert into _res values ('audio de 5 dias atras ENTRA na fila (a janela antiga recusava)',
      false, 'levantou: ' || sqlerrm);
  end;

  v_erro := null;
  begin
    perform public.app_enfileirar_audio(a8, 'teste/084/d8.m4a', 30);
  exception when others then v_erro := sqlerrm;
  end;
  insert into _res values ('audio de 10 dias atras continua RECUSADO',
    v_erro is not distinct from 'janela_de_gravacao_encerrada', format('erro=%s', coalesce(v_erro,'NENHUM')));

  perform set_config('request.jwt.claim.sub', '', true);

  -- ── ESCALACAO ─────────────────────────────────────────────────────────────
  -- Ate a janela fechar o problema e do professor; depois dela e da
  -- coordenacao. Se a escalacao continuasse em 3 dias, ela entregaria a
  -- coordenacao um professor que ainda tem 4 dias pra resolver sozinho.
  v_r := public.fn_pendencias_escalonadas(null, v_prof);
  insert into _res values ('a escalacao sem argumento usa a MESMA regua da janela',
    (v_r ->> 'limite_dias')::int = v_dias,
    format('limite_dias=%s janela=%s', v_r ->> 'limite_dias', v_dias));

  insert into _res values ('aula de 5 dias NAO sobe pra coordenacao (ainda e do professor)',
    not exists (
      select 1 from jsonb_array_elements(v_r -> 'linhas') l,
                    jsonb_array_elements(l -> 'aulas') a
       where (a ->> 'aula_id')::int = a5),
    format('linhas=%s', v_r ->> 'professores'));

  insert into _res values ('aula de 10 dias SOBE pra coordenacao',
    exists (
      select 1 from jsonb_array_elements(v_r -> 'linhas') l,
                    jsonb_array_elements(l -> 'aulas') a
       where (a ->> 'aula_id')::int = a8),
    format('linhas=%s', v_r ->> 'professores'));

  -- quem manda numero explicito continua mandando (nao virou parametro morto)
  v_r := public.fn_pendencias_escalonadas(30, v_prof);
  insert into _res values ('argumento explicito continua vencendo o default',
    (v_r ->> 'limite_dias')::int = 30, format('limite_dias=%s', v_r ->> 'limite_dias'));
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not coalesce(ok, false)),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok',
                                'obtido', coalesce(detalhe,'<assercao devolveu NULL>')))
                                from _res where not coalesce(ok, false)), '[]'::json)
       ) as resumo;
