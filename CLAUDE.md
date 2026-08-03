# LA Teacher — contexto que não pode se perder

## O Fábio é meu

Em **03/08/2026** o Alf passou o bastão: o Alfredo saiu para outras frentes e **eu sou o dono do Fábio** (Hermes + chat bridge). Não existe mais "eu aponto, o Alfredo aplica" — eu aplico.

Antes disso o combinado era read-only, e essa memória velha já me fez recusar trabalho que era meu. Se bater a dúvida "será que eu posso mexer?": pode.

## Acesso à VPS (o que eu já esqueci uma vez)

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186
```

⚠️ **A chave é essa.** Não é a `id_ed25519` padrão, e o `~/.ssh/config` **não** tem entrada para ela — o host `lahq` do config aponta para `root` com outra chave. Sem `-i` explícito o login falha com `Permission denied (publickey,password)`, e é fácil concluir errado que não tenho acesso. Já aconteceu.

Auditado em 03/08/2026: usuário `fabio`, host `la-hq`, grupos `fabio users`.

**O que eu posso:** ler e **escrever** em tudo sob `~` (dono é `fabio:fabio`), e **parar/iniciar os serviços** — eles são *user services* do systemd, então não precisa de sudo:

```bash
systemctl --user restart fabio-hermes-gateway.service
systemctl --user restart fabio-chat-bridge.service
```

**O que eu não posso:** `sudo` (pede senha). Nada fora de `~` precisa ser tocado.

## Mapa da VPS

| Caminho | O que é |
|---|---|
| `~/.hermes/` | O cérebro. `.env`, `config.yaml`, `SOUL.md`, `PERMISSOES.md`, `AGENTS.md` |
| `~/.hermes/skills/` | **Sistema de skills já existe.** A da casa é `la-music`; o resto é genérico |
| `~/.hermes/hermes-agent/skills/` + `optional-skills/` | Skills do agente |
| `~/.hermes/.skills_prompt_snapshot.json` | Snapshot do prompt montado a partir das skills (~44 KB) |
| `~/fabio-chat-bridge/` | Ponte app ↔ WhatsApp (a fila do chat) |
| `~/la-teacher/` | Cópia do repo na VPS |
| `~/backups/`, `~/.hermes/backups/` | Backups — o `.env` e o `config.yaml` têm histórico de `.bak` |

## O banco é compartilhado

LA Teacher, Fábio, Sol e LA Report vivem no **mesmo projeto Supabase**: `ouqwbbermlzqqvtqwlul` (LA Performance Report). A edge function `fabio-registro-aula` é publicada de lá, e o motor de relatório (`gerar-relatorio-pedagogico`) também. Juntar dados entre esses sistemas é SQL, não integração.

`pg_cron` 1.6.4 e `pg_net` 0.19.5 estão instalados, e o padrão da casa para rotina é cron → `net.http_post` → edge function (ver `processar-conversa-evasao-cada-minuto`).
