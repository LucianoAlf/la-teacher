-- Teste da migration 020. Não aborta: registra divergências e devolve resumo
-- estruturado, pro ROLLBACK do runner rodar com a transação sadia.
--
-- Rodar com:  npm run teste:020

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;

create function pg_temp.checar(p_passo text, p_esperado text, p_obtido text)
returns void language plpgsql as $c$
begin
  if p_esperado is distinct from p_obtido then
    insert into _falhas values (p_passo, coalesce(p_esperado,'(null)'), coalesce(p_obtido,'(null)'));
  end if;
end $c$;

-- ============================================================================
-- PARTE 1 — a FRONTEIRA family-safe
--
-- O passo 3 é o que importa: recado interno não pode sair. Se alguém trocar a
-- lista de permissão por lista de bloqueio, ele acusa.
-- ============================================================================
do $t$
declare v_fonte jsonb;
begin
  v_fonte := public.fn_devolutiva_fonte(
    jsonb_build_object('objetivo','Trabalhar ritmo','obs_gerais','pai reclamou da mensalidade',
                       'materiais','caderno de partitura'),
    jsonb_build_object('progresso','tocou a escala inteira',
                       'proximo_passo','juntar as duas mãos',
                       'dever_casa','praticar 10 min',
                       'observacao','a crianca chorou; suspeito de problema em casa'));

  perform pg_temp.checar('1. progresso passa','tocou a escala inteira', v_fonte->>'progresso');
  perform pg_temp.checar('2. objetivo passa','Trabalhar ritmo', v_fonte->>'objetivo');
  perform pg_temp.checar('3. OBSERVACAO nao sai','true', (v_fonte->'observacao' is null)::text);
  perform pg_temp.checar('4. obs_gerais nao sai','true', (v_fonte->'obs_gerais' is null)::text);
  perform pg_temp.checar('5. materiais nao sai','true', (v_fonte->'materiais' is null)::text);
  perform pg_temp.checar('6. o texto interno nao aparece em lugar nenhum','false',
    (v_fonte::text ilike '%chorou%' or v_fonte::text ilike '%mensalidade%')::text);

  -- lista de PERMISSÃO: campo novo fica de fora sozinho
  perform pg_temp.checar('7. campo desconhecido fica FORA por padrao','true',
    (public.fn_devolutiva_fonte('{}'::jsonb,
       jsonb_build_object('nota_interna','coordenacao ver isso'))->'nota_interna' is null)::text);
exception when others then
  insert into _falhas values ('PARTE 1 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 2 — a skill nasce ativa e única
-- ============================================================================
do $t$
begin
  perform pg_temp.checar('11. skill ativa existe','1',
    (select count(*)::text from public.fabio_skills where nome='devolutiva_aula' and ativa));
  perform pg_temp.checar('12. regra "pedir nunca acusar" esta na skill','true',
    (select (conteudo ilike '%PEDIR, NUNCA ACUSAR%')::text
       from public.fabio_skills where nome='devolutiva_aula' and ativa));
exception when others then
  insert into _falhas values ('PARTE 2 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 3 — o enfileirador FALHA FECHADO
--
-- Quatro registros no mesmo tronco: presente, ausente, sem a chave, e o próprio
-- tronco. Só o presente pode virar devolutiva.
-- ============================================================================
do $t$
declare
  v_aula integer; v_unidade uuid; v_tronco uuid;
  v_presente uuid; v_ausente uuid; v_semchave uuid; v_alunos integer[]; n integer;
begin
  select a.id, a.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a where a.professor_id = 25 order by a.id desc limit 1;
  select array_agg(id) into v_alunos from (
    select id from public.alunos where status='ativo' order by id limit 3) x;
  if v_aula is null or array_length(v_alunos,1) < 3 then
    insert into _falhas values ('PARTE 3 (setup)','aula + 3 alunos','faltou dado');
    return;
  end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem,
     confirmado_em)
  values (v_aula, v_unidade, 25, null, null, 'C', '{"objetivo":"turma"}'::jsonb,
          'gravado_emusys', 'app', now())
  returning id into v_tronco;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_alunos[1], v_tronco, 'C',
          '{"progresso":"foi bem","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_presente;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_alunos[2], v_tronco, 'C',
          '{"presenca":"ausente"}'::jsonb, 'confirmado','app', now())
  returning id into v_ausente;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_alunos[3], v_tronco, 'C',
          '{"progresso":"foi bem"}'::jsonb, 'gravado_emusys','app', now())   -- SEM presenca
  returning id into v_semchave;

  n := public.fabio_enfileirar_devolutivas(v_tronco);

  perform pg_temp.checar('21. enfileirou SO o presente','1', n::text);
  perform pg_temp.checar('22. o presente entrou','1',
    (select count(*)::text from public.fabio_devolutivas where registro_fatia_id=v_presente));
  perform pg_temp.checar('23. o AUSENTE nao entrou','0',
    (select count(*)::text from public.fabio_devolutivas where registro_fatia_id=v_ausente));
  perform pg_temp.checar('24. o SEM CHAVE nao entrou (falha fechada)','0',
    (select count(*)::text from public.fabio_devolutivas where registro_fatia_id=v_semchave));
  perform pg_temp.checar('25. o TRONCO nao entrou','0',
    (select count(*)::text from public.fabio_devolutivas where registro_fatia_id=v_tronco));

  -- reconfirmar não duplica
  n := public.fabio_enfileirar_devolutivas(v_tronco);
  perform pg_temp.checar('26. reconfirmar nao duplica','0', n::text);
  perform pg_temp.checar('27. continua 1 devolutiva','1',
    (select count(*)::text from public.fabio_devolutivas where registro_fatia_id=v_presente));
exception when others then
  insert into _falhas values ('PARTE 3 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 4 — fila: claim com cerca, backoff e o estado de espera
-- ============================================================================
do $t$
declare
  v_aula integer; v_unidade uuid; v_reg uuid; v_aluno integer;
  a jsonb; b jsonb; v_id uuid; v_tok uuid; v_skill uuid;
begin
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id = 25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  select id into v_skill from public.fabio_skills where nome='devolutiva_aula' and ativa;
  if v_aula is null then return; end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"ok","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg;

  perform public.fabio_enfileirar_devolutivas(v_reg);

  -- A fila é compartilhada: a devolutiva da Parte 3 ainda está pendente nesta
  -- mesma transação. Então a asserção é "a MINHA linha veio", não "veio uma".
  select id into v_id from public.fabio_devolutivas where registro_fatia_id = v_reg;
  a := public.fabio_devolutiva_claim('worker-A', 10);
  v_tok := (a->>'lease_token')::uuid;
  perform pg_temp.checar('31. worker A pegou a minha linha','1',
    (select count(*)::text from jsonb_array_elements(a->'itens') e
      where (e->>'id')::uuid = v_id));
  perform pg_temp.checar('32. status virou gerando','gerando',
    (select status from public.fabio_devolutivas where id=v_id));

  -- worker B não pega o que está com lease vivo
  b := public.fabio_devolutiva_claim('worker-B', 10);
  perform pg_temp.checar('33. worker B nao rouba lease vivo','0',
    jsonb_array_length(b->'itens')::text);

  -- cerca: token errado não conclui
  perform pg_temp.checar('34. token errado nao conclui','false',
    public.fabio_devolutiva_gerada(v_id, gen_random_uuid(), 'x','y','aluno','Fulano',16,
      v_skill, 1)::text);

  -- espera de destinatário sai do caminho do LLM
  perform pg_temp.checar('35. aguardando_destinatario com token certo','true',
    public.fabio_devolutiva_aguardar_destinatario(v_id, v_tok, 'idade impossivel')::text);
  perform pg_temp.checar('36. status e aguardando_destinatario','aguardando_destinatario',
    (select status from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('37. carimbou aguardando_desde','true',
    (select (aguardando_desde is not null)::text from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('38. lease foi devolvido','true',
    (select (lease_token is null)::text from public.fabio_devolutivas where id=v_id));

  -- volta pra fila e conclui com o token novo
  update public.fabio_devolutivas set status='pendente', aguardando_desde=null where id=v_id;
  a := public.fabio_devolutiva_claim('worker-C', 10);
  v_tok := (a->>'lease_token')::uuid;
  perform pg_temp.checar('39. gerada com token vigente','true',
    public.fabio_devolutiva_gerada(v_id, v_tok, 'texto normal','texto apoio',
      'responsavel','Renata', 9, v_skill, 1)::text);
  perform pg_temp.checar('40. gravou a versao da skill','1',
    (select skill_versao::text from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('41. gravou as DUAS versoes','true',
    (select (texto_normal is not null and texto_apoio_casa is not null)::text
       from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('42. idade congelada','9',
    (select idade_na_geracao::text from public.fabio_devolutivas where id=v_id));
exception when others then
  insert into _falhas values ('PARTE 4 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 5 — backoff: linha que falha não volta no tick seguinte
-- ============================================================================
do $t$
declare
  v_aula integer; v_unidade uuid; v_reg uuid; v_aluno integer;
  a jsonb; v_id uuid; v_tok uuid;
begin
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id = 25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id offset 1 limit 1;
  if v_aula is null then return; end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"ok","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg;
  perform public.fabio_enfileirar_devolutivas(v_reg);

  a := public.fabio_devolutiva_claim('worker-D', 10);
  v_id := ((a->'itens')->0)->>'id';
  v_tok := (a->>'lease_token')::uuid;

  perform pg_temp.checar('51. falhou com token certo','true',
    public.fabio_devolutiva_falhou(v_id, v_tok, 'LLM fora do ar', 600)::text);
  perform pg_temp.checar('52. voltou pra fila','pendente',
    (select status from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('53. backoff no futuro','true',
    (select (proxima_tentativa_em > now())::text from public.fabio_devolutivas where id=v_id));

  a := public.fabio_devolutiva_claim('worker-E', 10);
  perform pg_temp.checar('54. claim IGNORA quem esta em backoff','0',
    (select count(*)::text from jsonb_array_elements(a->'itens') e
      where (e->>'id')::uuid = v_id));
exception when others then
  insert into _falhas values ('PARTE 5 (excecao)','sem excecao', sqlerrm);
end $t$;

select json_build_object(
  'teste',  '020-devolutiva-aula-fila-e-skill',
  'falhas', (select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object(
                'passo', passo, 'esperado', esperado, 'obtido', obtido))
              from _falhas), '[]'::json)
) as resumo;
