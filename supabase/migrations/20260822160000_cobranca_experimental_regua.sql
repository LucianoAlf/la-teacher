-- Cobrança da devolutiva da aula experimental — régua de dados.
-- Spec: docs/superpowers/specs/2026-08-22-cobranca-devolutiva-experimental-design.md
--
-- POR QUE ESTA VIEW EXISTE SEPARADA. vw_registro_pendencia faz
-- `JOIN alunos al ON al.id = r.aluno_id`, e no roster de uma experimental o
-- lead entra com aluno_id NULO — o INNER JOIN derruba a aula inteira. Em 30
-- dias, 146 das 169 experimentais sem conteúdo eram invisíveis à cobrança.
-- Estender aquela view faria a régua de aluno carregar condicional que não é
-- dela; esta trilha tem gatilho próprio (status do lead), janela própria (3
-- dias, não 7) e destinatário próprio.

create or replace function public.fn_data_corte_experimental()
returns date language sql immutable parallel safe
as $$ select date '2026-08-22' $$;

comment on function public.fn_data_corte_experimental() is
  'Data em que a cobranca da experimental passou a valer. Sem ela, o dia 1 despejaria 27 escalonamentos de backlog na coordenacao.';

create or replace function public.fn_janela_experimental_dias()
returns integer language sql immutable
as $$ select 3 $$;

comment on function public.fn_janela_experimental_dias() is
  'Dias ate a experimental sem devolutiva escalar para a coordenacao. Separada de fn_janela_registro_dias() (7 dias, do aluno) de proposito.';

create or replace view public.vw_experimental_pendencia as
select
  v.id                                   as vinculo_id,
  le.id                                  as lead_id,
  le.nome_aluno,
  a.id                                   as aula_id,
  a.professor_id,
  u.nome                                 as professor_nome,
  a.unidade_id,
  un.nome                                as unidade_nome,
  a.curso_nome,
  a.data_hora_fim,
  floor(extract(epoch from now() - a.data_hora_fim) / 3600)::integer  as horas_em_atraso,
  floor(extract(epoch from now() - a.data_hora_fim) / 86400)::integer as dias_em_atraso,
  'experimental'::text                   as tipo_alvo
from public.lead_experimentais le
join public.lead_experimental_aulas v
  on v.lead_experimental_id = le.id
 and v.substituido_em is null
 and v.cancelado_em is null
join public.aulas_emusys a on a.id = v.aula_local_id
left join public.professores pr on pr.id = a.professor_id
left join public.usuarios u on u.id = pr.usuario_id
left join public.unidades un on un.id = a.unidade_id
where
  -- gatilho: a equipe deu presença ao lead (combinado: marcar na chegada)
  le.status in ('experimental_realizada', 'convertido')
  and a.id = public.fn_aula_operacional_id(a.id)
  and coalesce(a.cancelada, false) = false
  and a.data_hora_fim < now()
  -- só a partir do corte: a trilha nasce valendo pra frente
  and (a.data_hora_fim at time zone 'America/Sao_Paulo')::date >= public.fn_data_corte_experimental()
  -- não se cobra quem não tem a ferramenta
  and public.fn_professor_usa_app(a.professor_id)
  -- fecha na CONFIRMAÇÃO: gravado e não confirmado o comercial não recebe
  and not exists (
    select 1 from public.lead_experimental_registros r
     where r.vinculo_id = v.id
       and r.status not in ('descartado', 'aguardando_confirmacao')
  );

comment on view public.vw_experimental_pendencia is
  'Experimental realizada, do corte pra frente, cujo professor tem o app e ainda nao CONFIRMOU a devolutiva. Regua propria: a de aluno (vw_registro_pendencia) nao e tocada.';
