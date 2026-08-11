"""Contrato determinístico para o rascunho de registro de aula do Fábio.

Este módulo não acessa rede, banco ou variáveis de ambiente. Ele recebe somente
IDs já resolvidos pelo chamador e devolve uma forma fechada, pronta para ser
adaptada para cada porta de persistência ou preview.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any


class NormalizationContractError(ValueError):
    """O payload não pode atravessar a fronteira de normalização."""


_COMMON_FIELDS = ("objetivo", "atividades", "repertorio", "dever_casa", "observacoes")
_SLICE_FIELDS = ("progresso", "repertorio", "proximo_passo", "observacoes")
_TOP_LEVEL_KEYS = {"aula_id", "professor_id", "comum", "fatias"}
_SLICE_KEYS = {"aluno_id", "presenca", "campos"}
_PRESENCAS = {None, "presente", "ausente"}
_LEGACY_TOP_LEVEL_KEYS = {
    "audio_id", "aula_id", "professor_id", "origem", "molde", "tronco",
    "fatias", "transcricao", "texto_consolidado",
}
_LEGACY_TRUNK_KEYS = {"campos", "texto", "texto_consolidado"}
_LEGACY_COMMON_FIELDS = {
    "objetivo", "atividades", "repertorio", "dever_casa", "obs_gerais", "observacoes",
}
_LEGACY_SLICE_KEYS = {
    "aula_id", "aluno_id", "presenca", "texto", "texto_consolidado", "campos",
}
_LEGACY_SLICE_FIELDS = {
    "progresso", "repertorio", "proximo_passo", "observacao", "observacoes", "presenca",
}
_READBACK_STATUSES = {
    "aguardando_confirmacao", "rascunho", "confirmado", "gravado_emusys", "descartado",
}


def _require_exact_keys(value: dict[str, Any], allowed: set[str], path: str) -> None:
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise NormalizationContractError(f"{path}_chave_desconhecida")


def _require_int(value: Any, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise NormalizationContractError(f"{path}_invalido")
    return value


def _text(value: Any, path: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise NormalizationContractError(f"{path}_invalido")
    value = value.strip()
    return value or None


def _safe_readback_status(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    status = value.strip()
    return status if status in _READBACK_STATUSES else None


def _tokens(value: str | None) -> frozenset[str]:
    if not value:
        return frozenset()
    normalized = unicodedata.normalize("NFKD", value.casefold())
    normalized = "".join(char for char in normalized if not unicodedata.combining(char))
    return frozenset(re.findall(r"[a-z0-9]+", normalized))


_NOMINAL_PREFIX = re.compile(r"^\s*[A-ZÀ-ÖØ-Þ][A-Za-zÀ-ÖØ-öø-ÿ' -]{0,80}:\s*(.+?)\s*$")


def _without_nominal_prefix(value: str | None) -> str | None:
    if not value:
        return value
    matched = _NOMINAL_PREFIX.match(value)
    return matched.group(1) if matched else value


def _equivalent(left: str | None, right: str | None) -> bool:
    left_tokens = _tokens(_without_nominal_prefix(left))
    right_tokens = _tokens(_without_nominal_prefix(right))
    return bool(left_tokens) and left_tokens == right_tokens


def _ambiguous_observation(value: str | None) -> bool:
    terms = _tokens(value)
    return "sistema" in terms and "quadro" in terms


def _clean_fields(
    value: Any,
    *,
    fields: tuple[str, ...],
    path: str,
    uncertainties: list[dict[str, str]],
) -> dict[str, str | None]:
    if not isinstance(value, dict):
        raise NormalizationContractError(f"{path}_invalido")
    _require_exact_keys(value, set(fields), path)
    cleaned: dict[str, str | None] = {}
    for field in fields:
        text = _text(value.get(field), f"{path}.{field}")
        if field == "observacoes" and _ambiguous_observation(text):
            text = None
            uncertainties.append({"campo": f"{path}.{field}", "motivo": "termo_ambiguo"})
        cleaned[field] = text
    return cleaned


def validar_e_sanear_normalizacao(
    payload: dict,
    *,
    aula_id: int,
    professor_id: int,
    roster_ids: set[int],
) -> dict:
    """Valida um rascunho e devolve a forma fechada, sem inferir identidades.

    Incertezas são removidas dos campos factuais e aparecem apenas como códigos
    estruturados em ``incertezas``. Qualquer chave ou vínculo não previsto é um
    erro para que o chamador não persista nem apresente conteúdo não confiável.
    """
    if not isinstance(payload, dict):
        raise NormalizationContractError("payload_invalido")
    _require_exact_keys(payload, _TOP_LEVEL_KEYS, "payload")

    resolved_aula_id = _require_int(aula_id, "aula_id_resolvida")
    resolved_professor_id = _require_int(professor_id, "professor_id_resolvido")
    if _require_int(payload.get("aula_id"), "payload.aula_id") != resolved_aula_id:
        raise NormalizationContractError("aula_id_divergente")
    if _require_int(payload.get("professor_id"), "payload.professor_id") != resolved_professor_id:
        raise NormalizationContractError("professor_id_divergente")

    if (
        not isinstance(roster_ids, set)
        or not roster_ids
        or any(isinstance(item, bool) or not isinstance(item, int) for item in roster_ids)
    ):
        raise NormalizationContractError("roster_invalido")

    uncertainties: list[dict[str, str]] = []
    common = _clean_fields(
        payload.get("comum"),
        fields=_COMMON_FIELDS,
        path="comum",
        uncertainties=uncertainties,
    )
    if _equivalent(common["objetivo"], common["atividades"]):
        common["objetivo"] = None

    raw_slices = payload.get("fatias")
    if not isinstance(raw_slices, list) or not raw_slices:
        raise NormalizationContractError("fatias_invalida")

    slices: list[dict[str, Any]] = []
    seen_students: set[int] = set()
    common_values = tuple(value for value in common.values() if value)
    for index, raw_slice in enumerate(raw_slices):
        path = f"fatias[{index}]"
        if not isinstance(raw_slice, dict):
            raise NormalizationContractError(f"{path}_invalida")
        _require_exact_keys(raw_slice, _SLICE_KEYS, path)
        student_id = _require_int(raw_slice.get("aluno_id"), f"{path}.aluno_id")
        if student_id not in roster_ids:
            raise NormalizationContractError("aluno_fora_do_roster")
        if student_id in seen_students:
            raise NormalizationContractError("aluno_duplicado")
        seen_students.add(student_id)

        attendance = raw_slice.get("presenca")
        if attendance not in _PRESENCAS:
            raise NormalizationContractError(f"{path}.presenca_invalida")
        fields = _clean_fields(
            raw_slice.get("campos"),
            fields=_SLICE_FIELDS,
            path=f"{path}.campos",
            uncertainties=uncertainties,
        )
        for field, value in tuple(fields.items()):
            if any(_equivalent(value, common_value) for common_value in common_values):
                fields[field] = None

        slices.append({"aluno_id": student_id, "presenca": attendance, "campos": fields})

    # PresenÃ§a padrÃ£o na confirmaÃ§Ã£o percorre as fatias persistidas. Portanto,
    # cada aluno do roster precisa de uma fatia, mesmo quando o Ã¡udio sÃ³ trouxe
    # conteÃºdo comum ou complemento para outro aluno. Os IDs vÃªm somente do
    # roster jÃ¡ resolvido pelo chamador; nenhum aluno ou conteÃºdo Ã© inferido.
    for student_id in sorted(roster_ids - seen_students):
        slices.append({
            "aluno_id": student_id,
            "presenca": None,
            "campos": {field: None for field in _SLICE_FIELDS},
        })

    return {
        "aula_id": resolved_aula_id,
        "professor_id": resolved_professor_id,
        "comum": common,
        "fatias": slices,
        "incertezas": uncertainties,
    }


def adaptar_payload_legado_para_contrato(payload: dict) -> dict:
    """Converte o único formato legado aceito para a entrada fechada do contrato."""
    if not isinstance(payload, dict):
        raise NormalizationContractError("payload_legado_invalido")
    _require_exact_keys(payload, _LEGACY_TOP_LEVEL_KEYS, "payload_legado")
    trunk = payload.get("tronco")
    if not isinstance(trunk, dict):
        raise NormalizationContractError("tronco_legado_invalido")
    _require_exact_keys(trunk, _LEGACY_TRUNK_KEYS, "tronco_legado")
    legacy_common = trunk.get("campos")
    if not isinstance(legacy_common, dict):
        raise NormalizationContractError("tronco_campos_legado_invalido")
    _require_exact_keys(legacy_common, _LEGACY_COMMON_FIELDS, "tronco_campos_legado")
    if (
        legacy_common.get("obs_gerais") is not None
        and legacy_common.get("observacoes") is not None
        and legacy_common["obs_gerais"] != legacy_common["observacoes"]
    ):
        raise NormalizationContractError("observacoes_legado_divergentes")

    raw_slices = payload.get("fatias")
    if not isinstance(raw_slices, list):
        raise NormalizationContractError("fatias_legado_invalida")
    slices: list[dict[str, Any]] = []
    for index, raw_slice in enumerate(raw_slices):
        path = f"fatias_legado[{index}]"
        if not isinstance(raw_slice, dict):
            raise NormalizationContractError(f"{path}_invalida")
        _require_exact_keys(raw_slice, _LEGACY_SLICE_KEYS, path)
        legacy_fields = raw_slice.get("campos")
        if not isinstance(legacy_fields, dict):
            raise NormalizationContractError(f"{path}.campos_invalido")
        _require_exact_keys(legacy_fields, _LEGACY_SLICE_FIELDS, f"{path}.campos")
        if (
            legacy_fields.get("observacao") is not None
            and legacy_fields.get("observacoes") is not None
            and legacy_fields["observacao"] != legacy_fields["observacoes"]
        ):
            raise NormalizationContractError("observacao_legado_divergente")
        presence = raw_slice.get("presenca", legacy_fields.get("presenca"))
        if (
            raw_slice.get("presenca") is not None
            and legacy_fields.get("presenca") is not None
            and raw_slice["presenca"] != legacy_fields["presenca"]
        ):
            raise NormalizationContractError("presenca_legado_divergente")
        slices.append({
            "aluno_id": raw_slice.get("aluno_id"),
            "presenca": presence,
            "campos": {
                "progresso": legacy_fields.get("progresso"),
                "repertorio": legacy_fields.get("repertorio"),
                "proximo_passo": legacy_fields.get("proximo_passo"),
                "observacoes": legacy_fields.get("observacoes", legacy_fields.get("observacao")),
            },
        })

    return {
        "aula_id": payload.get("aula_id"),
        "professor_id": payload.get("professor_id"),
        "comum": {
            "objetivo": legacy_common.get("objetivo"),
            "atividades": legacy_common.get("atividades"),
            "repertorio": legacy_common.get("repertorio"),
            "dever_casa": legacy_common.get("dever_casa"),
            "observacoes": legacy_common.get("observacoes", legacy_common.get("obs_gerais")),
        },
        "fatias": slices,
    }


def adaptar_contrato_para_payload_rpc(
    normalized: dict,
    *,
    origem: str,
    molde: str,
    audio_id: str | None,
) -> dict:
    """Converte apenas dados já validados para o formato legado da RPC."""
    if not isinstance(normalized, dict):
        raise NormalizationContractError("normalizacao_invalida")
    if origem != "app" or not isinstance(molde, str) or not molde.strip():
        raise NormalizationContractError("metadados_rpc_invalidos")
    common = normalized.get("comum")
    slices = normalized.get("fatias")
    if not isinstance(common, dict) or not isinstance(slices, list):
        raise NormalizationContractError("normalizacao_invalida")
    return {
        "audio_id": audio_id or None,
        "aula_id": normalized.get("aula_id"),
        "professor_id": normalized.get("professor_id"),
        "origem": origem,
        "molde": molde.strip(),
        "tronco": {
            "campos": {
                "objetivo": common.get("objetivo"),
                "atividades": common.get("atividades"),
                "repertorio": common.get("repertorio"),
                "dever_casa": common.get("dever_casa"),
                "observacoes": common.get("observacoes"),
            },
        },
        "fatias": [
            {
                "aluno_id": slice_.get("aluno_id"),
                "presenca": slice_.get("presenca"),
                "campos": {
                    "progresso": slice_.get("campos", {}).get("progresso"),
                    "repertorio": slice_.get("campos", {}).get("repertorio"),
                    "proximo_passo": slice_.get("campos", {}).get("proximo_passo"),
                    "observacao": slice_.get("campos", {}).get("observacoes"),
                },
            }
            for slice_ in slices
        ],
    }


def _safe_preview_aula(value: Any) -> dict[str, str | None]:
    if not isinstance(value, dict):
        return {"data_aula": None, "hora": None, "turma": None, "curso": None, "tipo": None}
    return {
        field: _text(value.get(field), f"aula.{field}")
        for field in ("data_aula", "hora", "turma", "curso", "tipo")
    }


def sanear_readback_para_preview(
    readback: Any,
    *,
    professor_id: int,
    roster_ids: set[int],
) -> dict:
    """Remove o formato cru do read-back; retorna somente preview seguro ou erro fechado."""
    try:
        resolved_professor_id = _require_int(professor_id, "professor_id_resolvido")
        if not isinstance(readback, dict):
            raise NormalizationContractError("readback_invalido")
        trunk = readback.get("tronco")
        raw_slices = readback.get("fatias")
        if not isinstance(trunk, dict) or not isinstance(raw_slices, list) or not raw_slices:
            raise NormalizationContractError("readback_incompleto")
        legacy = {
            "aula_id": trunk.get("aula_id"),
            "professor_id": trunk.get("professor_id"),
            "tronco": {"campos": trunk.get("campos")},
            "fatias": [
                {
                    "aluno_id": slice_.get("aluno_id") if isinstance(slice_, dict) else None,
                    "presenca": slice_.get("presenca") if isinstance(slice_, dict) else None,
                    "campos": slice_.get("campos") if isinstance(slice_, dict) else None,
                }
                for slice_ in raw_slices
            ],
        }
        canonical = validar_e_sanear_normalizacao(
            adaptar_payload_legado_para_contrato(legacy),
            aula_id=_require_int(trunk.get("aula_id"), "readback.aula_id"),
            professor_id=resolved_professor_id,
            roster_ids=roster_ids,
        )
        if canonical["professor_id"] != _require_int(trunk.get("professor_id"), "readback.professor_id"):
            raise NormalizationContractError("readback_professor_divergente")
        names_by_student = {
            _require_int(slice_.get("aluno_id"), "readback.aluno_id"): _text(slice_.get("aluno_nome"), "readback.aluno_nome")
            for slice_ in raw_slices
            if isinstance(slice_, dict)
        }
        ids_by_student = {
            _require_int(slice_.get("aluno_id"), "readback.aluno_id"): _text(slice_.get("id"), "readback.fatia_id")
            for slice_ in raw_slices
            if isinstance(slice_, dict)
        }
        return {
            "ok": True,
            "aula": _safe_preview_aula(readback.get("aula")),
            "tronco": {
                "id": _text(trunk.get("id"), "readback.registro_id"),
                "aula_id": canonical["aula_id"],
                "professor_id": canonical["professor_id"],
                "status": _safe_readback_status(trunk.get("status")),
                "campos": {
                    "objetivo": canonical["comum"]["objetivo"],
                    "atividades": canonical["comum"]["atividades"],
                    "repertorio": canonical["comum"]["repertorio"],
                    "dever_casa": canonical["comum"]["dever_casa"],
                    "obs_gerais": canonical["comum"]["observacoes"],
                },
                "texto_consolidado": None,
            },
            "fatias": [
                {
                    "id": ids_by_student[slice_["aluno_id"]],
                    "aluno_id": slice_["aluno_id"],
                    "aluno_nome": names_by_student[slice_["aluno_id"]],
                    "presenca": slice_["presenca"],
                    "campos": {
                        "progresso": slice_["campos"]["progresso"],
                        "repertorio": slice_["campos"]["repertorio"],
                        "proximo_passo": slice_["campos"]["proximo_passo"],
                        "observacao": slice_["campos"]["observacoes"],
                    },
                    "texto_consolidado": None,
                }
                for slice_ in canonical["fatias"]
            ],
            "incertezas": canonical["incertezas"],
        }
    except (NormalizationContractError, TypeError, ValueError):
        return {
            "ok": False,
            "erro": "normalizacao_readback_invalida",
            "aula": None,
            "tronco": None,
            "fatias": [],
            "incertezas": [],
        }
