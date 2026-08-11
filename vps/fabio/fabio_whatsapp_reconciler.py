#!/usr/bin/env python3
"""One-shot reconciler for WhatsApp audio actions.

The database owns leases and action state.  This process only claims bounded
batches, reads guarded RPCs, and reports the resulting transition.  It never
updates action tables or Storage through an unguarded client.
"""
from __future__ import annotations

import os
import json
from typing import Any

from fabio_whatsapp_actions import FabioWhatsappBackend


DEFAULT_MAX_ATTEMPTS = 3
TRANSIENT_AUDIO_STATUSES = {"pendente", "transcrevendo", "transcrito", "normalizado"}
READY_RECORD_STATUS = "aguardando_confirmacao"
TERMINAL_RECORD_STATUSES = {"confirmado", "gravado_emusys", "descartado"}


def _one(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        if isinstance(value.get("data"), list):
            return value["data"][0] if value["data"] and isinstance(value["data"][0], dict) else None
        return value
    if isinstance(value, list):
        return value[0] if value and isinstance(value[0], dict) else None
    return None


def _items(value: Any) -> list[dict[str, Any]]:
    envelope = _one(value) or {}
    raw = envelope.get("itens")
    return [item for item in raw if isinstance(item, dict)] if isinstance(raw, list) else []


def _max_attempts() -> int:
    try:
        return max(1, int(os.getenv("FABIO_WHATSAPP_RECONCILIADOR_MAX_TENTATIVAS", str(DEFAULT_MAX_ATTEMPTS))))
    except (TypeError, ValueError):
        return DEFAULT_MAX_ATTEMPTS


def _attempts(action: dict[str, Any]) -> int:
    payload = action.get("payload") if isinstance(action.get("payload"), dict) else {}
    reconciler = payload.get("reconciliador") if isinstance(payload.get("reconciliador"), dict) else {}
    try:
        return max(0, int(reconciler.get("tentativas", 0)))
    except (TypeError, ValueError):
        return 0


def _action(item: dict[str, Any]) -> dict[str, Any]:
    nested = item.get("acao")
    return nested if isinstance(nested, dict) else item


def _conclude(
    backend: FabioWhatsappBackend,
    action: dict[str, Any],
    lease_token: str,
    event: str,
    data: dict[str, Any],
) -> str:
    response = _one(backend.rpc("fabio_concluir_reconciliacao", {
        "p_acao_id": action.get("id"),
        "p_lease_token": lease_token,
        "p_evento": event,
        "p_dados": data,
    }))
    if not response or response.get("ok") is False:
        return str((response or {}).get("codigo") or "conclusao_reconciliacao_falhou")
    return "ok"


def _fail_or_retry(
    backend: FabioWhatsappBackend,
    action: dict[str, Any],
    lease_token: str,
    reason: str,
    current_attempts: int,
    counters: dict[str, int],
) -> None:
    next_attempt = current_attempts + 1
    event = "falha_terminal" if next_attempt >= _max_attempts() else "falha_temporaria"
    code = _conclude(
        backend,
        action,
        lease_token,
        event,
        {"erro": reason, "tentativas": next_attempt},
    )
    if code == "lease_invalido":
        counters["stale"] += 1
    elif code != "ok":
        counters["falhas"] += 1
    elif event == "falha_terminal":
        counters["terminais"] += 1
    else:
        counters["retentativas"] += 1


def _record_status(backend: FabioWhatsappBackend, action: dict[str, Any], audio: dict[str, Any]) -> str | None:
    direct = audio.get("registro_status")
    if isinstance(direct, str):
        return direct
    registro_id = audio.get("registro_id")
    if not registro_id:
        return None
    readback = _one(backend.rpc("fabio_registro_completo", {
        "p_professor_id": action.get("professor_id"),
        "p_registro_id": registro_id,
    }))
    if not readback or readback.get("ok") is False:
        return None
    tronco = readback.get("tronco")
    return tronco.get("status") if isinstance(tronco, dict) else None


def reconcile_once(backend: FabioWhatsappBackend, limit: int = 10) -> dict[str, Any]:
    """Claim and process one bounded batch; never sleeps or keeps a lease locally."""
    claim = _one(backend.rpc("fabio_claim_acoes_processando", {
        "p_limite": max(0, int(limit)),
        "p_lease_segundos": 120,
    }))
    if not claim or claim.get("ok") is False:
        return {"ok": False, "codigo": (claim or {}).get("codigo", "claim_reconciliacao_falhou")}

    counters = {"promovidas": 0, "retentativas": 0, "terminais": 0, "stale": 0, "falhas": 0}
    claimed = _items(claim)
    for item in claimed:
        action = _action(item)
        lease_token = item.get("lease_token")
        if not action.get("id") or not lease_token or not action.get("audio_id"):
            counters["falhas"] += 1
            continue
        try:
            audio = _one(backend.rpc("fabio_status_audio_fila", {
                "p_professor_id": action.get("professor_id"),
                "p_audio_id": action.get("audio_id"),
            }))
        except Exception:
            audio = None

        if not audio or audio.get("ok") is False:
            _fail_or_retry(backend, action, str(lease_token), "status_audio_indisponivel", _attempts(action), counters)
            continue
        if audio.get("status") == "erro" or audio.get("tem_erro") is True:
            code = _conclude(
                backend,
                action,
                str(lease_token),
                "falha_terminal",
                {"erro": "pipeline_audio_com_erro", "tentativas": _attempts(action) + 1},
            )
            if code == "lease_invalido":
                counters["stale"] += 1
            elif code == "ok":
                counters["terminais"] += 1
            else:
                counters["falhas"] += 1
            continue

        registro_id = audio.get("registro_id")
        if not registro_id:
            _fail_or_retry(backend, action, str(lease_token), "registro_ainda_nao_criado", _attempts(action), counters)
            continue

        record_status = _record_status(backend, action, audio)
        if record_status == READY_RECORD_STATUS:
            code = _conclude(
                backend,
                action,
                str(lease_token),
                "rascunho_pronto",
                {"registro_id": registro_id, "tentativas": _attempts(action) + 1},
            )
            if code == "lease_invalido":
                counters["stale"] += 1
            elif code == "ok":
                counters["promovidas"] += 1
            else:
                counters["falhas"] += 1
        elif record_status in TERMINAL_RECORD_STATUSES:
            code = _conclude(
                backend,
                action,
                str(lease_token),
                "falha_terminal",
                {"erro": "registro_ja_fechado", "tentativas": _attempts(action) + 1},
            )
            if code == "lease_invalido":
                counters["stale"] += 1
            elif code == "ok":
                counters["terminais"] += 1
            else:
                counters["falhas"] += 1
        else:
            _fail_or_retry(backend, action, str(lease_token), "rascunho_ainda_nao_pronto", _attempts(action), counters)

    return {"ok": True, "claimed": len(claimed), **counters}


def cleanup_once(backend: FabioWhatsappBackend, limit: int = 20) -> dict[str, Any]:
    """Prove each cleanup candidate before deleting its Storage object."""
    claim = _one(backend.rpc("fabio_claim_acoes_limpeza", {
        "p_limite": max(0, int(limit)),
        "p_lease_segundos": 120,
    }))
    if not claim or claim.get("ok") is False:
        return {"ok": False, "codigo": (claim or {}).get("codigo", "claim_limpeza_falhou")}

    counters = {"limpas": 0, "bloqueadas": 0, "falhas": 0}
    claimed = _items(claim)
    for item in claimed:
        action_id = item.get("acao_id")
        path = item.get("storage_path")
        lease_token = item.get("lease_token")
        if not action_id or not path or not lease_token:
            counters["falhas"] += 1
            continue
        proof = _one(backend.rpc("fabio_provar_limpeza", {
            "p_acao_id": action_id,
            "p_storage_path": path,
        }))
        if not proof or proof.get("pode_remover") is not True:
            counters["bloqueadas"] += 1
            continue
        try:
            backend.remove_audio(str(path))
        except Exception:
            counters["falhas"] += 1
            continue
        result = _one(backend.rpc("fabio_concluir_limpeza", {
            "p_acao_id": action_id,
            "p_lease_token": lease_token,
            "p_resultado": {"removido": True, "prova": proof},
        }))
        if result and result.get("ok") is not False:
            counters["limpas"] += 1
        else:
            counters["falhas"] += 1
    return {"ok": True, "claimed": len(claimed), **counters}


def main() -> int:
    """Run one bounded reconciliation and cleanup cycle."""
    from fabio_chat_bridge import FabioBridgeBackend

    backend = FabioBridgeBackend(os.getenv("FABIO_AUDIO_BUCKET", "fabio-audios"))
    resultado = {
        "reconcile": reconcile_once(backend),
        "cleanup": cleanup_once(backend),
    }
    print(json.dumps(resultado, ensure_ascii=False, separators=(",", ":")))
    return 0 if all(item.get("ok") for item in resultado.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
