-- Teste da migration 019. Não aborta: registra divergências e devolve resumo
-- estruturado, para o ROLLBACK do runner executar com a transação sadia.
--
-- Rodar com:  npm run teste:019
--
-- O que ele prova, na ordem em que a auditoria pediu:
--   • presença é AFIRMAÇÃO: chave faltando ou lixo => nao_informada;
--   • aula 1:1 com aluno AUSENTE não vira registro pedagógico (era o buraco);
--   • aula 1:1 sem presença declarada vira pendência com NOME e ação — não
--     "Aluno" e nada, que era o beco sem saída;
--   • fatia de turma sem presença também vira pendência, em vez de gravar
--     "presente" por coalesce;
--   • a resposta do professor destrava a confirmação.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;

create function pg_temp.checar(p_passo text, p_esperado text, p_obtido text)
returns void language plpgsql as $c$
begin
  if p_esperado is distinct from p_obtido then
    insert into _falhas values (p_passo, coalesce(p_esperado,'(null)'), coalesce(p_obtido,'(null)'));
  end if;
end $c$;

-- O professor do piloto responde pelas RPCs de app (auth.uid() sai daqui).
set local request.jwt.claims = '{"sub":"25b46e60-8c41-460d-b5a4-6dd8d1d24de1","role":"authenticated"}';

-- ============================================================================
-- PARTE 1 — fn_presenca_declarada: ausência de dado NÃO é presença
-- ============================================================================
do $t$
begin
  perform pg_temp.checar('1. presente','presente',
    public.fn_presenca_declarada('{"presenca":"presente"}'::jsonb));
  perform pg_temp.checar('2. ausente','ausente',
    public.fn_presenca_declarada('{"presenca":"ausente"}'::jsonb));
  perform pg_temp.checar('3. chave faltando','nao_informada',
    public.fn_presenca_declarada('{"progresso":"tocou a escala"}'::jsonb));
  perform pg_temp.checar('4. campos vazio','nao_informada',
    public.fn_presenca_declarada('{}'::jsonb));
  perform pg_temp.checar('5. campos null','nao_informada',
    public.fn_presenca_declarada(null));
  perform pg_temp.checar('6. valor estranho','nao_informada',
    public.fn_presenca_declarada('{"presenca":"talvez"}'::jsonb));
exception when others then
  insert into _falhas values ('PARTE 1 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 2 — o contexto de auth do teste está de pé
-- ============================================================================
do $t$
begin
  perform pg_temp.checar('10. professor resolvido pelo jwt','25',
    public.fn_professor_do_usuario()::text);
exception when others then
  insert into _falhas values ('PARTE 2 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 3 — AULA 1:1 com aluno AUSENTE
--
-- Antes desta migration o ramo 1:1 nem consultava presença: gravava no
-- prontuário e virava gravado_emusys. Uma aula que não aconteceu.
-- ============================================================================
do $t$
declare v_aula integer; v_aluno integer; v_unidade uuid; v_id uuid; r jsonb;
begin
  select a.id, a.unidade_id, aa.aluno_id into v_aula, v_unidade, v_aluno
    from public.aulas_emusys a
    join public.aula_alunos_emusys aa on aa.aula_emusys_id = a.id
   where a.professor_id = 25 and coalesce(a.qtd_alunos,1) = 1
   order by a.id desc limit 1;
  if v_aula is null then
    insert into _falhas values ('PARTE 3 (setup)','uma aula 1:1 do professor 25','nenhuma encontrada');
    return;
  end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
     texto_consolidado, status, origem)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
     jsonb_build_object('progresso','trabalhou escala','presenca','ausente'),
     'texto qualquer', 'aguardando_confirmacao', 'app')
  returning id into v_id;

  r := public.app_confirmar_registro(v_id, 'novo');
  perform pg_temp.checar('21. nada gravado no prontuario','0', r->>'gravadas');
  perform pg_temp.checar('22. contabilizado como pulado','1', r->>'ausentes_puladas');
  perform pg_temp.checar('23. status NAO virou gravado_emusys','confirmado',
    (select status from public.fabio_registros_aula where id=v_id));
exception when others then
  insert into _falhas values ('PARTE 3 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 4 — AULA 1:1 SEM presença declarada
--
-- Antes: o coalesce dizia "presente" e a aula era gravada. Agora vira pendência
-- respondível — com nome do aluno e com os valores permitidos, porque a tela
-- não tem como adivinhar (na 1:1 não existe fatia pra procurar).
-- ============================================================================
do $t$
declare v_aula integer; v_aluno integer; v_unidade uuid; v_id uuid; r jsonb; p jsonb;
begin
  select a.id, a.unidade_id, aa.aluno_id into v_aula, v_unidade, v_aluno
    from public.aulas_emusys a
    join public.aula_alunos_emusys aa on aa.aula_emusys_id = a.id
   where a.professor_id = 25 and coalesce(a.qtd_alunos,1) = 1
   order by a.id desc limit 1;
  if v_aula is null then return; end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
     texto_consolidado, status, origem)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
     jsonb_build_object('progresso','trabalhou escala'),   -- SEM 'presenca'
     'texto qualquer', 'aguardando_confirmacao', 'app')
  returning id into v_id;

  r := public.app_confirmar_registro(v_id, 'novo');
  p := (r->'pendencias')->0;

  perform pg_temp.checar('31. nao gravou','0', r->>'gravadas');
  perform pg_temp.checar('32. gerou 1 pendencia','1',
    jsonb_array_length(r->'pendencias')::text);
  perform pg_temp.checar('33. alvo e a RAIZ, nao uma fatia','raiz', p->>'tipo_alvo');
  perform pg_temp.checar('34. alvo aponta pro registro', v_id::text, p->>'registro_alvo_id');
  perform pg_temp.checar('35. campo obrigatorio nomeado','presenca', p->>'campo_obrigatorio');
  perform pg_temp.checar('36. valores permitidos vem no contrato','["presente", "ausente"]',
    (p->'valores_permitidos')::text);
  perform pg_temp.checar('37. tem NOME do aluno (nao "Aluno")','true',
    (coalesce(p->>'aluno_nome','') <> '')::text);
  perform pg_temp.checar('38. compat: fatia_id ainda vem pro app atual', v_id::text,
    p->>'fatia_id');

  -- ===== a resposta do professor destrava =====
  perform public.app_responder_presenca(v_id, 'presente');
  perform pg_temp.checar('39. presenca gravada','presente',
    public.fn_presenca_declarada((select campos from public.fabio_registros_aula where id=v_id)));
exception when others then
  insert into _falhas values ('PARTE 4 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 5 — TURMA: fatia sem presença declarada
-- ============================================================================
do $t$
declare v_aula integer; v_aluno integer; v_unidade uuid; v_tronco uuid; v_fatia uuid; r jsonb; p jsonb;
begin
  select a.id, a.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a where a.professor_id = 25 order by a.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  if v_aula is null or v_aluno is null then return; end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem)
  values (v_aula, v_unidade, 25, null, null, 'C',
     jsonb_build_object('objetivo','aula de turma'), 'aguardando_confirmacao', 'app')
  returning id into v_tronco;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
     texto_consolidado, status, origem)
  values (v_aula, v_unidade, 25, v_aluno, v_tronco, 'C',
     jsonb_build_object('progresso','acompanhou bem'),     -- SEM 'presenca'
     'texto qualquer', 'aguardando_confirmacao', 'app')
  returning id into v_fatia;

  r := public.app_confirmar_registro(v_tronco, 'novo');
  p := (r->'pendencias')->0;

  perform pg_temp.checar('41. turma nao gravou a fatia sem presenca','0', r->>'gravadas');
  perform pg_temp.checar('42. gerou pendencia','1', jsonb_array_length(r->'pendencias')::text);
  perform pg_temp.checar('43. alvo e a FATIA','fatia', p->>'tipo_alvo');
  perform pg_temp.checar('44. alvo aponta pra fatia', v_fatia::text, p->>'registro_alvo_id');
  perform pg_temp.checar('45. campo obrigatorio nomeado','presenca', p->>'campo_obrigatorio');
  perform pg_temp.checar('46. tronco fica em confirmado (tem pendencia)','confirmado',
    (select status from public.fabio_registros_aula where id=v_tronco));
exception when others then
  insert into _falhas values ('PARTE 5 (excecao)','sem excecao', sqlerrm);
end $t$;

select json_build_object(
  'teste',  '019-presenca-declarada-e-pendencia-por-alvo',
  'falhas', (select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object(
                'passo', passo, 'esperado', esperado, 'obtido', obtido))
              from _falhas), '[]'::json)
) as resumo;
