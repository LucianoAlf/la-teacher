-- 085 — a nota do Radar
--
-- Função PURA: recebe os sinais e a config, devolve nota + decomposição. Não
-- lê tabela. Assim o teste varia peso e sinal sem tocar em configuração nem em
-- dado real, e o mesmo cálculo serve à tela e a qualquer worker futuro.
--
-- TRÊS AMARRAS QUE IMPEDEM A NOTA DE VIRAR OPINIÃO COM CARA DE NÚMERO:
--
-- 1. A NOTA SEMPRE ABRE. Devolve `decomposicao` com quanto cada sinal
--    CONTRIBUIU — não só o peso. Peso é a regra; contribuição é o efeito, e é
--    o efeito que explica por que a nota é 38. O LA Report já calcula a
--    contribuição e não a mostra; o tooltip de lá diz "peso 10%", que responde
--    a pergunta errada.
--
-- 2. SINAL SEM DADO SAI DA CONTA E O PESO SE REDISTRIBUI. Nunca conta como
--    neutro nem como zero. O LA Report usa `ELSE 50 -- sem feedback = neutro`:
--    com o semáforo em 0% respondido, 20% da nota de TODO MUNDO vira a mesma
--    constante e a nota mexe menos que a realidade. Contar como zero seria
--    pior — é o mesmo defeito do "não-marcado = falta" que a presença já teve.
--
-- 3. PISO DE COBERTURA. Com menos de `minimo_sinais_para_nota` sinais, a nota
--    vem NULA. "NOTA 38 · apurada em 1 de 4" é perigoso porque quem lê fixa no
--    38 e ignora a legenda. Medido em 10/08: subindo em ~20/08 seria 1 sinal
--    vivo (absenteísmo com 3 aulas, abaixo do piso; semáforo só abre em 25/08);
--    em ~01/09 são 3. A nota acende no começo de setembro, e isso é esperado.
create or replace function public.fn_radar_nota(p_sinais jsonb, p_config jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_dec        jsonb := '[]'::jsonb;
  v_peso_vivo  numeric := 0;
  v_apurados   int := 0;
  v_nota       numeric;
  v_status     text;
  v_minimo     int := coalesce((p_config->>'minimo_sinais_para_nota')::int, 2);
  r            record;
begin
  -- Cada sinal vira (nome, score 0-100, peso, rótulo do valor). Score nulo =
  -- sinal ausente: entra na decomposição como SEM DADO e fica fora do peso.
  for r in
    select * from (values
      ('absenteismo',
       case when (p_sinais->>'absenteismo_pct') is not null
            then greatest(0, 100 - (p_sinais->>'absenteismo_pct')::numeric) end,
       coalesce((p_config->>'peso_absenteismo')::numeric, 0),
       case when (p_sinais->>'absenteismo_pct') is not null
            then format('%s%% (%s de %s)', p_sinais->>'absenteismo_pct',
                        coalesce((p_sinais->>'aulas_medidas')::int, 0)
                          - round(coalesce((p_sinais->>'aulas_medidas')::numeric,0)
                            * (1 - (p_sinais->>'absenteismo_pct')::numeric/100)),
                        p_sinais->>'aulas_medidas') end),
      ('feedback',
       case p_sinais->>'feedback'
            when 'verde' then 100 when 'amarelo' then 50 when 'vermelho' then 0 end,
       coalesce((p_config->>'peso_feedback')::numeric, 0),
       p_sinais->>'feedback'),
      ('pratica',
       case p_sinais->>'pratica_em_casa'
            when 'sim' then 100 when 'as_vezes' then 50 when 'nao' then 0 end,
       coalesce((p_config->>'peso_pratica')::numeric, 0),
       p_sinais->>'pratica_em_casa'),
      -- greatest() do Postgres IGNORA NULL (greatest(0,null) = 0, não null —
      -- medido ao vivo). Por isso a guarda também precisa checar faltas_mes,
      -- não só aulas_mes: sem o "is not null", faltas_mes ausente virava o
      -- PIOR score possível em vez de sair da conta — o mesmo "não-marcado =
      -- falta" que este arquivo existe pra evitar, entrando pela porta dos
      -- fundos de uma função que o SQL padrão trataria como NULL-propagante.
      ('faltas_mes',
       case when (p_sinais->>'faltas_mes') is not null
                 and coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then greatest(0, 100 - 100.0 * (p_sinais->>'faltas_mes')::numeric
                                        / (p_sinais->>'aulas_mes')::numeric) end,
       coalesce((p_config->>'peso_faltas_mes')::numeric, 0),
       case when (p_sinais->>'faltas_mes') is not null
                 and coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then format('%s de %s no mês', p_sinais->>'faltas_mes', p_sinais->>'aulas_mes') end)
    ) as t(sinal, score, peso, valor)
  loop
    if r.score is null then
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', null, 'score', null,
        'peso', r.peso, 'peso_efetivo', null, 'contribuiu', null, 'sem_dado', true);
    else
      v_apurados  := v_apurados + 1;
      v_peso_vivo := v_peso_vivo + r.peso;
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', r.valor, 'score', r.score,
        'peso', r.peso, 'sem_dado', false);
    end if;
  end loop;

  -- Redistribuição: o peso efetivo é a fatia do sinal DENTRO do que sobrou.
  -- A NOTA NASCE DA SOMA DAS CONTRIBUIÇÕES JÁ ARREDONDADAS — não é mais uma
  -- conta paralela. Duas contas independentes (nota = round(bruto/vivo) de um
  -- lado, contribuição = round(score*peso/vivo, 1) de outro) cruzam o ,5 em
  -- direções diferentes: medido em produção, absenteísmo 100% + feedback
  -- verde dava nota 38 pela fórmula separada enquanto a decomposição somava
  -- 38,5 (arredonda pra 39) — a explicação discordava do número que
  -- explicava. Agora as duas SEMPRE batem, porque são a mesma conta.
  if v_peso_vivo > 0 then
    v_dec := (
      select jsonb_agg(
        case when (d->>'sem_dado')::boolean then d
             else d || jsonb_build_object(
               'peso_efetivo', round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1),
               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric
                                     / v_peso_vivo, 1),
               'de',           round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1))
        end order by ord)
        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));

    select round(sum((d->>'contribuiu')::numeric)) into v_nota
      from jsonb_array_elements(v_dec) d
     where not (d->>'sem_dado')::boolean;
  end if;

  -- O piso: com pouca cobertura a nota se cala — e a decomposição não pode
  -- vazar os INGREDIENTES de um número que a tela não vai mostrar. Sem isto,
  -- uma linha de peso 15 aparecia com "contribuiu: 100, peso_efetivo: 100"
  -- (100% de uma régua que não existe) mesmo com a nota nula. score/valor/
  -- peso/sem_dado continuam intactos: a tela ainda precisa poder dizer
  -- "1 de 4 sinais apurados".
  if v_apurados < v_minimo then
    v_nota := null;
    v_dec := (
      select jsonb_agg(
               d || jsonb_build_object('contribuiu', null, 'peso_efetivo', null, 'de', null)
               order by ord)
        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));
  end if;

  v_status := case
    when v_nota is null then null
    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'
    when v_nota >= coalesce((p_config->>'faixa_saudavel')::numeric, 70) then 'saudavel'
    else 'atencao' end;

  return jsonb_build_object(
    'nota', v_nota,
    'status', v_status,
    'sinais_apurados', v_apurados,
    'sinais_totais', 4,
    'suficiente', v_apurados >= v_minimo,
    'decomposicao', v_dec);
end $$;

comment on function public.fn_radar_nota(jsonb, jsonb) is
  'Nota do Radar. PURA. Sinal sem dado sai da conta e o peso se redistribui '
  '(nunca neutro, nunca zero). Abaixo de minimo_sinais_para_nota a nota vem '
  'NULA — mas a decomposicao vem, pra tela explicar.';

revoke all on function public.fn_radar_nota(jsonb, jsonb) from public;
grant execute on function public.fn_radar_nota(jsonb, jsonb) to authenticated;
