# `vps/fabio` — o que roda na VPS do Fábio

Espelho versionado dos scripts que vivem em `fabio@89.116.73.186:~/fabio-chat-bridge/`.
O repo é a fonte de leitura; **a VPS é onde executa**. Ao editar aqui, subir com `scp`.

| Arquivo | O que é | Onde roda |
|---|---|---|
| `fabio_auditoria.py` | Auditoria: diagnostica, **conserta o que dá**, reporta o resto | `fabio-auditoria.timer` → 7h e 21h (BRT) |
| `hermes-platform-toolsets.yaml.txt` | Fragmento do `~/.hermes/config.yaml`: **a fronteira entre professor e admin** | gateway do Hermes |
| `hermes-plugins/la-skills-leitura/` | Plugin que registra o toolset `skills_leitura` (skill sem `skill_manage`) | `~/.hermes/plugins/` |

## A fronteira professor × admin é o CANAL (09/08/2026)

O gateway **não sabe quem está perguntando**: `run_hermes_api` manda só
`{model, messages, stream}`. Então toda ferramenta ligada no `api_server` está
ligada para qualquer professor — e por isso a fronteira não pode ser uma
instrução dentro do prompt.

Quem sabe a identidade é o **bridge**, que resolveu o telefone contra o banco
(`fabio_identidade_whatsapp`) antes de existir prompt. `generate_answer()` usa
esse dado — que o modelo não consegue influenciar — para escolher o canal:

| Identidade | Canal | O que alcança |
|---|---|---|
| `professor` | `api_server` (8652) | `memory, skill_view, skills_list, todo, vision_analyze` — e nada mais |
| `admin` | `cli` oneshot | tudo, inclusive o `lareport` (SQL) e `skill_manage`. ~11s a ~140s |

O professor **carrega** skill (são 77, escolhidas na conversa) mas não **escreve**
nelas — `skill_manage` só existe no canal admin. O porquê está no cabeçalho do
`hermes-platform-toolsets.yaml.txt`; o resumo é que escrever numa skill é
escrever no próprio guardrail, e isso fica valendo pra todos os professores.

**Não existe fallback do professor para o oneshot.** O caminho `cli` concede
*mais* que o da API (terminal, file, SQL): cair pra lá quando a API falha seria
escalar privilégio exatamente no momento do erro. Falhar devolve a mensagem
para a fila, que é o comportamento certo. `FABIO_HERMES_MODE` e
`FABIO_HERMES_API_FALLBACK_ONESHOT` deixaram de valer para o professor **de
propósito** — eram alavancas para o caminho privilegiado.

O porquê medido está no cabeçalho do `hermes-platform-toolsets.yaml.txt`.

## Auditoria — filosofia

Decisão do Alf (02/08/2026): *"já conserta e traz o que foi corrigido e o que precisa de decisão minha"*.
O relatório **nunca** é lista de tarefa pro Alf. É: o que já foi resolvido sozinho + o que só um humano decide.

**Conserta sozinho** (só operações idempotentes e reversíveis — nada destrutivo):
- serviço caído → `systemctl --user restart`
- áudio parado em `pendente`/`erro` → `fn_fabio_retry_fila()`

**Só reporta** (precisa de humano): timer desarmado, briefing que falhou, áudio preso em
`transcrevendo` (o retry não cobre esse status), registro que não virou presença,
professor passando da régua de 3 dias, disco/RAM apertados.

**Não cobra presença do professor** — a régua é conteúdo (`fabio_pendencias_professor`).

## Comandos

```bash
# rodar à mão (imprime, NÃO envia)
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  "cd ~/fabio-chat-bridge && HERMES_HOME=/home/fabio/.hermes python3 fabio_auditoria.py"
```

Flags: `--send` (envia no WhatsApp) · `--no-fix` (só diagnostica) · `--janela 7h`.

## Envio: DESLIGADO por ora

O `ExecStart` do service **não** usa `--send` — a saída fica no journal
(`journalctl --user -u fabio-auditoria`). Para ligar o envio: definir
`FABIO_AUDIT_WHATSAPP` (número do Alf) no service e acrescentar `--send`.
Regra permanente: **envio real só com OK explícito do Alf.**

## Registro de aula pelo WhatsApp — fluxo e piloto

O fluxo novo fica desligado por padrão:

```dotenv
FABIO_WHATSAPP_REGISTRO_MODE=off
FABIO_WHATSAPP_REGISTRO_PILOT_IDS=
FABIO_WHATSAPP_REGISTRO_MAX_AUDIO_BYTES=26214400
FABIO_REGISTRO_RECIBO_MODE=off
FABIO_REGISTRO_RECIBO_PILOT_IDS=
```

As duas flags `FABIO_REGISTRO_RECIBO_*` acima são exclusivamente valores de
referência desta documentação. **Elas não estão presentes na configuração
runtime ativa enquanto o hard-stop existir** e não foram adicionadas à VPS.

Os modos são `off` (Hermes atual), `shadow` (classifica e mede, sem abrir
ação), `pilot` (somente os `professor_id` da allowlist) e `on` (professores
identificados). Entrada de áudio primeiro grava uma linha idempotente no inbox;
transcrição e upload acontecem somente depois do claim do poller. O bridge chama
apenas as RPCs `fabio_*`; não há SQL direto nem chave service-role em log.

O reconciliador é um ciclo limitado por lease e roda pelo unit/timer
`fabio-whatsapp-reconciler`. Ele faz read-back do registro, deixa o professor
confirmar antes da gravação final e prova no banco a limpeza do Storage antes de
remover um blob.

### G6 — paridade de fonte e congelamento do piloto (11/08/2026)

Há um piloto restrito já configurado na VPS. A allowlist existente não pode ser
ampliada durante esta fase. O recibo posterior à confirmação fica desligado por
padrão nas duas flags acima, e a lista dele deverá copiar a allowlist já ativa
sem revelar os valores.

**Hard-stop atual:** a Edge `fabio-registro-aula` ativa está na versão 17 e
assina o callback com HMAC, mas a fonte legível e versionável do receptor desse
callback não foi localizada no bridge nem no Hermes. Não adicionar flags,
reiniciar o bridge ou rodar novo E2E até localizar e versionar esse consumidor.
O preflight, hash e contrato exigido estão em
`docs/superpowers/evidence/2026-08-11-registro-aula-source-parity.md`.

## Timers do usuário `fabio`

| Timer | Quando | O quê |
|---|---|---|
| `fabio-auditoria.timer` | 7h e 21h BRT | esta auditoria |
| `fabio-briefing-matheus.timer` | 8h BRT | briefing matinal (piloto prof. 25) |
| `fabio-notification-worker.timer` | — | worker genérico (disabled) |
| `fabio-feedback.timer` | 9h30/12h30/15h30 BRT — 3 passes de recuperação, 1 cobrança (criado, **não habilitado**) | cobra o feedback mensal do professor (lembrete/reforço) e entrega a lista de quem não fechou ao grupo da coordenação no dia 1º — ver `fabio-feedback.systemd.txt` |

⚠️ **A VPS roda em UTC.** Os units usam `America/Sao_Paulo` no `OnCalendar`, então o
systemd converte sozinho — mas ao ler `list-timers`, os horários aparecem em UTC.
