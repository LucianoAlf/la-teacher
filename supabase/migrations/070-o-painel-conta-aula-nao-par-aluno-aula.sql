-- 070 — o painel para de contar aluno-aula e passa a contar AULA
--
-- SUPERA A 067 (só a função `app_coordenacao_em_aberto`; o resto da 067 e da
-- 065 continua valendo). Adiciona também a função de detalhe por professor.
--
-- SUPERADA POR: 071 — as duas funções ganharam filtro de unidade e de curso, e
-- a assinatura mudou (a 071 dá `drop` nestas). A conta em AULAS, que é o motivo
-- desta migration existir, continua valendo lá.
--
-- ── O DEFEITO ───────────────────────────────────────────────────────────────
--
-- A `vw_presenca_pendencia` tem uma linha por PAR aluno-aula. A 067 fazia
-- `count(*)` em cima disso e chamava de "em aberto" — mas o que o professor
-- lança é a AULA, uma vez, não uma vez por aluno.
--
-- Medido em 08/08/2026, janela de 7 dias:
--
--   linhas aluno-aula ....... 847
--   aulas de verdade ........ 624
--   alunos distintos ........ 809
--   alunos por aula ......... 1,36
--
-- Como a maioria das turmas tem um aluno só, "em aberto" e "alunos" saíam
-- quase iguais em TODA linha da fila. Os dois números juntos não informavam
-- nada — foi o Alf quem estranhou, olhando a tela: "em aberto 50, alunos 49,
-- o quê?".
--
-- Concreto: o Ramon Pina Morais aparecia com "50 em aberto / 49 alunos". O
-- trabalho real dele são **21 aulas em 3 dias** (6 na segunda, 9 na terça, 6 na
-- quarta). Cinquenta não é o esforço dele; é o formato da view.
--
-- E o número vazava pro WhatsApp: o texto da cobrança (`BotaoRecado.tsx`) dizia
-- "50 lançamentos em aberto" pra quem tinha 21 aulas pra lançar. Cobrança com
-- tamanho errado é pior que cobrança sem tamanho — ela decide quando o
-- professor senta.
--
-- ── POR QUE O CAMPO MUDA DE NOME ────────────────────────────────────────────
--
-- `em_aberto` → `aulas`. Mesma disciplina da 067 (`unidade_nome` → `unidades`):
-- campo que muda de SIGNIFICADO tem que mudar de nome, senão o próximo a ler
-- confia no comentário velho. `aulas` também diz a unidade sozinho.
--
-- ── SEGURANÇA DO `count(distinct aula_id)` ──────────────────────────────────
--
-- Conferido antes de usar (a casa já tomou susto com `emusys_aula_id` ser id de
-- EVENTO e não de ocorrência): nesta view, na janela de 7 dias,
-- `count(distinct aula_id)` = `count(distinct (aula_id, data_aula, hora))` =
-- 624, e **zero** `aula_id` aparece em mais de um dia. O id identifica a
-- ocorrência aqui.

create or replace function public.app_coordenacao_em_aberto(
  p_dias       int  default 7,
  p_unidade_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_saida jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (
    select professor_id, professor_nome, unidade_nome, curso_nome,
           aula_id, aluno_id, data_aula, dias_em_atraso
      from public.vw_presenca_pendencia
     where data_aula >= current_date - p_dias
       and data_aula <  current_date
       and (p_unidade_id is null or unidade_id = p_unidade_id)
  ),
  por_professor as (
    select professor_id,
           min(professor_nome)            as professor_nome,
           -- A UNIDADE DE TRABALHO: uma aula é um lançamento, tenha ela 1 ou 5
           -- alunos. Era `count(*)` — ver o cabeçalho.
           count(distinct aula_id)::int   as aulas,
           count(distinct aluno_id)::int  as alunos,
           max(dias_em_atraso)::int       as pior_atraso,
           (select string_agg(distinct u.unidade_nome, ', ' order by u.unidade_nome)
              from pend u where u.professor_id = p.professor_id) as unidades,
           -- Cursos dão CARA pro professor na fila ("Teclado, Piano"), que é o
           -- que a segunda linha do card mostra. Só os que aparecem na janela.
           (select string_agg(distinct c.curso_nome, ', ' order by c.curso_nome)
              from pend c where c.professor_id = p.professor_id
                            and c.curso_nome is not null) as cursos
      from pend p
     group by professor_id
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      -- Faixa executiva na mesma unidade da fila. Se o topo contasse pares e a
      -- linha contasse aulas, a soma da coluna não bateria com o número grande
      -- — e é assim que a coordenação para de confiar no painel.
      'sem_lancamento',     (select count(distinct aula_id) from pend),
      'professores',        (select count(distinct professor_id) from pend),
      'ontem',              (select count(distinct aula_id) from pend
                              where data_aula = current_date - 1),
      'professores_ativos', (select count(*) from public.professores where ativo)
    ),
    'professores', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'professor_id',   p.professor_id,
                 'professor_nome', p.professor_nome,
                 -- 43 dos 44 ativos têm foto, e os 38 da fila têm todas. As
                 -- iniciais são fallback de verdade, não o caso comum.
                 'foto_url',       pr.foto_url,
                 'unidades',       p.unidades,
                 'cursos',         p.cursos,
                 'aulas',          p.aulas,
                 'alunos',         p.alunos,
                 'pior_atraso',    p.pior_atraso)
               order by p.aulas desc, p.pior_atraso desc, p.professor_nome)
        from por_professor p
        join public.professores pr on pr.id = p.professor_id
    ), '[]'::jsonb)
  ) into v_saida;

  return v_saida;
end;
$function$;

-- `create or replace` PRESERVA privilégios: sem o revoke explícito, um grant
-- antigo sobrevive à substituição e o mutante de permissão passa batido.
revoke all on function public.app_coordenacao_em_aberto(int, uuid) from public;
revoke all on function public.app_coordenacao_em_aberto(int, uuid) from anon;
grant execute on function public.app_coordenacao_em_aberto(int, uuid) to authenticated;

comment on function public.app_coordenacao_em_aberto(int, uuid) is
  'Bloco 1 do painel da coordenacao: quem esta com lancamento em aberto, '
  'UMA linha por professor, contando AULAS (nao pares aluno-aula). '
  'Fonte unica: vw_presenca_pendencia (013). Supera a 067.';


-- ── DETALHE DE UM PROFESSOR ─────────────────────────────────────────────────
--
-- Responde a pergunta que a coordenação faz ANTES de cobrar: "quais aulas?".
-- Hoje ela cobra às cegas — a fila só diz quantas.
--
-- Agrupa por DIA porque é assim que o professor resolve: ele senta e lança o
-- dia inteiro. Uma lista corrida de 21 aulas não diz por onde começar.
--
-- Ordem: dia MAIS ANTIGO primeiro. O painel inteiro é ordenado por urgência, e
-- o painel de equipe já foi ao ar uma vez escrevendo "por urgência" em cima de
-- uma lista alfabética — lista ordenada errado parece lista ordenada.

create or replace function public.app_coordenacao_professor_detalhe(
  p_professor_id int,
  p_dias         int default 7
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_saida jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (
    select aula_id, data_aula, hora, curso_nome, turma_nome, unidade_nome,
           aluno_id, aluno_primeiro_nome, dias_em_atraso, professor_nome
      from public.vw_presenca_pendencia
     where professor_id = p_professor_id
       and data_aula >= current_date - p_dias
       and data_aula <  current_date
  ),
  por_aula as (
    select aula_id,
           min(data_aula)            as data_aula,
           min(hora::text)           as hora,
           min(curso_nome)           as curso_nome,
           min(turma_nome)           as turma_nome,
           min(unidade_nome)         as unidade_nome,
           max(dias_em_atraso)::int  as dias_em_atraso,
           count(distinct aluno_id)::int as alunos,
           string_agg(distinct aluno_primeiro_nome, ', '
                      order by aluno_primeiro_nome) as alunos_nomes
      from pend
     group by aula_id
  ),
  por_dia as (
    select data_aula,
           max(dias_em_atraso)::int as dias_em_atraso,
           count(*)::int            as aulas,
           jsonb_agg(jsonb_build_object(
             'aula_id',      aula_id,
             'hora',         hora,
             'curso_nome',   curso_nome,
             'turma_nome',   turma_nome,
             'unidade_nome', unidade_nome,
             'alunos',       alunos,
             'alunos_nomes', alunos_nomes)
             order by hora, curso_nome) as itens
      from por_aula
     group by data_aula
  )
  select jsonb_build_object(
    'professor_id',   p_professor_id,
    'professor_nome', (select min(professor_nome) from pend),
    'aulas',          (select count(*) from por_aula),
    'dias', coalesce((
      select jsonb_agg(jsonb_build_object(
               'data_aula',      data_aula,
               'dias_em_atraso', dias_em_atraso,
               'aulas',          aulas,
               'itens',          itens)
             order by data_aula)          -- mais antigo primeiro = mais urgente
        from por_dia
    ), '[]'::jsonb)
  ) into v_saida;

  return v_saida;
end;
$function$;

revoke all on function public.app_coordenacao_professor_detalhe(int, int) from public;
revoke all on function public.app_coordenacao_professor_detalhe(int, int) from anon;
grant execute on function public.app_coordenacao_professor_detalhe(int, int) to authenticated;

comment on function public.app_coordenacao_professor_detalhe(int, int) is
  'Detalhe da linha do painel: quais aulas do professor estao sem lancamento, '
  'agrupadas por dia (mais antigo primeiro). Fonte: vw_presenca_pendencia.';
