"""Detector de promessa que o Fábio não tem como cumprir.

POR QUE ISTO É MÁQUINA E NÃO PROMPT
`CAPACIDADE_PROFESSOR` existe desde 10/08/2026, escrito depois de a professora
Daiana ouvir "deixei o registro organizado e salvo" com ZERO escritas no banco.
Ele começa com "leia antes de prometer qualquer coisa". Mesmo assim, medido em
18/08 sobre as **308 respostas dos últimos 60 dias**, o Fábio prometeu 3 vezes —
e **duas foram depois** desse bloco existir. Prompt é probabilístico; a porta
continua aberta. Esta é a tranca determinística.

O DISCRIMINADOR, e por que ele é verdadeiro
Promessa sobre **consulta** é SEMPRE falsa: não existe, e nunca existiu, caminho
pelo qual o Fábio volte depois com um número. Ou ele responde na hora, ou ele
pergunta. Não há fila de "consultas pendentes".

Promessa sobre **áudio/registro** pode ser verdade — existe fila, existe worker,
existe preview. "Guardei esse áudio aqui, assim que a gente fechar o anterior
ele entra" é uma frase HONESTA, e um detector ingênuo mataria ela junto.

Por isso o objeto da promessa manda, e o estado da fila só é consultado no
segundo caso. Fixtures das duas famílias saíram da fala REAL (ver o teste) —
detector treinado em frase que eu invento passa verde e falha em produção.
"""
from __future__ import annotations

import re
import unicodedata
from typing import Any


def _norm(valor: Any) -> str:
    bruto = str(valor or "").lower()
    bruto = "".join(c for c in unicodedata.normalize("NFKD", bruto)
                    if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", bruto).strip()


# "vou conferir", "eu olho ... e te trago", "te passo", "te mostro".
# NÃO entra "pode deixar": no corpus ele aparece em "pode deixar a Fernanda
# mais à vontade" — frase inocente que um detector guloso mataria.
_COMPROMISSO = re.compile(
    r"\b(?:vou|irei|posso)\s+(?:conferir|verificar|olhar|checar|dar uma olhada|"
    r"buscar|puxar|levantar|consultar|calcular)"
    r"|\beu\s+(?:olho|vejo|confiro|verifico)\b"
    r"|\b(?:ja\s+)?te\s+(?:trago|passo|mando|aviso|retorno|informo|mostro|digo)\b"
    r"|\bte\s+dou\s+um\s+retorno\b"
    r"|\bfico\s+de\s+(?:te\s+)?(?:trazer|passar|avisar)\b")

# Objeto que NUNCA volta depois: número é síncrono ou não é.
_OBJETO_DE_CONSULTA = re.compile(
    r"\btotal\b|\bnumeros?\b|\bdivisao\b|\bquant[oa]s?\b|\bperiodo\b|\bmedia\b|"
    r"\bcontagem\b|\bsoma\b|\bbalanco\b|\bquantidade\b")

# Objeto que PODE voltar depois — se houver fila viva por trás.
_OBJETO_DE_FLUXO = re.compile(
    r"\baudio\b|\bregistro\b|\bpreview\b|\bresumo da aula\b|\bgravar\b|"
    r"\bprocessar\b|\brelatorio\b|\bdevolutiva\b|\bconfirmacao\b")

CONSULTA_DEPOIS = "consulta_depois"
FLUXO_SEM_FILA = "fluxo_sem_fila"


def classificar_promessa(resposta: str, ha_fluxo_pendente: bool) -> dict[str, str] | None:
    """A resposta promete algo que não vai acontecer?

    `ha_fluxo_pendente`: existe áudio na fila / ação viva / registro em
    processamento para este professor AGORA. Quem sabe isso é o bridge.

    Devolve None quando a fala é honesta — inclusive quando ela fala do futuro
    e o futuro existe de verdade.
    """
    hay = _norm(resposta)
    if not hay:
        return None
    compromisso = _COMPROMISSO.search(hay)
    if not compromisso:
        return None

    if _OBJETO_DE_CONSULTA.search(hay):
        # Não depende de estado nenhum: consulta não tem fila. Sempre falsa.
        return {"tipo": CONSULTA_DEPOIS, "gatilho": compromisso.group(0)}

    if _OBJETO_DE_FLUXO.search(hay) and not ha_fluxo_pendente:
        return {"tipo": FLUXO_SEM_FILA, "gatilho": compromisso.group(0)}

    return None
