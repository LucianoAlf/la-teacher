-- 086 — o gêmeo para de divergir na ESCRITA (não só na leitura)
--
-- Achado depois da 083, na mesma frente da professora Daiana. A 083 imunizou a
-- LEITURA (`vw_registro_pendencia` passou a resolver presença entre TODOS os
-- gêmeos do horário, afirmação vence silêncio). Mas quem escreve continuou
-- cego: `fn_registrar_presencas_core` sempre gravou SÓ na aula ÂNCORA (a de
-- turma, regra 'chamada_somente_na_aula_ancora'). O gêmeo INDIVIDUAL fica com o
-- que o Emusys mandou por último — e como cada aula real vira 2+ linhas desde
-- 09/07, isso significa: toda vez que um professor faz a chamada pelo app, a
-- tabela `aluno_presenca` nasce com DUAS respostas discordando para o mesmo
-- aluno na mesma aula.
--
-- Medido em produção antes de mexer: das 61 respostas fortes (professor/áudio)
-- que já existem, **59 têm um gêmeo com aula diferente da que recebeu a
-- escrita, e as 59 divergem ou não têm nada**. Não é exceção, é a regra —
-- e a Fatia 1 do Radar (`vw_aluno_sucesso_lista`, `vw_absenteismo_aluno`) lê
-- `aluno_presenca` direto, sem passar pela `vw_registro_pendencia` que a 083
-- blindou. Quem lê linha crua continua vendo falta fantasma. Ordem do Alf:
-- "isso aí vai multiplicar de acordo com os professores que estão entrando.
-- resolver na raiz, antes de partir pra SPEC."
--
-- ── O CONSERTO: um sincronizador, não uma cópia de código ───────────────────
-- Em vez de duplicar a lógica de resolução de gêmeo dentro de
-- `fn_registrar_presencas_core`, nasce `fn_sincronizar_gemeos_presenca(aula_id
-- default null)`: pra cada resposta FORTE (professor_la_teacher, fabio_audio,
-- manual, professor_whatsapp), acha o gêmeo (turma↔individual, mesma
-- unidade+horário+professor) e propaga a MESMA resposta pra ele — com a MESMA
-- trava que já protegia a âncora: só sobrescreve se o gêmeo estiver vazio ou
-- só tiver resposta fraca (emusys/sistema). Uma resposta humana forte no gêmeo
-- NUNCA é apagada pela sincronização.
--
-- Dois usos da MESMA função:
--   1. `fn_registrar_presencas_core` chama ela ESCOPADA (`p_aula_ancora_id =
--      v_aula.id`) ao final de toda chamada bem-sucedida — o defeito não
--      nasce mais.
--   2. Esta migration chama ela SEM escopo, uma vez, como BACKFILL — os 59
--      pares que já divergem são corrigidos no mesmo instante em que o app
--      entra no ar.
--
-- O parâmetro de escopo existe por custo: sem ele, toda chamada de um
-- professor varreria a tabela inteira da escola. Com ele, o trabalho de cada
-- chamada é proporcional ao roster daquela aula — o que importa cada vez mais
-- conforme mais professores entram, que foi exatamente o alerta do Alf.

create or replace function public.fn_sincronizar_gemeos_presenca(p_aula_ancora_id integer default null)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_sincronizados integer;
begin
  with fonte as (
    select ap.aluno_id, ap.professor_id, ap.status, ap.status_presenca,
           ap.respondido_por, ap.respondido_em,
           ae.tipo, ae.unidade_id, ae.data_hora_inicio
      from public.aluno_presenca ap
      join public.aulas_emusys ae on ae.id = ap.aula_emusys_id
     where ap.respondido_por in ('professor_la_teacher','fabio_audio','manual','professor_whatsapp')
       and (p_aula_ancora_id is null or ap.aula_emusys_id = p_aula_ancora_id)
  ),
  -- o gêmeo é o tipo OPOSTO ao da fonte: fonte em turma acha o individual do
  -- aluno, fonte em individual acha a turma — mesma unidade+horário+professor,
  -- espelhando a mesma regra usada em fn_aula_individual_do_aluno e na
  -- vw_registro_pendencia (083). NUNCA lança exceção: aluno sem gêmeo
  -- simplesmente não gera linha (LEFT-like via não casar no lateral abaixo).
  gemeo as (
    select f.*, g.id as gemeo_id, g.data_aula as gemeo_data_aula,
           g.data_hora_inicio as gemeo_inicio, g.curso_nome as gemeo_curso,
           g.turma_nome as gemeo_turma, g.sala_nome as gemeo_sala
      from fonte f
      join lateral (
        select i.id, i.data_aula, i.data_hora_inicio, i.curso_nome, i.turma_nome, i.sala_nome
          from public.aulas_emusys i
          join public.aula_alunos_emusys ri on ri.aula_emusys_id = i.id and ri.aluno_id = f.aluno_id
         where i.tipo = (case when f.tipo = 'turma' then 'individual' else 'turma' end)
           and i.unidade_id = f.unidade_id
           and i.data_hora_inicio = f.data_hora_inicio
           and not i.professor_id is distinct from f.professor_id
           and coalesce(i.cancelada, false) = false
         order by i.id
         limit 1
      ) g on true
  ),
  up as (
    insert into public.aluno_presenca
      (aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
       status, status_presenca, curso_nome, turma_nome, sala_nome, respondido_por, respondido_em)
    select distinct
           g.aluno_id, g.gemeo_id, g.professor_id, g.unidade_id, g.gemeo_data_aula,
           (g.gemeo_inicio at time zone 'America/Sao_Paulo')::time,
           g.status, g.status_presenca, g.gemeo_curso, g.gemeo_turma, g.gemeo_sala,
           g.respondido_por, g.respondido_em
      from gemeo g
      on conflict (aluno_id, aula_emusys_id) do update
        set status = excluded.status, status_presenca = excluded.status_presenca,
            respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em
        -- a MESMA trava da âncora: resposta humana forte no gêmeo nunca é apagada
        where aluno_presenca.respondido_por is null
           or aluno_presenca.respondido_por in ('emusys','sistema')
      returning 1
  )
  select count(*) into v_sincronizados from up;

  return coalesce(v_sincronizados, 0);
end
$function$;

comment on function public.fn_sincronizar_gemeos_presenca(integer) is
  'Propaga presença FORTE (professor/áudio/manual) pro gêmeo Emusys (turma↔'
  'individual do mesmo horário). Nunca sobrescreve resposta forte já existente '
  'no gêmeo. p_aula_ancora_id escopa o custo — null varre tudo (backfill).';

-- ── fn_registrar_presencas_core passa a chamar o sincronizador, escopado ────
create or replace function public.fn_registrar_presencas_core(p_aula_ancora_id integer, p_professor_id integer, p_alunos_ausentes integer[] default '{}'::integer[], p_respondido_por text default 'professor_la_teacher'::text, p_estrito boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_aula public.aulas_emusys%rowtype; v_roster_total integer; v_sem_vinculo integer; v_inseridos integer; v_promovidos integer;
  v_gemeos integer;
begin
  if p_respondido_por not in ('professor_la_teacher','fabio_audio') then raise exception 'respondido_por_invalido: %', p_respondido_por; end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then if p_estrito then raise exception 'aula_nao_encontrada'; end if; return jsonb_build_object('aula_id',p_aula_ancora_id,'aplicado',false,'motivo','aula_nao_encontrada'); end if;
  if coalesce(v_aula.cancelada,false) then if p_estrito then raise exception 'aula_cancelada'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aula_cancelada'); end if;
  if v_aula.professor_id is distinct from p_professor_id then if p_estrito then raise exception 'aula_nao_pertence_ao_professor' using errcode='42501'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','professor_divergente'); end if;
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then raise exception 'chamada_ainda_nao_disponivel'; end if;
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then raise exception 'janela_de_chamada_encerrada'; end if;
  end if;
  select count(*), count(*) filter (where aluno_id is null) into v_roster_total, v_sem_vinculo from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total = 0 then if p_estrito then raise exception 'roster_nao_sincronizado'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_nao_sincronizado'); end if;
  if v_sem_vinculo > 0 then if p_estrito then raise exception 'roster_incompleto'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_incompleto'); end if;
  if exists (select 1 from unnest(coalesce(p_alunos_ausentes,'{}'::integer[])) a(aluno_id) where not exists (select 1 from public.aula_alunos_emusys r where r.aula_emusys_id = v_aula.id and r.aluno_id = a.aluno_id)) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster'; else return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aluno_ausente_fora_do_roster'); end if;
  end if;
  with up as (
    insert into public.aluno_presenca (aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula, status, status_presenca, curso_nome, turma_nome, sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id, v_aula.data_aula, (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'falta' else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome, p_respondido_por, now()
    from public.aula_alunos_emusys r where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update set status = excluded.status, status_presenca = excluded.status_presenca, respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em
      where aluno_presenca.respondido_por is null or aluno_presenca.respondido_por in ('emusys','sistema')
    returning (xmax = 0) as inserido)
  select count(*) filter (where inserido), count(*) filter (where not inserido) into v_inseridos, v_promovidos from up;

  -- 086: o gêmeo (turma↔individual) recebe a MESMA resposta. Escopado nesta
  -- aula — não varre a escola inteira a cada chamada.
  v_gemeos := public.fn_sincronizar_gemeos_presenca(v_aula.id);

  return jsonb_build_object('aula_id', v_aula.id, 'total_roster', v_roster_total, 'inseridos', coalesce(v_inseridos,0), 'promovidos', coalesce(v_promovidos,0), 'ja_havia_forte', v_roster_total - coalesce(v_inseridos,0) - coalesce(v_promovidos,0), 'gemeos_sincronizados', coalesce(v_gemeos,0), 'aplicado', true);
end $function$;

-- ── BACKFILL, uma vez: os 59 pares que já divergem hoje ─────────────────────
select public.fn_sincronizar_gemeos_presenca();
