-- 081 — os sinais do Radar do aluno
--
-- SUPERADA POR: 088-a-falta-seguida-e-o-quinto-sinal.sql
--
-- A 088 reaplica esta MESMA view (create or replace) acrescentando o 5º
-- sinal (faltas_consecutivas) no fim da lista de colunas — create or replace
-- view recusa DROPAR coluna, então a versão daqui embaixo (20 colunas) não
-- reaplica mais contra a view viva (21 colunas). Isso não é bug: é o motivo
-- de existir o marcador. `scripts/mutantes-081.mjs` foi repontado pra mutar
-- o corpo da 088 (que ainda carrega intactas as 4 decisões que este arquivo
-- documenta), não este arquivo.
--
-- Fundação do Radar: uma linha por aluno da coorte, com os quatro sinais da
-- Fase 1 e a BASE de cada um. Quem lê o número tem que ver de quantas aulas
-- ele saiu.
--
-- A FONTE DE PRESENÇA JÁ EXISTIA. `vw_aluno_presenca_semantica_v1` cruza a
-- presença que nasce do lançamento do professor com a que a secretaria dá no
-- Emusys, e implementa os quatro estados (presente, falta_confirmada,
-- aula_justificada, aula_cancelada) mais os dois "não sei" (falta_provavel,
-- indeterminado). A coluna `considera_frequencia_denominador` já tira da conta
-- o que ninguém confirmou. NÃO se escreve view nova de presença.
--
-- O GRÃO É AULA, NÃO LINHA. A view semântica tem 1,69 linha por aula porque
-- `aula_emusys_id` é id de EVENTO — a mesma aula do mesmo aluno no mesmo
-- horário aparece duas vezes. Isso já está visível na tela do LA Report hoje
-- (o modal lista 03/08 duas vezes). Contar linha dobra toda falta.
--
-- A JANELA NASCE EM 01/08/2026 ("vira a página", decisão do Alf). Julho teve
-- duas semanas de recesso e as três unidades vinham sem compromisso com
-- presença. Aproveitar dado ruim porque é o que tem foi o erro que me fez
-- publicar "126 alunos sumidos" que eram chamada não lançada.
--
-- A COORTE é quem já entrou no app. Os sinais que o professor escreve só
-- existem pra quem está lá, e cobrar/expor quem não tem a tela é o jeito mais
-- rápido de o professor aprender a ignorar o sistema.
create or replace view public.vw_radar_aluno_sinais as
with coorte as (
  select id as professor_id
    from public.professores
   where coalesce(ativo, true) and usuario_id is not null
),
-- Grão honesto: uma linha por AULA. Presença é afirmação — se qualquer linha
-- do grupo diz presente, o aluno veio.
aula as (
  select v.aluno_id,
         v.data_aula,
         v.horario_aula,
         bool_or(v.considera_presenca) as veio
    from public.vw_aluno_presenca_semantica_v1 v
   where v.considera_frequencia_denominador
     and v.data_aula >= date '2026-08-01'
   group by 1, 2, 3
),
-- As 10 últimas aulas medidas de cada aluno.
ordenada as (
  select aluno_id, data_aula, veio,
         row_number() over (partition by aluno_id
                            order by data_aula desc, horario_aula desc nulls last) as rn
    from aula
),
janela as (
  select aluno_id,
         count(*)                          as aulas_medidas,
         count(*) filter (where not veio)  as faltas_janela
    from ordenada
   where rn <= 10
   group by 1
),
-- O outro olhar: o fato do mês corrente.
mes as (
  select aluno_id,
         count(*)                          as aulas_mes,
         count(*) filter (where not veio)  as faltas_mes
    from aula
   where data_aula >= public.fn_competencia_feedback()
   group by 1
),
-- O semáforo do mês, escrito pelo professor. Uma linha por aluno+professor.
semaforo as (
  select distinct on (f.aluno_id, f.professor_id)
         f.aluno_id, f.professor_id, f.feedback, f.pratica_em_casa,
         f.evolucao, f.animo, nullif(btrim(f.observacao), '') as observacao,
         f.competencia
    from public.aluno_feedback_professor f
   where f.competencia = public.fn_competencia_feedback()
   order by f.aluno_id, f.professor_id,
            coalesce(f.atualizado_em, f.respondido_em) desc
),
-- Aviso prévio: vive da linha ADM. O join até `alunos` é frágil (só 17 de 33
-- acham par), então ele é SELO, não fonte de dado do aluno.
aviso as (
  select distinct ma.aluno_id, min(ma.mes_saida) as mes_saida
    from public.movimentacoes_admin ma
   where ma.tipo = 'aviso_previo'
     and ma.mes_saida >= public.fn_competencia_feedback()
     and ma.aluno_id is not null
   group by ma.aluno_id
)
select s.id                                as aluno_id,
       s.nome                              as aluno_nome,
       s.unidade_id,
       s.unidade_codigo,
       s.professor_atual_id                as professor_id,
       s.professor_nome,
       s.curso_nome,
       coalesce(j.aulas_medidas, 0)        as aulas_medidas,
       coalesce(j.faltas_janela, 0)        as faltas_janela,
       -- NULO quando não há base. Zero seria "não faltou", e é mentira
       -- diferente de "não sei".
       case when coalesce(j.aulas_medidas, 0) > 0
            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)
       end                                 as absenteismo_pct,
       coalesce(m.faltas_mes, 0)           as faltas_mes,
       coalesce(m.aulas_mes, 0)            as aulas_mes,
       sf.feedback,
       sf.pratica_em_casa,
       sf.evolucao,
       sf.animo,
       sf.observacao,
       sf.competencia                      as feedback_competencia,
       (av.aluno_id is not null)           as avisou_que_sai,
       av.mes_saida
  from public.vw_aluno_sucesso_lista s
  join coorte c   on c.professor_id = s.professor_atual_id
  left join janela j  on j.aluno_id = s.id
  left join mes m     on m.aluno_id = s.id
  left join semaforo sf on sf.aluno_id = s.id and sf.professor_id = s.professor_atual_id
  left join aviso av  on av.aluno_id = s.id;

comment on view public.vw_radar_aluno_sinais is
  'Sinais do Radar da coordenação, grão de ALUNO. Presença vem de '
  'vw_aluno_presenca_semantica_v1 no grão de AULA (aluno,dia,hora), janela '
  'desde 01/08/2026, só coorte de professor com login liberado. '
  'absenteismo_pct é NULO sem base — nunca zero.';

-- ACHADO NA REVISÃO (rodada de correção, 10/08): sem security_invoker a view
-- roda como DEFINER — o dono de quem aplicou a migration — e passa por cima
-- da RLS de `aluno_feedback_professor` (2 policies vivas da 074, que travam
-- professor a só ver o PRÓPRIO feedback). Com `grant ... to authenticated`
-- qualquer login lia observacao/feedback/avisou_que_sai de aluno de OUTRO
-- professor pelo PostgREST. Fronteira mais dura da casa: o canal do professor
-- nunca alcança dado de colega.
--
-- Sem isto a view nasceria legível por `anon` e `authenticated` de qualquer
-- jeito: o ALTER DEFAULT PRIVILEGES do projeto concede SELECT nos dois, e
-- `revoke from public` sozinho não alcança nenhum. A porta é a FUNÇÃO, não a
-- view — a RPC da Task 4 (security definer, com o guard) é quem lê daqui pra
-- frente, do jeito que 028 já faz pra `vw_fabio_contexto_experimental`.
revoke all on table public.vw_radar_aluno_sinais from public, anon, authenticated;
grant select on table public.vw_radar_aluno_sinais to service_role;
