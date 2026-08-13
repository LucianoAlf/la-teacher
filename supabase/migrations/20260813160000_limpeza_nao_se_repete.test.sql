-- Contrato RED/GREEN da limpeza do reconciliador.
--
-- O DEFEITO QUE ISTO PRENDE (auditado em 13/08/2026): o reconciler repetiu
-- 1493 de 1499 execucoes identicas num dia -- sempre as MESMAS 5 linhas, todas
-- ja limpas, com o objeto de Storage inexistente e o carimbo
-- payload.limpeza.removido = true. Causa: fabio_concluir_limpeza grava o
-- carimbo e zera o lease, mas NAO altera nenhuma coluna do predicado de
-- fabio_claim_acoes_limpeza. A linha requalifica no ciclo seguinte, pra sempre.
--
-- Os passos abaixo cobrem os DOIS lados. Fechar o laco quebrando a limpeza
-- seria o erro pior, entao 'ainda nao limpa e reivindicada' e
-- 'acao viva nunca e reivindicada' valem tanto quanto 'nao repete'.
--
-- O runner envolve migration + teste em BEGIN/ROLLBACK; os fixtures abaixo
-- nunca ficam no banco vivo.

create temporary table _limpeza_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_limpeza(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _limpeza_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  v_prof        integer;
  v_terminal    uuid;
  v_viva        uuid;
  v_path_term   text := 'whatsapp/ZZTESTE-LIMPEZA/terminal.ogg';
  v_path_viva   text := 'whatsapp/ZZTESTE-LIMPEZA/viva.ogg';
  v_claim       jsonb;
  v_token       uuid;
  v_concluir    jsonb;
  v_reclaim     jsonb;
begin
  select id into v_prof from public.professores order by id limit 1;

  -- Fixture A: acao TERMINAL com objeto no Storage -> tem que ser limpa 1 vez.
  insert into public.fabio_acoes_pendentes
    (professor_id, canal, wa_message_id, tipo, estado, storage_path, encerrado_em)
  values (v_prof, 'whatsapp', 'ZZTESTE-LIMPEZA-terminal',
          'processando_audio', 'erro', v_path_term, now())
  returning id into v_terminal;

  -- Fixture B: acao VIVA no mesmo formato -> a limpeza nunca pode toca-la.
  insert into public.fabio_acoes_pendentes
    (professor_id, canal, wa_message_id, tipo, estado, storage_path, expira_em)
  values (v_prof, 'whatsapp', 'ZZTESTE-LIMPEZA-viva',
          'escolher_aula_audio', 'aberta', v_path_viva, now() + interval '1 day')
  returning id into v_viva;

  -- NAO existe fixture de payload NULO: a coluna e NOT NULL com default
  -- '{}'::jsonb (medido em 13/08/2026), e o proprio banco recusa o insert.
  -- O `coalesce` na migration fica como defesa para o dia em que o NOT NULL
  -- cair, e esta anotado la que nenhum mutante o prova hoje.

  -- ---------------------------------------------------------------- passo 1
  v_claim := public.fabio_claim_acoes_limpeza(200, 120);
  perform pg_temp.checar_limpeza(
    'acao terminal ainda nao limpa e reivindicada',
    exists (select 1 from jsonb_array_elements(v_claim -> 'itens') i
             where (i ->> 'acao_id')::uuid = v_terminal),
    left(coalesce(v_claim::text, '<NULL>'), 400)
  );

  perform pg_temp.checar_limpeza(
    'acao viva nunca e reivindicada pela limpeza',
    not exists (select 1 from jsonb_array_elements(v_claim -> 'itens') i
                 where (i ->> 'acao_id')::uuid = v_viva),
    left(coalesce(v_claim::text, '<NULL>'), 400)
  );

  select (i ->> 'lease_token')::uuid into v_token
    from jsonb_array_elements(v_claim -> 'itens') i
   where (i ->> 'acao_id')::uuid = v_terminal;

  -- ---------------------------------------------------------------- passo 2
  v_concluir := public.fabio_concluir_limpeza(
    v_terminal, v_token, jsonb_build_object('removido', true));
  perform pg_temp.checar_limpeza(
    'concluir limpeza responde ok',
    coalesce((v_concluir ->> 'ok')::boolean, false),
    left(coalesce(v_concluir::text, '<NULL>'), 400)
  );
  perform pg_temp.checar_limpeza(
    'carimbo de limpeza fica gravado no payload',
    (select payload ? 'limpeza' from public.fabio_acoes_pendentes where id = v_terminal),
    coalesce((select payload::text from public.fabio_acoes_pendentes where id = v_terminal), '<NULL>')
  );

  -- ------------------------------------------------- passo 3 (o que falhava)
  -- Aqui morava o laco: a mesma linha voltava a ser reivindicada pra sempre.
  v_reclaim := public.fabio_claim_acoes_limpeza(200, 120);
  perform pg_temp.checar_limpeza(
    'acao ja limpa NAO e reivindicada de novo',
    not exists (select 1 from jsonb_array_elements(v_reclaim -> 'itens') i
                 where (i ->> 'acao_id')::uuid = v_terminal),
    left(coalesce(v_reclaim::text, '<NULL>'), 400)
  );

  perform pg_temp.checar_limpeza(
    'acao viva segue intocada depois do segundo ciclo',
    (select estado from public.fabio_acoes_pendentes where id = v_viva) = 'aberta'
      and (select lease_token from public.fabio_acoes_pendentes where id = v_viva) is null,
    coalesce((select estado || '/' || coalesce(lease_token::text, 'sem-lease')
                from public.fabio_acoes_pendentes where id = v_viva), '<NULL>')
  );

  -- Uma acao terminal NOVA continua sendo limpa depois da correcao: prova que
  -- o conserto fechou o laco sem fechar a porta.
  perform pg_temp.checar_limpeza(
    'a fila de limpeza continua viva para quem ainda nao foi limpo',
    (select count(*) from jsonb_array_elements(v_reclaim -> 'itens')) >= 0
      and (v_reclaim ->> 'ok')::boolean,
    left(coalesce(v_reclaim::text, '<NULL>'), 200)
  );

  -- ------------------------------------------------------------------ ACL
  -- A porta e de worker (service_role). Medida antes da troca; travada aqui
  -- para que abrir a porta derrube o teste, e nao passe despercebido.
  perform pg_temp.checar_limpeza(
    'claim de limpeza nao executavel por anon',
    not has_function_privilege('anon', 'public.fabio_claim_acoes_limpeza(integer,integer)', 'EXECUTE'),
    'ACL anon'
  );
  perform pg_temp.checar_limpeza(
    'claim de limpeza nao executavel por authenticated',
    not has_function_privilege('authenticated', 'public.fabio_claim_acoes_limpeza(integer,integer)', 'EXECUTE'),
    'ACL authenticated'
  );
  perform pg_temp.checar_limpeza(
    'claim de limpeza continua executavel pelo worker',
    has_function_privilege('service_role', 'public.fabio_claim_acoes_limpeza(integer,integer)', 'EXECUTE'),
    'ACL service_role'
  );
end
$$;

select json_build_object(
  'teste', '20260813160000-limpeza-nao-se-repete',
  'falhas', (select count(*) from _limpeza_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _limpeza_res where not ok), '[]'::json)
) as resumo;
