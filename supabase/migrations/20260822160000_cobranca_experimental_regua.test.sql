-- Teste da régua de cobrança da experimental. Roda em BEGIN/ROLLBACK.
do $$
declare
  v_n integer; v_antes integer; v_depois integer;
  v_prof integer; v_uid integer; v_auth uuid; v_vinculo bigint; v_aula integer;
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

  -- 3. INVARIANTE 2: professor sem app nunca entra
  select count(*) into v_n from vw_experimental_pendencia v
   where not public.fn_professor_usa_app(v.professor_id);
  if v_n <> 0 then
    raise exception 'FALHOU 3: % linha(s) de professor sem app', v_n;
  end if;

  -- 4. INVARIANTE 3: nada antes da data de corte
  select count(*) into v_n from vw_experimental_pendencia v
   where (v.data_hora_fim at time zone 'America/Sao_Paulo')::date < public.fn_data_corte_experimental();
  if v_n <> 0 then
    raise exception 'FALHOU 4: % linha(s) anteriores ao corte', v_n;
  end if;

  -- 5. INVARIANTE 5: registro em aguardando_confirmacao CONTINUA pendente.
  --    Cenário sintético: pego uma pendência real e crio o registro nao
  --    confirmado; ela tem que permanecer. Tudo volta no ROLLBACK.
  select v.vinculo_id, v.aula_id into v_vinculo, v_aula
    from vw_experimental_pendencia v limit 1;
  if v_vinculo is not null then
    -- unidade_id e NOT NULL sem default nesta tabela: omitir derruba o INSERT
    -- por violacao de NOT NULL, e a falha PARECE o RED legitimo do passo 3.
    insert into lead_experimental_registros (vinculo_id, unidade_id, status, anotacao_pedagogica)
      select v_vinculo, a.unidade_id, 'aguardando_confirmacao', 'teste'
        from aulas_emusys a where a.id = v_aula;
    if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
      raise exception 'FALHOU 5: pendencia fechou com registro NAO confirmado (vinculo %)', v_vinculo;
    end if;
    update lead_experimental_registros set status = 'confirmado'
     where vinculo_id = v_vinculo and status = 'aguardando_confirmacao';
    if exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
      raise exception 'FALHOU 5b: pendencia NAO fechou com registro confirmado (vinculo %)', v_vinculo;
    end if;
  end if;

  -- 6. INVARIANTE 1 (fecho): a régua de aluno segue idêntica
  select count(*) into v_depois from vw_registro_pendencia where cobravel;
  if v_antes <> v_depois then
    raise exception 'FALHOU 6: regua de aluno mudou (% -> %)', v_antes, v_depois;
  end if;

  raise exception 'VERDE: todos os casos passaram (baseline aluno=%)', v_antes;
end $$;
