-- 065 — o painel da coordenação tem fonte
--
-- A coordenação precisa ver quem está em aberto AGORA. A fonte é a
-- `vw_presenca_pendencia` (013), que já é a resposta canônica para "sem presença
-- forte". Não se recalcula nada aqui: o LA Teacher já tem uma régua de presença
-- honesta e o LA Report tem outra — somar uma terceira, dentro de casa, seria
-- garantir que o painel e a agenda discordem um dia.
--
-- Ordena por urgência (em_aberto desc, pior_atraso desc), NUNCA por nome. Isso
-- não é preferência: o painel de equipe já foi ao ar com a fila alfabética
-- enquanto a tela dizia "por urgência", e ninguém percebeu porque uma lista
-- ordenada errado parece uma lista ordenada.
--
-- A janela é FECHADA em current_date: aula de hoje ainda não está atrasada. Sem
-- isso o painel cobraria o professor pela aula que ele está dando agora.

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
    select professor_id, professor_nome, unidade_nome,
           count(*)::int                 as em_aberto,
           count(distinct aluno_id)::int as alunos,
           max(dias_em_atraso)::int      as pior_atraso
      from pend
     group by 1, 2, 3
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
                 'unidade_nome',   p.unidade_nome,
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

-- `create or replace` PRESERVA privilégios: sem o revoke explícito abaixo, um
-- grant antigo sobrevive à substituição e o mutante de permissão passa batido.
revoke all on function public.app_coordenacao_em_aberto(int, uuid) from public;
revoke all on function public.app_coordenacao_em_aberto(int, uuid) from anon;
grant execute on function public.app_coordenacao_em_aberto(int, uuid) to authenticated;

comment on function public.app_coordenacao_em_aberto(int, uuid) is
  'Bloco 1 do painel da coordenacao: quem esta com lancamento em aberto, '
  'ordenado por urgencia. Fonte unica: vw_presenca_pendencia (013). '
  'So coordenacao (fn_e_coordenacao_la_teacher, 062).';
