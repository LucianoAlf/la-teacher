-- A aula operacional volta a usar o índice que foi feito pra ela.
--
-- MEDIDO na produção em 13/08/2026: `select count(*) from
-- vw_presenca_pendencia` leva **12,3 segundos** e gasta 3.999.329 buffers.
-- **3.903.506 deles — 97,6% — estão num filtro só:**
--
--   Bitmap Heap Scan on aulas_emusys ae
--     Filter: (id = fn_aula_operacional_id(id))
--     Buffers: shared hit=3903506
--
-- Essa view é a fonte única de "aula sem presença forte": dela saem a cobrança
-- da noite, a da manhã e o escalonamento pra coordenação. Doze segundos por
-- rodada não quebra nada — só deixa tudo lento o tempo todo, que é o jeito de
-- problema que ninguém abre chamado e ninguém conserta.
--
-- A CAUSA. `fn_aula_operacional_id` desempata as linhas duplicadas do mesmo
-- horário (o `aula_emusys_id` é id de EVENTO: o mesmo horário aparece mais de
-- uma vez). Para achar as candidatas ela compara unidade, professor, início,
-- fim e curso. E existe um índice desenhado exatamente pra isso:
--
--   idx_aulas_emusys_slot_operacional
--     ON (unidade_id, professor_id, data_hora_inicio, data_hora_fim, curso_nome)
--     WHERE COALESCE(cancelada,false) = false
--
-- O índice está lá, com 3 MB, e **não é usado**. Quatro das cinco comparações
-- eram `is not distinct from` — o operador null-safe, que **não é indexável**.
-- Ele não é um `=` mais cuidadoso: é outro operador, e o planejador não tem
-- como casá-lo com um btree. O índice certo existia e estava inalcançável.
--
-- (É primo do que a 064 achou: lá o índice era o errado; aqui é o certo,
-- barrado por um operador. Nos dois casos o plano entregou o culpado inteiro.)
--
-- A SAÍDA: DUAS PORTAS, MESMA SEMÂNTICA. O null-safe existia por um motivo
-- legítimo — `unidade_id`, `professor_id`, `data_hora_fim` e `curso_nome`
-- podem ser nulos, e `null = null` não casaria duas aulas igualmente órfãs.
-- Trocar tudo por `=` mudaria resultado, não só velocidade.
--
-- Então a função passa a olhar a linha base ANTES de perguntar: quando os
-- quatro campos são não-nulos — o caso normal, e o único que a
-- `vw_presenca_pendencia` alcança, porque ela já filtra `professor_id is not
-- null` — usa `=` puro e o índice entra. Quando algum é nulo, cai no caminho
-- antigo, byte por byte igual ao que estava aqui. Nenhuma linha muda de
-- resposta; só o caminho até ela.
--
-- POR QUE plpgsql E NÃO SQL. Escolher o ramo exige ler a linha base primeiro.
-- Em SQL puro isso viraria um `OR` entre as duas formas — e um `OR` com o
-- null-safe dentro derruba o índice de novo, que é o defeito com outra roupa.
--
-- O TESTE É DE EQUIVALÊNCIA, não de opinião: ele reconstrói a função ANTIGA
-- em `pg_temp` e compara as duas, linha a linha, num lote real. Otimização que
-- muda resposta não é otimização -- e "eu acho que é equivalente" é
-- exatamente o tipo de coisa que esta casa já pagou pra não repetir.

create or replace function public.fn_aula_operacional_id(p_aula_id integer)
returns integer
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_base public.aulas_emusys%rowtype;
  v_id   integer;
begin
  select * into v_base from public.aulas_emusys where id = p_aula_id;
  if not found then
    return null;
  end if;

  -- CAMINHO INDEXAVEL. So quando os quatro campos null-safe sao nao-nulos:
  -- ai `is not distinct from` e `=` decidem igual, e o `=` alcanca o
  -- idx_aulas_emusys_slot_operacional.
  if v_base.unidade_id     is not null
     and v_base.professor_id  is not null
     and v_base.data_hora_fim is not null
     and v_base.curso_nome    is not null then
    select candidata.id into v_id
      from public.aulas_emusys candidata
      left join lateral (
        select count(*)::integer as n_alunos
          from public.aula_alunos_emusys roster
         where roster.aula_emusys_id = candidata.id
      ) quantidade on true
     where candidata.unidade_id      = v_base.unidade_id
       and candidata.professor_id    = v_base.professor_id
       and candidata.data_hora_inicio = v_base.data_hora_inicio
       and candidata.data_hora_fim   = v_base.data_hora_fim
       and candidata.curso_nome      = v_base.curso_nome
       and coalesce(candidata.cancelada, false) = false
     order by coalesce(quantidade.n_alunos, 0) desc,
              case when candidata.tipo = 'turma' then 0 else 1 end,
              candidata.id desc
     limit 1;
    return v_id;
  end if;

  -- CAMINHO NULL-SAFE. Identico ao original: alguem tem campo nulo, e duas
  -- aulas igualmente orfas continuam casando entre si.
  select candidata.id into v_id
    from public.aulas_emusys candidata
    left join lateral (
      select count(*)::integer as n_alunos
        from public.aula_alunos_emusys roster
       where roster.aula_emusys_id = candidata.id
    ) quantidade on true
   where candidata.unidade_id      is not distinct from v_base.unidade_id
     and candidata.professor_id    is not distinct from v_base.professor_id
     and candidata.data_hora_inicio = v_base.data_hora_inicio
     and candidata.data_hora_fim   is not distinct from v_base.data_hora_fim
     and candidata.curso_nome      is not distinct from v_base.curso_nome
     and coalesce(candidata.cancelada, false) = false
   order by coalesce(quantidade.n_alunos, 0) desc,
            case when candidata.tipo = 'turma' then 0 else 1 end,
            candidata.id desc
   limit 1;
  return v_id;
end;
$function$;

comment on function public.fn_aula_operacional_id(integer) is
  'Desempata as linhas duplicadas do mesmo horario (aula_emusys_id e id de '
  'EVENTO). Dois caminhos com a MESMA semantica: com os quatro campos '
  'null-safe preenchidos usa `=` e alcanca idx_aulas_emusys_slot_operacional; '
  'com algum nulo cai no `is not distinct from` de sempre. O null-safe nao e '
  'indexavel -- era ele que segurava 97,6% dos buffers da '
  'vw_presenca_pendencia (12,3s, medido em 13/08/2026).';
