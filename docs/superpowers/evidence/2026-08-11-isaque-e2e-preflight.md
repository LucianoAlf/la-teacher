# Prévia do E2E — Isaque

Captura: 11/08/2026 23:11:27 UTC

## Alvo escolhido

- Professor: `professor_id=10`.
- Aula raiz: `aula_id=202642`, Teclado T, turma `T_Sáb_11`, 08/08/2026 11:00.
- Alvos individuais relacionados: `202643` e `202644`.
- Roster: dois alunos (`aluno_id=964` e `aluno_id=974`).

## Estado antes do áudio

- `fabio_registros_aula`: zero para a aula raiz e os alvos individuais.
- `fabio_fila_audios`: zero para esses alvos.
- `fabio_acoes_pendentes`: nenhuma ação ativa do professor 10.
- `fabio_notificacoes` do tipo `registro_recibo`: zero.
- Mensagens outbound do Fábio para o professor: zero no snapshot.
- Já existem linhas de presença fortes vindas do Emusys para os alvos; elas
  foram somente lidas e serão preservadas para provar a guarda contra
  over-marking e a sincronização dos gêmeos.

## Proteções ativadas

- O `.env` original foi copiado para o backup remoto protegido
  `/home/fabio/fabio-chat-bridge/backups/20260811-registro-recibo-g8-20260811230107/fabio.env.before-e2e`.
- O único valor alterado foi `FABIO_REGISTRO_RECIBO_MODE=pilot`; a allowlist
  existente não foi ampliada.
- O worker foi corrigido para percorrer somente a allowlist quando o timer não
  recebe `--professor-id` (`fcdf679`) e foi recompilado/publicado na VPS.
- Dois ciclos posteriores do timer terminaram sem itens e sem envio.

O teste funcional ainda não começou: aguarda o áudio real do professor para
esta aula. Nenhum registro, fila, notificação ou mensagem foi criado por este
preflight.
