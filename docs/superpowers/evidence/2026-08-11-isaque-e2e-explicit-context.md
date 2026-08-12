# E2E simulado do Isaque — contexto explícito de turma e horário

**Data local:** 11/08/2026 21:01 (America/Sao_Paulo)

**Professor:** Isaque (`professor_id=10`)

**Modo:** `FABIO_REGISTRO_RECIBO_MODE=pilot`

## Objetivo

Repetir o teste com um áudio real já existente do Isaque e contexto explícito
no texto de entrada: **Piano T · turma `P_Qui_19` · 19:00**. O alvo fechado
foi a aula `202499`, de 06/08/2026, com um único aluno e alvo individual
canônico `202500`.

O arquivo de áudio foi apenas lido e reutilizado como bytes de teste. A
transcrição adicional com turma/horário foi marcada somente na mensagem
sintética para validar a seleção; ela não substitui a transcrição produzida
pelo motor de áudio.

## Snapshot antes da escrita

- Aula candidata: `202499` — Piano T / `P_Qui_19` / 19:00.
- Roster: aluno `1629`; alvo individual canônico `202500`.
- `fabio_acoes_pendentes` ativas do professor: 0.
- Registros existentes em `202499`/`202500`: 0.
- Fila existente para `202499`/`202500`: 0.
- Fonte: áudio `3e5f79a5-a713-4ef8-8108-5a5be3b65fda`, origem `app`, status
  `normalizado`, aula original `202774`.

## Caminho percorrido

1. Mensagem sintética `e2e-isaque-preview-e42f8d7c768d46e9` foi inserida na
   inbox persistente como áudio WhatsApp, usando os bytes reais da fonte.
2. O bridge classificou como `registro`.
3. A shortlist fechou deterministicamente em `[202499]`; nenhum ID foi
   inventado ou escolhido pelo LLM.
4. O áudio foi enfileirado como origem `whatsapp` e a ação avançou para
   `processando_audio`.
5. A transcrição real terminou, mas o Edge/normalizador recusou a criação do
   rascunho com `fatia_aula_fora_da_sessao`.
6. O reconciliador registrou uma tentativa transitória e encerrou a ação como
   `erro`; não houve registro, preview ou confirmação.

## Evidência final

- Ação: `67a6c2c4-865f-417e-bb82-53afa80b2cfe` — `estado=erro`.
- Áudio WhatsApp: `43093d88-424c-47bc-ba0d-e0a5e2dec3e1` — `status=erro`.
- Erro observado: `RPC recusou o registro: fatia_aula_fora_da_sessao`.
- O banco resolve `fn_aula_individual_do_aluno(202499, 1629)` para `202500`,
  e há roster para as duas aulas.
- O objeto temporário
  `whatsapp/10/e2e-isaque-preview-e42f8d7c768d46e9.webm` foi removido pelo
  reconciliador; a consulta Storage devolveu `NoSuchKey`.
- A fonte original permanece `app/normalizado`, no mesmo caminho e com a
  mesma transcrição.
- Não foi enviado recibo, devolutiva ou mensagem para família.

## Veredicto

O teste validou a porta WhatsApp, a shortlist fechada, o enfileiramento, a
transcrição e a limpeza. **Não validou preview nem confirmação**, porque a
normalização falhou antes de criar o rascunho. O próximo gate deve inspecionar
o payload produzido pelo Edge/normalizador: o erro indica que a fatia chegou à
RPC com um vínculo de aula incompatível com o alvo canônico, mas não se deve
afrouxar a guarda da RPC nem confirmar manualmente este caso.
