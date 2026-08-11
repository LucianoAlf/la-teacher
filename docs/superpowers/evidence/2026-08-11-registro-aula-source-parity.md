# G6 — paridade de fonte do registro unificado

**Data:** 11/08/2026 (BRT)
**Worktree:** `D:\la-teacher-worktrees\fabio-whatsapp`
**Branch:** `codex/fabio-whatsapp`
**Status:** **SOURCE_PARITY_RECORDED — G6 operacional ainda não iniciado**

## Escopo desta atualização

Esta atualização resolve somente a localização e o espelhamento auditável das
fontes ativas do caminho de registro de aula. Não houve alteração na VPS,
migration, serviço, flag, piloto, dados pedagógicos, envio de WhatsApp ou na
Edge ativa `fabio-registro-aula`.

A única escrita externa de diagnóstico foi uma Edge Function temporária, criada
somente para devolver metadados sanitizados do alvo do callback e excluída
imediatamente após a leitura. Ela não recebeu nem expôs payload, URL bruta,
segredo, credencial ou dado pedagógico; não alterou `fabio-registro-aula`,
dados produtivos ou o fluxo de produção. Nenhum segredo, credencial, telefone
ou URL de callback foi copiado para o repositório.

Os testes SQL `teste:090`, `teste:091` e `teste:092` continuam fora deste
recorte: o runner abre transação no banco produtivo e executa DDL/DML antes do
rollback. A validação desta task é de integridade de fonte e de diff.

## Edge ativa `fabio-registro-aula`

| Item | Evidência |
|---|---|
| Slug | `fabio-registro-aula` |
| Versão ativa observada | `17` |
| Arquivo auditado | `supabase/functions/fabio-registro-aula/index.ts` |
| SHA-256 da Edge auditada | `B3B062BDD86EEF3AA04081A1C7E0DDE3ADCD79F987600BF26E0C90558DE7BF81` |

A Edge aceita `POST` JSON com `audio_id`, resolve a fila e os identificadores
da aula, cria URL temporária de Storage e envia um callback assinado por HMAC
SHA-256 no cabeçalho `X-Webhook-Signature`. O callback carrega
`audio_id`, `aula_id`, `unidade_id`, `professor_id`, `audio_url` e
`registro_id` (possivelmente nulo). A Edge não contém o receptor, o prompt ou
a normalização pedagógica.

## Caminho ativo do callback, agora correlacionado

```text
Edge fabio-registro-aula
  -> alvo sanitizado: VPS 89.116.73.186:8644
  -> fabio-hermes-gateway.service (systemd --user)
  -> adaptador Webhook genérico do Hermes (valida HMAC)
  -> rota dinâmica registro-aula
  -> skill de registro + ferramenta Python customizada
```

- O alvo do callback usa o host VPS `89.116.73.186` e a porta `8644`, sem
  query nem fragmento, com formato de rota de dois segmentos. A URL completa
  não é registrada.
- O listener da porta é o serviço de usuário `fabio-hermes-gateway.service`,
  não Nginx e não o bridge de conversa.
- A rota dinâmica ativa é `registro-aula`; a configuração tem segredo
  configurado, deliberadamente não exibido, e uma única skill:
  `registro-aula-audio-la-music`.
- O adaptador Webhook genérico valida HMAC antes do despacho para a rota.
- O adaptador é código upstream em
  `~/.hermes/hermes-agent/gateway/platforms/webhook.py`, no checkout Hermes
  observado em `2a10b8384aa2ef0418063ca0829e491c5916fba4`. Ele é referenciado,
  não copiado como se fosse customização do projeto.

## Espelhos exatos e procedência

O runtime continua **VPS-owned**: o repositório é um espelho de auditoria e não
é origem automática de deploy. Antes de qualquer cópia para a VPS, comparar
hashes e diff contra os caminhos vivos; nunca sobrescrever a fonte por reflexo.

| Artefato | Caminho runtime ativo | Espelho versionado | SHA-256 |
|---|---|---|---|
| Ferramenta customizada | `~/.hermes/hermes-agent/tools/fabio_registro_aula_tool.py` | `vps/fabio/hermes-tools/fabio_registro_aula_tool.py` | `c76a3600df7a368c2d9b9a6766e7559dfdaddb035e2c98e79cb167b35efa5e8a` |
| Skill de registro | `~/.hermes/skills/la-music/registro-aula-audio-la-music/SKILL.md` | `vps/fabio/hermes-skills/registro-aula-audio-la-music/SKILL.md` | `145bb5f6cff2bfd3aec753c7a20ddee93481aaff9e0c51e8ea47a82b170427a3` |

A ferramenta Python é um arquivo **untracked** dentro do checkout Hermes da VPS.
Esse é o motivo de ela não ter aparecido no histórico do Hermes; o espelho neste
repositório cria a trilha de auditoria sem mudar o processo em execução.

## Contrato fechado que permanece exigido antes do rascunho

Localizar a fonte não altera o contrato a ser implementado em G7. O consumidor
deve validar, antes de criar ou atualizar rascunho:

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

`aula_id` e cada `aluno_id` vêm exclusivamente da aula e do roster já
resolvidos. Incerteza mantém o campo correspondente nulo ou gera pergunta; não
vira fato de prontuário.

## Próximo gate explícito

**Próximo passo ativo: 11/08-G6 operacional, separado e sujeito à revisão desta
task.** Ele poderá, com autorização própria, comparar os espelhos contra a VPS,
fazer backup recuperável e tratar as flags de recibo sem ampliar a allowlist.

**G7 permanece proibido** até a revisão desta paridade e a conclusão segura do
G6 operacional. Esta atualização não libera migration, mudança funcional,
reinício, novo E2E ou expansão do piloto.
