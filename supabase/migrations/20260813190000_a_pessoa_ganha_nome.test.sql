-- Contrato da identidade da pessoa.
--
-- Os passos abaixo cobram exatamente o que a auditoria de 13/08/2026 mediu, e
-- cada numero aqui foi conferido contra a producao E contra a API do Emusys
-- antes de virar assercao.

create temporary table _pessoa_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_pessoa(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _pessoa_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  v_chave_265  text;
  v_chave_1465 text;
  v_contagem   jsonb;
  v_pessoas    bigint;
  v_so_id      bigint;
  v_sem_id     bigint;
  v_fundidos   bigint;
begin
  -- 1) O caso que motivou tudo: a Luiza e UMA pessoa.
  select pessoa_chave into v_chave_265  from public.vw_aluno_pessoa where aluno_id = 265;
  select pessoa_chave into v_chave_1465 from public.vw_aluno_pessoa where aluno_id = 1465;
  perform pg_temp.checar_pessoa(
    'os dois cadastros da Luiza (265 e 1465) sao a MESMA pessoa',
    v_chave_265 is not null and v_chave_265 = v_chave_1465,
    format('265=%s | 1465=%s', coalesce(v_chave_265,'<NULL>'), coalesce(v_chave_1465,'<NULL>'))
  );

  -- 2) A fronteira que o id sozinho NAO respeita: mesmo numero, unidades
  --    diferentes, pessoas diferentes (Pietro @ BARRA x Julia @ RECREIO).
  select count(distinct pessoa_chave)
    into v_pessoas
    from public.vw_aluno_pessoa
   where emusys_student_id = '1001' and arquivado_em is null;
  perform pg_temp.checar_pessoa(
    'o mesmo emusys_student_id em unidades diferentes NAO vira a mesma pessoa',
    v_pessoas >= 2,
    format('pessoas distintas para o id 1001: %s', v_pessoas)
  );

  -- 3) A saida conservadora: quem nao tem id do Emusys nao se funde com
  --    ninguem. Sem isto, `(unidade, null)` juntaria criancas sem relacao.
  select count(*) filter (where pessoa_sem_identidade_emusys),
         count(distinct pessoa_chave) filter (where pessoa_sem_identidade_emusys)
    into v_sem_id, v_fundidos
    from public.vw_aluno_pessoa where arquivado_em is null;
  perform pg_temp.checar_pessoa(
    'aluno sem identidade no Emusys continua sendo pessoa propria',
    v_sem_id = v_fundidos,
    format('cadastros sem id=%s, pessoas geradas=%s (tem que ser igual)', v_sem_id, v_fundidos)
  );

  -- 4) A chave e MAIS FINA que o id sozinho -- e essa diferenca sao pessoas
  --    reais que seriam fundidas.
  select count(distinct pessoa_chave), count(distinct emusys_student_id)
    into v_pessoas, v_so_id
    from public.vw_aluno_pessoa
   where arquivado_em is null and emusys_student_id is not null;
  perform pg_temp.checar_pessoa(
    'a chave por unidade separa gente que o id sozinho fundiria',
    v_pessoas > v_so_id,
    format('pelo par=%s, so pelo id=%s (o par tem que ser MAIOR)', v_pessoas, v_so_id)
  );

  -- 5) A contagem da carteira responde por PESSOA, e bate com o que o Alf
  --    decidiu contar na carteira do professor 25.
  v_contagem := public.app_professor_carteira_contagem(25);
  perform pg_temp.checar_pessoa(
    'carteira do professor 25 conta 20 pessoas',
    (v_contagem ->> 'pessoas')::int = 20,
    coalesce(v_contagem::text, '<NULL>')
  );
  perform pg_temp.checar_pessoa(
    'a contagem devolve pessoas MENOR que linhas (multi-curso aparece)',
    (v_contagem ->> 'pessoas')::int < (v_contagem ->> 'linhas')::int
      and (v_contagem ->> 'matriculas')::int <= (v_contagem ->> 'linhas')::int,
    coalesce(v_contagem::text, '<NULL>')
  );

  -- 6) ACL: porta de worker.
  perform pg_temp.checar_pessoa(
    'contagem da carteira nao e alcancavel pelo cliente',
    not has_function_privilege('anon', 'public.app_professor_carteira_contagem(integer)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.app_professor_carteira_contagem(integer)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.app_professor_carteira_contagem(integer)', 'EXECUTE'),
    'anon/authenticated fora, service_role dentro'
  );
  perform pg_temp.checar_pessoa(
    'a view de pessoa nao e legivel pelo cliente',
    not has_table_privilege('anon', 'public.vw_aluno_pessoa', 'SELECT')
      and not has_table_privilege('authenticated', 'public.vw_aluno_pessoa', 'SELECT'),
    'anon/authenticated fora'
  );
end
$$;

select json_build_object(
  'teste', '20260813190000-a-pessoa-ganha-nome',
  'falhas', (select count(*) from _pessoa_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _pessoa_res where not ok), '[]'::json)
) as resumo;
