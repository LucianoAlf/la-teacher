-- 072 — a pendência aprende o Emusys (a transição existe)
--
-- SUPERA A 071 nas duas funções (mesmas assinaturas; só o corpo muda).
--
-- ── O DEFEITO, apontado pelo Alf antes do painel chegar na coordenação ──────
--
-- "A gente não pode colocar como em aberto, porque de repente está na tabela
--  onde chega o conteúdo de aula do Emusys. Os professores ainda usam Emusys."
--
-- Ele tinha razão, e medido (08/08, janela de 7 dias) o tamanho é este:
--
--   aulas na pendência ............ 744
--   com ANOTAÇÃO no Emusys ........ 125 (17%)
--
-- E não é anotação de enfeite: média de 255 caracteres, estruturada
-- ("Objetivo… Conteúdo…"). O caso extremo é o Isaque Mendes — o painel dizia
-- "29 em aberto" e **25 têm aula lançada no Emusys**. Um clique em "Cobrar" e
-- o Fábio mandava WhatsApp cobrando quem fez o trabalho; a resposta seria
-- "tô lançando no Emusys, olha lá" e o painel morreria de descrédito no
-- primeiro dia.
--
-- ── POR QUE A ANOTAÇÃO, e não a presença do Emusys ──────────────────────────
--
-- A presença vinda do sync continua NÃO limpando pendência — a régua da 012
-- fica de pé: ~4.254/4.266 "verdes" do Emusys eram fake (default do sistema,
-- não gesto do professor). `professor_presenca` idem: preenchido em 744 de
-- 744, ou seja, não distingue nada.
--
-- A ANOTAÇÃO é diferente: é texto digitado. Não existe sync que fabrique
-- "Revisão dos grooves básicos de semínima e colcheia". Anotação = professor
-- trabalhou, no sistema velho, como a transição permite.
--
-- ── O MODELO: três estados, não dois ────────────────────────────────────────
--
--   REGISTRADA ........ presença forte no LA Teacher (some da pendência — já era)
--   NO EMUSYS ......... anotação digitada lá (pendência de MIGRAÇÃO, não de
--                       trabalho — informa, não acusa)
--   SEM NADA .......... nenhum registro em lugar nenhum — só isto é cobrável
--
-- A fila passa a ordenar por SEM NADA, o atraso passa a ser o da aula mais
-- antiga SEM NADA, e o resumo separa os dois números. `sem_lancamento` morre
-- de nome junto com o significado (regra da 067/070: campo que muda de
-- significado muda de nome): virou `sem_nada` + `no_emusys`.

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
    select v.professor_id, v.professor_nome, v.unidade_id, v.unidade_nome,
           v.curso_nome, public.fn_curso_chave(v.curso_nome) as curso_chave,
           v.aula_id, v.aluno_id, v.data_aula, v.dias_em_atraso,
           -- Anotação digitada no Emusys = trabalho feito lá. Presença do sync
           -- NÃO entra aqui de propósito — ver o cabeçalho.
           (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.data_aula >= current_date - p_dias
       and v.data_aula <  current_date
  ),
  pend as (
    select * from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and (p_curso is null or curso_chave = p_curso)
  ),
  por_professor as (
    select professor_id,
           min(professor_nome) as professor_nome,
           count(distinct aula_id)                                    as aulas,
           count(distinct aula_id) filter (where not no_emusys)::int  as sem_nada,
           count(distinct aula_id) filter (where no_emusys)::int      as no_emusys,
           count(distinct aluno_id) filter (where not no_emusys)::int as alunos,
           -- O atraso é o da aula mais antiga SEM NADA: cobrar pelo atraso de
           -- uma aula que está lançada no Emusys é a mesma acusação indevida.
           max(dias_em_atraso) filter (where not no_emusys)::int      as pior_atraso,
           (select string_agg(distinct u.unidade_nome, ', ' order by u.unidade_nome)
              from pend u where u.professor_id = p.professor_id) as unidades,
           (select string_agg(distinct c.curso_nome, ', ' order by c.curso_nome)
              from pend c where c.professor_id = p.professor_id
                            and c.curso_nome is not null) as cursos
      from pend p
     group by professor_id
  ),
  fac_unidade as (
    select unidade_id, min(unidade_nome) as unidade_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_curso is null or curso_chave = p_curso)
       and unidade_id is not null
     group by unidade_id
  ),
  fac_curso as (
    select curso_chave,
           min(regexp_replace(btrim(curso_nome), '\s+(t|ind)$', '', 'i')) as curso_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and curso_chave is not null
     group by curso_chave
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'sem_nada',   (select count(distinct aula_id) from pend where not no_emusys),
      'no_emusys',  (select count(distinct aula_id) from pend where no_emusys),
      'professores',(select count(distinct professor_id) from pend),
      -- "Só de ontem" também é só o cobrável: número de alarme não pode
      -- misturar pendência de migração.
      'ontem',      (select count(distinct aula_id) from pend
                      where data_aula = current_date - 1 and not no_emusys),
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
                 'sem_nada',       p.sem_nada,
                 'no_emusys',      p.no_emusys,
                 'alunos',         p.alunos,
                 'pior_atraso',    p.pior_atraso)
               -- SEM NADA manda na ordem. Com o count total, o Isaque (25 de
               -- 29 no Emusys) aparecia acima de quem não lançou em lugar
               -- nenhum — a fila apontava a cobrança pra quem trabalha.
               order by p.sem_nada desc, p.pior_atraso desc nulls last,
                        p.professor_nome)
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
  'Bloco 1 do painel da coordenacao. Tres estados por aula: registrada (forte, '
  'fora da pendencia), no Emusys (anotacao digitada la — informa, nao acusa) e '
  'SEM NADA (a unica cobravel; manda na ordem). Supera a 071.';


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
    select v.aula_id, v.data_aula, v.hora, v.curso_nome, v.turma_nome,
           v.unidade_nome, v.aluno_id, v.aluno_primeiro_nome,
           v.dias_em_atraso, v.professor_nome,
           (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.professor_id = p_professor_id
       and v.data_aula >= current_date - p_dias
       and v.data_aula <  current_date
       and (p_unidade_id is null or v.unidade_id = p_unidade_id)
       and (p_curso is null or public.fn_curso_chave(v.curso_nome) = p_curso)
  ),
  por_aula as (
    select aula_id,
           min(data_aula)            as data_aula,
           min(hora::text)           as hora,
           min(curso_nome)           as curso_nome,
           min(turma_nome)           as turma_nome,
           min(unidade_nome)         as unidade_nome,
           max(dias_em_atraso)::int  as dias_em_atraso,
           bool_or(no_emusys)        as no_emusys,
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
             'alunos_nomes', alunos_nomes,
             -- A linha da fila diz "N no Emusys"; é AQUI que se vê quais.
             'no_emusys',    no_emusys)
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
  'Detalhe da linha do painel, agrupado por dia (mais antigo primeiro). Cada '
  'aula diz se tem anotacao no Emusys. Aceita os filtros da fila. Supera a 071.';
