-- 067 — a fila do painel para de repetir professor
--
-- SUPERA A 065 (só a função `app_coordenacao_em_aberto`; o resto da 065 continua
-- valendo).
--
-- O DEFEITO, achado com o painel já rodando: a 065 agrupava por
-- (professor, unidade). Como 27 dos 44 professores da casa dão aula em mais de
-- uma unidade, 38 professores viravam **60 linhas** — e a própria tela
-- denunciava, mostrando "Professores afetados: 38" em cima de uma fila de 60.
--
-- Não é cosmético. A coordenação cobraria o mesmo professor duas vezes, e o
-- segundo clique bateria na dedupe diária da 066 respondendo "o Fábio já cobrou
-- hoje" — uma explicação que não explica nada, porque quem clicou foi ela mesma,
-- dez segundos antes.
--
-- A unidade não some: vira lista ("Campo Grande, Recreio"). Quem cobra precisa
-- saber onde o professor dá aula, mas cobra a PESSOA, não a lotação.
--
-- Por isso o campo mudou de nome (`unidade_nome` → `unidades`): um campo que
-- passa a guardar várias e mantém o nome no singular é a próxima armadilha.

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
    select professor_id, professor_nome, unidade_nome,
           aluno_id, data_aula, dias_em_atraso
      from public.vw_presenca_pendencia
     where data_aula >= current_date - p_dias
       and data_aula <  current_date
       and (p_unidade_id is null or unidade_id = p_unidade_id)
  ),
  por_professor as (
    select professor_id,
           min(professor_nome)            as professor_nome,
           count(*)::int                  as em_aberto,
           count(distinct aluno_id)::int  as alunos,
           max(dias_em_atraso)::int       as pior_atraso,
           (select string_agg(distinct u.unidade_nome, ', ' order by u.unidade_nome)
              from pend u where u.professor_id = p.professor_id) as unidades
      from pend p
     group by professor_id
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'sem_lancamento',     (select count(*) from pend),
      'professores',        (select count(distinct professor_id) from pend),
      'ontem',              (select count(*) from pend
                              where data_aula = current_date - 1),
      'professores_ativos', (select count(*) from public.professores where ativo)
    ),
    'professores', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'professor_id',   p.professor_id,
                 'professor_nome', p.professor_nome,
                 'unidades',       p.unidades,
                 'em_aberto',      p.em_aberto,
                 'alunos',         p.alunos,
                 'pior_atraso',    p.pior_atraso)
               order by p.em_aberto desc, p.pior_atraso desc, p.professor_nome)
        from por_professor p
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
  'UMA linha por professor (as unidades viram lista), ordenado por urgencia. '
  'Fonte unica: vw_presenca_pendencia (013). Supera a 065.';
