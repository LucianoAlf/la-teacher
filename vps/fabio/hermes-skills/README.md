# Espelho das skills do Fábio

> **Cópia, não fonte.** A skill que vale é a que está na VPS, em
> `~/.hermes/skills/la-music/<nome>/SKILL.md`. Isto aqui existe pra que uma
> mudança de comportamento do Fábio apareça no `git log` e possa ser auditada
> pelo Alfredo — igual a `vps/fabio/*.py` e ao
> `hermes-platform-toolsets.yaml.txt`.

Antes de 09/08/2026 as skills viviam **só** na VPS. Uma edição de skill muda o
que o Fábio responde pro professor, exatamente como um deploy de código —
e não deixava rastro nenhum.

## Como sincronizar

Depois de editar na VPS, traga de volta:

```bash
scp -i ~/.ssh/id_ed25519_lahq_fabio_claude_code \
  fabio@89.116.73.186:'~/.hermes/skills/la-music/chat-fabio-la-music/SKILL.md' \
  vps/fabio/hermes-skills/chat-fabio-la-music/SKILL.md
```

⚠️ **O sentido é VPS → repo.** Não copie o repo por cima da VPS sem conferir
antes: outra sessão (ou o próprio Hermes) pode ter mexido lá, e um `scp` na
direção errada apaga a mudança de outra pessoa em silêncio. Sempre `diff`
primeiro.

## O que está espelhado

| Skill | Governa |
|---|---|
| `chat-fabio-la-music` | a conversa livre 1:1 com o professor (app + WhatsApp) — personalidade, roteamento de intenção, guardrails e, desde 09/08, a seção do **Feedback do mês** |

As outras skills da casa (`briefing-pedagogico`, `cobrar-registro-aula`,
`governanca-presenca-fabio`, `consultar-prontuario-aluno`,
`registro-aula-audio`) ainda vivem só na VPS. Espelhar cada uma na primeira
vez que for editada.

## O que NÃO fica aqui

O prompt não é só a skill. O bloco `ESCOPO_PROFESSOR` — que é quem de fato
segura a fronteira entre professor e coordenação — mora no
`fabio_chat_bridge.py:1510`, e esse já tem espelho em `vps/fabio/`. O
`.skills_prompt_snapshot.json` da VPS carrega só as **descrições** das skills,
não o corpo: mudar o corpo não exige regenerar o snapshot, mudar o
`description:` do frontmatter exige.
