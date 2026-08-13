-- A porta que faltava pro agente
--
-- O QUE ACONTECEU. A `20260813190000` criou a contagem honesta da carteira e
-- concedeu execucao ao `service_role`. Dei a instrucao na skill e perguntei ao
-- Fabio: ele respondeu **20 pessoas** (certo) mas, ao ser cobrado dos numeros
-- exatos, disse que "precisa conferir" as matriculas -- se tivesse chamado a
-- RPC, os tres numeros viriam juntos numa tacada.
--
-- Nao era teimosia do modelo: era porta fechada. A ferramenta de banco do
-- Hermes e um `postgres-mcp` que conecta com um papel PROPRIO, `fabio_agent`,
-- e nao com `service_role`. Medido:
--   has_function_privilege('fabio_agent', ..., 'EXECUTE') = false
--
-- POR QUE ISTO NAO ALARGA NADA. O mesmo `fabio_agent` ja tem SELECT em
-- `vw_fabio_carteira_professor`, em `vw_aluno_pessoa` e em `alunos` -- ou seja,
-- ele ja consegue chegar exatamente nos mesmos dados, so que contando na mao e
-- errando o grao. Conceder a funcao nao abre dado novo: **troca o caminho
-- ruim pelo caminho certo**. A funcao e `stable`, so le, e nao aceita escrita.
--
-- A licao que fica: publicar contrato sem conferir QUEM vai chama-lo e o mesmo
-- que nao publicar. O grant tem que mirar o papel real do consumidor, nao o
-- papel que a gente imagina que ele usa.

grant execute on function public.app_professor_carteira_contagem(integer)
  to fabio_agent;
