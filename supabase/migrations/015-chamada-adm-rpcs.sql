-- 015-chamada-adm-rpcs.sql  (P3 — chamada da secretaria no LA Report)
-- ⚠️⚠️ DRAFT — NÃO APLICADA EM PRODUÇÃO. Gates, nesta ordem:
--   (1) review do Alfredo (SQL);  (2) shape-ack do Codex (consumidor);  (3) OK explícito do Alf.
-- Contrato/decisões: docs/superpowers/specs/2026-07-22-p3-chamada-adm-contrato-design.md
--
-- Fonte nova: 'adm_la_report' (secretaria fez chamada de verdade = evidência humana).
-- Entra na matriz única fn_presenca_e_forte → efeitos automáticos e desejados:
-- sai da fila da Sol/Fábio, acende o selo do professor, semântica v1.3 classifica confirmada.
-- Precedência 009 intocada: promove só sobre fraca (null/emusys/sistema); NUNCA sobre humana.
-- Pós-aplicação, do lado Codex: branch 'adm_la_report' no CASE de proveniencia da
-- vw_aluno_presenca_semantica_v1 (hoje cai em 'desconhecida'; o resultado já sai certo pela matriz).

-- =====================================================================================
-- PARTE 0  Superset da CHECK + colunas de auditoria (aditivas, sem impacto no existente)
-- =====================================================================================
alter table public.aluno_presenca drop constraint if exists aluno_presenca_respondido_por_check;
alter table public.aluno_presenca add constraint aluno_presenca_respondido_por_check
  check (
    respondido_por is null
    or respondido_por in (
      'professor_whatsapp','professor_la_teacher','manual','sistema','emusys','fabio_audio','adm_la_report'
    )
  );

alter table public.aluno_presenca add column if not exists marcado_por text;
comment on column public.aluno_presenca.marcado_por is
  'Autoria humana granular (ex.: e-mail da ADM) quando respondido_por=adm_la_report. Null nas demais fontes.';

alter table public.aluno_presenca_administrativo add column if not exists motivo text;
alter table public.aluno_presenca_administrativo add column if not exists marcado_por text;

-- =====================================================================================
-- PARTE 1  Matriz única ganha a fonte da secretaria (v2)
-- =====================================================================================
create or replace function public.fn_presenca_e_forte(p_respondido_por text)
returns boolean
language sql immutable parallel safe
as $$
  select coalesce(
    p_respondido_por in (
      'professor_la_teacher','fabio_audio','manual','professor_whatsapp','adm_la_report'
    ),
    false
  )
$$;

comment on function public.fn_presenca_e_forte(text) is
  'Matriz canonica de fontes humanas fortes para escrita, selo operacional e leitura semantica de presenca. v2: + adm_la_report (chamada da secretaria no LA Report).';

-- =====================================================================================
-- PARTE 2  adm_registrar_chamada — escrita em lote da ADM (promoção, nunca sobre humana)
-- Sem janela 15min/24h do professor: ADM concilia retroativo até 45d (aula encerrada).
-- Parcial permitido: só os alunos enviados em p_itens são tocados.
-- =====================================================================================
create or replace function public.adm_registrar_chamada(
  p_aula_emusys_id integer,
  p_itens          jsonb,
  p_marcado_por    text
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_aula       public.aulas_emusys%rowtype;
  v_turma_irma integer;
  v_mantidos   jsonb;
  v_inseridos  integer;
  v_promovidos integer;
begin
  if p_marcado_por is null or length(btrim(p_marcado_por)) < 3 then
    raise exception 'marcado_por_obrigatorio';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'itens_vazios';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_itens) as i(aluno_id int, status text)
    where i.aluno_id is null or i.status not in ('presente','falta')
  ) then
    raise exception 'item_invalido (esperado {aluno_id, status: presente|falta})';
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found then raise exception 'aula_nao_encontrada'; end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if v_aula.data_hora_fim is null or v_aula.data_hora_fim > now() then
    raise exception 'aula_nao_encerrada';
  end if;
  if v_aula.data_aula < current_date - 45 then
    raise exception 'fora_da_janela_operacional (45 dias)';
  end if;

  -- âncora do slot (mesma regra da 009/013): individual com turma-irmã não recebe chamada
  if coalesce(v_aula.tipo, '') <> 'turma' then
    select t.id into v_turma_irma
    from public.aulas_emusys t
    where t.tipo = 'turma'
      and t.unidade_id       = v_aula.unidade_id
      and t.data_hora_inicio = v_aula.data_hora_inicio
      and t.professor_id is not distinct from v_aula.professor_id
      and coalesce(t.cancelada, false) = false
    limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma;
    end if;
  end if;

  -- itens ⊆ roster conciliado
  if exists (
    select 1 from jsonb_to_recordset(p_itens) as i(aluno_id int, status text)
    where not exists (
      select 1 from public.aula_alunos_emusys r
      where r.aula_emusys_id = v_aula.id and r.aluno_id = i.aluno_id)
  ) then
    raise exception 'aluno_fora_do_roster';
  end if;

  -- quem já tinha fonte humana ANTES: a promoção não toca (retrato pro retorno/UI)
  select coalesce(jsonb_agg(jsonb_build_object('aluno_id', ap.aluno_id, 'fonte', ap.respondido_por)), '[]'::jsonb)
    into v_mantidos
  from public.aluno_presenca ap
  join jsonb_to_recordset(p_itens) as i(aluno_id int, status text) on i.aluno_id = ap.aluno_id
  where ap.aula_emusys_id = v_aula.id
    and public.fn_presenca_e_forte(ap.respondido_por);

  with up as (
    insert into public.aluno_presenca (
      aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
      status, status_presenca, curso_nome, turma_nome, sala_nome,
      respondido_por, respondido_em, marcado_por)
    select i.aluno_id, v_aula.id, v_aula.professor_id, v_aula.unidade_id, v_aula.data_aula,
      (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case i.status when 'falta' then 'ausente' else 'presente' end,
      case i.status when 'falta' then 'falta'   else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome,
      'adm_la_report', now(), btrim(p_marcado_por)
    from jsonb_to_recordset(p_itens) as i(aluno_id int, status text)
    on conflict (aluno_id, aula_emusys_id) do update
      set status          = excluded.status,
          status_presenca = excluded.status_presenca,
          respondido_por  = excluded.respondido_por,
          respondido_em   = excluded.respondido_em,
          marcado_por     = excluded.marcado_por
      where aluno_presenca.respondido_por is null
         or aluno_presenca.respondido_por in ('emusys','sistema')
    returning (xmax = 0) as inserido)
  select count(*) filter (where inserido), count(*) filter (where not inserido)
    into v_inseridos, v_promovidos
  from up;

  return jsonb_build_object(
    'aula_id',                 v_aula.id,
    'itens',                   jsonb_array_length(p_itens),
    'inseridos',               coalesce(v_inseridos, 0),
    'promovidos_sobre_emusys', coalesce(v_promovidos, 0),
    'mantidos_fonte_forte',    v_mantidos);
end
$function$;

-- =====================================================================================
-- PARTE 3  adm_chamada_do_dia — leitura da grade + estado SEMÂNTICO por aluno.
-- Uma interpretação só: estado vem da vw_aluno_presenca_semantica_v1; 'nao_marcado' =
-- aluno do roster SEM linha (o gap que não se armazena). editavel=false quando já há
-- fonte humana (a UI trava; a RPC de escrita protege de novo — defesa dupla).
-- =====================================================================================
create or replace function public.adm_chamada_do_dia(p_unidade_id uuid, p_data date)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  with aulas as (
    select ae.*
    from public.aulas_emusys ae
    where ae.unidade_id = p_unidade_id
      and ae.data_aula  = p_data
      and coalesce(ae.cancelada, false) = false
      and (ae.tipo = 'turma' or not exists (
            select 1 from public.aulas_emusys t
            where t.tipo = 'turma'
              and t.unidade_id       = ae.unidade_id
              and t.data_hora_inicio = ae.data_hora_inicio
              and t.professor_id is not distinct from ae.professor_id
              and coalesce(t.cancelada, false) = false))
  ),
  linhas as (
    select a.id as aula_id, a.data_hora_inicio,
           to_char(a.data_hora_inicio at time zone 'America/Sao_Paulo', 'HH24:MI') as hora,
           a.curso_nome, a.turma_nome, a.sala_nome, a.professor_id, p.nome as professor_nome,
           r.aluno_id, al.nome as aluno_nome,
           s.resultado_pedagogico, s.proveniencia, s.respondido_por, s.respondido_em,
           ap.marcado_por
    from aulas a
    join public.aula_alunos_emusys r on r.aula_emusys_id = a.id and r.aluno_id is not null
    join public.alunos al           on al.id = r.aluno_id
    left join public.professores p  on p.id = a.professor_id
    left join public.vw_aluno_presenca_semantica_v1 s
           on s.aula_emusys_id = a.id and s.aluno_id = r.aluno_id
    left join public.aluno_presenca ap
           on ap.aula_emusys_id = a.id and ap.aluno_id = r.aluno_id
  ),
  por_aula as (
    select aula_id,
           min(data_hora_inicio) as dhi,
           min(hora)            as hora,
           min(curso_nome)      as curso_nome,
           min(turma_nome)      as turma_nome,
           min(sala_nome)       as sala_nome,
           min(professor_id)    as professor_id,
           min(professor_nome)  as professor_nome,
           bool_and(public.fn_presenca_e_forte(respondido_por)) as chamada_completa,
           jsonb_agg(jsonb_build_object(
             'aluno_id',      aluno_id,
             'nome',          aluno_nome,
             'estado',        coalesce(resultado_pedagogico, 'nao_marcado'),
             'proveniencia',  proveniencia,
             'marcado_por',   marcado_por,
             'respondido_em', respondido_em,
             'editavel',      (respondido_por is null or not public.fn_presenca_e_forte(respondido_por))
           ) order by aluno_nome) as alunos
    from linhas
    group by aula_id
  )
  select jsonb_build_object(
    'unidade_id', p_unidade_id,
    'data',       p_data,
    'cobertura',  jsonb_build_object(
       'aulas',                (select count(*) from por_aula),
       'com_chamada_completa', (select count(*) from por_aula where chamada_completa)),
    'aulas', coalesce((
       select jsonb_agg(jsonb_build_object(
         'aula_id', aula_id, 'hora', hora, 'curso_nome', curso_nome, 'turma_nome', turma_nome,
         'sala_nome', sala_nome, 'professor_id', professor_id, 'professor_nome', professor_nome,
         'chamada_completa', chamada_completa, 'alunos', alunos
       ) order by dhi)
       from por_aula), '[]'::jsonb))
$function$;

-- =====================================================================================
-- PARTE 4  adm_justificar_falta — justificativa administrativa com motivo e autoria
-- =====================================================================================
create or replace function public.adm_justificar_falta(
  p_aula_emusys_id integer,
  p_aluno_id       integer,
  p_motivo         text,
  p_marcado_por    text
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_aula public.aulas_emusys%rowtype;
begin
  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    raise exception 'motivo_obrigatorio';
  end if;
  if p_marcado_por is null or length(btrim(p_marcado_por)) < 3 then
    raise exception 'marcado_por_obrigatorio';
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found then raise exception 'aula_nao_encontrada'; end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if not exists (
    select 1 from public.aula_alunos_emusys r
    where r.aula_emusys_id = v_aula.id and r.aluno_id = p_aluno_id
  ) then
    raise exception 'aluno_fora_do_roster';
  end if;

  insert into public.aluno_presenca_administrativo (
    aluno_id, aula_emusys_id, unidade_id, justificada, fonte, motivo, marcado_por)
  values (p_aluno_id, v_aula.id, v_aula.unidade_id, true, 'adm_la_report',
          btrim(p_motivo), btrim(p_marcado_por))
  on conflict (aluno_id, aula_emusys_id) do update
    set justificada = true,
        fonte       = 'adm_la_report',
        motivo      = excluded.motivo,
        marcado_por = excluded.marcado_por,
        updated_at  = now();

  return jsonb_build_object(
    'aula_id', v_aula.id, 'aluno_id', p_aluno_id, 'justificada', true);
end
$function$;

-- =====================================================================================
-- PARTE 5  Segurança: as 3 RPCs são do backend do LA Report — só service_role.
-- =====================================================================================
revoke all on function public.adm_registrar_chamada(integer, jsonb, text) from public, anon, authenticated;
revoke all on function public.adm_chamada_do_dia(uuid, date)              from public, anon, authenticated;
revoke all on function public.adm_justificar_falta(integer, integer, text, text) from public, anon, authenticated;
grant execute on function public.adm_registrar_chamada(integer, jsonb, text)      to service_role;
grant execute on function public.adm_chamada_do_dia(uuid, date)                   to service_role;
grant execute on function public.adm_justificar_falta(integer, integer, text, text) to service_role;
