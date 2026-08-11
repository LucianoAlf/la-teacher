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
| `registro-aula-audio-la-music` | o consumo do callback de registro de aula na rota dinâmica `registro-aula`; orienta a ferramenta Python customizada |

As outras skills da casa (`briefing-pedagogico`, `cobrar-registro-aula`,
`governanca-presenca-fabio`, `consultar-prontuario-aluno`) ainda vivem só
na VPS. Espelhar cada uma na primeira vez que for editada.

### Registro de aula — procedência do espelho (11/08/2026)

O espelho `registro-aula-audio-la-music/SKILL.md` corresponde exatamente ao
runtime
`~/.hermes/skills/la-music/registro-aula-audio-la-music/SKILL.md` no momento
da coleta. SHA-256: `145bb5f6cff2bfd3aec753c7a20ddee93481aaff9e0c51e8ea47a82b170427a3`.
Ele é auditável no Git, mas a VPS continua sendo a dona da fonte viva: não
copie este arquivo para ela sem comparar hash e diff.

**Exceção de proveniência byte a byte:** o `SKILL.md` espelhado mantém o
whitespace de fim de linha já presente na fonte viva. Não o normalizar; o
SHA-256 acima é a prova de paridade e qualquer alteração, inclusive de espaços
finais, exige nova coleta e revisão.

## O que NÃO fica aqui

O prompt não é só a skill. O bloco `ESCOPO_PROFESSOR` — que é quem de fato
segura a fronteira entre professor e coordenação — mora no
`fabio_chat_bridge.py:1510`, e esse já tem espelho em `vps/fabio/`. O
`.skills_prompt_snapshot.json` da VPS carrega só as **descrições** das skills,
não o corpo: mudar o corpo não exige regenerar o snapshot, mudar o
`description:` do frontmatter exige.
