-- 070 (teste) — o painel conta AULA, não par aluno-aula
--
-- O passo que dá nome à migration é "o resumo conta AULAS, nao pares". Ele só
-- vale com a âncora logo acima dele: se toda aula da janela tivesse um aluno
-- só, `count(*)` e `count(distinct aula_id)` dariam o mesmo número e o passo
-- passaria verde sem medir nada — exatamente o buraco que deixou o defeito da
-- 065 atravessar 10 passos e 5 mutantes.
--
-- E tem o passo de CRUZAMENTO: a soma do detalhe de um professor tem que bater
-- com a linha dele na fila. São duas funções lendo a mesma view por caminhos
-- diferentes; se divergirem, a tela mostra "21 aulas" na linha e lista outra
-- quantidade ao expandir — e aí ninguém confia em nenhum dos dois.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Guardas: as duas funções recusam quem não é da coordenação ─────────────
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_coordenacao_em_aberto(7, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade a fila recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin perform public.app_coordenacao_professor_detalhe(1, 7);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade o detalhe recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_uid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;
  insert into _res values ('ancora: ha coordenador com login', 'sim',
    case when v_uid is null then 'NAO' else 'sim' end);
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

create temp table _saida on commit drop as
  select public.app_coordenacao_em_aberto(7, null) as j;

-- ─── O PASSO DESTA MIGRATION ────────────────────────────────────────────────
-- Sem esta âncora o passo seguinte é decoração: com 1 aluno por aula em toda a
-- janela, contar par e contar aula dá o mesmo número.
insert into _res select 'ancora: ha aula com mais de um aluno na janela', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — toda aula tem 1 aluno; o passo abaixo nao falseia' end
     from (select aula_id from public.vw_presenca_pendencia
            where data_aula >= current_date - 7 and data_aula < current_date
            group by aula_id having count(distinct aluno_id) > 1) t);

insert into _res select 'o resumo conta AULAS, nao pares aluno-aula',
  (select count(distinct aula_id)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

-- Contra-passo: se alguém trouxer o `count(*)` de volta, é este que grita. Ele
-- afirma que os dois números NÃO são iguais nos dados de hoje.
insert into _res select 'o resumo NAO e mais o total de linhas da view', 'sim',
  (select case when (j->'resumo'->>'sem_lancamento')::int
                  < (select count(*) from public.vw_presenca_pendencia
                      where data_aula >= current_date - 7 and data_aula < current_date)
               then 'sim' else 'NAO — voltou a contar par aluno-aula' end
     from _saida);

insert into _res select 'somar as AULAS das linhas devolve o total do resumo',
  (select j->'resumo'->>'sem_lancamento' from _saida),
  (select coalesce(sum((x->>'aulas')::int), 0)::text
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select '"so de ontem" tambem conta aula',
  (select count(distinct aula_id)::text from public.vw_presenca_pendencia
    where data_aula = current_date - 1),
  (select j->'resumo'->>'ontem' from _saida);

-- ─── Campos novos da linha (foto e cursos) ──────────────────────────────────
insert into _res select 'ancora: os professores da fila tem foto no cadastro', 'sim',
  (select case when count(*) = 0 then 'sim'   -- ninguem sem foto = ancora ok
               else 'NAO — ' || count(*)::text || ' sem foto (fallback vira o caso comum)' end
     from public.professores pr
    where pr.id in (select professor_id from public.vw_presenca_pendencia
                     where data_aula >= current_date - 7 and data_aula < current_date)
      and coalesce(pr.foto_url, '') = '');

insert into _res select 'a linha traz a foto de quem tem', 'sim',
  (select case when bool_and(x->>'foto_url' is not null) then 'sim'
               else 'NAO — veio linha sem foto_url' end
     from _saida, lateral jsonb_array_elements(j->'professores') x
    where (x->>'professor_id')::int in (
      select id from public.professores where coalesce(foto_url,'') <> ''));

insert into _res select 'a linha traz os cursos do professor', 'sim',
  (select case when bool_and(coalesce(x->>'cursos','') <> '') then 'sim'
               else 'NAO — veio linha sem curso' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

-- ─── Ordem e chave (o que a 067 garantiu e não pode regredir) ───────────────
insert into _res select 'a fila NAO repete professor', 'sim',
  (select case when count(*) = count(distinct (x->>'professor_id')::int) then 'sim'
               else 'NAO — ' || count(*)::text || ' linhas para '
                    || count(distinct (x->>'professor_id')::int)::text || ' professores' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'ancora: ha valores distintos de aulas', 'sim',
  (select case when count(distinct (x->>'aulas')::int) >= 2 then 'sim'
               else 'NAO — todos empatados' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'a fila desce por urgencia', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — fila fora de ordem' end
     from (
       select (x->>'aulas')::int
              <= lag((x->>'aulas')::int, 1, 2147483647) over (order by ord) as ok
         from _saida, lateral jsonb_array_elements(j->'professores')
              with ordinality t(x, ord)
     ) s);

insert into _res select 'a aula de HOJE nao entra na cobranca',
  (select count(distinct aula_id)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

-- ─── O DETALHE, e o cruzamento com a fila ───────────────────────────────────
create temp table _alvo on commit drop as
  select (j->'professores'->0->>'professor_id')::int as professor_id,
         (j->'professores'->0->>'aulas')::int        as aulas_na_fila
    from _saida;

create temp table _det on commit drop as
  select public.app_coordenacao_professor_detalhe(
           (select professor_id from _alvo), 7) as j;

insert into _res select 'ancora: o alvo do detalhe existe', 'sim',
  (select case when professor_id is not null then 'sim' else 'NAO — fila vazia' end
     from _alvo);

insert into _res select 'o detalhe bate com a linha da fila',
  (select aulas_na_fila::text from _alvo),
  (select j->>'aulas' from _det);

insert into _res select 'somar os dias devolve o total do detalhe',
  (select j->>'aulas' from _det),
  (select coalesce(sum((d->>'aulas')::int), 0)::text
     from _det, lateral jsonb_array_elements(j->'dias') d);

insert into _res select 'somar os itens devolve o total do detalhe',
  (select j->>'aulas' from _det),
  (select count(*)::text
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i);

insert into _res select 'ancora: o detalhe tem mais de um dia', 'sim',
  (select case when jsonb_array_length(j->'dias') >= 2 then 'sim'
               else 'NAO — um dia so; a ordem abaixo nao falseia' end from _det);

insert into _res select 'os dias sobem do mais ANTIGO para o mais novo', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — ordem invertida' end
     from (
       select (d->>'data_aula')::date
              >= lag((d->>'data_aula')::date, 1, '1900-01-01'::date) over (order by ord) as ok
         from _det, lateral jsonb_array_elements(j->'dias') with ordinality t(d, ord)
     ) s);

insert into _res select 'o detalhe nao repete aula', 'sim',
  (select case when count(*) = count(distinct (i->>'aula_id')) then 'sim'
               else 'NAO — aula repetida no detalhe' end
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i);

insert into _res select 'a aula de HOJE nao entra no detalhe', 'sim',
  (select case when count(*) = 0 then 'sim' else 'NAO — hoje vazou pro detalhe' end
     from _det, lateral jsonb_array_elements(j->'dias') d
    where (d->>'data_aula')::date >= current_date);

insert into _res select 'ancora: ha aula com turma no detalhe', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — nenhuma turma com 2+ alunos; alunos_nomes nao falseia' end
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i
    where (i->>'alunos')::int > 1);

insert into _res select 'aula de turma lista mais de um nome', 'sim',
  (select case when count(*) = 0 then 'sim'
               else 'NAO — ' || count(*)::text || ' turma(s) com 1 nome so' end
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i
    where (i->>'alunos')::int > 1
      and coalesce(i->>'alunos_nomes','') not like '%, %');

-- ─── Permissões das DUAS funções ────────────────────────────────────────────
insert into _res select 'anon NAO executa a fila', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
     then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa a fila', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
     then 'sim' else 'NAO' end);

insert into _res select 'anon NAO executa o detalhe', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_professor_detalhe(int, int)', 'execute')
     then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa o detalhe', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_professor_detalhe(int, int)', 'execute')
     then 'sim' else 'NAO' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
