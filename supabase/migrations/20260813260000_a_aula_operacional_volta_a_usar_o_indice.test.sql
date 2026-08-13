-- Equivalência primeiro, velocidade depois.
--
-- Otimização que muda resposta não é otimização. O passo 1 reconstrói a função
-- ANTIGA em pg_temp e compara as duas em lote real -- inclusive nas linhas com
-- campo nulo, que são justamente as que o caminho rápido NÃO atende.

create temporary table _op_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_op(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _op_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

-- A função ANTIGA, byte por byte como estava em produção antes deste arquivo.
create or replace function pg_temp.fn_operacional_antiga(p_aula_id integer)
returns integer language sql stable as $$
  select candidata.id
    from public.aulas_emusys base
    join lateral (
      select atual.id
        from public.aulas_emusys atual
        left join lateral (
          select count(*)::integer as n_alunos
            from public.aula_alunos_emusys roster
           where roster.aula_emusys_id = atual.id
        ) quantidade on true
       where atual.unidade_id is not distinct from base.unidade_id
         and atual.professor_id is not distinct from base.professor_id
         and atual.data_hora_inicio = base.data_hora_inicio
         and atual.data_hora_fim is not distinct from base.data_hora_fim
         and atual.curso_nome is not distinct from base.curso_nome
         and coalesce(atual.cancelada, false) = false
       order by coalesce(quantidade.n_alunos, 0) desc,
                case when atual.tipo = 'turma' then 0 else 1 end,
                atual.id desc
       limit 1
    ) candidata on true
   where base.id = p_aula_id
$$;

do $$
declare
  v_div      integer;
  v_total    integer;
  v_com_nulo integer;
  v_plano    jsonb;
  v_buffers  bigint;
begin
  -- 1) EQUIVALENCIA no lote quente (o que a view alcanca).
  with amostra as (
    select ae.id from public.aulas_emusys ae
     where ae.data_aula >= current_date - 45
     order by ae.id desc limit 3000
  )
  select count(*) filter (where public.fn_aula_operacional_id(a.id)
                            is distinct from pg_temp.fn_operacional_antiga(a.id)),
         count(*)
    into v_div, v_total
    from amostra a;
  perform pg_temp.checar_op(
    'equivalencia no lote quente: zero divergencia',
    v_div = 0 and v_total > 500,
    format('%s divergencia(s) em %s aulas', v_div, v_total));

  -- 2) EQUIVALENCIA onde o caminho rapido NAO se aplica -- as linhas com campo
  --    nulo sao o unico lugar onde a troca poderia mudar resposta.
  --
  --    A amostra e ESTRATIFICADA, um lote por coluna. Um `limit 1000` sobre o
  --    OR pegaria so o nulo abundante: medido em 13/08, ha 9.089 aulas sem
  --    professor e apenas **17** sem curso. As 17 sumiriam da amostra, e um
  --    passo que nunca alcanca o caso que deveria vigiar e decoracao -- foi
  --    exatamente assim que um mutante sobreviveu aqui na primeira rodada.
  with orfas as (
    (select ae.id from public.aulas_emusys ae where ae.unidade_id     is null order by ae.id desc limit 300)
    union
    (select ae.id from public.aulas_emusys ae where ae.professor_id   is null order by ae.id desc limit 300)
    union
    (select ae.id from public.aulas_emusys ae where ae.data_hora_fim  is null order by ae.id desc limit 300)
    union
    (select ae.id from public.aulas_emusys ae where ae.curso_nome     is null order by ae.id desc limit 300)
  )
  select count(*) filter (where public.fn_aula_operacional_id(o.id)
                            is distinct from pg_temp.fn_operacional_antiga(o.id)),
         count(*)
    into v_div, v_com_nulo
    from orfas o;
  perform pg_temp.checar_op(
    'equivalencia nas linhas com campo nulo (caminho null-safe)',
    v_div = 0,
    format('%s divergencia(s) em %s aulas orfas', v_div, v_com_nulo));

  -- 2b) A guarda do CURSO precisa de fixture, porque o dado de hoje nao a
  --     alcanca: medido em 13/08, as 17 aulas sem curso estao TODAS tambem sem
  --     professor, entao a guarda do professor decide antes e a do curso nunca
  --     e exercitada. Sem este bloco, mexer nela nao quebra teste nenhum --
  --     cobertura fantasma. As linhas nascem e morrem dentro da transacao.
  insert into public.aulas_emusys
    (id, emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
     data_hora_fim, curso_nome, tipo, cancelada)
  select -100001, -100001, m.unidade_id, m.professor_id, m.data_aula,
         m.data_hora_inicio, m.data_hora_fim, null, m.tipo, false
    from public.aulas_emusys m
   where m.professor_id is not null and m.curso_nome is not null
     and m.data_hora_fim is not null and m.unidade_id is not null
   order by m.id desc limit 1;

  insert into public.aulas_emusys
    (id, emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
     data_hora_fim, curso_nome, tipo, cancelada)
  select -100002, -100002, a.unidade_id, a.professor_id, a.data_aula,
         a.data_hora_inicio, a.data_hora_fim, null, 'turma', false
    from public.aulas_emusys a where a.id = -100001;

  perform pg_temp.checar_op(
    'com curso nulo e professor PREENCHIDO, as duas funcoes concordam',
    public.fn_aula_operacional_id(-100001)
      is not distinct from pg_temp.fn_operacional_antiga(-100001)
    and public.fn_aula_operacional_id(-100001) is not null,
    format('nova=%s antiga=%s',
           coalesce(public.fn_aula_operacional_id(-100001)::text,'NULL'),
           coalesce(pg_temp.fn_operacional_antiga(-100001)::text,'NULL')));

  -- 3) Aula inexistente devolve NULL, nao explode.
  perform pg_temp.checar_op(
    'id inexistente devolve NULL',
    public.fn_aula_operacional_id(-1) is null,
    coalesce(public.fn_aula_operacional_id(-1)::text, 'NULL'));

  -- 4) O ORCAMENTO. Antes: 3.999.329 buffers e 12,3s. O teto de 1.000.000 e
  --    folgado de proposito -- ele nao mede microsegundo, mede se o indice
  --    voltou a ser alcancavel. Se um dia estourar de novo, e sinal, nao ruido.
  execute 'explain (analyze, buffers, format json) select count(*) from public.vw_presenca_pendencia'
     into v_plano;
  v_buffers := (v_plano #>> '{0,Plan,Shared Hit Blocks}')::bigint
             + coalesce((v_plano #>> '{0,Plan,Shared Read Blocks}')::bigint, 0);
  perform pg_temp.checar_op(
    'a vw_presenca_pendencia cabe em 1 milhao de buffers',
    v_buffers < 1000000,
    format('%s buffers (antes: 3.999.329)', v_buffers));

  -- 5) O caminho rapido tem que estar escrito com `=`, senao o item 4 passou
  --    por acaso (cache quente, tabela pequena naquele instante).
  perform pg_temp.checar_op(
    'o caminho rapido usa igualdade indexavel, nao null-safe',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_aula_operacional_id')
      like '%candidata.unidade_id      = v_base.unidade_id%',
    'sem `=` nao ha indice');

  -- 6) E o caminho null-safe NAO pode ter sido jogado fora junto.
  perform pg_temp.checar_op(
    'o caminho null-safe continua existindo para as linhas orfas',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_aula_operacional_id')
      ilike '%is not distinct from v_base.unidade_id%',
    'trocar tudo por = mudaria resposta, nao so velocidade');
end $$;

select json_build_object(
  'teste', '20260813260000-a-aula-operacional-volta-a-usar-o-indice',
  'falhas', (select count(*) from _op_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _op_res where not ok), '[]'::json)
) as resumo;
