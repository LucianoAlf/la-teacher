# G6 — paridade de fonte e congelamento do piloto de registro unificado

**Data:** 11/08/2026 (BRT)
**Worktree:** `D:\la-teacher-worktrees\fabio-whatsapp`
**Branch:** `codex/fabio-whatsapp`
**Status:** **BLOCKED**

## Escopo cumprido

Esta auditoria foi somente leitura em Git, VPS e Edge. Não houve migration,
alteração de Python/TypeScript/Edge, deploy, envio de WhatsApp, alteração de
dados pedagógicos, leitura de `.env` ou de logs de mensagens.

O `git status --short` estava vazio antes da auditoria. O único diretório
temporário criado para baixar a fonte da Edge será removido antes do commit; a
evidência abaixo mantém apenas o hash verificável.

## Runtime e teste de segurança

- `fabio-chat-bridge.service`: carregado, ativo e em execução.
- `fabio-whatsapp-reconciler.timer`: carregado, ativo e em execução.
- O bridge ativo executa o espelho `fabio_chat_bridge.py` e lê o arquivo de
  ambiente protegido do Hermes. O conteúdo desse arquivo não foi exibido nem
  lido nesta tarefa.
- `npm run teste:090`, `npm run teste:091` e `npm run teste:092` **não foram
  executados**. O runner `scripts/rodar-teste-sql.mjs` abre uma transação no
  projeto produtivo, executa DDL/DML dos SQLs e só então faz `ROLLBACK`.
  Embora tenha guarda de limpeza, isso não é consulta somente leitura e viola
  o limite explícito desta G6.

## Edge ativa `fabio-registro-aula`

| Item | Evidência |
|---|---|
| Slug | `fabio-registro-aula` |
| Versão ativa | `17` |
| Obtenção | `supabase functions download` em diretório temporário local |
| Arquivo | `supabase/functions/fabio-registro-aula/index.ts` |
| SHA-256 | `B3B062BDD86EEF3AA04081A1C7E0DDE3ADCD79F987600BF26E0C90558DE7BF81` |

### Contrato HTTP observado

1. A Edge aceita somente `POST` com JSON contendo `audio_id`; ausência do
   campo recebe erro de cliente.
2. Ela lê a fila de áudio, recusa status fora dos estados de processamento e
   cria uma URL temporária do Storage.
3. O callback recebe JSON com `audio_id`, `aula_id`, `unidade_id`,
   `professor_id`, `audio_url` e `registro_id` (que pode ser nulo).
4. O corpo é assinado com HMAC-SHA-256; a assinatura vai no cabeçalho
   `X-Webhook-Signature`.
5. Qualquer resposta HTTP de sucesso do receptor conclui o envio. Resposta não
   bem-sucedida vira erro da fila na Edge. Não há, nessa fonte, contrato
   estruturado que diferencie erro técnico de erro semântico do normalizador.

## Fonte do receptor: hard-stop

Foi feita busca somente por nomes de arquivos-fonte em `/home/fabio`, incluindo
o bridge e o diretório Hermes, excluindo logs, ambientes, backups, cache Python
e dependências. Procuraram-se as referências ao nome da URL, à rota de registro,
ao callback e à validação HMAC/assinatura. Nenhum arquivo-fonte legível e
versionável foi localizado que:

- receba o `POST` da Edge;
- valide `X-Webhook-Signature`; ou
- monte o payload normalizado que vira rascunho de registro.

O bridge ativo não é prova desse consumidor: ele é o processo de conversa do
WhatsApp. A Edge apenas conhece uma URL configurada; ela não contém o receptor
nem a normalização posterior. Portanto, não é seguro inferir ou recriar esse
trecho do motor.

**Consequência obrigatória:** a G6 para aqui. Não foram adicionadas as flags
`FABIO_REGISTRO_RECIBO_MODE` e `FABIO_REGISTRO_RECIBO_PILOT_IDS`, não houve
backup de configuração, reinício de serviço, expansão de piloto ou novo E2E.
O piloto existente permanece exatamente como estava antes desta auditoria.

**Bloqueio de sequência:** G7 e qualquer task posterior estão proibidos até que
a fonte do receptor HMAC seja localizada e versionada. Nenhum novo gate pode
interpretar este hard-stop como autorização para contorná-lo.

Para retomar, é necessário localizar e versionar a fonte do receptor do
callback (ou fornecer seu repositório e procedimento de deploy), com prova da
validação HMAC e do ponto que materializa o registro normalizado. Só depois
disso é permitido executar o preflight de configuração e adicionar as duas
flags, inicialmente com recibo desligado.

## Contrato fechado exigido antes do rascunho

Quando o receptor versionável existir, ele deve produzir/validar este contrato
antes de qualquer rascunho. Não é uma inferência da Edge atual e não foi
implementado nesta G6:

```json
{
  "registro_id": "uuid",
  "aula_id": 0,
  "professor_id": 0,
  "comum": {
    "objetivo": null,
    "atividades": null,
    "repertorio": null,
    "dever_casa": null,
    "observacoes": null
  },
  "fatias": [
    {
      "aluno_id": 0,
      "progresso": null,
      "repertorio": null,
      "presenca": null
    }
  ],
  "incertezas": [
    {
      "campo": "observacoes",
      "trecho": "..."
    }
  ]
}
```

`aula_id` e cada `aluno_id` devem vir exclusivamente do roster já resolvido.
Uma incerteza mantém o campo correspondente nulo; ela não pode virar fato de
prontuário.

## Preflight pendente para a retomada

1. Identificar o processo, arquivo e repositório do receptor HMAC.
2. Conferir que a fonte é legível, versionável e corresponde à configuração
   ativa, sem exibir valores protegidos.
3. Criar e verificar backup recuperável em
   `/home/fabio/fabio-chat-bridge/backups/20260811-registro-unificado/`.
4. Acrescentar `FABIO_REGISTRO_RECIBO_MODE=off` e copiar a allowlist já ativa
   para `FABIO_REGISTRO_RECIBO_PILOT_IDS`, sem imprimir seus valores.
5. Conferir somente a saída sanitizada: `registro_mode=pilot`,
   `recibo_mode=off` e a contagem de IDs; reiniciar apenas pelo procedimento
   já provado do serviço.

Nenhum desses cinco passos está autorizado antes de remover o hard-stop acima.
