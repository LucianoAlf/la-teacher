do $$
declare
  r jsonb;
  v_unidade uuid;
  v_prof integer;
  v_aula_a integer; v_aula_b integer; v_aula_c integer;
  v_lead_a integer; v_lead_b integer; v_lead_c integer;
  v_vinc_a bigint; v_vinc_b bigint; v_vinc_c bigint;
begin
  -- SENTINELA DE VAZAMENTO — antes de qualquer insert ou DDL. Este teste
  -- redefine fn_data_corte_experimental() em produção (ver comentário mais
  -- abaixo); se uma rodada anterior tiver perdido o raise exception final
  -- por algum motivo, o corte fica preso em 2000-01-01 e todo run seguinte
  -- rodaria sobre uma régua errada, em silêncio. Aborta alto e explícito em
  -- vez de deixar isso passar despercebido.
  if public.fn_data_corte_experimental() <> date '2026-08-22' then
    raise exception 'ABORTADO: fn_data_corte_experimental esta em % (esperado 2026-08-22) — provavel vazamento de uma rodada anterior deste teste; conferir antes de rodar', public.fn_data_corte_experimental();
  end if;

  -- === PERMISSAO (FALHOU 11) — logo no comeco, antes do cenario sintetico.
  -- Nao depende de nenhum dado: se FALHOU 1..10 quebrar mais adiante, o
  -- teste aborta ali e esta checagem — a que mais precisa sobreviver — nunca
  -- chega a rodar. As RPCs sao security definer (rodam como o dono; RLS das
  -- tabelas de baixo nao protege nada) e a view expoe nome de aluno/curso/
  -- unidade/professor. O schema public e o schema exposto do PostgREST, com
  -- default privileges pra anon/authenticated — objeto novo nasce alcancavel
  -- pela chave publicavel do PWA se ninguem revogar explicitamente. Isso ja
  -- vazou uma vez (as 3 RPCs + a view nasceram com anon=X/authenticated=X).
  --
  -- has_function_privilege/has_table_privilege em vez de regex no texto do
  -- ACL: a régua textual (~ '(anon|authenticated)=X') é cega ao "=X" de
  -- PUBLIC — se alguém revogar só de anon/authenticated e a função ficar
  -- com GRANT ... TO PUBLIC (ex.: copiar a linha de revoke da view, que não
  -- lista public, em vez da linha da função), o ACL vira
  -- "{=X/postgres,postgres=X/postgres,...}" — sem "anon=" nem "authenticated="
  -- textual — e anon continua podendo executar. has_function_privilege
  -- resolve PUBLIC, ACL nula e papel intermediário de uma vez, porque
  -- pergunta o privilégio EFETIVO, não o texto do ACL.
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_experimental_lembrete_alvos',
                         'fn_experimental_pendencia_do_professor',
                         'fn_experimental_escalonadas')
       and (has_function_privilege('anon', p.oid, 'execute')
         or has_function_privilege('authenticated', p.oid, 'execute'))
    union all
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'vw_experimental_pendencia'
       and (has_table_privilege('anon', c.oid, 'select')
         or has_table_privilege('authenticated', c.oid, 'select'))
  ) then
    raise exception 'FALHOU 11: RPC ou view de cobranca alcancavel por anon/authenticated';
  end if;

  -- === CENARIO SINTETICO ===
  -- A view vw_experimental_pendencia fica em 0 linhas por horas seguidas —
  -- é o normal do dia a dia (aula recém-encerrada ainda não virou pendência,
  -- ou o professor já confirmou tudo). Sem montar um caso aqui, os asserts
  -- de professor_id/dias_em_atraso/horas_em_atraso abaixo PASSAM VAZIOS
  -- SEMPRE — verde que não falsifica nada é decoração, não teste (é por
  -- isso que a régua da casa manda matar mutante). As 3 aulas abaixo usam
  -- emusys_id negativo (nunca colide com dado real) e os asserts filtram só
  -- pelo vinculo_id devolvido na inserção — o teste vale igual com a view
  -- vazia ou com dado real dentro dela.
  select id into v_unidade from unidades limit 1;
  select p.id into v_prof from professores p where fn_professor_usa_app(p.id) limit 1;

  if v_unidade is null or v_prof is null then
    raise exception 'SETUP FALHOU: nao achei unidade ou professor com app pra montar o cenario';
  end if;

  -- O corte (fn_data_corte_experimental) é fixo em 2026-08-22 pra sempre;
  -- pra simular uma aula de dias atrás (necessário pro caso C / mutante da
  -- janela) é preciso afrouxá-lo só durante este teste. O raise exception
  -- no fim deste bloco aborta a transação implícita do comando inteiro e
  -- desfaz esta redefinição (DDL é transacional) junto com os dados
  -- sintéticos — não precisa de restore manual.
  -- ⚠️ QUEM FOR EDITAR: o raise exception do fim do bloco É o que desfaz
  -- isto. Tirá-lo (p.ex. "pra ver o resultado sem abortar") deixa
  -- fn_data_corte_experimental() = 2000-01-01 valendo em PRODUÇÃO.
  execute $ddl$
    create or replace function public.fn_data_corte_experimental()
    returns date language sql immutable parallel safe
    as $body$ select date '2000-01-01' $body$
  $ddl$;

  insert into aulas_emusys (emusys_id, unidade_id, professor_id, curso_nome, data_aula, data_hora_inicio, data_hora_fim, cancelada)
  values (-900001, v_unidade, v_prof, 'TESTE SINTETICO A', current_date, now() - interval '40 minutes', now() - interval '10 minutes', false)
  returning id into v_aula_a;

  insert into aulas_emusys (emusys_id, unidade_id, professor_id, curso_nome, data_aula, data_hora_inicio, data_hora_fim, cancelada)
  values (-900002, v_unidade, v_prof, 'TESTE SINTETICO B', (now() - interval '1 day')::date, now() - interval '1 day' - interval '30 minutes', now() - interval '1 day', false)
  returning id into v_aula_b;

  insert into aulas_emusys (emusys_id, unidade_id, professor_id, curso_nome, data_aula, data_hora_inicio, data_hora_fim, cancelada)
  values (-900003, v_unidade, v_prof, 'TESTE SINTETICO C', (now() - interval '4 days')::date, now() - interval '4 days' - interval '30 minutes', now() - interval '4 days', false)
  returning id into v_aula_c;

  insert into lead_experimentais (nome_aluno, unidade_id, professor_experimental_id, status)
  values ('Teste Sintetico A', v_unidade, v_prof, 'experimental_realizada') returning id into v_lead_a;
  insert into lead_experimentais (nome_aluno, unidade_id, professor_experimental_id, status)
  values ('Teste Sintetico B', v_unidade, v_prof, 'experimental_realizada') returning id into v_lead_b;
  insert into lead_experimentais (nome_aluno, unidade_id, professor_experimental_id, status)
  values ('Teste Sintetico C', v_unidade, v_prof, 'convertido') returning id into v_lead_c;

  insert into lead_experimental_aulas (lead_experimental_id, aula_local_id, estado)
  values (v_lead_a, v_aula_a, 'vinculado') returning id into v_vinc_a;
  insert into lead_experimental_aulas (lead_experimental_id, aula_local_id, estado)
  values (v_lead_b, v_aula_b, 'vinculado') returning id into v_vinc_b;
  insert into lead_experimental_aulas (lead_experimental_id, aula_local_id, estado)
  values (v_lead_c, v_aula_c, 'vinculado') returning id into v_vinc_c;

  if (select count(*) from public.vw_experimental_pendencia where vinculo_id in (v_vinc_a, v_vinc_b, v_vinc_c)) <> 3 then
    raise exception 'SETUP FALHOU: view nao pegou as 3 linhas sinteticas';
  end if;

  -- forma: sempre {ok, linhas}, linhas nunca null
  r := public.fn_experimental_lembrete_alvos(20);
  if (r->>'ok')::boolean is not true or jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 1: forma errada em lembrete_alvos: %', r;
  end if;

  r := public.fn_experimental_pendencia_do_professor(-1);
  if jsonb_array_length(r->'linhas') <> 0 then
    raise exception 'FALHOU 2: professor inexistente devia vir vazio, veio %', r;
  end if;

  r := public.fn_experimental_escalonadas();
  if jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 3: escalonadas devia ser array, veio %', jsonb_typeof(r->'linhas');
  end if;

  -- janela: nada com menos dias que a janela pode aparecer no escalonamento
  -- (com o cenário sintético em pé, C -- 4 dias -- garante que a query
  -- abaixo tem algo pra examinar de verdade, não roda contra 0 linhas)
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_escalonadas()->'linhas') x
     where (x->>'dias_em_atraso')::int < public.fn_janela_experimental_dias()
  ) then
    raise exception 'FALHOU 4: escalonamento trouxe caso dentro da janela';
  end if;

  -- lembrete: janela de minutos é respeitada
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_lembrete_alvos(20)->'linhas') x
     where (x->>'horas_em_atraso')::int > 1
  ) then
    raise exception 'FALHOU 5: lembrete trouxe aula de mais de 1h atras com janela de 20min';
  end if;

  -- === asserts que só o cenário sintético consegue exercitar de verdade ===
  r := public.fn_experimental_lembrete_alvos(20);
  if not exists (select 1 from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint = v_vinc_a) then
    raise exception 'FALHOU 6: lembrete nao trouxe a aula A (10min atras): %', r;
  end if;
  if exists (select 1 from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint in (v_vinc_b, v_vinc_c)) then
    raise exception 'FALHOU 7: lembrete trouxe aula velha demais (B ou C): %', r;
  end if;

  -- Ruling 17 (22/08/2026): fn_experimental_pendencia_do_professor passou a
  -- cortar pela MESMA janela que fn_experimental_escalonadas usa
  -- (fn_janela_experimental_dias) — quem passou da janela sobe pra
  -- coordenacao (FALHOU 9/10 abaixo) e nao pode continuar sendo cobrado
  -- aqui tambem, senao e cobranca em dobro sem ninguem assumir. O cenario
  -- sintetico A (0 dias) / B (1 dia) / C (4 dias, janela=3) ja da os dois
  -- lados da borda: A e B ficam DENTRO, C fica FORA.
  r := public.fn_experimental_pendencia_do_professor(v_prof);
  if (select count(*) from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint in (v_vinc_a, v_vinc_b)) <> 2 then
    raise exception 'FALHOU 8: pendencia do professor nao trouxe A e B (dentro da janela, dias_em_atraso < %): %', public.fn_janela_experimental_dias(), r;
  end if;
  if exists (select 1 from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint = v_vinc_c) then
    raise exception 'FALHOU 8b: pendencia do professor trouxe C (4 dias, fora da janela de %) — ja escalou pra coordenacao (FALHOU 9), cobrar aqui tambem e a cobranca em dobro do Ruling 17: %', public.fn_janela_experimental_dias(), r;
  end if;

  r := public.fn_experimental_escalonadas();
  if not exists (select 1 from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint = v_vinc_c) then
    raise exception 'FALHOU 9: escalonadas nao trouxe C (4 dias, fora da janela): %', r;
  end if;
  if exists (select 1 from jsonb_array_elements(r->'linhas') x where (x->>'vinculo_id')::bigint = v_vinc_b) then
    raise exception 'FALHOU 10: escalonadas trouxe B (1 dia, dentro da janela): %', r;
  end if;

  raise exception 'VERDE: RPCs ok (cenario sintetico A/B/C + asserts originais)';
end $$;
