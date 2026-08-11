# G6 — paridade de fonte do registro unificado

**Data:** 11/08/2026 (BRT)
**Worktree:** `D:\la-teacher-worktrees\fabio-whatsapp`
**Branch:** `codex/fabio-whatsapp`
**Status:** **SOURCE_PARITY_RECORDED — 11/08-G6 operacional concluído; G7 ainda requer autorização própria**

## Escopo desta atualização

Esta atualização resolve a localização e o espelhamento auditável das fontes
ativas do caminho de registro de aula e, em 11/08-G6 operacional, aplica
exclusivamente os dois flags não funcionais de recibo na VPS. Não houve
migration, alteração na Edge ativa `fabio-registro-aula`, mudança de fonte,
envio de WhatsApp, alteração de dados pedagógicos, expansão do piloto nem
restart/reload de serviço.

A única escrita externa de diagnóstico foi uma Edge Function temporária, criada
somente para devolver metadados sanitizados do alvo do callback e excluída
imediatamente após a leitura. Ela não recebeu nem expôs payload, URL bruta,
segredo, credencial ou dado pedagógico; não alterou `fabio-registro-aula`,
dados produtivos ou o fluxo de produção. Nenhum segredo, credencial, telefone
ou URL de callback foi copiado para o repositório.

Os testes SQL `teste:090`, `teste:091` e `teste:092` continuam fora deste
recorte: o runner abre transação no banco produtivo e executa DDL/DML antes do
rollback. A validação desta task é de integridade de fonte e de diff.

## 11/08-G6 operacional — configuração mínima do piloto

Foi feita uma substituição atômica de `/home/fabio/.hermes/.env`, precedida de
pré-validação fail-closed e de backup privado recuperável em
`/home/fabio/fabio-chat-bridge/backups/20260811-registro-unificado/`. O backup
e o arquivo de ambiente ficaram em modo `0600`.

- A origem continuou com `registro_mode=pilot` e uma única ID de piloto; a
  allowlist não foi ampliada.
- Foram gravados exatamente uma vez `FABIO_REGISTRO_RECIBO_MODE=off` e
  `FABIO_REGISTRO_RECIBO_PILOT_IDS`, este último copiado byte a byte da
  allowlist de registro já existente. As duas listas têm contagem `1`; valores
  não foram registrados.
- O read-back sanitizado confirmou: as duas chaves de recibo ocorrem uma vez,
  `recibo_mode=off`, arquivo e backup em `0600` e bridge ativo.
- `MainPID` e o timestamp monotônico de início do
  `fabio-chat-bridge.service` permaneceram iguais antes e depois da escrita.
  Nenhum processo foi reiniciado, recarregado ou sinalizado.

Os flags só passam a ser lidos em um futuro restart explicitamente aprovado.
Esta task não fez esse restart e, portanto, não mudou o comportamento do
processo em execução.

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

**11/08-G6 operacional está concluído.** O backup recuperável existe, o recibo
permanece desligado e a allowlist foi preservada. **G7 permanece proibido** até
uma autorização explícita do próximo gate. Esta atualização não libera
migration, mudança funcional, reinício, novo E2E ou expansão do piloto.
