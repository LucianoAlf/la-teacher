#!/usr/bin/env python3
"""Closed, side-effect-free contracts for the WhatsApp action bridge.

This module deliberately does not call Hermes, Supabase or UAZAPI.  It can
rank evidence, but it never turns a guess into a database write authority.
"""
from __future__ import annotations

import json
import re
import unicodedata
from typing import Any, Literal

AudioIntent = Literal["registro", "conversa", "ambiguo"]
TextIntent = Literal["chamada", "conversa", "ambiguo"]

_AUDIO_INTENTS = {"registro", "conversa", "ambiguo"}
_TEXT_INTENTS = {"chamada", "conversa", "ambiguo"}
_AFFIRMATIVE = {
    "sim", "s", "pode", "confirmo", "confirmado", "confirma", "manda",
    "vamos", "ok", "okay", "certo", "isso", "isso mesmo", "pode gravar",
}
_CANCEL_WORDS = ("cancela", "cancelar", "cancele", "deixa pra la", "deixa isso", "esquece")
_DEFER_WORDS = ("depois", "mais tarde", "outra hora", "amanha", "amanhã")
_PRESENCE_WORDS = (
    "presenca", "presença", "chamada", "presente", "presentes", "veio", "vieram",
    "faltou", "faltaram", "ausente", "ausentes", "nao veio", "não veio",
)
_CONTENT_WORDS = (
    "trabalhei", "trabalhamos", "fizemos", "atividade", "exercicio", "exercício",
    "conteudo", "conteúdo", "objetivo", "repertorio", "repertório", "tecnica",
    "técnica", "respiracao", "respiração", "registro", "aula de", "estudamos",
)
_CONVERSATION_WORDS = (
    "oi", "ola", "olá", "como", "como foi", "agenda", "quem e", "quem é", "obrigado",
    "valeu", "me ajuda", "pode me ajudar", "qual", "quando", "onde",
)
_TEXTUAL_FIELDS = {
    "objetivo", "materiais", "repertorio", "marco_ref", "anotacao_pedagogica",
    "devolutiva_familia", "proximos_passos", "leitura_de_conversao",
}
_ALLOWED_FIELDS = _TEXTUAL_FIELDS | {"presenca"}


def _norm(value: Any) -> str:
    raw = str(value or "").lower()
    raw = "".join(c for c in unicodedata.normalize("NFKD", raw) if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", raw).strip()


def _has_phrase(hay: str, phrases: tuple[str, ...]) -> bool:
    return any(
        re.search(rf"\b{re.escape(phrase)}\b", hay) if " " not in phrase else phrase in hay
        for phrase in phrases
    )


def _parse_llm_label(llm_json: str | None, allowed: set[str]) -> str | None:
    if llm_json is None:
        return None
    if not isinstance(llm_json, str) or not llm_json.strip() or llm_json.strip().lower() in {"timeout", "none", "null"}:
        return None
    try:
        value = json.loads(llm_json)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict):
        return None
    label = value.get("intencao", value.get("intent"))
    return label if isinstance(label, str) and label in allowed else None


def _audio_heuristic(text: str) -> AudioIntent:
    hay = _norm(text)
    if not hay:
        return "ambiguo"
    has_presence = _has_phrase(hay, _PRESENCE_WORDS)
    has_content = _has_phrase(hay, _CONTENT_WORDS)
    if has_presence and has_content:
        return "ambiguo"
    if has_presence:
        return "ambiguo"
    if has_content:
        return "registro"
    if _has_phrase(hay, _CONVERSATION_WORDS):
        return "conversa"
    return "ambiguo"


def classificar_intencao_audio(transcricao: str, llm_json: str | None = None) -> AudioIntent:
    """Return a closed audio intent; malformed model output fails closed."""
    heuristic = _audio_heuristic(transcricao)
    if llm_json is None:
        return heuristic
    label = _parse_llm_label(llm_json, _AUDIO_INTENTS)
    if label is None or heuristic == "ambiguo" or label != heuristic:
        return "ambiguo"
    return label  # type: ignore[return-value]


def _text_heuristic(text: str) -> TextIntent:
    hay = _norm(text)
    if not hay:
        return "ambiguo"
    has_presence = _has_phrase(hay, _PRESENCE_WORDS)
    has_content = _has_phrase(hay, _CONTENT_WORDS)
    if has_presence and has_content:
        return "ambiguo"
    if has_presence:
        uncertain = any(word in hay for word in ("acho", "talvez", "parece", "nao sei", "não sei"))
        return "ambiguo" if uncertain else "chamada"
    if _has_phrase(hay, _CONVERSATION_WORDS):
        return "conversa"
    if has_content:
        return "conversa"
    return "ambiguo"


def classificar_intencao_texto(texto: str, llm_json: str | None = None) -> TextIntent:
    """Classify a text call trigger without ever consulting a candidate pool."""
    heuristic = _text_heuristic(texto)
    if llm_json is None:
        return heuristic
    label = _parse_llm_label(llm_json, _TEXT_INTENTS)
    if label is None or heuristic == "ambiguo" or label != heuristic:
        return "ambiguo"
    return label  # type: ignore[return-value]


def _candidate_values(candidate: dict[str, Any]) -> list[str]:
    values = [candidate.get("curso"), candidate.get("turma"), candidate.get("data"), candidate.get("hora")]
    alunos = candidate.get("alunos") or candidate.get("alunos_sem_presenca_forte") or []
    if isinstance(alunos, list):
        values.extend((a.get("nome") if isinstance(a, dict) else a) for a in alunos)
    return [_norm(value) for value in values if len(_norm(value)) >= 3]


def _explicit_time(text: str) -> str | None:
    match = re.search(r"\b([01]?\d|2[0-3])(?:\s*(?:h|horas?)|:)\s*([0-5]\d)?\b", _norm(text))
    if not match:
        return None
    return f"{int(match.group(1)):02d}:{int(match.group(2) or 0):02d}"


def _compatible(text: str, candidate: dict[str, Any], all_candidates: list[dict[str, Any]]) -> bool:
    hay = _norm(text)
    # An explicit course, class, student name or time is a discriminator only
    # when that value is present in at least one supplied DB candidate.
    for key in ("curso", "turma"):
        known = {_norm(c.get(key)) for c in all_candidates if len(_norm(c.get(key))) >= 3}
        mentioned = {value for value in known if re.search(rf"\b{re.escape(value)}\b", hay)}
        if mentioned and _norm(candidate.get(key)) not in mentioned:
            return False
    known_names: dict[str, set[int]] = {}
    for item in all_candidates:
        for value in _candidate_values(item):
            if value not in {_norm(item.get("curso")), _norm(item.get("turma")), _norm(item.get("data")), _norm(item.get("hora"))}:
                known_names.setdefault(value, set()).add(int(item["aula_id"]))
    mentioned_names = {value for value in known_names if re.search(rf"\b{re.escape(value)}\b", hay)}
    if mentioned_names and int(candidate["aula_id"]) not in set().union(*(known_names[v] for v in mentioned_names)):
        return False
    requested_time = _explicit_time(text)
    if requested_time and _norm(candidate.get("hora")) and _norm(candidate.get("hora")) != requested_time:
        return False
    return True


def _question_for(candidates: list[dict[str, Any]], discriminante: bool = False) -> str:
    if discriminante:
        return "Qual dia, horário ou turma foi essa aula?"
    labels = []
    for item in candidates:
        label = " ".join(str(x) for x in (item.get("data"), item.get("hora"), item.get("curso"), item.get("turma")) if x)
        labels.append(label or f"aula {item['aula_id']}")
    return "Qual delas foi: " + " ou ".join(labels) + "?"


def reduzir_shortlist(texto: str, candidatas: list[dict[str, Any]]) -> dict[str, Any]:
    """Filter/rank supplied DB rows; never invent or return an external ID."""
    unique: list[dict[str, Any]] = []
    seen: set[int] = set()
    for item in candidatas or []:
        if not isinstance(item, dict):
            continue
        try:
            aula_id = int(item["aula_id"])
        except (KeyError, TypeError, ValueError):
            continue
        if aula_id <= 0 or aula_id in seen:
            continue
        seen.add(aula_id)
        unique.append(dict(item, aula_id=aula_id))
    compatible = [item for item in unique if _compatible(texto, item, unique)]
    if not compatible:
        return {"status": "nenhuma", "aula_id": None, "candidatas": [], "pergunta": None}
    if len(compatible) > 3:
        return {"status": "discriminante", "aula_id": None, "candidatas": [], "pergunta": _question_for(compatible, True)}
    if len(compatible) == 1:
        return {"status": "selecionada", "aula_id": compatible[0]["aula_id"], "candidatas": compatible, "pergunta": None}
    return {"status": "perguntar", "aula_id": None, "candidatas": compatible[:3], "pergunta": _question_for(compatible[:3])}


def interpretar_resposta_pendente(texto: str, acao: dict[str, Any]) -> dict[str, Any]:
    hay = re.sub(r"[^a-z0-9áéíóúãõç ]", " ", _norm(texto))
    hay = re.sub(r"\s+", " ", hay).strip()
    tipo = str((acao or {}).get("tipo") or "")
    if not hay:
        return {"tipo": "perguntar", "motivo": "resposta_vazia"}
    if any(word in hay for word in _CANCEL_WORDS):
        return {"tipo": "cancelar"}
    if any(hay.startswith(prefix) for prefix in ("qual ", "como ", "o que ", "quando ", "onde ")):
        return {"tipo": "conversa"}
    if any(hay == word or hay.startswith(word + " ") for word in _DEFER_WORDS):
        return {"tipo": "adiar"}
    candidates = [int(x) for x in (acao or {}).get("candidatas", []) if str(x).isdigit()]
    if tipo.startswith("escolher_aula"):
        ordinals = {"primeira": 0, "1": 0, "segunda": 1, "2": 1, "terceira": 2, "3": 2}
        match = next((index for word, index in ordinals.items() if re.search(rf"\b{word}\b", hay)), None)
        if match is not None and match < len(candidates):
            return {"tipo": "escolher_aula", "aula_id": candidates[match]}
        for candidate in candidates:
            if re.search(rf"\b{candidate}\b", hay):
                return {"tipo": "escolher_aula", "aula_id": candidate}
        return {"tipo": "perguntar", "motivo": "aula_nao_reconhecida"}
    if tipo in {"confirmar_registro", "confirmar_chamada"} and (
        hay.startswith("nao ") or hay.startswith("não ") or " veio" in hay or " faltou" in hay
    ) and any(word in hay for word in ("veio", "vieram", "faltou", "faltaram", "troca", "corrige", "correcao", "correção")):
        return {"tipo": "correcao", "texto": texto.strip()}
    if hay in _AFFIRMATIVE or any(hay.startswith(word + " ") for word in _AFFIRMATIVE):
        return {"tipo": "confirmar_intencao" if tipo.startswith("confirmar_intencao") else "confirmar"}
    if hay.startswith("nao ") or hay.startswith("não ") or hay in {"nao", "não"}:
        return {"tipo": "negar"}
    return {"tipo": "conversa"}


def validar_patch_correcao(saida: dict[str, Any], rascunho: dict[str, Any], roster: list[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(saida, dict) or not isinstance(rascunho, dict):
        return {"ok": False, "motivo": "formato_invalido"}
    if rascunho.get("status") not in {"rascunho", "aguardando_confirmacao"}:
        return {"ok": False, "motivo": "rascunho_fechado"}
    if str(saida.get("registro_id")) != str(rascunho.get("id")):
        return {"ok": False, "motivo": "registro_divergente"}
    aluno_id = saida.get("aluno_id", rascunho.get("aluno_id"))
    if rascunho.get("aluno_id") is not None and aluno_id != rascunho.get("aluno_id"):
        return {"ok": False, "motivo": "aluno_divergente"}
    if aluno_id is not None and not any(isinstance(row, dict) and row.get("aluno_id") == aluno_id for row in roster or []):
        return {"ok": False, "motivo": "aluno_fora_roster"}
    fields = saida.get("campos")
    if not isinstance(fields, dict) or not fields or any(key not in _ALLOWED_FIELDS for key in fields):
        return {"ok": False, "motivo": "campo_nao_permitido"}
    for key, value in fields.items():
        if key == "presenca":
            if value not in {"presente", "ausente"}:
                return {"ok": False, "motivo": "presenca_invalida"}
        elif not isinstance(value, str) or not value.strip() or len(value) > 4000:
            return {"ok": False, "motivo": "valor_invalido"}
    return {"ok": True, "registro_id": rascunho["id"], "aluno_id": aluno_id, "campos": dict(fields)}
