-- O aviso ao comercial volta a caber no índice.
--
-- DEFEITO VIVO, medido contra a PRODUÇÃO em 13/08/2026 -- não contra o texto
-- do repo (essa distinção já me fez errar uma vez esta semana). O `EXPLAIN`
-- abaixo, rodado no banco de verdade, falha com `42P10`:
--
--   insert into fabio_notificacoes (...) values (...)
--   on conflict (referencia_tipo, referencia_id, canal)
--     where referencia_tipo is not null and referencia_id is not null
--   do nothing;
--   -- ERROR: 42P10 there is no unique or exclusion constraint matching the
--   --        ON CONFLICT specification
--
-- POR QUÊ. O índice ganhou uma terceira condição em algum momento:
--
--   uq_fabio_notif_por_referencia
--     ON (referencia_tipo, referencia_id, canal)
--     WHERE referencia_tipo IS NOT NULL
--       AND referencia_id   IS NOT NULL
--       AND tipo <> 'registro_recibo'      <-- esta
--
-- O `registro_recibo` ganhou índice próprio (`professor_id, tipo,
-- referencia_tipo, referencia_id, canal`) e foi excluído do índice geral. Para
-- o Postgres inferir um índice PARCIAL, o predicado do `ON CONFLICT` precisa
-- IMPLICAR o predicado do índice. Duas condições não implicam três: quem só
-- diz "ref_tipo e ref_id não são nulos" não garante `tipo <> 'registro_recibo'`.
-- A inferência falha no PLANEJAMENTO -- antes de olhar uma linha sequer.
--
-- QUEM FICOU PARA TRÁS. `fabio_claim_notificacao_por_referencia` **já foi
-- corrigida** (é por isso que a devolutiva funciona: 39 entregues, a última
-- hoje 20:20). Ficaram duas, as duas do caminho da experimental:
--   * `fabio_claim_aviso_comercial`
--   * `fabio_claim_aviso_falta_experimental`
-- É a MESMA falha do incidente de 12/08 (`delivered_unclosed`), consertada num
-- lugar e não nos outros.
--
-- O QUE ISSO CUSTA HOJE: nada, e é justamente esse o problema. A fila está
-- vazia (`na_fila: 0`, medido com `--dry-run` no worker da VPS), então o
-- defeito nunca disparou. Ele espera a próxima aula experimental registrada
-- para o comercial simplesmente não ficar sabendo -- sem erro na tela de
-- ninguém, porque quem morre é o worker, num timer de 3 minutos.
--
-- POR QUE UM PATCH DE TEXTO E NÃO O CORPO INTEIRO AQUI. As duas funções têm
-- ~150 linhas cada, e o miolo delas é o bloco family-safe da devolutiva --
-- formatação com `E'...'`, escapes, emoji e a HIERARQUIA que mantém a leitura
-- de conversão embaixo da régua, para não vazar num Ctrl+C do consultor.
-- Transcrever isso duas vezes à mão para mudar UMA cláusula é o jeito mais
-- provável de quebrar exatamente o que não pode quebrar. Então a migration
-- lê a definição viva, troca só a cláusula, e ABORTA se o alvo não for o que
-- ela espera.
--
-- A troca é segura porque foi MEDIDA antes: em cada função a âncora aparece
-- exatamente 2 vezes, e há exatamente 2 `on conflict` -- ou seja, a âncora só
-- existe dentro de cláusula de conflito, nunca num `where` comum. Se essa
-- proporção mudar, o bloco levanta exceção em vez de adivinhar.

do $$
declare
  v_nome  text;
  v_def   text;
  v_de    constant text := 'where referencia_tipo is not null and referencia_id is not null';
  v_para  constant text := 'where referencia_tipo is not null and referencia_id is not null and tipo <> ''registro_recibo''';
  v_ancoras int;
  v_conflitos int;
begin
  foreach v_nome in array array['fabio_claim_aviso_comercial',
                                'fabio_claim_aviso_falta_experimental'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nome;

    if v_def is null then
      raise exception 'funcao ausente: %', v_nome;
    end if;

    -- Idempotente: replayar não deve empilhar a condição duas vezes.
    if position('tipo <> ''registro_recibo''' in v_def) > 0 then
      raise notice 'ja corrigida, nada a fazer: %', v_nome;
      continue;
    end if;

    v_ancoras   := (length(v_def) - length(replace(v_def, v_de, ''))) / length(v_de);
    v_conflitos := (select count(*) from regexp_matches(
                      v_def, 'on conflict \(referencia_tipo, referencia_id, canal\)', 'g'));

    if v_ancoras = 0 or v_ancoras <> v_conflitos then
      raise exception
        'nao vou adivinhar em %: % ancora(s) para % clausula(s) on conflict',
        v_nome, v_ancoras, v_conflitos;
    end if;

    execute replace(v_def, v_de, v_para);
    raise notice 'corrigida %: % clausula(s)', v_nome, v_ancoras;
  end loop;
end $$;
