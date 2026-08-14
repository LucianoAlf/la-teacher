-- O relatório de presença do dia anterior, para o grupo de cada unidade.
--
-- O QUE O ALF PEDIU, em 13/08/2026: *"isso vai entrar para Sol e enfiar no
-- grupo. Bonitinho, organizado, as pendências do dia anterior. Ficou aluno sem
-- presença e sem falta. Essa lista vai para o WhatsApp do grupo de cada
-- unidade. E uma partezinha vai ser essa divergência entre professor e
-- secretaria. E aí eles vão ter que validar."*
--
-- E a decisão que veio junto, sobre a divergência: **ninguém ganha.** O
-- sistema não escolhe entre o professor e a secretaria -- ele mostra os dois
-- lados no grupo e a unidade corrige.
--
-- POR QUE ISTO PRECISAVA EXISTIR. Havia 97 conflitos abertos desde 12/08 e
-- **nada avisava ninguém** -- sem cron, sem notificação, sem alerta. Achei
-- porque fui procurar. Em 5 deles a falta que a pessoa marcou aparecia como
-- PRESENÇA no que a coordenação lê. O mecanismo de detecção funcionava; o
-- silêncio é que matava.
--
-- DUAS SEÇÕES, DUAS PERGUNTAS DIFERENTES:
--
--   1. SEM RESPOSTA -- o aluno não tem presença nem falta. Ninguém respondeu.
--      Isto NÃO acusa o aluno: acusa que a chamada não foi fechada. É o
--      "ausente do Emusys" que, por decisão do Alf, não vira falta -- vira
--      pendência e cobra a equipe.
--
--   2. DIVERGÊNCIA -- professor e secretaria responderam COISAS DIFERENTES
--      para o mesmo aluno na mesma aula. Aqui há resposta; o que falta é
--      acordo. A unidade decide.
--
-- O CANAL JÁ EXISTE e não estou inventando nada: `fila_relatorios_sol_hermes`
-- entrega para o grupo de WhatsApp de cada unidade e funcionou hoje
-- (`caixa_financeiro`, entregue às 23:30, 46 segundos entre enfileirar e
-- chegar). O formato das linhas aqui é cópia do que essa entrega usou:
-- `status='sol_pendente'`, `jid` do grupo, `metadata.rota='sol_hermes_native'`.
--
-- ESTA MIGRATION NÃO ENFILEIRA NADA E NÃO CRIA CRON. Ela publica as funções.
-- Disparo automático para três grupos de WhatsApp é coisa que se liga com o
-- Alf olhando o texto antes -- mandar errado para o grupo da unidade é o tipo
-- de erro que não tem desfazer.

-- ── 1. O DADO ───────────────────────────────────────────────────────────────
-- Uma linha por aluno que precisa de atenção, com o motivo.
create or replace function public.fn_presenca_pendencias_do_dia(
  p_unidade_id uuid,
  p_data date
)
returns table (
  motivo text,
  professor_nome text,
  curso_nome text,
  turma_nome text,
  hora text,
  aluno_nome text,
  detalhe text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with pares as (
    -- O grão é (aluno, professor, horário) -- NUNCA a linha crua. O
    -- `aula_emusys_id` é id de EVENTO: o mesmo horário existe em mais de uma
    -- linha, e contar linha dobra tudo.
    select distinct ae.professor_id, ae.data_hora_inicio, r.aluno_id,
           ae.curso_nome, ae.turma_nome
      from public.aulas_emusys ae
      join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id
     where ae.unidade_id = p_unidade_id
       and ae.data_aula = p_data
       and ae.data_hora_fim < now()
       and not coalesce(ae.cancelada, false)
       and ae.professor_id is not null
       and r.aluno_id is not null
       and ae.id = public.fn_aula_operacional_id(ae.id)
  ),
  -- SEM RESPOSTA: ninguém fechou a chamada deste aluno neste horário.
  sem_resposta as (
    select 'sem_resposta'::text as motivo, p.*,
           null::text as detalhe
      from pares p
     where not exists (
       select 1 from public.aluno_presenca ap
       join public.aulas_emusys g on g.id = ap.aula_emusys_id
        where ap.aluno_id = p.aluno_id
          and g.professor_id = p.professor_id
          and g.data_hora_inicio = p.data_hora_inicio
          and public.fn_presenca_fecha_chamada(ap.status_presenca, ap.respondido_por))
  ),
  -- DIVERGENCIA: duas fontes HUMANAS responderam diferente. Emusys nao entra
  -- aqui de proposito -- ele marca a aula, nao o aluno, e "discordar" dele em
  -- turma seria ruido, nao divergencia (medido: em 161 turmas ele nunca
  -- diferenciou um aluno do outro).
  divergencia as (
    select 'divergencia'::text as motivo, p.*,
           (select string_agg(distinct ap.respondido_por || ': ' || ap.status_presenca, '  x  ')
              from public.aluno_presenca ap
              join public.aulas_emusys g on g.id = ap.aula_emusys_id
             where ap.aluno_id = p.aluno_id
               and g.professor_id = p.professor_id
               and g.data_hora_inicio = p.data_hora_inicio
               and public.fn_presenca_e_forte(ap.respondido_por)) as detalhe
      from pares p
     where (select count(distinct ap.status_presenca)
              from public.aluno_presenca ap
              join public.aulas_emusys g on g.id = ap.aula_emusys_id
             where ap.aluno_id = p.aluno_id
               and g.professor_id = p.professor_id
               and g.data_hora_inicio = p.data_hora_inicio
               and public.fn_presenca_e_forte(ap.respondido_por)) > 1
  ),
  tudo as (
    select * from sem_resposta union all select * from divergencia
  )
  select t.motivo,
         coalesce(pr.nome, '(sem professor)')::text,
         coalesce(t.curso_nome, t.turma_nome, 'Aula')::text,
         t.turma_nome::text,
         to_char(t.data_hora_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
         al.nome::text,
         t.detalhe
    from tudo t
    join public.alunos al on al.id = t.aluno_id
    left join public.professores pr on pr.id = t.professor_id
   order by t.motivo, 2, 5, 6;
$function$;

comment on function public.fn_presenca_pendencias_do_dia(uuid, date) is
  'As duas listas do relatorio de presenca da unidade: SEM RESPOSTA (ninguem '
  'fechou a chamada) e DIVERGENCIA (duas fontes humanas discordam). Grao e '
  '(aluno, professor, horario) -- nunca a linha crua, porque aula_emusys_id e '
  'id de EVENTO e contar linha dobra.';

-- ── 2. O TEXTO ──────────────────────────────────────────────────────────────
-- Formato copiado do relatorio diario administrativo que ja vai pro grupo:
-- regua, emoji, secao. Se ficar diferente do resto, ninguem le.
create or replace function public.fn_texto_relatorio_presenca(
  p_unidade_id uuid,
  p_data date
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_unidade text;
  v_txt text;
  v_sem int;
  v_div int;
  v_linha record;
  v_prof text := '';
  v_dia text;
begin
  select nome into v_unidade from public.unidades where id = p_unidade_id;

  v_dia := to_char(p_data, 'DD') || '/' ||
    case extract(month from p_data)
      when 1 then 'janeiro' when 2 then 'fevereiro' when 3 then 'março'
      when 4 then 'abril'   when 5 then 'maio'      when 6 then 'junho'
      when 7 then 'julho'   when 8 then 'agosto'    when 9 then 'setembro'
      when 10 then 'outubro' when 11 then 'novembro' else 'dezembro'
    end || '/' || to_char(p_data, 'YYYY');

  select count(*) filter (where motivo='sem_resposta'),
         count(*) filter (where motivo='divergencia')
    into v_sem, v_div
    from public.fn_presenca_pendencias_do_dia(p_unidade_id, p_data);

  v_txt := '━━━━━━━━━━━━━━━━━━━━━━' || E'\n'
        || '📋 *PRESENÇA — PENDÊNCIAS*' || E'\n'
        || '🏢 *' || upper(coalesce(v_unidade,'?')) || '*' || E'\n'
        || '📆 ' || v_dia || E'\n'
        || '━━━━━━━━━━━━━━━━━━━━━━' || E'\n';

  if v_sem = 0 and v_div = 0 then
    return v_txt || E'\n' || '✅ *Tudo fechado.* Nenhuma pendência de presença.' || E'\n';
  end if;

  -- SEM RESPOSTA
  if v_sem > 0 then
    v_txt := v_txt || E'\n' || '⚠️ *SEM PRESENÇA E SEM FALTA* (' || v_sem || ')' || E'\n'
          || '_ninguém fechou a chamada — não é falta do aluno_' || E'\n'
          || '━━━━━━━━━━━━━━━━━━━━━━' || E'\n';
    v_prof := '';
    for v_linha in
      select * from public.fn_presenca_pendencias_do_dia(p_unidade_id, p_data)
       where motivo = 'sem_resposta'
    loop
      if v_linha.professor_nome is distinct from v_prof then
        v_prof := v_linha.professor_nome;
        v_txt := v_txt || E'\n' || '👤 *' || v_prof || '*' || E'\n';
      end if;
      v_txt := v_txt || '• ' || v_linha.hora || ' — ' || v_linha.aluno_nome
            || ' _(' || v_linha.curso_nome || ')_' || E'\n';
    end loop;
  end if;

  -- DIVERGENCIA
  if v_div > 0 then
    -- O titulo NAO promete "professor x secretaria". A primeira versao
    -- prometia, e o primeiro texto real desmentiu: veio
    -- `agenda_secretaria: falta x agenda_secretaria: presente` -- a MESMA
    -- origem respondendo diferente nas duas linhas da aula (o `aula_emusys_id`
    -- e id de EVENTO). Titulo que promete mais do que o dado sustenta faz a
    -- equipe procurar briga onde nao tem.
    v_txt := v_txt || E'\n' || '🔀 *RESPOSTAS QUE NÃO BATEM* (' || v_div || ')' || E'\n'
          || '_o mesmo aluno na mesma aula com duas respostas — validem qual vale_' || E'\n'
          || '━━━━━━━━━━━━━━━━━━━━━━' || E'\n';
    v_prof := '';
    for v_linha in
      select * from public.fn_presenca_pendencias_do_dia(p_unidade_id, p_data)
       where motivo = 'divergencia'
    loop
      if v_linha.professor_nome is distinct from v_prof then
        v_prof := v_linha.professor_nome;
        v_txt := v_txt || E'\n' || '👤 *' || v_prof || '*' || E'\n';
      end if;
      v_txt := v_txt || '• ' || v_linha.hora || ' — ' || v_linha.aluno_nome || E'\n'
            || '   ↳ ' || coalesce(v_linha.detalhe, '?') || E'\n';
    end loop;
  end if;

  v_txt := v_txt || E'\n' || '━━━━━━━━━━━━━━━━━━━━━━' || E'\n'
        || '_Corrijam no app ou na agenda. O que ficar sem resposta continua '
        || 'aparecendo amanhã._' || E'\n';

  return v_txt;
end;
$function$;

comment on function public.fn_texto_relatorio_presenca(uuid, date) is
  'Monta o texto do relatorio de presenca no MESMO formato do relatorio '
  'diario administrativo que ja vai pro grupo. Quando nao ha pendencia, diz '
  'isso explicitamente -- relatorio que some quando esta tudo certo ensina '
  'a equipe a nao procurar por ele.';

-- ── 3. A ENTREGA ────────────────────────────────────────────────────────────
create or replace function public.fn_enfileirar_relatorio_presenca(
  p_data date default (current_date - 1),
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_u record;
  v_txt text;
  v_out jsonb := '[]'::jsonb;
  v_id bigint;
begin
  for v_u in
    -- O grupo de cada unidade sai do proprio historico de entregas: e o mesmo
    -- destino que ja recebeu relatorio diario, com JID conferido em campo.
    -- Tabela de config paralela envelheceria longe de quem usa.
    select distinct on (f.unidade_id)
           f.unidade_id, f.unidade_nome, f.grupo_nome, f.jid
      from public.fila_relatorios_sol_hermes f
     where f.grupo_nome ilike 'RELAT%DI%RIOS%'
       and f.status = 'enviada' and f.jid is not null
     order by f.unidade_id, f.enviada_em desc
  loop
    v_txt := public.fn_texto_relatorio_presenca(v_u.unidade_id, p_data);

    if p_dry_run then
      v_out := v_out || jsonb_build_object(
        'unidade', v_u.unidade_nome, 'grupo', v_u.grupo_nome,
        'jid', v_u.jid, 'texto', v_txt);
      continue;
    end if;

    -- Idempotencia: uma entrega por unidade por dia. Sem isto, rodar duas
    -- vezes mandaria a mesma lista duas vezes pro grupo -- e no WhatsApp isso
    -- nao tem desfazer.
    if exists (select 1 from public.fila_relatorios_sol_hermes
                where tipo_relatorio = 'presenca_pendencias'
                  and unidade_id = v_u.unidade_id
                  and data_dia = p_data
                  and status <> 'erro') then
      v_out := v_out || jsonb_build_object(
        'unidade', v_u.unidade_nome, 'pulado', 'ja enfileirado para este dia');
      continue;
    end if;

    insert into public.fila_relatorios_sol_hermes
      (tipo_relatorio, origem, unidade_id, unidade_nome, jid, grupo_nome,
       texto, status, agendada_para, data_dia, tentativas, metadata)
    values
      ('presenca_pendencias', 'auto_cron', v_u.unidade_id, v_u.unidade_nome,
       v_u.jid, v_u.grupo_nome, v_txt, 'sol_pendente', now(), p_data, 0,
       jsonb_build_object('rota','sol_hermes_native','fonte','fn_enfileirar_relatorio_presenca'))
    returning id into v_id;

    v_out := v_out || jsonb_build_object(
      'unidade', v_u.unidade_nome, 'grupo', v_u.grupo_nome, 'fila_id', v_id);
  end loop;

  return jsonb_build_object('ok', true, 'data', p_data,
                            'dry_run', p_dry_run, 'unidades', v_out);
end;
$function$;

comment on function public.fn_enfileirar_relatorio_presenca(date, boolean) is
  'Enfileira o relatorio de presenca para o grupo de cada unidade. '
  'p_dry_run=true (DEFAULT) apenas devolve o texto sem escrever na fila -- o '
  'default e o seguro de proposito, porque mandar errado pro grupo da unidade '
  'nao tem desfazer. Idempotente por (unidade, dia).';

revoke all on function public.fn_enfileirar_relatorio_presenca(date, boolean)
  from public, anon, authenticated;
grant execute on function public.fn_enfileirar_relatorio_presenca(date, boolean)
  to service_role;
grant execute on function public.fn_presenca_pendencias_do_dia(uuid, date)
  to service_role, authenticated;
grant execute on function public.fn_texto_relatorio_presenca(uuid, date)
  to service_role, authenticated;
