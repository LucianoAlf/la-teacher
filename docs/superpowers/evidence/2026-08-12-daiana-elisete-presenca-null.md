# Incidente Daiana/Elisete — presença JSON null

## Diagnóstico

Na aula de 11/08/2026 às 16:00 (`aulas_emusys.id=205442`, alvo individual
`205446`), a professora confirmou pelo aplicativo. A raiz foi confirmada, mas
a fatia da Elisete (`680571ed-542a-4ba6-9993-b4c4b6750927`) ficou em
`aguardando_confirmacao` porque `campos.presenca` existia como JSON `null`.
O normalizador antigo testava apenas a existência da chave, embora o core
interpretasse esse valor como `nao_informada`. Portanto, foi bug do fluxo, não
erro de uso da professora.

## Correção publicada

- Migration `20260812135033_fix_presence_json_null_confirmation.sql` passou a
  usar `fn_presenca_declarada(...) = 'nao_informada'` na materialização.
- Presença explícita `presente`/`ausente` permanece preservada.
- Acesso à função continua fechado para `public`, `anon`, `authenticated` e
  `service_role`; owner permanece `postgres`.
- Migration aplicada pelo script definitivo e registrada no histórico remoto.

## Reconciliação da ocorrência

Foi criado backup antes da escrita na VPS:

- antes: `/home/fabio/backups/la-teacher/daiana-elisete-20260812.json`
  (`704fe65638d11c86828a80e9e0df06b1df0fec49ba2bc5f8feaf8e5ed6c6ae41`)
- depois: `/home/fabio/backups/la-teacher/daiana-elisete-20260812-after.json`
  (`9152ca095d15eefbdfd395ae404865052e8a77ea02f2335dc3966f22779a4143`)

A reconciliação foi transacional, com lock e guardas para a raiz
`4ed1ff2a-08e8-4e00-843b-56069e0c8dd5`, a fatia da Elisete e os dois alunos
com falta explícita. O core confirmou a aula sem alterar essas faltas.

## Prova pós-correção

Consulta independente no banco retornou:

- raiz gravada: `true`;
- fatia da Elisete gravada no alvo `205446`: `true`;
- faltas explícitas preservadas: `true`;
- texto na aula-alvo: `true`;
- presença da Elisete: `1`;
- devolutivas: `1`;
- recibos do registro: `1`;
- log do alvo: `1`;
- aula da Elisete ainda pendente: `false`;
- migration no histórico remoto: `1`.

Não houve envio automático à família; o recibo é o carimbo normal destinado à
professora.
