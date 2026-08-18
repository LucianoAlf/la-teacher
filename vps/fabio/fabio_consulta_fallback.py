"""Passada A — a rede de segurança da consulta letiva.

CONTRATO (Alf, 18/08/2026): o determinístico roda primeiro; A só entra quando
ele volta vazio. O modelo diz O QUE consultar — nunca DE QUEM. `professor_id`
nasce da linha, no bridge, e **não existe campo para ele aqui**.

Este módulo é puro de propósito: nem rede, nem banco, nem relógio. Quem chama o
modelo e quem dispara a RPC é o bridge. Assim dá para atacar a fronteira em
teste sem subir nada — mesma escolha de `montar_chamada_consulta`.

O prompt curto NÃO é economia. Medido em 18/08/2026: com o prompt cheio (12.024
chars) a passada A inventou o campo `aulas_ministradas` e devolveu
`professor_id`; com 424 chars saiu o schema exato, 4/4. Encolher rendeu só 0,6s
— o ganho todo foi obediência. Ver
`docs/superpowers/specs/2026-08-18-passada-a-fallback-consulta-letiva.md`.
"""
from __future__ import annotations

import json
import re
import unicodedata
from datetime import date
from typing import Any

# Item 10 do contrato: schema fechado. Chave fora daqui rejeita o payload.
CAMPOS_PERMITIDOS = frozenset({"consulta", "inicio", "fim", "unidade"})

_CONSULTA_PARA_METRICA = {"aulas_periodo": "aulas", "presencas_periodo": "presencas"}
_JANELA_MAXIMA_DIAS = 92
_DERIVA_MAXIMA_DIAS = 730          # data a mais de 2 anos de hoje é alucinação


def _norm(valor: Any) -> str:
    bruto = str(valor or "").lower()
    bruto = "".join(c for c in unicodedata.normalize("NFKD", bruto)
                    if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", bruto).strip()


# ── O gate ────────────────────────────────────────────────────────────────────
#
# Largo de propósito: quem decide de verdade é `validar_pedido`, e o custo de um
# falso alarme é A devolver "nenhuma". Mas NÃO pode abrir para registro de aula.
# Medido no corpus de 60 dias (165 mensagens de professor): das 30 que só um
# gate largo pegaria, a maioria é registro — "quero registrar a aula de piano T,
# turma P_QUI_19, do dia 6 de agosto". Rodar A ali é ~7s de custo no exato
# momento em que o professor quer gravar a aula.
_FALA_DO_PROPRIO_TRABALHO = re.compile(
    r"\baula|\bturma|\baluno|\bfalta|\bpresenc|\bdei\b|\btrabalh|\bministr")
_SINAL_DE_CONTA_OU_TEMPO = re.compile(
    r"\bquant|\btotal|semana|\bmes\b|\bmeses\b|ontem|hoje|passad|retrasad|"
    r"\bdia \d|\bde \d|\bjaneiro|\bfevereiro|\bmarco|\babril|\bmaio|\bjunho|"
    r"\bjulho|\bagosto|\bsetembro|\boutubro|\bnovembro|\bdezembro")
# Registro tem verbo de AÇÃO sobre a aula; consulta tem verbo de pergunta.
_E_REGISTRO = re.compile(
    r"\bregistr|\blancar\b|\blanca\b|\bgravar\b|\bgrava\b|\banotar\b|\bmarcar\b")
# Pedido pedagógico ("me ajuda na aula da X") não é consulta de vida letiva.
_E_PEDIDO_PEDAGOGICO = re.compile(r"\bme ajuda|\bplano de|\bsugest|\bdica\b|\bideia")


def deve_tentar_fallback(texto: str) -> bool:
    """Vale gastar a passada extra nesta mensagem?

    Chamado SÓ depois de o determinístico voltar vazio (item 3 do contrato).
    """
    hay = _norm(texto)
    if not hay:
        return False
    if _E_REGISTRO.search(hay) or _E_PEDIDO_PEDAGOGICO.search(hay):
        return False
    return bool(_FALA_DO_PROPRIO_TRABALHO.search(hay)
                and _SINAL_DE_CONTA_OU_TEMPO.search(hay))


# ── O prompt ──────────────────────────────────────────────────────────────────
#
# Curto, schema fechado, e sem a palavra "professor" em lugar nenhum: o modelo
# não pode ser convidado a preencher um campo de identidade que não existe.
_PROMPT = (
    'Hoje e {hoje}. Leia a mensagem abaixo e devolva SO um JSON, sem texto antes '
    'ou depois, exatamente com estas chaves:\n'
    '{{"consulta":"aulas_periodo|presencas_periodo|nenhuma",'
    '"inicio":"AAAA-MM-DD","fim":"AAAA-MM-DD","unidade":null}}\n'
    'Use "nenhuma" se nao for pergunta sobre aulas dadas ou faltas/presencas, '
    'ou se o periodo nao estiver claro. Nao crie outras chaves.\n'
    'Mensagem: {texto}'
)


def montar_prompt_pedido(texto: str, hoje: date) -> str:
    return _PROMPT.format(hoje=hoje.isoformat(), texto=str(texto or "")[:400])


# ── A validação (a fronteira) ─────────────────────────────────────────────────

_CERCA = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.S)


def _so_o_json(bruto: str) -> Any:
    texto = str(bruto or "").strip()
    cerca = _CERCA.match(texto)
    if cerca:
        texto = cerca.group(1)
    try:
        return json.loads(texto)
    except (ValueError, TypeError):
        return None


def _data(valor: Any) -> date | None:
    if not isinstance(valor, str):
        return None
    try:
        return date.fromisoformat(valor.strip())
    except ValueError:
        return None      # "2026-02-30" nao existe; nao vira data torta


def validar_pedido(bruto: str, hoje: date, unidades: list[str]) -> dict[str, Any] | None:
    """O pedido do modelo vira consulta, ou vira None.

    None NUNCA é silêncio: quem chama pergunta o período ao professor (item 8).
    É por isso que rejeitar sai barato — o pior caso é o Fábio perguntar, que é
    o comportamento honesto de sempre.
    """
    dados = _so_o_json(bruto)
    if not isinstance(dados, dict):
        return None

    # Item 9/10: schema fechado. Chave fora do contrato REJEITA o payload
    # inteiro — não "limpa e segue". Limpar faria funcionar e esconderia que o
    # modelo desobedeceu, que é justamente o que precisa aparecer no log.
    if set(dados) - CAMPOS_PERMITIDOS:
        return None

    consulta = dados.get("consulta")
    if consulta == "nenhuma":
        return None                      # não é falha: A dizendo que não era consulta
    metrica = _CONSULTA_PARA_METRICA.get(consulta if isinstance(consulta, str) else "")
    if metrica is None:
        return None

    inicio, fim = _data(dados.get("inicio")), _data(dados.get("fim"))
    if inicio is None or fim is None or inicio > fim:
        return None
    if (fim - inicio).days + 1 > _JANELA_MAXIMA_DIAS:
        return None
    if abs((inicio - hoje).days) > _DERIVA_MAXIMA_DIAS or abs((fim - hoje).days) > _DERIVA_MAXIMA_DIAS:
        return None

    # Unidade só passa se for uma unidade REAL. Texto livre do modelo vira None:
    # consulta sem recorte é honesta; consulta com recorte inventado mente.
    unidade = None
    pedida = _norm(dados.get("unidade"))
    if pedida:
        for nome in unidades or []:
            if _norm(nome) == pedida:
                unidade = nome
                break

    return {"metrica": metrica, "inicio": inicio, "fim": fim, "unidade": unidade}


def motivo_da_recusa(bruto: str) -> str:
    """Rótulo curto pro log. Nunca devolve o texto do modelo inteiro."""
    dados = _so_o_json(bruto)
    if not isinstance(dados, dict):
        return "nao_e_json"
    extras = set(dados) - CAMPOS_PERMITIDOS
    if any("professor" in _norm(chave) for chave in extras):
        return "tentou_escolher_identidade"
    if extras:
        return f"campo_fora_do_schema:{sorted(extras)[0][:32]}"
    if dados.get("consulta") == "nenhuma":
        return "modelo_disse_que_nao_e_consulta"
    return "valores_invalidos"
