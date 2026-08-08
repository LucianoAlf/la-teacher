-- 071 — o painel filtra por unidade e por curso
--
-- SUPERA A 070 nas duas funções (assinatura nova; ver "por que DROP" abaixo).
--
-- ── A ARMADILHA DO FILTRO DE CURSO ──────────────────────────────────────────
--
-- Na janela de 7 dias a `vw_presenca_pendencia` tem **34 nomes de curso**, mas
-- não 34 cursos: o sufixo ` T` (turma) e ` IND` (individual) é MODALIDADE, não
-- curso. Medido em 08/08/2026:
--
--   Bateria      129 aulas  em 3 nomes (Bateria | Bateria IND | Bateria T)
--   Canto        126 aulas  em 3 nomes
--   Teclado       98 aulas  em 2 nomes
--   Violão        43 aulas  em 3 nomes
--   Musicalização
--   para bebês    22 aulas  em 3 nomes — e aqui a diferença é de CAIXA
--                            ("para bebês" | "Para Bebês" | "para Bebês T")
--
-- Um filtro por nome cru deixaria a coordenação escolher "Bateria" e ver 46 de
-- 129 aulas. Filtro que esconde dois terços do problema é pior do que não ter
-- filtro: ele responde com confiança.
--
-- Por isso o filtro recebe a CHAVE normalizada (`fn_curso_chave`), não o nome.
--
-- ── FACETAS: as opções não podem sumir ──────────────────────────────────────
--
-- A lista de unidades é calculada com o filtro de CURSO aplicado e o de unidade
-- NÃO; a de cursos, o contrário. É o que impede o beco sem saída de escolher
-- uma unidade, a lista de cursos encolher para um, e não haver caminho de volta
-- sem recarregar.
--
-- Cada opção vem com a contagem ("Barra · 12"), porque a coordenação decide
-- ONDE olhar antes de clicar.
--
-- ── DROP DA VELHA + REPLACE DA NOVA ─────────────────────────────────────────
--
-- `create or replace function` NÃO troca assinatura: criar a versão de 3
-- argumentos deixaria a de 2 viva, com o corpo velho. Pior que corpo velho:
-- o PostgREST resolve por argumento nomeado, e com duas candidatas aceitando
-- (p_dias, p_unidade_id) ele recusa a chamada com "could not choose the best
-- candidate function" — o painel quebraria inteiro, não em parte. Daí o `drop`
-- explícito da assinatura antiga.
--
-- E `create OR REPLACE` na nova, não `create` puro: a suíte reaplica cada
-- migration num ensaio descartável, e `create` morre na segunda vez com
-- "already exists". Foi o que aconteceu na primeira versão deste arquivo — o
-- `teste:tudo` classificou a 071 como "não reaplicável" e o teste dela saiu da
-- suíte em silêncio. Teste que não roda é teste que não existe.
--
-- ── O DETALHE FILTRA JUNTO ──────────────────────────────────────────────────
--
-- Se a fila filtra e o detalhe não, o selo da linha diz "12 aulas" e o expandir
-- lista 35. O teste da 070 cruza esses dois números de propósito; manter o
-- cruzamento verde exige passar os mesmos filtros pros dois lados.

-- Chave de agrupamento do curso: tira a modalidade e ignora caixa.
-- `immutable` porque só depende do argumento — dá pra indexar depois se
-- precisar, e o planner pode dobrar a constante.
create or replace function public.fn_curso_chave(p_nome text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select nullif(lower(regexp_replace(btrim(p_nome), '\s+(t|ind)$', '', 'i')), '')
$function$;

comment on function public.fn_curso_chave(text) is
  'Agrupa nomes de curso tirando a modalidade (" T" / " IND") e a caixa. '
  '"Bateria", "Bateria T" e "Bateria IND" viram a mesma chave.';


drop function if exists public.app_coordenacao_em_aberto(int, uuid);

-- `create or replace` (e não `create`) na assinatura NOVA: assim a migration é
-- reaplicável e a suíte continua rodando o teste dela toda vez. Com `create`
-- puro, a segunda execução morre com "already exists" e o arquivo sai da
-- suíte em silêncio — teste que não roda é teste que não existe.
create or replace function public.app_coordenacao_em_aberto(
  p_dias       int  default 7,
  p_unidade_id uuid default null,
  p_curso      text default null
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

  with janela as (
    -- Sem NENHUM filtro além da janela: é a base das facetas.
    select professor_id, professor_nome, unidade_id, unidade_nome, curso_nome,
           public.fn_curso_chave(curso_nome) as curso_chave,
           aula_id, aluno_id, data_aula, dias_em_atraso
      from public.vw_presenca_pendencia
     where data_aula >= current_date - p_dias
       and data_aula <  current_date
  ),
  pend as (
    select * from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and (p_curso is null or curso_chave = p_curso)
  ),
  por_professor as (
    select professor_id,
           min(professor_nome)            as professor_nome,
           count(distinct aula_id)::int   as aulas,
           count(distinct aluno_id)::int  as alunos,
           max(dias_em_atraso)::int       as pior_atraso,
           (select string_agg(distinct u.unidade_nome, ', ' order by u.unidade_nome)
              from pend u where u.professor_id = p.professor_id) as unidades,
           (select string_agg(distinct c.curso_nome, ', ' order by c.curso_nome)
              from pend c where c.professor_id = p.professor_id
                            and c.curso_nome is not null) as cursos
      from pend p
     group by professor_id
  ),
  -- Faceta de unidade: ignora o próprio filtro, respeita o de curso.
  fac_unidade as (
    select unidade_id, min(unidade_nome) as unidade_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_curso is null or curso_chave = p_curso)
       and unidade_id is not null
     group by unidade_id
  ),
  -- Faceta de curso: ignora o próprio filtro, respeita o de unidade.
  fac_curso as (
    select curso_chave,
           -- Rótulo: o nome mais curto do grupo, sem a modalidade. Evita
           -- `initcap`, que estragaria "Musicalização Preparatória para
           -- instrumento".
           min(regexp_replace(btrim(curso_nome), '\s+(t|ind)$', '', 'i')) as curso_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and curso_chave is not null
     group by curso_chave
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'sem_lancamento',     (select count(distinct aula_id) from pend),
      'professores',        (select count(distinct professor_id) from pend),
      'ontem',              (select count(distinct aula_id) from pend
                              where data_aula = current_date - 1),
      'professores_ativos', (select count(*) from public.professores where ativo)
    ),
    'filtros', jsonb_build_object(
      'unidades', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'unidade_id', unidade_id, 'nome', unidade_nome, 'aulas', aulas)
               order by unidade_nome)
          from fac_unidade), '[]'::jsonb),
      'cursos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'chave', curso_chave, 'nome', curso_nome, 'aulas', aulas)
               order by aulas desc, curso_nome)
          from fac_curso), '[]'::jsonb)
    ),
    'professores', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'professor_id',   p.professor_id,
                 'professor_nome', p.professor_nome,
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

revoke all on function public.app_coordenacao_em_aberto(int, uuid, text) from public;
revoke all on function public.app_coordenacao_em_aberto(int, uuid, text) from anon;
grant execute on function public.app_coordenacao_em_aberto(int, uuid, text) to authenticated;

comment on function public.app_coordenacao_em_aberto(int, uuid, text) is
  'Bloco 1 do painel da coordenacao: quem esta com lancamento em aberto, '
  'UMA linha por professor, contando AULAS. Filtra por unidade e por curso '
  '(chave agrupada, nao nome cru) e devolve as facetas com contagem. '
  'Fonte unica: vw_presenca_pendencia (013). Supera a 070.';


drop function if exists public.app_coordenacao_professor_detalhe(int, int);

create or replace function public.app_coordenacao_professor_detalhe(
  p_professor_id int,
  p_dias         int  default 7,
  p_unidade_id   uuid default null,
  p_curso        text default null
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
       -- Os MESMOS filtros da fila: senão o selo da linha e a lista do
       -- expandir contam coisas diferentes na mesma tela.
       and (p_unidade_id is null or unidade_id = p_unidade_id)
       and (p_curso is null or public.fn_curso_chave(curso_nome) = p_curso)
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

revoke all on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) from public;
revoke all on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) from anon;
grant execute on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) to authenticated;

comment on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) is
  'Detalhe da linha do painel: quais aulas do professor estao sem lancamento, '
  'agrupadas por dia (mais antigo primeiro). Aceita os mesmos filtros da fila. '
  'Fonte: vw_presenca_pendencia.';
