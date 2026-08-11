#!/usr/bin/env python3
"""Deterministic WhatsApp action orchestration.

The bridge supplies a backend adapter.  This module knows no HTTP, database
client or Hermes implementation and therefore cannot bypass the RPC doors.
"""
from __future__ import annotations

import os
import re
from typing import Any, Protocol

from fabio_whatsapp_intents import (
    classificar_intencao_audio,
    classificar_intencao_texto,
    interpretar_resposta_pendente,
    reduzir_shortlist,
    validar_patch_correcao,
)


class FabioWhatsappBackend(Protocol):
    def rpc(self, name: str, payload: dict[str, Any]) -> dict[str, Any] | None: ...

    def download_audio(self, media_url: str, max_bytes: int) -> tuple[bytes, str, str]: ...

    def upload_audio(self, storage_path: str, content: bytes, mime: str) -> None: ...

    def remove_audio(self, storage_path: str) -> None: ...


def _result(code: str, *, handled: bool = True, reply: str | None = None,
            forward: bool = False, action_id: str | None = None, **extra: Any) -> dict[str, Any]:
    return {
        "handled": handled,
        "reply": reply,
        "forward_to_hermes": forward,
        "action_id": action_id,
        "code": code,
        **extra,
    }


def _unwrap(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    nested = value.get("acao")
    return nested if isinstance(nested, dict) else value


def _action(backend: FabioWhatsappBackend, context: dict[str, Any]) -> dict[str, Any] | None:
    if "acao" in context:
        return _unwrap(context.get("acao"))
    response = backend.rpc("fabio_acao_ativa", {"p_professor_id": int(context["professor_id"])})
    if not isinstance(response, dict):
        return None
    return _unwrap(response.get("acao")) if "acao" in response else response


def _call(backend: FabioWhatsappBackend, name: str, payload: dict[str, Any]) -> dict[str, Any]:
    response = backend.rpc(name, payload)
    if not isinstance(response, dict) or response.get("ok") is False:
        raise RuntimeError(f"{name}_recusado")
    return response


def _event(backend: FabioWhatsappBackend, action: dict[str, Any], context: dict[str, Any], event: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
    return _call(backend, "fabio_aplicar_evento_acao", {
        "p_acao_id": action["id"],
        "p_professor_id": int(context["professor_id"]),
        "p_wa_message_id": str(context["wa_message_id"]),
        "p_evento": event,
        "p_dados": data or {},
    })


def _start(backend: FabioWhatsappBackend, context: dict[str, Any], tipo: str,
           storage_path: str | None, payload: dict[str, Any]) -> dict[str, Any]:
    response = _call(backend, "fabio_iniciar_acao", {
        "p_professor_id": int(context["professor_id"]),
        "p_wa_message_id": str(context["wa_message_id"]),
        "p_tipo": tipo,
        "p_storage_path": storage_path,
        "p_payload": payload,
    })
    action = _unwrap(response)
    if not action or not action.get("id"):
        raise RuntimeError("acao_nao_criada")
    return action


def _pool(backend: FabioWhatsappBackend, context: dict[str, Any], fluxo: str) -> list[dict[str, Any]]:
    response = _call(backend, "fabio_aulas_candidatas", {
        "p_professor_id": int(context["professor_id"]),
        "p_fluxo": fluxo,
        "p_referencia": context.get("referencia") or "now",
    })
    candidates = response.get("candidatas")
    return candidates if isinstance(candidates, list) else []


def _stage_audio(backend: FabioWhatsappBackend, context: dict[str, Any]) -> tuple[str, str]:
    media_url = context.get("media_url")
    if not media_url:
        raise RuntimeError("audio_url_missing")
    max_bytes = int(context.get("max_audio_bytes") or os.getenv("FABIO_WHATSAPP_REGISTRO_MAX_AUDIO_BYTES", str(25 * 1024 * 1024)))
    content, extension, mime = backend.download_audio(str(media_url), max_bytes)
    if len(content) > max_bytes:
        raise RuntimeError("audio_too_large")
    extension = re.sub(r"[^a-z0-9]", "", str(extension or "ogg").lower()) or "ogg"
    path = f"whatsapp/{int(context['professor_id'])}/{context['wa_message_id']}.{extension}"
    backend.upload_audio(path, content, mime or "audio/ogg")
    return path, mime or "audio/ogg"


def _select_and_enqueue_audio(backend: FabioWhatsappBackend, context: dict[str, Any], action: dict[str, Any], aula_id: int) -> dict[str, Any]:
    _event(backend, action, context, "aula_escolhida", {"aula_id": aula_id})
    response = _call(backend, "fabio_enfileirar_audio", {
        "p_professor_id": int(context["professor_id"]),
        "p_aula_id": aula_id,
        "p_storage_path": action.get("storage_path"),
        "p_duracao_segundos": int(context.get("duracao_segundos") or 0),
        "p_registro_id": None,
    })
    audio_id = response.get("audio_id")
    if not audio_id:
        raise RuntimeError("audio_id_missing")
    _event(backend, action, context, "audio_enfileirado", {"audio_id": audio_id})
    return _result("audio_enqueued", reply="Áudio recebido. Vou processar a aula e te mostro o resumo antes de gravar.", action_id=str(action["id"]), audio_id=audio_id)


def _start_from_candidates(backend: FabioWhatsappBackend, context: dict[str, Any], fluxo: str, candidates: list[dict[str, Any]], storage_path: str | None) -> dict[str, Any]:
    shortlist = reduzir_shortlist(str(context.get("text") or ""), candidates)
    if shortlist["status"] == "nenhuma":
        if storage_path:
            backend.remove_audio(storage_path)
        return _result("no_candidate", reply="Não encontrei uma aula elegível com segurança. Não gravei nada.")
    tipo = "escolher_aula_audio" if fluxo == "registro" else "escolher_aula_chamada"
    ids = [int(item["aula_id"]) for item in shortlist["candidatas"]]
    action = _start(backend, context, tipo, storage_path, {
        "intencao": fluxo,
        "transcricao": context.get("text") or "",
    })
    if shortlist["status"] == "discriminante":
        _event(backend, action, context, "pergunta_refinada", {})
        return _result("refine_class", reply=shortlist["pergunta"], action_id=str(action["id"]))
    _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
    if shortlist["status"] == "perguntar":
        return _result("choose_audio_class" if fluxo == "registro" else "choose_call_class", reply=shortlist["pergunta"], action_id=str(action["id"]))
    aula_id = int(shortlist["aula_id"])
    if fluxo == "registro":
        return _select_and_enqueue_audio(backend, context, action, aula_id)
    _event(backend, action, context, "aula_escolhida", {"aula_id": aula_id})
    return _result("call_preview", reply="Encontrei a aula. Quem esteve presente? Confirma essa chamada?", action_id=str(action["id"]), aula_id=aula_id)


def _correction_output(text: str, action: dict[str, Any], readback: dict[str, Any] | None) -> dict[str, Any]:
    payload = action.get("payload") if isinstance(action.get("payload"), dict) else {}
    draft = payload.get("rascunho") if isinstance(payload.get("rascunho"), dict) else None
    roster = payload.get("roster") if isinstance(payload.get("roster"), list) else []
    if draft is None:
        draft = {"id": action.get("registro_id"), "status": "aguardando_confirmacao"}
    if not roster and isinstance(readback, dict):
        roster = [{"aluno_id": row.get("aluno_id"), "nome": row.get("aluno_nome") or row.get("nome")} for row in (readback.get("fatias") or []) if isinstance(row, dict)]
    hay = text.lower()
    presence = "ausente" if any(word in hay for word in ("faltou", "faltaram", "não veio", "nao veio")) else "presente" if any(word in hay for word in ("veio", "vieram", "presente")) else None
    if not presence:
        return {"registro_id": draft.get("id"), "aluno_id": draft.get("aluno_id"), "campos": {"objetivo": text}}
    matches = [row for row in roster if isinstance(row, dict) and row.get("nome") and str(row["nome"]).lower() in hay]
    if len(matches) != 1:
        return {"registro_id": draft.get("id"), "aluno_id": None, "campos": {"presenca": presence}}
    return {"registro_id": draft.get("id"), "aluno_id": matches[0].get("aluno_id"), "campos": {"presenca": presence}}


def _handle_existing_action(backend: FabioWhatsappBackend, context: dict[str, Any], action: dict[str, Any]) -> dict[str, Any]:
    if str(action.get("wa_message_id")) == str(context.get("wa_message_id")):
        return _result("replay", reply="Essa mensagem já está em processamento.", action_id=str(action["id"]))
    response = interpretar_resposta_pendente(str(context.get("text") or ""), action)
    kind = response["tipo"]
    if kind == "conversa":
        return _result("conversation", handled=False, forward=True, action_id=str(action["id"]))
    if kind == "cancelar":
        _event(backend, action, context, "cancelado", {})
        return _result("cancelled", reply="Cancelei essa ação. Nada foi gravado no prontuário.", action_id=str(action["id"]))
    if kind == "adiar":
        _event(backend, action, context, "adiado", {})
        return _result("deferred", reply="Tudo bem. Deixei para depois sem renovar o prazo.", action_id=str(action["id"]))
    if kind == "escolher_aula":
        if action.get("tipo") == "escolher_aula_audio":
            return _select_and_enqueue_audio(backend, context, action, int(response["aula_id"]))
        _event(backend, action, context, "aula_escolhida", {"aula_id": int(response["aula_id"])})
        return _result("call_preview", reply="Encontrei a aula. Confirma essa chamada?", action_id=str(action["id"]), aula_id=int(response["aula_id"]))
    if kind == "confirmar_intencao":
        if action.get("tipo") == "confirmar_intencao_audio":
            _event(backend, action, context, "intencao_confirmada", {})
            next_context = dict(context, text=action.get("payload", {}).get("transcricao") or "")
            return _start_from_candidates(backend, next_context, "registro", _pool(backend, next_context, "registro"), action.get("storage_path"))
        _event(backend, action, context, "intencao_confirmada", {})
        next_context = dict(context, text=action.get("payload", {}).get("transcricao") or "")
        return _start_from_candidates(backend, next_context, "chamada", _pool(backend, next_context, "chamada"), None)
    if kind == "correcao":
        readback = None
        if action.get("registro_id"):
            readback = _call(backend, "fabio_registro_completo", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"]})
        patch = _correction_output(response.get("texto") or str(context.get("text") or ""), action, readback)
        valid = validar_patch_correcao(patch, (action.get("payload") or {}).get("rascunho") or {"id": action.get("registro_id"), "status": "aguardando_confirmacao"}, (action.get("payload") or {}).get("roster") or ((readback or {}).get("fatias") or []))
        if not valid["ok"]:
            return _result("correction_question", reply="Não consegui identificar essa correção com segurança. Qual aluno e qual informação devo ajustar?", action_id=str(action["id"]))
        fields = valid["campos"]
        if "presenca" in fields:
            _call(backend, "fabio_responder_presenca", {"p_professor_id": int(context["professor_id"]), "p_registro_alvo_id": valid["registro_id"], "p_presenca": fields["presenca"]})
        else:
            _call(backend, "fabio_atualizar_fatia", {"p_professor_id": int(context["professor_id"]), "p_id": valid["registro_id"], "p_texto": fields.get("objetivo"), "p_campos": fields})
        updated = _call(backend, "fabio_registro_completo", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"]})
        _event(backend, action, context, "correcao_aplicada", {"registro_id": valid["registro_id"]})
        return _result("correction_applied", reply="Atualizei o rascunho. Ainda não gravei no prontuário; quer confirmar?", action_id=str(action["id"]), readback=updated)
    if kind == "confirmar":
        if action.get("tipo") == "confirmar_registro":
            committed = _call(backend, "fabio_confirmar_registro", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"], "p_modo": "novo"})
            readback = _call(backend, "fabio_registro_completo", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"]})
            _event(backend, action, context, "confirmado", {"registro_id": action["registro_id"]})
            receipt = {key: committed.get(key) for key in ("registro_id", "gravadas", "ausentes_pulados", "presenca") if key in committed}
            receipt["readback"] = readback
            return _result("confirmed", reply="Registro confirmado. Estou preparando seu carimbo.", action_id=str(action["id"]), receipt=receipt)
        aula_id = int(action["aula_id"])
        committed = _call(backend, "fabio_registrar_presencas_aula", {"p_professor_id": int(context["professor_id"]), "p_aula_emusys_id": aula_id, "p_alunos_ausentes": action.get("payload", {}).get("alunos_ausentes", [])})
        _event(backend, action, context, "confirmado", {"aula_id": aula_id})
        return _result("confirmed_call", reply="Pronto: chamada registrada.", action_id=str(action["id"]), receipt=committed)
    return _result("pending_question", reply="Ainda não gravei. Você quer confirmar, corrigir, cancelar ou deixar para depois?", action_id=str(action["id"]))


def _is_devolutiva_revision(text: str) -> bool:
    hay = text.lower()
    return any(word in hay for word in ("melhora", "melhorar", "ajusta", "ajustar", "revisa", "revisar"))


def _handle_devolutiva_revision(backend: FabioWhatsappBackend, context: dict[str, Any]) -> dict[str, Any] | None:
    devolutiva_id = context.get("devolutiva_id")
    text = str(context.get("text") or "").strip()
    if not devolutiva_id or not _is_devolutiva_revision(text):
        return None
    texto_apoio_casa = str(context.get("devolutiva_texto_apoio_casa") or "").strip()
    if not texto_apoio_casa:
        return _result(
            "devolutiva_revision_question",
            reply="Posso revisar esse rascunho, mas preciso do texto do dever de casa. Quer manter o atual ou me diga o novo texto?",
            devolutiva_id=str(devolutiva_id),
        )
    updated = _call(backend, "fabio_atualizar_devolutiva_rascunho", {
        "p_professor_id": int(context["professor_id"]),
        "p_devolutiva_id": devolutiva_id,
        "p_texto_normal": text,
        "p_texto_apoio_casa": texto_apoio_casa,
        "p_motivo": "revisao solicitada no WhatsApp",
        "p_canal": "whatsapp",
        "p_acao_id": str(context["wa_message_id"]),
    })
    return _result(
        "devolutiva_draft_updated",
        reply="Atualizei o rascunho da devolutiva. Ainda não enviei para a família.",
        devolutiva_id=str(devolutiva_id),
        devolutiva=updated,
    )


def tratar_mensagem_professor(contexto: dict[str, Any], backend: FabioWhatsappBackend) -> dict[str, Any]:
    context = dict(contexto or {})
    if not context.get("professor_id") or not context.get("wa_message_id"):
        return _result("invalid_context", handled=False, forward=True)
    revision = _handle_devolutiva_revision(backend, context)
    if revision is not None:
        return revision
    action = _action(backend, context)
    if action:
        return _handle_existing_action(backend, context, action)
    text = str(context.get("text") or context.get("media_extracted_text") or "")
    if context.get("kind") == "audio":
        intent = classificar_intencao_audio(text, context.get("llm_json"))
        if intent == "conversa":
            return _result("conversation", handled=False, forward=True)
        storage_path, _ = _stage_audio(backend, context)
        if intent == "ambiguo":
            action = _start(backend, context, "confirmar_intencao_audio", storage_path, {"transcricao": text, "intencao": "ambiguo"})
            return _result("confirm_audio_intent", reply="Quer registrar esse áudio como conteúdo de aula?", action_id=str(action["id"]))
        return _start_from_candidates(backend, dict(context, text=text), "registro", _pool(backend, context, "registro"), storage_path)
    intent = classificar_intencao_texto(text, context.get("llm_json"))
    if intent == "conversa":
        return _result("conversation", handled=False, forward=True)
    if intent == "ambiguo":
        action = _start(backend, context, "confirmar_intencao_chamada", None, {"transcricao": text, "intencao": "ambiguo"})
        return _result("confirm_call_intent", reply="Você quer bater a chamada de uma aula com isso?", action_id=str(action["id"]))
    return _start_from_candidates(backend, context, "chamada", _pool(backend, context, "chamada"), None)
