-- Teste da régua de cobrança da experimental. Roda em BEGIN/ROLLBACK.
do $$
declare
  v_n integer; v_antes integer; v_depois integer; v_vinculo bigint; v_aula integer;
  v_usuario integer; v_auth_original uuid; v_data_hora_fim_original timestamptz;
begin
  -- 1. as funções existem e devolvem o combinado
  if public.fn_data_corte_experimental() <> date '2026-08-22' then
    raise exception 'FALHOU 1a: corte deveria ser 2026-08-22, veio %', public.fn_data_corte_experimental();
  end if;
  if public.fn_janela_experimental_dias() <> 3 then
    raise exception 'FALHOU 1b: janela deveria ser 3, veio %', public.fn_janela_experimental_dias();
  end if;

  -- 2. INVARIANTE 1: a régua de ALUNO não muda. Se esta contagem mudar, a
  --    entrega quebrou o que já estava no ar.
  select count(*) into v_antes from vw_registro_pendencia where cobravel;
  if v_antes = 0 then
    raise exception 'FALHOU 2: baseline de aluno veio 0 — teste nao mede nada';
  end if;

  -- 3. INVARIANTE 2 (AO VIVO): professor sem app nunca entra, no dado de hoje.
  select count(*) into v_n from vw_experimental_pendencia v
   where not public.fn_professor_usa_app(v.professor_id);
  if v_n <> 0 then
    raise exception 'FALHOU 3: % linha(s) de professor sem app', v_n;
  end if;

  -- 4. INVARIANTE 3 (AO VIVO): nada antes da data de corte, no dado de hoje.
  select count(*) into v_n from vw_experimental_pendencia v
   where (v.data_hora_fim at time zone 'America/Sao_Paulo')::date < public.fn_data_corte_experimental();
  if v_n <> 0 then
    raise exception 'FALHOU 4: % linha(s) anteriores ao corte', v_n;
  end if;

  -- ── cenário sintético GARANTIDO, usado pelos passos 3s/4s/5 abaixo ────────
  -- I2 (revisão 22/08/2026): os passos 3 e 4 acima só contam linha na view AO
  -- VIVO. Hoje os mutantes que tiram `fn_professor_usa_app` ou o corte de data
  -- do WHERE morrem porque o dado AMBIENTE calha de ter 4 linhas de professor
  -- sem app e 33 de aula pré-corte pendentes — mas isso é sorte do dia, não
  -- prova. No dia em que aqueles 4 professores ganharem o app (próximo passo
  -- planejado do rollout), o passo 3 vira `0 = 0` e para de significar
  -- qualquer coisa, sem NADA ficar vermelho. Por isso o mesmo vínculo real
  -- que o bloco de INVARIANTES 4/5/6 já perturbava (só a data) agora também
  -- sustenta 3s e 4s: perturbação do RELÓGIO e do CADASTRO, nunca do dado em
  -- si — tudo dentro da mesma transação, tudo desfeito antes do ROLLBACK
  -- final (que de qualquer forma desfaz tudo).
  select v.id, a.id into v_vinculo, v_aula
    from public.lead_experimental_aulas v
    join public.lead_experimentais le on le.id = v.lead_experimental_id
    join public.aulas_emusys a on a.id = v.aula_local_id
   where le.status in ('experimental_realizada', 'convertido')
     and v.substituido_em is null and v.cancelado_em is null
     and a.id = public.fn_aula_operacional_id(a.id)
     and coalesce(a.cancelada, false) = false
     and a.data_hora_fim < now()
     and public.fn_professor_usa_app(a.professor_id)
     and not exists (select 1 from public.lead_experimental_registros r where r.vinculo_id = v.id)
   limit 1;

  if v_vinculo is null then
    raise exception 'FALHOU setup: nenhum vinculo elegivel para sintetizar (professor com app, aula concluida, sem registro) — teste nao pode medir nada';
  end if;

  select a.data_hora_fim into v_data_hora_fim_original from public.aulas_emusys a where a.id = v_aula;

  update public.aulas_emusys set data_hora_fim = now() - interval '2 hours' where id = v_aula;

  if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU setup: vinculo sintetico nao apareceu pendente logo apos o deslocamento de data (setup quebrado)';
  end if;

  -- 3s. INVARIANTE 2 (SINTÉTICO): revoga o app do professor do vínculo
  --     sintético (mesmo mecanismo de fn_professor_usa_app: auth_user_id vira
  --     null) e confirma que a linha SOME — depois religa e confirma que ela
  --     VOLTA. Isso mata o mutante que tira `fn_professor_usa_app` do WHERE
  --     independente de quantos professores sem app existam em produção hoje.
  select u.id, u.auth_user_id into v_usuario, v_auth_original
    from public.aulas_emusys a
    join public.professores pr on pr.id = a.professor_id
    join public.usuarios u on u.id = pr.usuario_id
   where a.id = v_aula;

  if v_usuario is null then
    raise exception 'FALHOU 3s-setup: professor do vinculo sintetico nao tem usuario associado';
  end if;

  update public.usuarios set auth_user_id = null where id = v_usuario;
  if exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 3s: professor SEM app (auth_user_id nulo) ainda aparece na pendencia (vinculo %)', v_vinculo;
  end if;

  update public.usuarios set auth_user_id = v_auth_original where id = v_usuario;
  if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 3s-restore: vinculo sintetico nao voltou a pendente apos religar o app (setup quebrado)';
  end if;

  -- 4s. INVARIANTE 3 (SINTÉTICO): desloca a MESMA aula pra um dia ANTES do
  --     corte e confirma que a linha SOME — depois devolve pra dentro da
  --     janela e confirma que ela VOLTA. O corte é uma DATA FIXA
  --     (2026-08-22); contar contra a view ao vivo só pega o mutante enquanto
  --     produção calhar de ter aula pré-corte pendente (33 linhas hoje), e
  --     essas linhas saem de "aula concluída sem registro" por outros motivos
  --     com o tempo — sem sintético, o teste vira decoração no mesmo padrão
  --     do 3s.
  update public.aulas_emusys
     set data_hora_fim = (public.fn_data_corte_experimental() - interval '1 day') + time '10:00'
   where id = v_aula;
  if exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 4s: aula com data_hora_fim ANTES do corte ainda aparece na pendencia (vinculo %)', v_vinculo;
  end if;

  update public.aulas_emusys set data_hora_fim = now() - interval '2 hours' where id = v_aula;
  if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 4s-restore: vinculo sintetico nao voltou a pendente apos religar dentro da janela (setup quebrado)';
  end if;

  -- 5. INVARIANTES 4/5/6 — cenário sintético GARANTIDO (mesmo vínculo de 3s/4s).
  --    Não depende da produção ter uma pendência real no momento em que o
  --    teste roda: medido em 22/08/2026 (fix round 1) a produção tinha 0
  --    pendências pós-corte, e um "select ... limit 1" na view real teria
  --    virado no-op silencioso justo no caso que mais precisa ser provado (a
  --    trava do Achado 1).

  -- 5a. registro em aguardando_confirmacao CONTINUA pendente.
  --     unidade_id e NOT NULL sem default nesta tabela: omitir derruba o
  --     INSERT por violacao de NOT NULL, e a falha PARECE o RED legitimo do
  --     passo 3.
  insert into lead_experimental_registros (vinculo_id, unidade_id, status, anotacao_pedagogica)
    select v_vinculo, a.unidade_id, 'aguardando_confirmacao', 'teste'
      from aulas_emusys a where a.id = v_aula;
  if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 5a: pendencia fechou com registro NAO confirmado (vinculo %)', v_vinculo;
  end if;

  -- 5b. ACHADO 1 (fix round 1): 'rascunho' e o DEFAULT NOT NULL da coluna
  --     status. O denylist antigo ("not in descartado/aguardando_confirmacao")
  --     tratava rascunho como "tem devolutiva" — todo INSERT que omite o
  --     status cai em rascunho por default e fechava a pendencia sem o
  --     comercial nunca ter recebido nada. So 'confirmado' pode fechar.
  update lead_experimental_registros set status = 'rascunho'
   where vinculo_id = v_vinculo and status = 'aguardando_confirmacao';
  if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 5b: pendencia fechou com registro em RASCUNHO (vinculo %) — allowlist quebrada', v_vinculo;
  end if;

  -- 5c. confirmado fecha
  update lead_experimental_registros set status = 'confirmado'
   where vinculo_id = v_vinculo and status = 'rascunho';
  if exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
    raise exception 'FALHOU 5c: pendencia NAO fechou com registro confirmado (vinculo %)', v_vinculo;
  end if;

  -- Restaura a data original da aula sintética antes do fecho — defensivo:
  -- o ROLLBACK final desfaz tudo de qualquer forma, mas nenhum passo daqui
  -- pra frente depende mais do deslocamento.
  update public.aulas_emusys set data_hora_fim = v_data_hora_fim_original where id = v_aula;

  -- 6. INVARIANTE 1 (fecho): a régua de aluno segue idêntica
  select count(*) into v_depois from vw_registro_pendencia where cobravel;
  if v_antes <> v_depois then
    raise exception 'FALHOU 6: regua de aluno mudou (% -> %)', v_antes, v_depois;
  end if;

  raise exception 'VERDE: todos os casos passaram (baseline aluno=%)', v_antes;
end $$;
