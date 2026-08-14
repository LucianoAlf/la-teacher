-- Liga o relatório de presença: 9h da manhã, no grupo de cada unidade.
--
-- Decisão do Alf em 13/08/2026, depois de ver a prévia: **9h**, cron criado,
-- valendo a partir de amanhã. A equipe corrige no começo do dia.
--
-- TRÊS AJUSTES ANTES DE LIGAR, e os três vieram de olhar o texto real:
--
-- 1. NOME DE FONTE EM PORTUGUÊS. A prévia saiu com `agenda_secretaria` e
--    `professor_la_teacher` crus. Isso é nome de coluna, não é linguagem de
--    grupo de WhatsApp -- quem lê às 9h da manhã não deveria precisar traduzir
--    o banco de dados na cabeça.
--
-- 2. DIA SEM AULA NÃO GERA RELATÓRIO. Sem esta guarda, todo domingo o cron
--    mandaria "✅ Tudo fechado" para três grupos falando de um dia em que a
--    escola nem abriu. Relatório que chega quando não há o que dizer ensina a
--    equipe a ignorar o relatório -- e aí ele não serve mais nem quando
--    importa. Repare na diferença: **teve aula e está tudo fechado** É
--    informação boa e continua sendo enviada; **não teve aula** não é.
--
-- 3. HORÁRIO EM UTC. `pg_cron` roda em UTC neste banco -- conferido no job
--    `relatorio-diario-20h`, que é `0 23` para sair às 20h BRT. Então 9h BRT
--    é `0 12`. Escrever `0 9` teria mandado o relatório às 6h da manhã.

-- ── Nome de fonte que gente lê ──────────────────────────────────────────────
create or replace function public.fn_presenca_fonte_legivel(p_respondido_por text)
returns text
language sql
immutable
parallel safe
as $function$
  select case p_respondido_por
    when 'agenda_secretaria'     then 'Secretaria'
    when 'professor_la_teacher'  then 'Professor (app)'
    when 'professor_whatsapp'    then 'Professor (WhatsApp)'
    when 'fabio_audio'           then 'Professor (áudio)'
    when 'manual'                then 'Ajuste manual'
    when 'emusys'                then 'Emusys'
    when 'sistema'               then 'Sistema'
    else coalesce(p_respondido_por, '?')
  end
$function$;

comment on function public.fn_presenca_fonte_legivel(text) is
  'Traduz o nome tecnico da fonte de presenca para o nome que a equipe usa. '
  'Existe porque a primeira previa do relatorio saiu com `agenda_secretaria` '
  'cru no grupo de WhatsApp.';

-- ── O detalhe da divergência passa a usar o nome legível ────────────────────
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
  sem_resposta as (
    select 'sem_resposta'::text as motivo, p.*, null::text as detalhe
      from pares p
     where not exists (
       select 1 from public.aluno_presenca ap
       join public.aulas_emusys g on g.id = ap.aula_emusys_id
        where ap.aluno_id = p.aluno_id
          and g.professor_id = p.professor_id
          and g.data_hora_inicio = p.data_hora_inicio
          and public.fn_presenca_fecha_chamada(ap.status_presenca, ap.respondido_por))
  ),
  divergencia as (
    select 'divergencia'::text as motivo, p.*,
           (select string_agg(distinct public.fn_presenca_fonte_legivel(ap.respondido_por)
                              || ' diz ' || ap.status_presenca, '   x   ')
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
  tudo as (select * from sem_resposta union all select * from divergencia)
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

-- ── Dia sem aula não vira relatório ─────────────────────────────────────────
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
  v_teve_aula boolean;
begin
  for v_u in
    select distinct on (f.unidade_id)
           f.unidade_id, f.unidade_nome, f.grupo_nome, f.jid
      from public.fila_relatorios_sol_hermes f
     where f.grupo_nome ilike 'RELAT%DI%RIOS%'
       and f.status = 'enviada' and f.jid is not null
     order by f.unidade_id, f.enviada_em desc
  loop
    -- TEVE AULA? Se a unidade nao abriu, nao ha relatorio a dar. "Tudo
    -- fechado" num domingo e ruido, e ruido ensina a ignorar o canal.
    select exists (
      select 1 from public.aulas_emusys ae
       where ae.unidade_id = v_u.unidade_id
         and ae.data_aula = p_data
         and ae.data_hora_fim < now()
         and not coalesce(ae.cancelada, false)
         and ae.professor_id is not null
    ) into v_teve_aula;

    if not v_teve_aula then
      v_out := v_out || jsonb_build_object(
        'unidade', v_u.unidade_nome, 'pulado', 'nenhuma aula neste dia');
      continue;
    end if;

    v_txt := public.fn_texto_relatorio_presenca(v_u.unidade_id, p_data);

    if p_dry_run then
      v_out := v_out || jsonb_build_object(
        'unidade', v_u.unidade_nome, 'grupo', v_u.grupo_nome,
        'jid', v_u.jid, 'texto', v_txt);
      continue;
    end if;

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

revoke all on function public.fn_enfileirar_relatorio_presenca(date, boolean)
  from public, anon, authenticated;
grant execute on function public.fn_enfileirar_relatorio_presenca(date, boolean)
  to service_role;
grant execute on function public.fn_presenca_fonte_legivel(text)
  to service_role, authenticated, anon;
