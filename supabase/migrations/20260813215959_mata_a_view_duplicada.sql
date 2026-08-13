-- Mata a view duplicada
--
-- Eu criei `vw_aluno_pessoa` sem antes perguntar se a casa ja tinha resolvido
-- isso. Tinha:
--
--   `vw_aluno_identidade_unidade_canonica` -- ja com uma coluna chamada
--     `pessoa_chave` (o MESMO nome que escolhi), e ainda `aluno_id_canonico`,
--     `aluno_ids_locais`, `identidade_fonte` e `identidade_confianca`.
--   `vw_professor_carteira_pessoa_canonica_sombra` -- a carteira por pessoa.
--
-- Os numeros batiam exatamente (prof 25 = 20, Ramon = 47 nas duas), entao a
-- minha nao acrescentava nada e ainda era mais pobre. Duas fontes para a mesma
-- verdade e como o numero comeca a divergir sem ninguem perceber.
--
-- Conferido antes de apagar: o UNICO objeto que dependia de `vw_aluno_pessoa`
-- era a propria `app_professor_carteira_contagem`, criada junto na mesma
-- sessao. Nada mais no banco a lia.
--
-- A RPC fica -- ela nao duplica nada, e o acessorio que entrega o numero
-- calculado pro Fabio. So passa a ler a canonica.

create or replace function public.app_professor_carteira_contagem(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select jsonb_build_object(
    'professor_id', p_professor_id,
    'pessoas', (select count(*)
                  from public.vw_professor_carteira_pessoa_canonica_sombra s
                 where s.professor_id = p_professor_id),
    'matriculas', (select count(distinct c.aluno_id)
                     from public.vw_fabio_carteira_professor c
                    where c.professor_id = p_professor_id),
    'linhas', (select count(*)
                 from public.vw_fabio_carteira_professor c
                where c.professor_id = p_professor_id)
  );
$function$;

comment on function public.app_professor_carteira_contagem(integer) is
  'Carteira contada por PESSOA (decisao do Alf, 13/08/2026). A identidade da '
  'pessoa vem da canonica vw_professor_carteira_pessoa_canonica_sombra -- NAO '
  'reimplementar deduplicacao aqui. Devolve pessoas/matriculas/linhas juntos: '
  'quando divergem, a diferenca e informacao (aluno multi-curso). '
  'ATENCAO: hoje INCLUI banda, e docs/REGRAS-DE-NEGOCIO.md §3.5 do LA Report '
  'exclui banda da carteira do professor para KPI. Decisao do Alf pendente: '
  'operacional ("quem eu ensino") x KPI sao duas perguntas diferentes.';

drop view if exists public.vw_aluno_pessoa;

revoke all on function public.app_professor_carteira_contagem(integer)
  from public, anon, authenticated;
grant execute on function public.app_professor_carteira_contagem(integer)
  to service_role, fabio_agent;
