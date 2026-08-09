-- Teste da 077. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- O que este teste precisa provar, em ordem de importância:
--   1. a OBSERVAÇÃO sai no payload (é o motivo da migration existir)
--   2. verde silencioso NÃO entra na lista (senão vira parede de texto)
--   3. a contagem é de ALUNO, não de linha da carteira (renovação duplica)
--   4. quem não é coordenação não lê nada disso
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord   uuid;
  v_prof    int;
  v_uni     uuid;
  v_alunos  int[];
  v_prof2   int;
  v_uni2    uuid;
  v_aluno2  int;
  v_comp    date := public.fn_competencia_feedback(null);
  v_r       jsonb;
  v_lista   jsonb;
  v_linhas  int;
  v_unicos  int;
  v_erro    text;
begin
  -- ── Quem vai perguntar ────────────────────────────────────────────────────
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  -- Um professor com pelo menos 3 alunos distintos na carteira.
  select v.professor_id, (array_agg(distinct v.unidade_id))[1]
    into v_prof, v_uni
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where v.unidade_id is not null
   group by v.professor_id
  having count(distinct v.aluno_id) >= 3
   limit 1;

  select array_agg(x.aluno_id) into v_alunos from (
    select distinct v.aluno_id
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
     where v.professor_id = v_prof
     order by v.aluno_id
     limit 3) x;

  -- Um aluno de OUTRA unidade. Sem ele o passo do filtro não vale nada: com
  -- todo mundo na mesma unidade, uma função que ignora o filtro devolve
  -- exatamente a mesma lista e o teste passa igual (foi o que aconteceu — o
  -- mutante V7 sobreviveu na primeira rodada).
  select v.professor_id, v.unidade_id, v.aluno_id
    into v_prof2, v_uni2, v_aluno2
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where v.unidade_id is not null and v.unidade_id <> v_uni
     and not (v.aluno_id = any(v_alunos))
   limit 1;

  insert into _res values ('cenario montado',
    v_coord is not null and v_prof is not null and array_length(v_alunos,1) = 3
      and v_uni2 is not null and v_uni2 <> v_uni,
    format('coord=%s prof=%s alunos=%s uni2=%s', v_coord, v_prof, v_alunos, v_uni2));

  -- ── As três respostas do mês ──────────────────────────────────────────────
  -- vermelho calado · verde COM recado · verde calado (o que não deve aparecer)
  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, observacao, respondido_em)
  values
    (v_alunos[1], v_prof, v_uni, v_comp, 'vermelho', 'nao', 'parado', 'desanimado', null, now()),
    (v_alunos[2], v_prof, v_uni, v_comp, 'verde', 'sim', 'evoluindo', 'animado',
     'MARCADOR_077 precisa de partitura nova', now()),
    (v_alunos[3], v_prof, v_uni, v_comp, 'verde', 'sim', 'evoluindo', 'animado', null, now()),
    -- O vermelho da outra unidade — a isca do filtro.
    (v_aluno2, v_prof2, v_uni2, v_comp, 'vermelho', 'nao', 'parado', 'desanimado', null, now());

  -- ── Quem não é coordenação não lê ─────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_coordenacao_feedback_mes();
    insert into _res values ('quem nao e coordenacao nao le', false, 'a funcao respondeu');
  exception when others then
    v_erro := sqlerrm;
    insert into _res values ('quem nao e coordenacao nao le',
      v_erro = 'apenas_admin', v_erro);
  end;

  -- ── Daqui pra baixo, a coordenação perguntando ────────────────────────────
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_r := public.app_coordenacao_feedback_mes();
  v_lista := v_r -> 'alunos';

  -- 1. A OBSERVAÇÃO CHEGA. Antes da 077 nenhum consumidor lia esta coluna.
  insert into _res values ('a observacao do professor sai no payload',
    exists (select 1 from jsonb_array_elements(v_lista) e
             where (e ->> 'aluno_id')::int = v_alunos[2]
               and e ->> 'observacao' = 'MARCADOR_077 precisa de partitura nova'),
    v_lista::text);

  -- 2. Vermelho entra mesmo sem uma palavra escrita.
  insert into _res values ('vermelho calado entra na lista',
    exists (select 1 from jsonb_array_elements(v_lista) e
             where (e ->> 'aluno_id')::int = v_alunos[1]),
    format('procurando aluno %s', v_alunos[1]));

  -- 3. Verde calado FICA DE FORA — é o que separa "lista de trabalho" de
  --    "despejo da carteira inteira".
  insert into _res values ('verde sem recado nao entra',
    not exists (select 1 from jsonb_array_elements(v_lista) e
                 where (e ->> 'aluno_id')::int = v_alunos[3]),
    format('procurando aluno %s', v_alunos[3]));

  -- 4. Ordem: quem está vermelho é lido antes de quem só mandou recado.
  insert into _res values ('vermelho vem antes do verde com recado',
    (select min(o) from (select ordinality o, e from jsonb_array_elements(v_lista)
                          with ordinality t(e, ordinality)) z
      where (z.e ->> 'aluno_id')::int = v_alunos[1])
    <
    (select min(o) from (select ordinality o, e from jsonb_array_elements(v_lista)
                          with ordinality t(e, ordinality)) z
      where (z.e ->> 'aluno_id')::int = v_alunos[2]),
    'ordem da lista');

  -- 5. O resumo conta o que a lista mostra.
  insert into _res values ('resumo conta vermelho e recado',
    (v_r #>> '{resumo,vermelho}')::int >= 1
      and (v_r #>> '{resumo,com_recado}')::int >= 1
      and (v_r #>> '{resumo,verde}')::int >= 2,
    v_r -> 'resumo' ->> 'vermelho');

  -- 6. ALUNO, NÃO LINHA. A carteira tem uma linha por matrícula e a renovação
  --    duplica: contar linha faria a coordenação ver mais alunos do que o
  --    professor vê na mesa dele. Este passo só é válido se a base REALMENTE
  --    tem duplicata — por isso ele mede as duas contagens antes de comparar.
  select count(*), count(distinct v.aluno_id) into v_linhas, v_unicos
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null;

  insert into _res values ('a base tem linha duplicada (senao o passo 7 nao vale)',
    v_linhas > v_unicos, format('%s linhas, %s alunos', v_linhas, v_unicos));

  insert into _res values ('resumo conta aluno e nao linha da carteira',
    (v_r #>> '{resumo,alunos}')::int = v_unicos,
    format('resumo=%s unicos=%s linhas=%s', v_r #>> '{resumo,alunos}', v_unicos, v_linhas));

  -- 7. Corte que se anuncia. Lista truncada em silêncio lê como "é só isso".
  v_r := public.app_coordenacao_feedback_mes(null, null, 1);
  insert into _res values ('corte se anuncia (truncado + total real)',
    (v_r ->> 'truncado')::boolean
      and (v_r ->> 'precisam_de_olho')::int >= 2
      and jsonb_array_length(v_r -> 'alunos') = 1,
    format('truncado=%s precisam=%s itens=%s', v_r ->> 'truncado',
           v_r ->> 'precisam_de_olho', jsonb_array_length(v_r -> 'alunos')));

  -- 8. O filtro de unidade recorta a lista — provado com uma isca que SÓ
  --    aparece se o filtro for ignorado.
  insert into _res values ('sem filtro, a isca da outra unidade aparece',
    exists (select 1 from jsonb_array_elements(v_lista) e
             where (e ->> 'aluno_id')::int = v_aluno2),
    format('isca aluno %s da unidade %s', v_aluno2, v_uni2));

  v_r := public.app_coordenacao_feedback_mes(null, v_uni);
  insert into _res values ('filtro de unidade nao devolve outra unidade',
    not exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
                 where (e ->> 'unidade_id')::uuid is distinct from v_uni)
    and not exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
                     where (e ->> 'aluno_id')::int = v_aluno2),
    format('unidade %s', v_uni));

  -- 9. As opções do filtro ignoram o próprio filtro (senão vira beco sem saída:
  --    escolheu uma unidade, some a lista das outras, não dá pra voltar).
  insert into _res values ('opcoes de unidade sobrevivem ao filtro',
    jsonb_array_length(v_r #> '{filtros,unidades}') >= 2,
    (v_r #> '{filtros,unidades}')::text);
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object('caso', caso, 'detalhe', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
