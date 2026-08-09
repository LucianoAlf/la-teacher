"""Toolset `skills_leitura` — as skills sem a ferramenta que ESCREVE nelas.

POR QUE ISSO EXISTE
-------------------
As regras do Fabio (personalidade, roteamento, guardrails) moram em arquivos
SKILL.md. O toolset nativo `skills` empacota TRES ferramentas:

    skills_list  (lista)   skill_view  (le/carrega)   skill_manage  (ESCREVE)

`skill_manage` aceita create/patch/edit/delete/write_file/remove_file. No canal
do professor (api_server, por onde passa toda mensagem de WhatsApp) isso quer
dizer que um professor pode, em tese, convencer o Fabio a reescrever o proprio
manual de regras. E diferente de um vazamento: a edicao FICA, e passa a valer
para todos os professores dali em diante. Injecao persistente.

POR QUE NAO AS ALTERNATIVAS
---------------------------
- Pedir confirmacao: arXiv 2510.26328 mostra que uma aprovacao benigna com
  "nao perguntar de novo" TRANSBORDA para acoes proximas e nocivas. Garantia
  falsa.
- Escanear a skill: nao funciona por definicao -- "Agent Skills are all
  instructions"; e escanear com LLM herda o jailbreak do proprio scanner.
- Tirar o toolset `skills` inteiro: levaria junto o `skill_view`, que e a
  ferramenta MAIS usada do canal (113 chamadas). O Fabio tem 77 skills e as
  carrega dinamicamente conforme a conversa -- e isso NAO pode quebrar.
- Deixar os arquivos somente-leitura: trava lateral, falha confusa, e a
  ferramenta continua no menu do modelo.

O que sobra, e o que a pesquisa sustenta, e REMOVER A CAPACIDADE. E a mesma
forma que o proprio Hermes esta construindo (issue #33905 -> #21849, PR #61792):
politica por actor/plataforma x ferramenta x decisao.

QUANDO O HERMES TIVER ISSO NATIVO, ESTE PLUGIN PODE MORRER.
Trocar por config e tirar `skills_leitura` do platform_toolsets.api_server.

MODO DE FALHA
-------------
Se o registro falhar, `skills_leitura` nao existe e o canal do professor fica
SEM ferramenta de skill nenhuma -- o Fabio perde a personalidade, mas continua
sem poder escrever. Degrada fechado, nao aberto. Por isso o erro e gritado no
log em vez de engolido.
"""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

NOME = "skills_leitura"
FERRAMENTAS = ["skills_list", "skill_view"]


def register(ctx) -> None:
    try:
        from toolsets import create_custom_toolset, resolve_toolset

        create_custom_toolset(
            name=NOME,
            description=(
                "Skills somente leitura: lista e carrega skill, nao cria, "
                "edita nem apaga. Para canais nao confiaveis."
            ),
            tools=list(FERRAMENTAS),
        )

        # Prova na hora do boot: se o toolset nao resolver exatamente para as
        # duas de leitura, alguem mexeu nos nomes das ferramentas e o gate
        # deixou de valer. Melhor gritar aqui do que descobrir em producao.
        resolvido = set(resolve_toolset(NOME))
        if resolvido != set(FERRAMENTAS):
            logger.error(
                "la-skills-leitura: toolset %s resolveu para %s, esperado %s",
                NOME, sorted(resolvido), sorted(FERRAMENTAS),
            )
        elif "skill_manage" in resolvido:
            logger.error("la-skills-leitura: skill_manage vazou para %s", NOME)
        else:
            logger.info("la-skills-leitura: toolset %s registrado (%s)",
                        NOME, ", ".join(sorted(resolvido)))
    except Exception:
        logger.exception("la-skills-leitura: FALHOU ao registrar o toolset %s", NOME)
