-- A régua nova tem que dar EXATAMENTE o que a produção já dá hoje.
--
-- O passo que vale é o 1: comparar a função com o predicado inline que está
-- no ar, linha a linha, na tabela inteira. Régua canônica que muda resposta
-- não é unificação -- é uma terceira régua.

create temporary table _veredito_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_v(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _veredito_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare
  v_div bigint;
  v_tot bigint;
  v_plano text;
  v_linha text;
begin
  -- 1) EQUIVALENCIA com o predicado VIVO, na tabela inteira.
  --    O predicado abaixo e copia do que a producao executa hoje (conferido
  --    no EXPLAIN da vw_presenca_pendencia em 13/08/2026).
  select count(*), count(*) filter (where
           public.fn_presenca_e_resposta(ap.respondido_por, ap.status_presenca, ap.status)
           is distinct from
           coalesce(
             (coalesce(ap.status_presenca,
                       case ap.status when 'presente' then 'presente'
                                      when 'ausente'  then 'falta' else null end)
              = any (array['presente','falta','falta_justificada']))
             and (coalesce(ap.respondido_por::text = any (array[
                    'professor_la_teacher','fabio_audio','manual',
                    'professor_whatsapp','agenda_secretaria']), false)
                  or (ap.respondido_por::text = 'emusys'
                      and coalesce(ap.status_presenca,
                            case ap.status when 'presente' then 'presente'
                                           when 'ausente'  then 'falta' else null end)
                          = 'presente')),
             false))
    into v_tot, v_div
    from public.aluno_presenca ap;

  perform pg_temp.checar_v(
    'a funcao reproduz o predicado VIVO na tabela inteira',
    v_div = 0 and v_tot > 10000,
    format('%s divergencia(s) em %s linhas', v_div, v_tot));

  -- 2) A DECISAO DO ALF, caso a caso.
  perform pg_temp.checar_v('equipe marcando presenca CONTA',
    public.fn_presenca_e_resposta('agenda_secretaria','presente','presente'), 'agenda_secretaria');
  perform pg_temp.checar_v('equipe marcando FALTA conta (falta afirmada e resposta)',
    public.fn_presenca_e_resposta('agenda_secretaria','falta','ausente'), 'agenda_secretaria falta');
  perform pg_temp.checar_v('professor no app CONTA',
    public.fn_presenca_e_resposta('professor_la_teacher','presente','presente'), 'professor_la_teacher');
  perform pg_temp.checar_v('audio do Fabio CONTA',
    public.fn_presenca_e_resposta('fabio_audio','falta','ausente'), 'fabio_audio');
  perform pg_temp.checar_v('EMUSYS PRESENTE conta (decisao do Alf, 13/08)',
    public.fn_presenca_e_resposta('emusys','presente','presente'), 'emusys presente');
  perform pg_temp.checar_v('EMUSYS AUSENTE nao vale nada -- vira pendencia',
    not public.fn_presenca_e_resposta('emusys', null, 'ausente'), 'emusys ausente');
  perform pg_temp.checar_v('EMUSYS falta explicita tambem nao vale',
    not public.fn_presenca_e_resposta('emusys','falta','ausente'), 'emusys falta');
  perform pg_temp.checar_v('sem resposta nenhuma nao vira falta',
    not public.fn_presenca_e_resposta(null, null, null), 'null');
  perform pg_temp.checar_v('fonte desconhecida nao conta',
    not public.fn_presenca_e_resposta('sistema','presente','presente'), 'sistema');

  -- 3) O FALLBACK da coluna antiga. 10 linhas de agosto dependem disso.
  perform pg_temp.checar_v(
    'status antigo sozinho ainda e lido (status_presenca nulo)',
    public.fn_presenca_e_resposta('emusys', null, 'presente')
      and public.fn_presenca_status_efetivo(null,'ausente') = 'falta',
    'coalesce com a coluna `status`');

  -- 4) AS DUAS REGUAS CONTINUAM SEPARADAS. Se alguem fundir, o Emusys vira
  --    fonte forte e a equipe perde o direito de corrigir a sincronizacao.
  perform pg_temp.checar_v(
    'Emusys CONTA como resposta mas NAO e forte (segue sobrescrivel)',
    public.fn_presenca_e_resposta('emusys','presente','presente')
      and not public.fn_presenca_e_forte('emusys'),
    'as duas perguntas sao diferentes, de proposito');

  -- 5) CUSTO ZERO -- provado, nao prometido. Se a funcao deixar de ser
  --    inlinada (virar plpgsql, ou passar a ler tabela), o nome dela APARECE
  --    no plano e este passo cai. Hoje mesmo uma funcao que lia tabela dentro
  --    de um filtro custou 97,6% dos buffers da pendencia de presenca.
  --
  --    O plano vem linha a linha (`for ... in execute`), nao com `into`:
  --    `into` pegaria so a PRIMEIRA linha, e o `Filter` -- que e onde a
  --    funcao apareceria -- nunca e a primeira. Passo que olha a linha errada
  --    passa verde sem medir nada.
  v_plano := '';
  for v_linha in
    execute 'explain (costs off) select count(*) from public.aluno_presenca '
         || 'where public.fn_presenca_e_resposta(respondido_por, status_presenca, status)'
  loop
    v_plano := v_plano || coalesce(v_linha, '') || E'\n';
  end loop;

  perform pg_temp.checar_v(
    'a funcao e INLINADA pelo planejador (nao aparece no plano)',
    v_plano not ilike '%fn_presenca_e_resposta%'
      and v_plano ilike '%professor_la_teacher%',
    'se o nome aparecer, virou chamada de verdade e passa a custar por linha: '
      || left(v_plano, 400));
end $$;

select json_build_object(
  'teste', '20260813270000-a-regua-do-veredito-vira-funcao',
  'falhas', (select count(*) from _veredito_res where not coalesce(ok,false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _veredito_res where not coalesce(ok,false)), '[]'::json)
) as resumo;
