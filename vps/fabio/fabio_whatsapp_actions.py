#!/usr/bin/env python3
"""Deterministic WhatsApp action orchestration.

The bridge supplies a backend adapter.  This module knows no HTTP, database
client or Hermes implementation and therefore cannot bypass the RPC doors.
"""
from __future__ import annotations

import logging
import os
import re
from typing import Any, Protocol

from fabio_whatsapp_intents import (
    classificar_intencao_audio,
    classificar_intencao_texto,
    detectar_substituicao,
    parece_consulta_letiva,
    interpretar_resposta_pendente,
    reduzir_shortlist,
    tem_sinal_de_aula,
    texto_tem_horario,
    validar_patch_correcao,
)

log = logging.getLogger(__name__)


class FabioWhatsappBackend(Protocol):
    def rpc(self, name: str, payload: dict[str, Any]) -> dict[str, Any] | None: ...

    def download_audio(self, media_url: str, max_bytes: int) -> tuple[bytes, str, str]: ...

    def upload_audio(self, storage_path: str, content: bytes, mime: str) -> None: ...

    def remove_audio(self, storage_path: str) -> None: ...

    def send_preview(self, action_id: str, professor_id: int, content: str) -> dict[str, Any]: ...


def _preview_text(value: Any) -> str:
    return str(value or "").strip() or "—"


def _preview_date(value: Any) -> str:
    text = str(value or "").strip()
    parts = text[:10].split("-")
    if len(parts) == 3 and all(parts):
        return f"{parts[2]}/{parts[1]}/{parts[0]}"
    return text or "—"


def _preview_presence(value: Any) -> str:
    text = str(value or "").strip().lower()
    if text in {"ausente", "faltou", "falta", "nao", "não"}:
        return "❌ Falta"
    if text in {"presente", "veio", "sim"}:
        return "✅ Presente"
    return "✅ Presente (padrão ao confirmar)"


def format_registro_preview(readback: dict[str, Any]) -> str:
    """Render only the guarded canonical read-back, including honest blanks."""
    if not isinstance(readback, dict) or readback.get("ok") is False:
        raise ValueError("readback_invalido")
    aula = readback.get("aula") if isinstance(readback.get("aula"), dict) else {}
    tronco = readback.get("tronco") if isinstance(readback.get("tronco"), dict) else {}
    comum = tronco.get("campos") if isinstance(tronco.get("campos"), dict) else {}
    fatias = readback.get("fatias") if isinstance(readback.get("fatias"), list) else []
    if not tronco.get("id") or not fatias:
        raise ValueError("readback_incompleto")

    curso = _preview_text(aula.get("curso") or aula.get("nome") or "Aula")
    turma = _preview_text(aula.get("turma") or aula.get("turma_nome"))
    hora = _preview_text(aula.get("hora") or aula.get("horario"))
    if hora != "—":
        hora = hora[:5]
    linhas = [
        "📋 *Preview do registro*",
        f"📚 {curso} • {turma}",
        f"🗓️ {_preview_date(aula.get('data_aula') or aula.get('data'))} • {hora}",
        "",
        "🧩 *Conteúdo da aula*",
        f"🎯 Objetivo: {_preview_text(comum.get('objetivo'))}",
        f"📖 Conteúdo: {_preview_text(comum.get('atividades') or comum.get('conteudo'))}",
        f"🎵 Repertório: {_preview_text(comum.get('repertorio'))}",
        f"🏠 Dever de casa: {_preview_text(comum.get('dever_casa'))}",
        f"💬 Observações: {_preview_text(comum.get('obs_gerais') or comum.get('observacoes'))}",
        "",
        "👥 *Por aluno*",
    ]
    for fatia in fatias:
        if not isinstance(fatia, dict):
            continue
        campos = fatia.get("campos") if isinstance(fatia.get("campos"), dict) else {}
        linhas.extend([
            f"👤 *{_preview_text(fatia.get('aluno_nome') or fatia.get('nome'))}*",
            f"   Presença: {_preview_presence(fatia.get('presenca') or campos.get('presenca'))}",
            f"   Progresso: {_preview_text(campos.get('progresso'))}",
            f"   Observação: {_preview_text(campos.get('observacao'))}",
            f"   Próximo passo: {_preview_text(campos.get('proximo_passo'))}",
        ])
    linhas.extend([
        "",
        "Se estiver certo, responda *sim*. Para ajustar, diga o aluno e o campo.",
    ])
    return "\n".join(linhas)


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
        # Uma mensagem pode atravessar shortlist -> aula escolhida -> fila.
        # O ledger live tem wa_message_id unico por evento; a chave derivada
        # preserva replay idempotente sem descartar as transicoes seguintes.
        "p_wa_message_id": f"{context['wa_message_id']}:fabio:{event}",
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
    # O id do UAZAPI e `<telefone>:<hash>`, e o dois-pontos atravessava cru pro
    # nome do objeto. Upload 200 e assinatura 200, mas o GET da URL assinada
    # voltava 400 InvalidSignature: o audio morria e o professor ficava no
    # silencio (prof. Valdo, 15/08/2026 — provado com dois objetos identicos,
    # um com ':' e outro sem). Mesma higiene que a `extension` acima ja fazia.
    nome = re.sub(r"[^A-Za-z0-9._-]", "-", str(context["wa_message_id"]))
    path = f"whatsapp/{int(context['professor_id'])}/{nome}.{extension}"
    backend.upload_audio(path, content, mime or "audio/ogg")
    return path, mime or "audio/ogg"


# ─────────────────────────────────────────────────────────────────────────────
# A fila de espera do áudio.
#
# O modelo é UMA ação aberta por professor. Isso não muda — é ele que impede o
# Fábio de perguntar de três aulas ao mesmo tempo. O que faltava era uma fila
# do lado de fora dessa porta: até 15/08/2026 o segundo áudio era só GUARDADO,
# e a resposta prometia *"assim que a gente fechar o anterior, ele entra"* sem
# ninguém pra cumprir.
#
# FIFO por professor (migration 20260815110000): a ordem é a do trabalho dele.


# Teto por mensagem. Cada áudio drenado normalmente ABRE uma ação nova, então
# na prática o laço roda uma vez — o teto existe pro caso em que a aula é
# resolvida sem pergunta e o próximo já pode entrar. Sem teto, um lote grande
# viraria uma rajada de mensagens no WhatsApp do professor.
_MAX_DRENAGEM_POR_MENSAGEM = 3


def _parquear(backend: FabioWhatsappBackend, context: dict[str, Any], storage_path: str) -> None:
    _call(backend, "fabio_parquear_audio", {
        "p_professor_id": int(context["professor_id"]),
        "p_wa_message_id": str(context["wa_message_id"]),
        "p_storage_path": storage_path,
        "p_transcricao": str(context.get("text") or context.get("media_extracted_text") or ""),
        "p_duracao_segundos": int(context.get("duracao_segundos") or 0),
    })


def _drenar_parqueados(backend: FabioWhatsappBackend, context: dict[str, Any], resultado: dict[str, Any]) -> dict[str, Any]:
    """Chama o próximo da fila quando o professor não tem mais ação aberta.

    Roda DEPOIS de tratar a mensagem atual, e só se a ação fechou de verdade —
    a consulta é ao banco, não ao que o resultado parece dizer. Falha aqui
    nunca derruba a resposta que o professor já ia receber: o áudio continua na
    fila e entra na próxima mensagem.

    ⚠️ LIMITE CONHECIDO: o gatilho é a mensagem de WhatsApp. Se a ação fechar
    por outro caminho — o professor confirma o registro no app —, o áudio
    parqueado espera até ele mandar a próxima mensagem. Não se perde (a fila é
    tabela, não memória), mas também não entra sozinho no mesmo instante.
    Fechar isso pede um timer lendo a fila, como o da devolutiva.
    """
    partes: list[str] = []
    try:
        for _ in range(_MAX_DRENAGEM_POR_MENSAGEM):
            if _action(backend, context):
                break
            parqueado = _call(backend, "fabio_audio_parqueado_proximo", {
                "p_professor_id": int(context["professor_id"]),
            })
            if not parqueado or not parqueado.get("id"):
                break

            contexto_audio = dict(
                context,
                wa_message_id=str(parqueado["wa_message_id"]),
                text=str(parqueado.get("transcricao") or ""),
                kind="audio",
                duracao_segundos=int(parqueado.get("duracao_segundos") or 0),
            )
            saida = _start_from_candidates(
                backend, contexto_audio, "registro",
                _pool(backend, contexto_audio, "registro"),
                str(parqueado["storage_path"]),
            )

            if saida.get("action_id"):
                _call(backend, "fabio_audio_parqueado_consumir", {
                    "p_id": str(parqueado["id"]),
                    "p_acao_id": str(saida["action_id"]),
                })
            else:
                # Sem ação nenhuma: `_start_from_candidates` já apagou o objeto
                # do Storage. Sair da fila com motivo escrito é obrigatório —
                # senão a próxima mensagem tenta de novo um áudio que não
                # existe mais, pra sempre.
                _call(backend, "fabio_audio_parqueado_descartar", {
                    "p_id": str(parqueado["id"]),
                    "p_motivo": str(saida.get("status") or "sem_candidata"),
                })
            if saida.get("reply"):
                partes.append(str(saida["reply"]))
    except Exception:  # noqa: BLE001
        return resultado

    if partes:
        anterior = str(resultado.get("reply") or "").strip()
        resultado = dict(resultado)
        resultado["reply"] = "\n\n".join([p for p in [anterior, *partes] if p])
        resultado["drenados"] = len(partes)
    return resultado


def _roster_aluno_id(alunos_roster: list[dict[str, Any]] | None, nome: str) -> int | None:
    """aluno_id do matriculado citado. O detector devolve o NOME do roster
    (string original), então casa por igualdade — sem chute."""
    for aluno in alunos_roster or []:
        if isinstance(aluno, dict) and aluno.get("nome") == nome:
            aid = aluno.get("aluno_id")
            try:
                return int(aid) if aid is not None else None
            except (TypeError, ValueError):
                return None
    return None


def _registrar_substituicao_shadow(
    backend: FabioWhatsappBackend,
    context: dict[str, Any],
    aula_id: int,
    alunos_roster: list[dict[str, Any]] | None,
) -> str | None:
    """SHADOW: se a transcrição diz que alguém participou no lugar de um aluno do
    roster, registra a candidata via RPC — em paralelo ao registro normal.

    Freios (do Alf): nunca levanta (só loga); não toca presença/falta/reposição/
    financeiro/Emusys (a RPC é `security definer` e escreve só na camada de
    ocorrência); se identidade ambígua, devolve uma pergunta curta de confirmação
    (o participante ainda não é resolvido para um aluno — vai como nome citado,
    `precisa_confirmar`). Retorna a pergunta a anexar ao reply, ou None.
    """
    try:
        transcricao = str(context.get("text") or context.get("media_extracted_text") or "").strip()
        if not transcricao:
            return None
        roster_nomes = [str(a.get("nome")) for a in (alunos_roster or [])
                        if isinstance(a, dict) and a.get("nome")]
        if not roster_nomes:
            return None
        par = detectar_substituicao(transcricao, roster_nomes)
        if not par:
            return None
        matriculado_id = _roster_aluno_id(alunos_roster, par["matriculado"])
        if matriculado_id is None:
            return None
        participante = str(par["participante"]).title()
        resposta = backend.rpc("fabio_participacao_registrar_candidata", {
            "p_aula_id": int(aula_id),
            "p_professor_id": int(context["professor_id"]),
            "p_aluno_matriculado_id": int(matriculado_id),
            "p_participante_real_id": None,
            "p_participante_nome": participante,
            "p_participante_telefone": None,
            "p_confianca": "baixa",
            "p_metodo_extracao": "deterministico",
            "p_origem_message_id": str(context["wa_message_id"]),
            "p_origem_transcricao": transcricao,
        })
        if not isinstance(resposta, dict) or not resposta.get("ok"):
            log.warning("substituicao shadow: RPC nao ok (aula %s): %s", aula_id, resposta)
            return None
        if resposta.get("precisa_confirmar"):
            return (f"Ah, e anotei em observação: parece que {participante} participou no "
                    f"lugar de {par['matriculado']}. Confere pra mim? (não muda a chamada)")
        return None
    except Exception as exc:  # freio: shadow nunca derruba o registro
        log.warning("substituicao shadow ignorada (aula %s): %s", aula_id, exc)
        return None


def _select_and_enqueue_audio(backend: FabioWhatsappBackend, context: dict[str, Any], action: dict[str, Any], aula_id: int, alunos_roster: list[dict[str, Any]] | None = None) -> dict[str, Any]:
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
    # SHADOW, DEPOIS da aula pinada e do áudio enfileirado: observa a divergência
    # roster×participação sem alterar o registro. Falha aqui não derruba nada.
    reply = "Áudio recebido. Vou processar a aula e te mostro o resumo antes de gravar."
    pergunta = _registrar_substituicao_shadow(backend, context, aula_id, alunos_roster)
    if pergunta:
        reply = f"{reply}\n\n{pergunta}"
    return _result("audio_enqueued", reply=reply, action_id=str(action["id"]), audio_id=audio_id)


def _citacao_do_audio(action: dict[str, Any]) -> str:
    previa = str((action.get("payload") or {}).get("transcricao") or "").strip()[:140]
    return f' ("{previa}…")' if previa else ""


def _pergunta_pendente(action: dict[str, Any]) -> str:
    """A pendencia que esta na frente, dita com o AUDIO citado e com saida.

    18/08/2026: o Isaque recebeu "ainda nao sei de qual aula voce esta falando"
    sobre um audio de ONTEM, sem citacao e sem *cancela*. Ele nao tinha como
    saber do que a maquina falava nem como se livrar dela.
    """
    citacao = _citacao_do_audio(action)
    if str(action.get("tipo") or "").startswith("confirmar_intencao"):
        return (f"Antes, preciso fechar um áudio anterior{citacao}: era conteúdo de aula "
                "pra registrar? Responde *sim* pra seguir com ele, ou *cancela* pra "
                "descartar aquele.")
    return (f"Antes, preciso saber de qual aula era um áudio anterior{citacao}. "
            "Me diz o dia e o horário ou o nome do aluno — ou responde *cancela* "
            "pra descartar aquele.")


def _continuar_apos_intencao(backend: FabioWhatsappBackend, context: dict[str, Any],
                             fluxo: str, action: dict[str, Any]) -> dict[str, Any]:
    """O espelho de `_start_from_candidates` para uma acao que JA existe.

    Depois de `intencao_confirmada` o banco transiciona a MESMA linha para
    escolher_aula_*; os eventos seguintes se aplicam a ela. E quando a
    shortlist volta "nenhuma", a acao e CANCELADA em vez de ficar aberta:
    pergunta sem candidata e pergunta que nenhuma resposta fecha — foi a
    fantasma que sequestrou o canal do professor 10 por 18 horas.
    """
    candidates = _pool(backend, context, fluxo)
    shortlist = reduzir_shortlist(str(context.get("text") or ""), candidates)
    if shortlist["status"] == "nenhuma":
        _event(backend, action, context, "cancelado", {"motivo": "sem_candidata_apos_intencao"})
        if action.get("storage_path"):
            backend.remove_audio(str(action["storage_path"]))
        return _result("no_candidate",
                       reply=("Não encontrei uma aula elegível com segurança pra esse áudio, "
                              "então cancelei essa pendência. Nada foi gravado."),
                       action_id=str(action["id"]))
    ids = [int(item["aula_id"]) for item in shortlist["candidatas"]]
    if not shortlist.get("truncada"):
        _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
    if shortlist["status"] == "discriminante":
        _event(backend, action, context, "pergunta_refinada", {})
        return _result("refine_class", reply=shortlist["pergunta"], action_id=str(action["id"]))
    if shortlist["status"] == "perguntar":
        return _result("choose_audio_class" if fluxo == "registro" else "choose_call_class",
                       reply=shortlist["pergunta"], action_id=str(action["id"]))
    aula_id = int(shortlist["aula_id"])
    if fluxo == "registro":
        return _select_and_enqueue_audio(backend, context, action, aula_id,
                                         _roster_da_aula(candidates, aula_id))
    _event(backend, action, context, "aula_escolhida", {"aula_id": aula_id})
    return _result("call_preview", reply="Encontrei a aula. Quem esteve presente? Confirma essa chamada?",
                   action_id=str(action["id"]), aula_id=aula_id)


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
    # A shortlist é guardada ANTES de qualquer pergunta, inclusive a
    # discriminante. Ela é o único vocabulário que o interpretador de resposta
    # tem pra entender o que o professor responder; perguntar sem guardar é
    # abrir uma pergunta que nenhuma resposta consegue fechar.
    #
    # A EXCEÇÃO é a lista truncada: guardar 3 de 10 transforma as outras 7 em
    # resposta impossível, porque `_refine_pending_class` filtra o pool pela
    # lista guardada. Sem lista, a resposta casa contra o pool inteiro — que é
    # o que a pergunta aberta pede. Guardar meia verdade é pior que não guardar.
    if not shortlist.get("truncada"):
        _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
    if shortlist["status"] == "discriminante":
        _event(backend, action, context, "pergunta_refinada", {})
        return _result("refine_class", reply=shortlist["pergunta"], action_id=str(action["id"]))
    if shortlist["status"] == "perguntar":
        return _result("choose_audio_class" if fluxo == "registro" else "choose_call_class", reply=shortlist["pergunta"], action_id=str(action["id"]))
    aula_id = int(shortlist["aula_id"])
    if fluxo == "registro":
        return _select_and_enqueue_audio(backend, context, action, aula_id, _roster_da_aula(candidates, aula_id))
    _event(backend, action, context, "aula_escolhida", {"aula_id": aula_id})
    return _result("call_preview", reply="Encontrei a aula. Quem esteve presente? Confirma essa chamada?", action_id=str(action["id"]), aula_id=aula_id)


def _roster_da_aula(candidates: list[dict[str, Any]] | None, aula_id: int) -> list[dict[str, Any]] | None:
    """Roster (alunos) da aula escolhida dentro do pool. `fabio_aulas_candidatas`
    devolve `alunos: [{aluno_id, nome, ...}]` no fluxo de registro."""
    for candidate in candidates or []:
        if isinstance(candidate, dict) and str(candidate.get("aula_id")) == str(aula_id):
            alunos = candidate.get("alunos")
            return alunos if isinstance(alunos, list) else None
    return None


def _mentions_candidate_student(text: str, candidates: list[dict[str, Any]]) -> bool:
    hay = str(text or "").lower()
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        alunos = candidate.get("alunos") or candidate.get("alunos_sem_presenca_forte") or []
        if not isinstance(alunos, list):
            continue
        for aluno in alunos:
            if not isinstance(aluno, dict):
                continue
            nome = str(aluno.get("nome") or "").strip().lower()
            if len(nome) >= 3 and re.search(rf"\b{re.escape(nome)}\b", hay):
                return True
    return False


def _looks_like_class_refinement(text: str, candidates: list[dict[str, Any]] | None = None) -> bool:
    hay = str(text or "").lower()
    return bool(
        # Mesma régua de horário do casador — inclusive os apelidos
        # ("meio-dia"). Ver `texto_tem_horario`.
        texto_tem_horario(hay)
        or re.search(r"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b", hay)
        or any(word in hay for word in (
            "hoje", "ontem", "amanha", "amanhã", "turma", "curso",
            "piano", "teclado", "violao", "violão", "canto", "guitarra",
        ))
        or _mentions_candidate_student(text, candidates or [])
    )


def _refine_pending_class(
    backend: FabioWhatsappBackend,
    context: dict[str, Any],
    action: dict[str, Any],
) -> dict[str, Any] | None:
    if action.get("tipo") not in {"escolher_aula_audio", "escolher_aula_chamada"}:
        return None
    text = str(context.get("text") or "")
    if not action.get("candidatas") and not _looks_like_class_refinement(text):
        return None

    fluxo = "registro" if action.get("tipo") == "escolher_aula_audio" else "chamada"
    candidates = _pool(backend, context, fluxo)
    if action.get("candidatas"):
        allowed_ids = {
            int(candidate_id)
            for candidate_id in action["candidatas"]
            if str(candidate_id).isdigit()
        }
        candidates = [
            candidate for candidate in candidates
            if isinstance(candidate, dict)
            and str(candidate.get("aula_id")).isdigit()
            and int(candidate["aula_id"]) in allowed_ids
        ]
        if not _looks_like_class_refinement(text, candidates):
            return None
    shortlist = reduzir_shortlist(
        text,
        candidates,
    )
    if shortlist["status"] == "nenhuma":
        if action.get("candidatas"):
            return _result(
                "choose_audio_class" if fluxo == "registro" else "choose_call_class",
                reply="Não consegui identificar uma única aula com segurança. Qual das opções que enviei foi?",
                action_id=str(action["id"]),
            )
        return _result(
            "no_candidate",
            reply="Ainda não encontrei uma aula compatível com esse dia, horário ou turma. Não gravei nada.",
            action_id=str(action["id"]),
        )

    ids = [int(item["aula_id"]) for item in shortlist["candidatas"]]
    if shortlist["status"] == "discriminante":
        # Mesma regra do primeiro contato: guarda antes de perguntar — e pela
        # mesma razão, NÃO guarda quando a lista veio truncada.
        if not action.get("candidatas") and not shortlist.get("truncada"):
            _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
        _event(backend, action, context, "pergunta_refinada", {})
        return _result("refine_class", reply=shortlist["pergunta"], action_id=str(action["id"]))

    if shortlist["status"] == "perguntar":
        if action.get("candidatas"):
            return _result(
                "choose_audio_class" if fluxo == "registro" else "choose_call_class",
                reply=shortlist["pergunta"],
                action_id=str(action["id"]),
            )
        _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
        return _result(
            "choose_audio_class" if fluxo == "registro" else "choose_call_class",
            reply=shortlist["pergunta"],
            action_id=str(action["id"]),
        )

    if not action.get("candidatas"):
        _event(backend, action, context, "shortlist_definida", {"candidatas": ids})
    aula_id = int(shortlist["aula_id"])
    if fluxo == "registro":
        return _select_and_enqueue_audio(backend, context, action, aula_id, _roster_da_aula(candidates, aula_id))
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
        # 18/08/2026: despejar o texto da correção em `objetivo` CORROMPE o
        # rascunho — "Tira solfejo, do re mi fá é o nome da música" viraria o
        # objetivo da aula. Sem um extrator estruturado de conteúdo (a etapa
        # seguinte), devolvemos patch VAZIO: `validar_patch_correcao` rejeita e a
        # máquina responde honesto ("qual aluno e qual informação?"), em vez de o
        # LLM mentir que corrigiu OU de gravar lixo no prontuário do aluno.
        return {"registro_id": draft.get("id"), "aluno_id": draft.get("aluno_id"), "campos": {}}
    matches = [row for row in roster if isinstance(row, dict) and row.get("nome") and str(row["nome"]).lower() in hay]
    if len(matches) != 1:
        return {"registro_id": draft.get("id"), "aluno_id": None, "campos": {"presenca": presence}}
    return {"registro_id": draft.get("id"), "aluno_id": matches[0].get("aluno_id"), "campos": {"presenca": presence}}


def _rotulo_da_aula(aula: dict[str, Any]) -> str:
    """Rotulo curto no mesmo formato que o professor ja ve na shortlist."""
    if not isinstance(aula, dict):
        return ""
    hora = str(aula.get("hora") or aula.get("horario") or "")[:5]
    partes = [
        _preview_date(aula.get("data_aula") or aula.get("data")),
        hora,
        str(aula.get("curso") or aula.get("nome") or ""),
        str(aula.get("turma") or aula.get("turma_nome") or ""),
    ]
    return " ".join(p for p in partes if p and p != "—").strip()


def _confirmacao_responde_a_maquina(backend: FabioWhatsappBackend, context: dict[str, Any],
                                    action: dict[str, Any]) -> bool:
    """O "sim" e resposta a ULTIMA fala do Fabio? So a maquina pode ter falado.

    FAIL-SAFE de proposito: banco mudo, resposta em formato inesperado ou
    excecao contam como INSEGURO. Uma trava que abre quando o banco nao
    responde e uma trava que abre justamente no dia em que tudo esta ruim — e
    o que ela protege e escrita no prontuario do aluno.
    """
    try:
        resposta = backend.rpc("fabio_acao_confirmacao_segura", {
            "p_professor_id": int(context["professor_id"]),
            "p_acao_id": str(action["id"]),
        })
    except Exception:  # noqa: BLE001
        return False
    if not isinstance(resposta, dict):
        return False
    return resposta.get("segura") is True


def _pedir_confirmacao_de_novo(backend: FabioWhatsappBackend, context: dict[str, Any],
                               action: dict[str, Any]) -> dict[str, Any]:
    """Nao grava e devolve a pergunta DIZENDO qual aula esta em jogo.

    Repetir "quer confirmar?" sem dizer o que devolveria o professor ao mesmo
    escuro que criou o erro. E a pergunta se cura sozinha: como agora quem
    falou por ultimo e a propria maquina, o proximo "sim" passa direto.
    """
    rotulo = ""
    if action.get("registro_id"):
        try:
            readback = _call(backend, "fabio_registro_completo", {
                "p_professor_id": int(context["professor_id"]),
                "p_registro_id": action["registro_id"],
            })
            rotulo = _rotulo_da_aula(readback.get("aula") or {})
        except Exception:  # noqa: BLE001
            rotulo = ""
    if not rotulo:
        payload = action.get("payload") if isinstance(action.get("payload"), dict) else {}
        rotulo = _rotulo_da_aula(payload.get("aula") or payload.get("candidata") or {})
    alvo = f"o registro da aula {rotulo}" if rotulo else "o registro que eu te mostrei"
    return _result(
        "confirm_restate",
        reply=(f"Antes de gravar, confirma comigo: e {alvo}? "
               "Responde *sim* de novo que eu gravo."),
        action_id=str(action["id"]),
    )


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
    refined = _refine_pending_class(backend, context, action)
    if refined is not None:
        return refined
    if kind == "confirmar_intencao":
        # A MESMA trava do confirmar_registro/chamada, que faltava aqui.
        # 18/08/2026: o "Confirma tudo" do Isaque chegou 8min depois de o LLM
        # falar por ultimo e confirmou a pergunta de ONTEM — um audio que ele
        # nem lembrava. A repergunta CITA o audio: repetir "quer registrar?"
        # sem dizer o que devolveria o professor ao mesmo escuro.
        if not _confirmacao_responde_a_maquina(backend, context, action):
            return _result(
                "confirm_intent_restate",
                reply=(f"Só confirmando antes de seguir: você quer dizer *sim* pra um "
                       f"áudio anterior{_citacao_do_audio(action)}? Se for isso, responde "
                       "*sim* de novo. Se não, responde *cancela* que eu descarto aquele."),
                action_id=str(action["id"]),
            )
        fluxo = "registro" if action.get("tipo") == "confirmar_intencao_audio" else "chamada"
        _event(backend, action, context, "intencao_confirmada", {})
        next_context = dict(context, text=action.get("payload", {}).get("transcricao") or "")
        # NUNCA _start aqui: o `intencao_confirmada` ja TRANSICIONOU esta acao
        # no banco (mesma linha, tipo novo). Abrir outra por cima e o que o
        # banco recusa — e em 18/08 essa recusa virou RuntimeError, derrubou o
        # poller e prendeu a mensagem do professor por 3 minutos.
        return _continuar_apos_intencao(backend, next_context, fluxo, action)
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
        # ── A TRAVA: o "sim" so vale pra acao que FALOU por ultimo ───────────
        # 15/08/2026, professor 10. O LLM conduziu sozinho uma conversa inteira
        # sobre a aula das 14h ("Ajustei... Posso gravar esse registro agora?
        # Responde sim") enquanto a acao viva na maquina era a das 13h. O "sim"
        # do professor era resposta ao LLM; a maquina colheu pra outra aula e
        # gravou 13h no prontuario.
        #
        # Nao da pra confiar so em consertar o lote (bridge:3197): se a maquina
        # tivesse pego aquele "sim", ela gravaria a das 13h do mesmo jeito. O
        # que separa confirmacao legitima de sequestrada e QUEM falou por ultimo
        # com o professor — e isso o banco sabe responder.
        if not _confirmacao_responde_a_maquina(backend, context, action):
            return _pedir_confirmacao_de_novo(backend, context, action)
        if action.get("tipo") == "confirmar_registro":
            readback_before = _call(backend, "fabio_registro_completo", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"]})
            trunk_before = readback_before.get("tronco") if isinstance(readback_before.get("tronco"), dict) else {}
            status_before = trunk_before.get("status")
            recovered = status_before in {"confirmado", "gravado_emusys"}
            if recovered:
                committed = {"registro_id": action["registro_id"], "recuperado_pos_commit": True}
                readback = readback_before
            elif status_before in {"rascunho", "aguardando_confirmacao"}:
                committed = _call(backend, "fabio_confirmar_registro", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"], "p_modo": "novo"})
                readback = _call(backend, "fabio_registro_completo", {"p_professor_id": int(context["professor_id"]), "p_registro_id": action["registro_id"]})
            else:
                raise RuntimeError("status_registro_nao_confirmavel")
            _event(backend, action, context, "confirmado", {"registro_id": action["registro_id"]})
            receipt = {key: committed.get(key) for key in ("registro_id", "gravadas", "ausentes_pulados", "presenca") if key in committed}
            if recovered:
                receipt["recuperado_pos_commit"] = True
            receipt["readback"] = readback
            return _result("confirmed", reply="Registro confirmado. Estou preparando seu carimbo.", action_id=str(action["id"]), receipt=receipt)
        aula_id = int(action["aula_id"])
        committed = _call(backend, "fabio_confirmar_chamada_acao", {
            "p_acao_id": action["id"],
            "p_professor_id": int(context["professor_id"]),
            "p_wa_message_id": f"{context['wa_message_id']}:fabio:confirmado",
        })
        receipt = committed.get("escrita") if isinstance(committed.get("escrita"), dict) else committed
        return _result("confirmed_call", reply="Pronto: chamada registrada.", action_id=str(action["id"]), aula_id=aula_id, receipt=receipt)
    # O fallback tem que oferecer o menu DO ESTADO EM QUE ELE ESTÁ. Enquanto a
    # pergunta aberta era "qual aula?", responder "confirmar, corrigir,
    # cancelar ou deixar para depois" é o menu de outro estado — e foi ele que
    # ensinou o Isaque a responder "Grave" e "Confirma os 2", que este estado
    # não tem como aceitar. O código já sabia o motivo (`aula_nao_reconhecida`)
    # e jogava fora na hora de falar.
    if str(action.get("tipo") or "").startswith("escolher_aula"):
        return _result(
            "choose_audio_class" if action.get("tipo") == "escolher_aula_audio" else "choose_call_class",
            reply="Ainda não sei de qual aula você está falando. Me diz o dia e o horário (ex.: \"sábado, meio-dia\") ou o nome do aluno.",
            action_id=str(action["id"]),
        )
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
    """Porta unica da maquina. Excecao aqui dentro NUNCA vaza pro poller.

    18/08/2026: uma RuntimeError (`fabio_iniciar_acao_recusado`) atravessou
    esta funcao, derrubou o poll_loop e prendeu a mensagem do professor por 3
    minutos ate o stale reclaim. Erro de maquina vira resposta honesta e
    mensagem processada — e NAO abre a porta do LLM (`forward=False`): o LLM
    respondendo por cima de um estado meio-mutado e a receita das duas bocas.

    AssertionError passa direto de proposito: e o duble de teste acusando RPC
    inesperada, e mascarar isso transformaria bug de teste em verde.
    """
    try:
        return _tratar_mensagem_professor(contexto, backend)
    except AssertionError:
        raise
    except Exception as exc:  # noqa: BLE001
        return _result(
            "machine_error",
            reply=("Tive um erro aqui do meu lado ao processar essa mensagem e "
                   "não gravei nada. Me manda de novo em um instante?"),
            erro=str(exc)[:300],
        )


def _tratar_mensagem_professor(contexto: dict[str, Any], backend: FabioWhatsappBackend) -> dict[str, Any]:
    context = dict(contexto or {})
    if not context.get("professor_id") or not context.get("wa_message_id"):
        return _result("invalid_context", handled=False, forward=True)
    revision = _handle_devolutiva_revision(backend, context)
    if revision is not None:
        return revision
    # A CONSULTA VENCE TUDO — antes da acao pendente E antes de classificar audio.
    #
    # "Quantas aulas eu dei de 11/08 a 15/08?" e pergunta, nao resposta a "qual
    # aula?" nem lancamento de conteudo. Quem responde e o bridge, injetando a
    # RPC no prompt. Este break-out mora aqui em cima, e nao mais so no caminho
    # de texto-sem-acao, porque o Valdo (17/08) perguntou POR AUDIO e com uma
    # `escolher_aula_chamada` aberta desde a noite de 16/08: os dois desvios que
    # ficavam ABAIXO — o `if action:` e o `classificar_intencao_audio` —
    # engoliam a consulta antes de ela ser reconhecida, e cada audio dele virava
    # "ainda nao sei de qual aula voce esta falando".
    #
    # A acao pendente NAO e cancelada aqui de proposito: se o professor estava
    # mesmo no meio de uma chamada e so quis conferir um numero, a chamada
    # continua de pe pra proxima resposta dele. O predicado e estreito
    # (interrogativo: "quantas/quais/total/ministrei/quem faltou"), entao nao
    # rouba uma resposta legitima de "qual aula?" (ver teste do refinamento).
    text = str(context.get("text") or context.get("media_extracted_text") or "")
    if parece_consulta_letiva(text):
        return _result("conversation", handled=False, forward=True)
    action = _action(backend, context)
    if action:
        # GUARDAR É INCONDICIONAL; rotear é que depende de estado.
        #
        # Até 15/08/2026 o áudio que chegava com uma ação aberta era tratado
        # como resposta de TEXTO e o `_stage_audio` lá embaixo nunca era
        # alcançado: os bytes iam pro lixo. O Isaque mandou dois áudios
        # seguidos e o da aula das 13h morreu assim — sobrou a transcrição em
        # `fabio_chat_mensagens`, sumiu o áudio. Professor manda áudio em
        # sequência: é assim que ele trabalha, não é uso errado.
        #
        # O caminho sai do `wa_message_id`, que essa mesma tabela já guarda —
        # então áudio guardado é recuperável por consulta, sem coluna nova.
        # Isto NÃO retoma o áudio sozinho: a fila de pendentes por professor
        # ainda não existe (ver RETOMADA). O que isto faz é parar de destruir.
        # Replay da MESMA mensagem não é áudio novo: é a que abriu a ação, e o
        # áudio dela já está guardado. Subir de novo desfaria a idempotência
        # que o `_handle_existing_action` garante logo abaixo.
        eh_replay = str(action.get("wa_message_id")) == str(context.get("wa_message_id"))
        guardado = None
        if context.get("kind") == "audio" and not eh_replay:
            try:
                guardado, _ = _stage_audio(backend, context)
                _parquear(backend, context, guardado)
            except Exception:  # noqa: BLE001
                # Falhar ao guardar não pode derrubar o fluxo que já funciona:
                # a pergunta pendente do professor continua valendo.
                guardado = None
        resultado = _handle_existing_action(backend, context, action)
        if guardado and resultado.get("code") == "conversation":
            # 18/08/2026: os 3 audios do Isaque foram parqueados MAS o professor
            # nunca soube — "conversation" descartava o aviso junto com o reply
            # da maquina, o LLM respondia bonito por cima, e ele mandou
            # "Confirma tudo" achando que os 3 estavam prontos. Audio parqueado
            # responde pela MAQUINA: o que foi guardado, o que esta na frente,
            # e como se livrar da pendencia. Texto de conversa segue livre.
            resultado = _result(
                "audio_parked_pending",
                reply=("Guardei esse áudio — ele entra assim que a gente fechar a "
                       f"pendência anterior.\n\n{_pergunta_pendente(action)}"),
                action_id=str(action["id"]),
            )
        elif guardado and resultado.get("reply"):
            resultado["reply"] = (
                f"{resultado['reply']} (Guardei esse áudio aqui — assim que a "
                "gente fechar o anterior, ele entra.)"
            )
        return _drenar_parqueados(backend, context, resultado)
    # `text` e a consulta ja foram tratados no topo (a consulta vence tudo).
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
        # DUVIDA SEM SINAL DE AULA NAO ABRE ACAO. Em 16/08 o "Ok" do Valdo —
        # resposta a uma pergunta de consulta — criou uma
        # `confirmar_intencao_chamada` do nada (nao havia acao pendente), e a
        # conversa terminou em "Nao gravei nada". Ambiguo COM sinal segue
        # perguntando: ali ha conteudo real e o caminho deterministico e o
        # unico que consegue grava-lo.
        if not tem_sinal_de_aula(text):
            return _result("conversation", handled=False, forward=True)
        action = _start(backend, context, "confirmar_intencao_chamada", None, {"transcricao": text, "intencao": "ambiguo"})
        return _result("confirm_call_intent", reply="Você quer bater a chamada de uma aula com isso?", action_id=str(action["id"]))
    return _start_from_candidates(backend, context, "chamada", _pool(backend, context, "chamada"), None)
