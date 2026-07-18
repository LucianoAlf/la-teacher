-- 013-vw-presenca-pendencia.sql  (Fase 3 — governança de presença)
-- FONTE ÚNICA operacional: "alunos sem presença FORTE, por aula/unidade/dia".
-- Roster-gap-aware (pega até quem ficou SEM linha nenhuma) + source-aware (fn_presenca_e_forte, da Fase 2).
-- Todos bebem daqui: Fábio (filtro por professor), Sol/Hugo (agrega por unidade), coordenação (dias_em_atraso>=3).
--
-- NÃO compete com o canon analítico (frequencia_canonica / semantica_v1 = % e classificação de linha, do
-- LA Report). Esta é a FILA operacional pra governança/cobrança.
--
-- Regra de ouro respeitada: só aula ENCERRADA (não a latência da aula em curso); roster conciliado
-- (aluno_id not null); janela operacional de 45 dias (além disso é buraco assentado, não nag diário).
-- Âncora por slot (turma, ou individual sem turma-irmã) pra não contar a mesma presença 2x.

create or replace view public.vw_presenca_pendencia as
select
  ae.unidade_id,
  u.nome                                    as unidade_nome,
  ae.professor_id,
  p.nome                                    as professor_nome,
  ae.id                                     as aula_id,        -- âncora (turma ou individual standalone)
  ae.tipo,
  ae.data_aula,
  ae.data_hora_inicio,
  ae.data_hora_fim,
  to_char(ae.data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI') as hora,
  ae.curso_nome,
  ae.turma_nome,
  r.aluno_id,
  al.nome                                   as aluno_nome,
  split_part(btrim(al.nome), ' ', 1)        as aluno_primeiro_nome,
  coalesce(adm.justificada, false)          as justificada,
  floor(extract(epoch from now() - ae.data_hora_fim) / 86400)::int as dias_em_atraso
from public.aulas_emusys ae
join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id and r.aluno_id is not null
join public.alunos al on al.id = r.aluno_id
join public.unidades u  on u.id = ae.unidade_id
left join public.professores p on p.id = ae.professor_id
left join public.aluno_presenca_administrativo adm
  on adm.aula_emusys_id = ae.id and adm.aluno_id = r.aluno_id
where coalesce(ae.cancelada, false) = false
  and ae.professor_id is not null
  and ae.data_hora_fim < now()                                   -- só aula encerrada
  and ae.data_aula >= current_date - 45                          -- janela operacional
  and (ae.tipo = 'turma' or not exists (                         -- âncora do slot (sem contar 2x)
        select 1 from public.aulas_emusys t
        where t.tipo = 'turma'
          and t.unidade_id = ae.unidade_id
          and t.data_hora_inicio = ae.data_hora_inicio
          and t.professor_id is not distinct from ae.professor_id
          and coalesce(t.cancelada, false) = false))
  and not exists (                                               -- SEM presença FORTE pra esse aluno nessa aula
        select 1 from public.aluno_presenca ap
        where ap.aula_emusys_id = ae.id
          and ap.aluno_id = r.aluno_id
          and public.fn_presenca_e_forte(ap.respondido_por));

comment on view public.vw_presenca_pendencia is
  'Governanca operacional (Fase 3): alunos sem presenca FORTE por aula/unidade/dia (fn_presenca_e_forte), roster-gap-aware, janela 45d. Fonte unica p/ Fabio (professor), Sol/Hugo (unidade), coordenacao (dias>=3). Nao e o canon analitico.';

-- Backend/governança apenas (crons/edge via service_role). Nunca anon/authenticated (expõe presença cross-unidade).
revoke all on public.vw_presenca_pendencia from anon, authenticated;
