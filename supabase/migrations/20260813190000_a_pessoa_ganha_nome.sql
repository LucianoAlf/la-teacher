-- SUPERADA POR: 20260813215959_mata_a_view_duplicada.sql
--
-- Esta migration criou `vw_aluno_pessoa` -- que era DUPLICATA. A casa ja tinha
-- `vw_aluno_identidade_unidade_canonica` (com uma coluna `pessoa_chave`, o
-- mesmo nome) e `vw_professor_carteira_pessoa_canonica_sombra`. Os numeros
-- batiam exatamente, entao a minha nao acrescentava nada.
--
-- A 20260813215959 apagou a view e repontou a RPC para a canonica. Replayar
-- este arquivo RESSUSCITARIA a duplicata -- por isso ele fica marcado.
--
-- O raciocinio sobre a CHAVE (por que `(unidade_id, emusys_student_id)` e nao
-- o id sozinho, e por que `data_nascimento` nao entra) segue valido e esta
-- preservado abaixo como registro da auditoria.

-- A pessoa ganha nome
--
-- O QUE ESTAVA FALTANDO. `public.alunos` nao e uma tabela de pessoas: a unica
-- chave unica dela alem da PK e
-- `UNIQUE (telefone, unidade_id, nome, curso_id)` -- com `curso_id` DENTRO.
-- Ou seja, o grao declarado e PESSOA x CURSO. Quem faz dois cursos tem que
-- virar duas linhas, por contrato da propria tabela.
--
-- Isso nao e defeito: a vida do aluno no Canto e no Teclado sao diferentes
-- mesmo (outro professor, outro repertorio, outra frequencia), e fundir as
-- duas destruiria o diagnostico que a coordenacao precisa. O buraco e outro:
-- **nao existia nada dizendo que duas linhas sao a mesma pessoa.**
--
-- Medido em 13/08/2026, na carteira do professor 25:
--   `aluno_id 265`  -> Luiza, Teclado -> 44 presencas, health_score 'saudavel'
--   `aluno_id 1465` -> Luiza, Canto   -> 65 presencas, health_score NULO
-- Uma crianca so, partida em duas. Metade verde, metade sem nota. Quem abrisse
-- "a Luiza" via a metade em que caiu.
--
-- A CHAVE, E POR QUE ELA E ESTA. Cruzado com a API do Emusys ao vivo:
--   `3183` @ CG      -> UMA Luiza com 2 matriculas
--   `1001` @ BARRA   -> Pietro Matola Abreu
--   `1001` @ RECREIO -> Julia Salarini Gama
-- Os IDs do Emusys sao POR UNIDADE. Entao:
--   * `emusys_student_id` SOZINHO nao serve -- funde 89 pessoas diferentes
--     (1.400 viram 1.311). Juntaria o Pietro com a Julia.
--   * o par `(unidade_id, emusys_student_id)` e exato: dos 224 grupos
--     duplicados, 137 sao mesma unidade (mesma pessoa) e 87 sao unidades
--     diferentes (pessoas diferentes). ZERO grupos de mesma unidade apontam
--     para pessoas distintas.
--   * `data_nascimento` NAO entra na chave: acrescenta-la mantem os mesmos
--     1.400. Ela vale como assercao de sanidade, nao como identidade.
--
-- A SAIDA CONSERVADORA IMPORTA. 16 alunos ativos nao tem `emusys_student_id`.
-- Se a chave fosse o par cru, `(unidade, null)` fundiria os 16 numa pessoa so
-- por unidade -- trocando um erro de contagem por outro, pior, que junta
-- criancas sem relacao. Quem nao tem id continua sendo ele mesmo.
--
-- ESTE ARQUIVO E ADITIVO. Nao muda nenhuma linha, nenhuma FK e nenhum grao.
-- 53 tabelas apontam para `alunos`; mexer no grao seria migracao de meses.
-- Aqui so se da NOME ao que ja existe.

create or replace view public.vw_aluno_pessoa
with (security_invoker = true)
as
select
  a.id            as aluno_id,
  a.unidade_id,
  nullif(btrim(coalesce(a.emusys_student_id, '')), '') as emusys_student_id,
  a.curso_id,
  a.nome,
  a.data_nascimento,
  a.arquivado_em,
  case
    when nullif(btrim(coalesce(a.emusys_student_id, '')), '') is not null
      then 'emusys:' || a.unidade_id::text || ':' || btrim(a.emusys_student_id)
    else 'cadastro:' || a.id::text
  end             as pessoa_chave,
  (nullif(btrim(coalesce(a.emusys_student_id, '')), '') is null) as pessoa_sem_identidade_emusys
from public.alunos a;

comment on view public.vw_aluno_pessoa is
  'Diz QUEM e a pessoa por tras de cada linha de alunos, sem mudar o grao '
  'pessoa x curso da tabela. pessoa_chave usa (unidade_id, emusys_student_id) '
  'porque os IDs do Emusys sao por unidade -- o id sozinho fundiria 89 pessoas '
  'diferentes. Quem nao tem id do Emusys vira chave propria, para nunca juntar '
  'criancas sem relacao.';

revoke all on table public.vw_aluno_pessoa from public, anon, authenticated;

-- Contagem honesta da carteira: PESSOAS, nao linhas.
--
-- Existe porque hoje o Fabio recebe a lista crua e o MODELO conta. Ele vem
-- acertando (20, 20, 20 em tres perguntas), mas contar lista nao e contrato:
-- numa carteira maior, ou com duplicata de grafia diferente, nada garante o
-- numero. Aqui o numero e calculado.
create or replace function public.app_professor_carteira_contagem(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select jsonb_build_object(
    'professor_id',  p_professor_id,
    'pessoas',       count(distinct p.pessoa_chave),
    'matriculas',    count(distinct c.aluno_id),
    'linhas',        count(*),
    'sem_identidade_emusys', count(distinct p.pessoa_chave)
                              filter (where p.pessoa_sem_identidade_emusys)
  )
  from public.vw_fabio_carteira_professor c
  join public.vw_aluno_pessoa p on p.aluno_id = c.aluno_id
  where c.professor_id = p_professor_id;
$function$;

comment on function public.app_professor_carteira_contagem(integer) is
  'Carteira contada por PESSOA (decisao do Alf em 13/08/2026), nao por '
  'matricula nem por linha. Devolve os tres numeros juntos de proposito: '
  'quando eles divergirem, a diferenca e informacao (aluno multi-curso), '
  'nao erro.';

-- Porta de worker: quem chama e a ponte do Fabio. Um professor autenticado
-- nao pode consultar a carteira de OUTRO professor, e esta funcao aceita
-- p_professor_id livre -- por isso ela nao vai para `authenticated`. Se a tela
-- do professor precisar do numero, a porta e outra, derivando de auth.uid()
-- via fn_professor_do_usuario().
revoke all on function public.app_professor_carteira_contagem(integer)
  from public, anon, authenticated;
grant execute on function public.app_professor_carteira_contagem(integer)
  to service_role;
