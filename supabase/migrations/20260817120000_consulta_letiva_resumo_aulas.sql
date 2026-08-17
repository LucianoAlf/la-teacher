-- Consulta letiva do professor (Fase 1): quantas aulas ele deu num periodo.
-- Nasceu do pedido do prof. Valdo em 16/08 ("me informe o total de aulas que eu
-- dei de 11/08 a 15/08"), que o Fabio nao soube responder — ele nao tem
-- ferramenta de banco, por desenho (o canal do professor e `no_mcp`).
--
-- Read-only. O p_professor_id vem do BRIDGE (linha da mensagem), nunca do texto
-- do professor. NAO le contrato/mensalidade/repasse/folha: a fronteira do
-- financeiro e uma porta que nao existe, e o teste de catalogo verifica o corpo
-- desta funcao (mutante que injeta coluna financeira tem que morrer).
--
-- A contagem colapsa eventos pelo fn_aula_operacional_id: desde 09/07 o mesmo
-- horario aparece 2x em aulas_emusys (aula_emusys_id e id de EVENTO). Contar
-- linha crua devolveria 74 no lugar de 36 na semana do Valdo — e o professor
-- perderia a confianca na primeira resposta.

create or replace function public.fabio_professor_resumo_aulas(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date,
  p_unidade      text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
begin
  if p_professor_id is null or p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'motivo', 'parametros_obrigatorios');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'motivo', 'periodo_invertido');
  end if;
  if (p_fim - p_inicio) > 90 then
    return jsonb_build_object('ok', false, 'motivo', 'janela_maior_que_90_dias');
  end if;

  return (
    with base as (
      select distinct
        coalesce(public.fn_aula_operacional_id(ae.id), ae.id) as aula_op,
        ae.data_aula,
        u.nome as unidade
      from public.aulas_emusys ae
      left join public.unidades u on u.id = ae.unidade_id
      where ae.professor_id = p_professor_id
        and ae.data_aula between p_inicio and p_fim
        and coalesce(ae.cancelada, false) = false
        and (p_unidade is null or u.nome ilike p_unidade)
    ),
    marcada as (
      select b.*,
             exists (
               select 1
                 from public.fabio_registros_aula r
                -- O REGISTRO TAMBEM PRECISA SER COLAPSADO. Medido em 17/08:
                -- 2 de 149 troncos dos ultimos 60 dias apontam pra linha de
                -- EVENTO duplicada, nao pro id operacional. Comparar
                -- `r.aula_id = b.aula_op` cru perderia esses — a aula
                -- apareceria como "sem registro" tendo registro.
                where coalesce(public.fn_aula_operacional_id(r.aula_id), r.aula_id) = b.aula_op
                  and r.parent_id is null
                  and r.status in ('confirmado', 'gravado_emusys')
             ) as tem_registro
        from base b
    )
    select jsonb_build_object(
      'ok', true,
      'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
      'total_aulas', count(*),
      'por_unidade', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'unidade', coalesce(unidade, '(sem unidade)'), 'aulas', n)
                 order by n desc, coalesce(unidade, '(sem unidade)')), '[]'::jsonb)
          from (select unidade, count(*) as n from marcada group by unidade) q
      ),
      'por_dia', (
        select coalesce(jsonb_agg(jsonb_build_object('data', data_aula, 'aulas', n)
                 order by data_aula), '[]'::jsonb)
          from (select data_aula, count(*) as n from marcada group by data_aula) q
      ),
      'registradas', count(*) filter (where tem_registro),
      'sem_registro', count(*) filter (where not tem_registro)
    )
    from marcada
  );
end
$fn$;

comment on function public.fabio_professor_resumo_aulas(integer, date, date, text) is
  'Consulta letiva Fase 1: total de aulas do PROPRIO professor num periodo, deduplicado por fn_aula_operacional_id nos dois lados (agenda e registro). Read-only, sem financeiro.';

revoke all on function public.fabio_professor_resumo_aulas(integer, date, date, text) from public, anon, authenticated;
grant execute on function public.fabio_professor_resumo_aulas(integer, date, date, text) to service_role;
