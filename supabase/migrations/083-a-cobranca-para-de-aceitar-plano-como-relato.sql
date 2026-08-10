-- 083 — a cobranca para de aceitar PLANO como RELATO, e para de perder aula
--       quando o gemeo-ancora esta marcado como falta
--
-- Achado conversando com o log da professora Daiana (professor 3) em 10/08. Ela
-- mandou 8 audios de conteudo pedagogico pro Fabio no WhatsApp; 7 se perderam.
-- Ao conferir o que a governanca tinha visto disso, apareceram DOIS buracos na
-- `vw_registro_pendencia` — os dois fazem a mesma coisa: apagam aula da lista de
-- quem devia registrar. Lista que esconde trabalho nao feito e' pior que lista
-- nenhuma, porque ela AFIRMA que esta tudo em dia.
--
-- ── BURACO A: o plano do Emusys contava como registro ───────────────────────
-- A view dizia "ja registrada" quando `coalesce(anotacoes_fabio, anotacoes)`
-- tinha texto. So que `anotacoes` e' o campo de PLANO do Emusys — o professor
-- escreve ali o que PRETENDE dar, nao o que aconteceu. Amostra medida em
-- producao, entre as aulas que escapavam por esse caminho:
--
--     57 aulas com o texto IDENTICO "Atividades programaticas fixadas: ..."
--     55 aulas com o texto IDENTICO "Canto de entrada: (QUE BOM ESTAR AQUI) ..."
--     16 aulas com "MES DE JULHO > REVISAO ..."
--
-- Texto que se repete em 57 aulas nao e' relato de nenhuma delas. Medido:
-- 1.609 aulas desde 01/07 (323 dentro da janela cobravel) escapavam so por
-- isso. Nenhuma delas jamais foi cobrada, e nenhuma delas tem o que o
-- prontuario, a devolutiva e o historico do aluno precisam.
--
-- ⚠️ A licao da 041 continua valendo em cheio: "cobranca errada no grupo queima
-- a governanca no primeiro uso". Por isso a view NAO finge que essas aulas sao
-- terra arrasada — ela ganha a coluna `tem_plano_emusys`, pra quem monta a
-- mensagem poder dizer "tem plano no Emusys, falta o relato" em vez de "voce
-- nao fez nada". A cobranca fica verdadeira sem ficar injusta.
--
-- ── BURACO B: o gemeo com falta escondia a aula inteira ─────────────────────
-- Desde 09/07 cada aula real vira 2+ linhas em `aluno_presenca` (o
-- `aula_emusys_id` e' id de EVENTO, nao da aula). A view filtrava a presenca
-- pela linha da aula ANCORA. Quando o gemeo-ancora vinha do Emusys marcado
-- `falta` e o gemeo individual dizia `presente`, a aula sumia da pendencia.
--
-- Foi exatamente o caso da aula de 05/08 16h da Daiana (Julia e Clara):
--     aula 202396 (turma)      -> as duas 'falta'    (emusys)
--     aula 202397/202398 (ind) -> as duas 'presente' (emusys)
-- Aula dada, duas alunas presentes, zero registro — e ela nunca foi cobrada.
-- Medido: 572 pares de gemeos discordam entre si desde 01/07 (333 turma=falta
-- com individual=presente, 239 o inverso), de 3.617 pares.
--
-- A regra que fica e' a mesma que ja governa presenca nesta casa: **presenca e'
-- AFIRMACAO, nao ausencia**. Se qualquer gemeo do mesmo horario/professor/
-- unidade afirma `presente`, o aluno esteve la e ha conteudo a registrar. So
-- quando TODOS os gemeos dizem `falta` e' que nao ha o que relatar.
--
-- Efeito colateral bom: `status_presenca` e `chamada_feita` deixam de depender
-- de qual gemeo o Emusys sorteou como ancora.

create or replace view public.vw_registro_pendencia as
 select ae.professor_id,
    ae.professor_nome,
    ae.unidade_id,
    ae.id as aula_ancora_id,
    alvo.id as aula_alvo_id,
    ae.data_aula,
    ae.data_hora_inicio,
    ae.data_hora_fim,
    ae.curso_nome,
    fn_curso_base(ae.curso_nome::text) as curso_base,
    ae.turma_nome,
    ae.tipo,
    r.aluno_id,
    al.nome as aluno_nome,
    split_part(btrim(al.nome::text), ' '::text, 1) as aluno_primeiro_nome,
    -- resolvido entre TODOS os gemeos do horario, nao so o da ancora (buraco B)
    pres.status_presenca,
    pres.chamada_feita,
    floor(extract(epoch from now() - ae.data_hora_fim) / 86400::numeric)::integer as dias_em_atraso,
    ae.data_aula >= fn_data_corte_cobranca() as cobravel,
    -- coluna nova, no fim (create or replace so aceita acrescimo no fim):
    -- "tem plano no Emusys mas falta o relato" — pra mensagem nao acusar
    -- injustamente quem escreveu no sistema antigo
    nullif(btrim(coalesce(alvo.anotacoes, ''::text)), ''::text) is not null as tem_plano_emusys
   from aulas_emusys ae
     join aula_alunos_emusys r on r.aula_emusys_id = ae.id
     join alunos al on al.id = r.aluno_id
     join lateral ( select coalesce(( select i.id
                   from aulas_emusys i
                     join aula_alunos_emusys ri on ri.aula_emusys_id = i.id and ri.aluno_id = r.aluno_id
                  where i.tipo::text = 'individual'::text and i.unidade_id = ae.unidade_id and i.data_hora_inicio = ae.data_hora_inicio and not i.professor_id is distinct from ae.professor_id and coalesce(i.cancelada, false) = false
                  order by i.id
                 limit 1), ae.id) as id) alvo_id on true
     join aulas_emusys alvo on alvo.id = alvo_id.id
     -- ── presenca resolvida entre os gemeos (buraco B) ──────────────────────
     -- `bool_or(presente)` e' a afirmacao vencendo o silencio. Sem linha
     -- nenhuma, `chamada_feita` = false e `status_presenca` = null, exatamente
     -- como o LEFT JOIN antigo devolvia.
     join lateral (
       select count(*) > 0 as chamada_feita,
              case when bool_or(g.st = 'presente'::text) then 'presente'::text
                   when count(*) > 0                     then 'falta'::text
                   else null::text end as status_presenca
         from ( select ap2.status_presenca as st
                  from aulas_emusys gem
                  join aluno_presenca ap2
                    on ap2.aula_emusys_id = gem.id and ap2.aluno_id = r.aluno_id
                 where gem.unidade_id = ae.unidade_id
                   and gem.data_hora_inicio = ae.data_hora_inicio
                   and not gem.professor_id is distinct from ae.professor_id
                   and coalesce(gem.cancelada, false) = false ) g
     ) pres on true
  where (ae.tipo::text = 'turma'::text or not (exists ( select 1
           from aulas_emusys t
          where t.tipo::text = 'turma'::text and t.unidade_id = ae.unidade_id and t.data_hora_inicio = ae.data_hora_inicio and not t.professor_id is distinct from ae.professor_id and coalesce(t.cancelada, false) = false)))
    and ae.professor_id is not null
    and coalesce(ae.cancelada, false) = false
    and ae.data_hora_fim < now()
    -- so' fica de fora quem NAO esteve em nenhum gemeo. Sem linha de presenca
    -- alguma, a aula continua cobravel: "nao lancado" nunca foi falta.
    and coalesce(pres.status_presenca, 'presente'::text) <> 'falta'::text
    -- ── buraco A: `anotacoes` (plano do Emusys) nao e' mais registro ────────
    and nullif(btrim(coalesce(alvo.anotacoes_fabio, ''::text)), ''::text) is null;

comment on view public.vw_registro_pendencia is
  'Aulas que aconteceram e ainda nao tem RELATO do professor (anotacoes_fabio). '
  'O plano do Emusys (anotacoes) NAO conta como relato — ver tem_plano_emusys. '
  'Presenca resolvida entre todos os gemeos do horario: afirmacao vence silencio.';

-- ── a mensagem ganha o numero honesto ──────────────────────────────────────
-- `aulas_com_plano_emusys` existe pra cobranca poder ser justa com quem
-- escreveu no sistema antigo. Sem ele, o professor que colou plano em 59 aulas
-- recebe "59 aulas sem registro" e conclui, com razao, que o Fabio nao le nada.
create or replace function public.fn_pendencias_do_professor(p_professor_id integer, p_incluir_passivo boolean default false)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with p as (
    select * from public.vw_registro_pendencia
     where professor_id = p_professor_id
       and (p_incluir_passivo or cobravel)
  ), por_aula as (
    select
      p.aula_ancora_id, p.data_aula, p.data_hora_inicio,
      to_char(p.data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI') as hora,
      p.curso_nome, p.turma_nome, p.tipo,
      max(p.dias_em_atraso) as dias_em_atraso,
      bool_and(p.chamada_feita) as chamada_feita,
      bool_or(p.tem_plano_emusys) as tem_plano_emusys,
      count(*) as n_alunos,
      jsonb_agg(jsonb_build_object(
        'aluno_id', p.aluno_id,
        'nome', p.aluno_nome,
        'primeiro_nome', p.aluno_primeiro_nome,
        'aula_alvo_id', p.aula_alvo_id
      ) order by p.aluno_nome) as alunos
    from p group by 1,2,3,4,5,6,7
  )
  select jsonb_build_object(
    'professor_id', p_professor_id,
    'total_aulas',  (select count(*) from por_aula),
    'total_alunos', (select coalesce(sum(n_alunos),0) from por_aula),
    'pior_atraso_dias', (select coalesce(max(dias_em_atraso),0) from por_aula),
    'aulas_com_plano_emusys',
      (select count(*) from por_aula where tem_plano_emusys),
    'aulas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'aula_id', a.aula_ancora_id,
        'data', a.data_aula,
        'hora', a.hora,
        'curso', a.curso_nome,
        'turma', a.turma_nome,
        'dias_em_atraso', a.dias_em_atraso,
        'chamada_feita', a.chamada_feita,
        'tem_plano_emusys', a.tem_plano_emusys,
        'n_alunos', a.n_alunos,
        'alunos', a.alunos
      ) order by a.data_hora_inicio desc)
      from por_aula a), '[]'::jsonb)
  )
$function$;
