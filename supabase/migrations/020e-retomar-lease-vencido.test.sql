-- Teste da 020e — o teste de CRASH que faltava.
--
-- Rodar com: npm run teste:020e
--
-- O passo 4 é o que o Alfredo pediu: worker morre no meio (lease vence), e
-- ALGUÉM tem que voltar naquela linha. Sem a 020e ele devolve 0 e a devolutiva
-- fica presa pra sempre — silenciosamente, que é o pior jeito.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_aula integer; v_unidade uuid; v_aluno integer; v_reg uuid;
  a jsonb; b jsonb; v_id uuid; v_tok_morto uuid; v_tok_novo uuid; v_skill uuid;
begin
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id=25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  select id into v_skill from public.fabio_skills where nome='devolutiva_aula' and ativa;
  if v_aula is null then
    insert into _falhas values ('setup','uma aula do professor 25','nenhuma'); return;
  end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"ok","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg;
  perform public.fabio_enfileirar_devolutivas(v_reg);

  -- worker A pega e MORRE (simulado: some sem concluir)
  a := public.fabio_devolutiva_claim('worker-que-morre', 20);
  select id into v_id from public.fabio_devolutivas where registro_fatia_id = v_reg;
  v_tok_morto := (a->>'lease_token')::uuid;
  perform pg_temp.checar('1. worker A pegou a linha','1',
    (select count(*)::text from jsonb_array_elements(a->'itens') e where (e->>'id')::uuid = v_id));
  perform pg_temp.checar('2. ficou em gerando','gerando',
    (select status from public.fabio_devolutivas where id=v_id));

  -- ainda no prazo: ninguém rouba
  b := public.fabio_devolutiva_claim('worker-B', 20);
  perform pg_temp.checar('3. lease vivo: ninguem retoma','0',
    (select count(*)::text from jsonb_array_elements(b->'itens') e where (e->>'id')::uuid = v_id));

  -- ===== O CRASH: o prazo vence e o worker A nunca volta =====
  update public.fabio_devolutivas set lease_expira_em = now() - interval '1 minute' where id=v_id;

  b := public.fabio_devolutiva_claim('worker-C', 20);
  v_tok_novo := (b->>'lease_token')::uuid;
  perform pg_temp.checar('4. CRASH: alguem RETOMA a orfa','1',
    (select count(*)::text from jsonb_array_elements(b->'itens') e where (e->>'id')::uuid = v_id));
  perform pg_temp.checar('5. token trocou na retomada','true',
    (v_tok_morto is distinct from v_tok_novo)::text);
  perform pg_temp.checar('6. retomada consumiu tentativa','2',
    (select tentativas::text from public.fabio_devolutivas where id=v_id));

  -- ===== FENCING: o worker A volta do alem e tenta escrever =====
  perform pg_temp.checar('7. worker morto NAO conclui','false',
    public.fabio_devolutiva_gerada(v_id, v_tok_morto, 'texto do zumbi','apoio do zumbi',
      'aluno','Fulano', 16, v_skill, 1)::text);
  perform pg_temp.checar('8. worker morto NAO falha a linha','false',
    public.fabio_devolutiva_falhou(v_id, v_tok_morto, 'erro do zumbi', 60)::text);
  perform pg_temp.checar('9. worker morto NAO devolve o lease','false',
    public.fabio_devolutiva_devolver(v_id, v_tok_morto)::text);
  perform pg_temp.checar('10. texto do zumbi nao entrou','true',
    (select (texto_normal is null)::text from public.fabio_devolutivas where id=v_id));

  -- quem tem o lease vigente conclui
  perform pg_temp.checar('11. dono atual conclui','true',
    public.fabio_devolutiva_gerada(v_id, v_tok_novo, 'texto bom','apoio bom',
      'aluno','Fulano', 16, v_skill, 1)::text);

  -- ===== teto: linha venenosa sai da fila em vez de virar loop =====
  update public.fabio_devolutivas
     set status='gerando', tentativas=5, lease_expira_em = now() - interval '1 minute'
   where id=v_id;
  perform pg_temp.checar('12. ceifa a linha que estourou o teto','1',
    public.fabio_devolutiva_ceifar_travadas(5)::text);
  perform pg_temp.checar('13. saiu da fila como falhou','falhou',
    (select status from public.fabio_devolutivas where id=v_id));
exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

select json_build_object('teste','020e-retomar-lease-vencido',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
