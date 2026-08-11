"""Restricted LA Music lesson-registration tools for Fábio webhook routes.

These tools intentionally expose only the minimum capabilities needed by the
LA Teacher app webhook: fetch aula context, transcribe a trusted Supabase audio
URL, and create a pending lesson record through the dedicated Supabase RPC.
They do NOT expose arbitrary SQL, shell, filesystem, or generic HTTP writes.
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List
from urllib.parse import urlparse
from datetime import datetime

import requests

from tools.registry import registry

_TOOLSET = "fabio_registro_aula"
_DEFAULT_SUPABASE_URL = "https://ouqwbbermlzqqvtqwlul.supabase.co"
_MAX_AUDIO_BYTES = int(os.getenv("FABIO_AUDIO_MAX_BYTES", str(80 * 1024 * 1024)))
_HTTP_TIMEOUT = (10, 120)


def _supabase_url() -> str:
    return (os.getenv("LAREPORT_SUPABASE_URL") or _DEFAULT_SUPABASE_URL).rstrip("/")


def _service_role() -> str:
    return os.getenv("LAREPORT_SUPABASE_SERVICE_ROLE") or os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""


def _headers(prefer: str | None = None) -> Dict[str, str]:
    key = _service_role()
    if not key:
        raise RuntimeError("LAREPORT_SUPABASE_SERVICE_ROLE is not configured")
    h = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if prefer:
        h["Prefer"] = prefer
    return h


def _safe_json_response(resp: requests.Response) -> Any:
    try:
        return resp.json()
    except Exception:
        return resp.text[:4000]


def check_requirements() -> bool:
    return bool(_service_role())


def _validate_https_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https":
        raise ValueError("audio_url must be https")
    if not parsed.netloc:
        raise ValueError("audio_url missing host")
    # The app currently sends temporary Supabase Storage URLs. Keep the guard
    # permissive enough for signed Supabase host variants, but reject obvious
    # localhost/private shortcut hosts.
    host = parsed.hostname or ""
    if host in {"localhost", "127.0.0.1", "::1"} or host.endswith(".local"):
        raise ValueError("audio_url host is not allowed")


def fabio_buscar_contexto_aula(aula_id: int, professor_id: int | None = None) -> str:
    """Return rows from vw_fabio_aulas_contexto for one aula.

    The returned rows let the agent map named students to aluno_id and, for
    group classes, to each student's own aula_local_id for the RPC fatias.
    """
    params: Dict[str, str] = {
        "aula_local_id": f"eq.{int(aula_id)}",
        "select": "aula_local_id,aula_emusys_id,unidade_id,unidade_codigo,unidade_nome,data_aula,data_hora_inicio,data_hora_fim,horario_inicio_brt,horario_fim_brt,aula_tipo,aula_categoria,turma_nome,curso_nome,sala_nome,professor_id,professor_nome,aluno_id,aluno_nome,presenca_status,cancelada,nr_da_aula,qtd_alunos,anotacoes_fabio,qualidade_contexto",
        "order": "aluno_nome.asc",
    }
    if professor_id is not None:
        params["professor_id"] = f"eq.{int(professor_id)}"
    url = f"{_supabase_url()}/rest/v1/vw_fabio_aulas_contexto"
    resp = requests.get(url, headers=_headers(), params=params, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        return json.dumps({"ok": False, "status_code": resp.status_code, "error": data}, ensure_ascii=False)
    return json.dumps({"ok": True, "rows": data}, ensure_ascii=False)



def _weekday_pt(date_value: str | None) -> str | None:
    if not date_value:
        return None
    try:
        d = datetime.fromisoformat(str(date_value)[:10]).date()
    except Exception:
        return None
    return ["Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado", "Domingo"][d.weekday()]


def _time_hhmmss(value: str | None) -> str | None:
    if not value:
        return None
    text = str(value).strip()
    if "T" in text:
        text = text.split("T", 1)[1]
    text = text.split("+", 1)[0].split("-03", 1)[0].split("Z", 1)[0]
    parts = text.split(":")
    if len(parts) >= 2:
        hh = parts[0].zfill(2)
        mm = parts[1].zfill(2)
        ss = (parts[2] if len(parts) >= 3 else "00").split(".", 1)[0].zfill(2)
        return f"{hh}:{mm}:{ss}"
    return None


def _context_rows(aula_id: int, professor_id: int | None = None) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    params: Dict[str, str] = {
        "aula_local_id": f"eq.{int(aula_id)}",
        "select": "aula_local_id,aula_emusys_id,unidade_id,unidade_codigo,unidade_nome,data_aula,data_hora_inicio,data_hora_fim,horario_inicio_brt,horario_fim_brt,aula_tipo,aula_categoria,turma_nome,curso_nome,sala_nome,professor_id,professor_nome,aluno_id,aluno_nome,presenca_status,cancelada,nr_da_aula,qtd_alunos,anotacoes_fabio,qualidade_contexto",
        "order": "aluno_nome.asc",
    }
    if professor_id is not None:
        params["professor_id"] = f"eq.{int(professor_id)}"
    resp = requests.get(f"{_supabase_url()}/rest/v1/vw_fabio_aulas_contexto", headers=_headers(), params=params, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400 or not isinstance(data, list):
        return [], {"status_code": resp.status_code, "error": data}
    return data, None


def _dedupe_roster(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    seen: set[int] = set()
    for row in rows:
        aluno_id = row.get("aluno_id")
        if aluno_id is None:
            continue
        try:
            aid = int(aluno_id)
        except Exception:
            continue
        if aid in seen:
            continue
        seen.add(aid)
        out.append({
            "aluno_id": aid,
            "aluno_nome": row.get("aluno_nome"),
            "aula_id": row.get("aula_local_id") or row.get("aula_id"),
            "fonte": row.get("fonte") or row.get("qualidade_contexto") or "contexto",
        })
    return out


def _buscar_roster_aula(aula_id: int, professor_id: int | None = None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Resolve roster real da aula para impedir tronco null + 0 fatias."""
    ctx_rows, err = _context_rows(aula_id, professor_id)
    if err:
        return [], {"ok": False, "erro": err, "fonte": "vw_fabio_aulas_contexto"}
    if not ctx_rows:
        return [], {"ok": False, "erro": "aula não encontrada", "fonte": "vw_fabio_aulas_contexto"}

    roster = _dedupe_roster(ctx_rows)
    base = ctx_rows[0]
    expected = base.get("qtd_alunos")
    try:
        expected_int = int(expected) if expected is not None else None
    except Exception:
        expected_int = None
    if roster:
        return roster, {"ok": True, "fonte": "vw_fabio_aulas_contexto", "qtd_contexto": expected_int, "qtd_roster": len(roster)}

    dia = _weekday_pt(base.get("data_aula"))
    horario = _time_hhmmss(base.get("horario_inicio_brt") or base.get("data_hora_inicio"))
    if not (base.get("professor_id") and base.get("unidade_id") and base.get("curso_nome") and dia and horario):
        return [], {"ok": False, "erro": "contexto insuficiente para fallback de roster", "qtd_contexto": expected_int}

    params: Dict[str, str] = {
        "select": "aluno_id,aluno_nome,curso_nome,dia_aula,horario_aula,professor_id,unidade_id,unidade_codigo,aluno_status,tipo_matricula_nome,emusys_matricula_id",
        "professor_id": f"eq.{int(base['professor_id'])}",
        "unidade_id": f"eq.{base['unidade_id']}",
        "curso_nome": f"eq.{base['curso_nome']}",
        "dia_aula": f"eq.{dia}",
        "horario_aula": f"eq.{horario}",
        "order": "aluno_nome.asc",
    }
    resp = requests.get(f"{_supabase_url()}/rest/v1/vw_fabio_carteira_professor", headers=_headers(), params=params, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400 or not isinstance(data, list):
        return [], {"ok": False, "erro": data, "status_code": resp.status_code, "fonte": "vw_fabio_carteira_professor"}
    roster = _dedupe_roster([{**r, "aula_local_id": int(aula_id), "fonte": "vw_fabio_carteira_professor"} for r in data])
    meta = {"ok": True, "fonte": "vw_fabio_carteira_professor", "qtd_contexto": expected_int, "qtd_roster": len(roster), "dia": dia, "horario": horario}
    if expected_int is not None and len(roster) != expected_int:
        meta["alerta"] = "qtd_roster_diferente_de_qtd_alunos"
    return roster, meta


def fabio_buscar_roster_aula(aula_id: int, professor_id: int | None = None) -> str:
    roster, meta = _buscar_roster_aula(aula_id, professor_id)
    return json.dumps({"ok": bool(roster), "roster": roster, "meta": meta}, ensure_ascii=False)


def fabio_buscar_presencas_pendentes_professor(professor_id: Any) -> str:
    """Read-only RPC wrapper for professor attendance-governance pending items."""
    try:
        prof_int = int(professor_id)
    except Exception:
        return json.dumps({"ok": False, "error": "professor_id inválido"}, ensure_ascii=False)

    url = f"{_supabase_url()}/rest/v1/rpc/fabio_presencas_pendentes_professor"
    resp = requests.post(url, headers=_headers(), json={"p_professor_id": prof_int}, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        return json.dumps({"ok": False, "status_code": resp.status_code, "error": data}, ensure_ascii=False)
    return json.dumps({"ok": True, "status_code": resp.status_code, "result": data}, ensure_ascii=False)


def _normalizar_shape_com_roster(p_payload: Dict[str, Any]) -> tuple[Dict[str, Any] | None, dict[str, Any] | None]:
    """Garante que nunca seja criado tronco aluno_id null + 0 fatias.

    A RPC pública atual hardcoda aluno_id null no tronco. Até o banco aceitar
    tronco.aluno_id, o caminho seguro é materializar fatias a partir do roster.
    Individual vira 1 fatia; turma vira 1 fatia por aluno.
    """
    fatias = p_payload.get("fatias")
    if isinstance(fatias, list) and len(fatias) > 0:
        # A Alma/LLM pode mandar presenca no topo da fatia. A RPC atual persiste
        # apenas fatia->campos, então precisamos copiar fatia.presenca para
        # campos.presenca antes de retornar o shape já materializado.
        novas_fatias = []
        changed = False
        for fatia in fatias:
            if not isinstance(fatia, dict):
                novas_fatias.append(fatia)
                continue
            nova = dict(fatia)
            campos = nova.get("campos") if isinstance(nova.get("campos"), dict) else {}
            if "presenca" in nova and "presenca" not in campos:
                campos = {**campos, "presenca": nova.get("presenca")}
                nova["campos"] = campos
                changed = True
            novas_fatias.append(nova)
        if changed:
            p_payload = dict(p_payload)
            p_payload["fatias"] = novas_fatias
        return p_payload, None

    try:
        aula_int = int(p_payload.get("aula_id"))
        prof_int = int(p_payload.get("professor_id")) if p_payload.get("professor_id") is not None else None
    except Exception:
        return None, {"error": "aula_id/professor_id inválidos para resolver roster"}

    roster, meta = _buscar_roster_aula(aula_int, prof_int)
    if not roster:
        return None, {"error": "roster não resolvido; registro não criado para evitar tronco null + 0 fatias", "meta": meta}

    expected = meta.get("qtd_contexto") if isinstance(meta, dict) else None
    if isinstance(expected, int) and expected > 0 and len(roster) != expected:
        return None, {"error": "roster divergente de qtd_alunos; registro não criado", "meta": meta, "roster": roster}

    tronco = p_payload.get("tronco") if isinstance(p_payload.get("tronco"), dict) else {}
    texto = tronco.get("texto") or p_payload.get("texto_consolidado")
    campos_base = tronco.get("campos") if isinstance(tronco.get("campos"), dict) else {}
    novas_fatias = []
    for aluno in roster:
        novas_fatias.append({
            "aula_id": aluno.get("aula_id") or aula_int,
            "aluno_id": aluno["aluno_id"],
            "texto": texto,
            "campos": {**campos_base, "aluno_nome": aluno.get("aluno_nome"), "shape_autogerado_por_roster": True},
        })
    p_payload = dict(p_payload)
    p_payload["fatias"] = novas_fatias
    p_payload["tronco"] = {**tronco, "campos": {**campos_base, "shape_roster_meta": meta}}
    return p_payload, None


def fabio_transcrever_audio_url(audio_url: str, language: str | None = "pt") -> str:
    """Download and transcribe a temporary Supabase audio URL with local Whisper."""
    _validate_https_url(audio_url)
    with requests.get(audio_url, stream=True, timeout=_HTTP_TIMEOUT) as resp:
        if resp.status_code >= 400:
            return json.dumps({"ok": False, "status_code": resp.status_code, "error": resp.text[:1000]}, ensure_ascii=False)
        suffix = Path(urlparse(audio_url).path).suffix or ".audio"
        total = 0
        with tempfile.NamedTemporaryFile(prefix="fabio_audio_", suffix=suffix, delete=False) as f:
            tmp_path = f.name
            try:
                for chunk in resp.iter_content(chunk_size=1024 * 1024):
                    if not chunk:
                        continue
                    total += len(chunk)
                    if total > _MAX_AUDIO_BYTES:
                        return json.dumps({"ok": False, "error": "audio too large", "max_bytes": _MAX_AUDIO_BYTES}, ensure_ascii=False)
                    f.write(chunk)
            except Exception:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                raise
    try:
        import subprocess
        from faster_whisper import WhisperModel

        # Browser MediaRecorder usually uploads WebM/Opus. faster-whisper can
        # often read it directly, but normalizing to mono 16 kHz WAV removes
        # container/codec edge cases from the production pipeline.
        wav_path = tmp_path + ".wav"
        subprocess.run(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", tmp_path, "-ac", "1", "-ar", "16000", "-vn", wav_path,
            ],
            check=True,
            timeout=90,
        )

        model_name = os.getenv("FABIO_WHISPER_MODEL") or os.getenv("HERMES_STT_LOCAL_MODEL") or "base"
        model = WhisperModel(model_name, device="cpu", compute_type="int8")
        segments, info = model.transcribe(wav_path, language=language or None, vad_filter=True)
        parts: List[str] = []
        for seg in segments:
            text = (getattr(seg, "text", "") or "").strip()
            if text:
                parts.append(text)
        text = " ".join(parts).strip()
        used_vad = True

        # WebM/Opus gravado pelo browser pode ser classificado como não-fala
        # pelo VAD do faster-whisper mesmo com áudio válido. Se o VAD remover
        # tudo, refaz uma única vez sem VAD. Isso preserva o guardrail: não
        # inventa conteúdo, só evita falso vazio do transcritor.
        if not text:
            segments, info = model.transcribe(wav_path, language=language or None, vad_filter=False)
            parts = []
            for seg in segments:
                text = (getattr(seg, "text", "") or "").strip()
                if text:
                    parts.append(text)
            text = " ".join(parts).strip()
            used_vad = False

        return json.dumps({
            "ok": True,
            "text": text,
            "language": getattr(info, "language", None),
            "duration": getattr(info, "duration", None),
            "bytes": total,
            "vad_filter": used_vad,
            "model": model_name,
        }, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"ok": False, "error": f"transcription_failed: {type(e).__name__}: {e}"}, ensure_ascii=False)
    finally:
        for _p in (locals().get("wav_path"), tmp_path):
            if not _p:
                continue
            try:
                os.unlink(_p)
            except OSError:
                pass


def fabio_atualizar_status_audio(audio_id: str, status: str, erro: str | None = None, transcricao: str | None = None) -> str:
    """Update only the queue status for one Fábio audio row.

    This is intentionally narrow: no arbitrary SQL, no table choice, and only
    the lifecycle states used by the audio queue.
    """
    allowed = {"pendente", "transcrevendo", "transcrito", "normalizado", "erro"}
    if status not in allowed:
        return json.dumps({"ok": False, "error": "invalid status", "allowed": sorted(allowed)}, ensure_ascii=False)
    if not audio_id:
        return json.dumps({"ok": False, "error": "audio_id is required"}, ensure_ascii=False)

    if status == "normalizado":
        check_url = f"{_supabase_url()}/rest/v1/fabio_registros_aula"
        check_resp = requests.get(
            check_url,
            headers=_headers(),
            params={"audio_id": f"eq.{audio_id}", "select": "id", "limit": "1"},
            timeout=_HTTP_TIMEOUT,
        )
        check_data = _safe_json_response(check_resp)
        if check_resp.status_code >= 400:
            return json.dumps({"ok": False, "status_code": check_resp.status_code, "error": check_data}, ensure_ascii=False)
        if not check_data:
            status = "erro"
            erro = erro or "normalização sem registro criado; verificar transcrição/RPC"

    url = f"{_supabase_url()}/rest/v1/fabio_fila_audios"
    body: Dict[str, Any] = {"status": status, "atualizado_em": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat()}
    body["erro"] = erro[:500] if erro else None
    if transcricao is not None:
        body["transcricao"] = transcricao
    resp = requests.patch(url, headers=_headers(prefer="return=representation"), params={"id": f"eq.{audio_id}"}, json=body, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        return json.dumps({"ok": False, "status_code": resp.status_code, "error": data}, ensure_ascii=False)
    return json.dumps({"ok": True, "status_code": resp.status_code, "result": data}, ensure_ascii=False)


def _has_pedagogical_content(value: Any) -> bool:
    """Return True if payload carries real teacher-derived content.

    Structural labels, ids and empty placeholders do not count. This prevents
    empty transcriptions from creating fake/blank lesson records.
    """
    if value is None:
        return False
    if isinstance(value, str):
        t = value.strip()
        if not t or t in {"—", "-", "null", "None"}:
            return False
        placeholders = ["a completar com o professor", "transcrição vazia", "transcricao vazia"]
        return not any(p in t.lower() for p in placeholders)
    if isinstance(value, dict):
        ignored = {"audio_id", "aula_id", "professor_id", "aluno_id", "origem", "molde", "presenca", "status"}
        return any(_has_pedagogical_content(v) for k, v in value.items() if k not in ignored)
    if isinstance(value, list):
        return any(_has_pedagogical_content(v) for v in value)
    return False


def _infer_audio_id_for_payload(p_payload: Dict[str, Any]) -> tuple[str, Any]:
    """Recover the queue audio_id when the model omits it from p_payload.

    The webhook prompt carries audio_id and the agent usually uses it in prior
    tool calls, but occasionally drops it in the final RPC payload. At that
    point the queue may already be transcrito/erro, so searching only
    status=transcrevendo produces candidates=[]. Keep this fallback narrow:
    same aula/professor, recent lifecycle row, and prefer rows without an
    existing registro.
    """
    try:
        aula_id = int(p_payload.get("aula_id"))
        professor_id = int(p_payload.get("professor_id"))
    except Exception:
        return "", {"error": "aula_id/professor_id inválidos para inferir audio_id"}

    try:
        import datetime as _dt
        since = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(minutes=90)).isoformat()
        q_resp = requests.get(
            f"{_supabase_url()}/rest/v1/fabio_fila_audios",
            headers=_headers(),
            params={
                "select": "id,status,erro,atualizado_em,criado_em,transcricao",
                "aula_id": f"eq.{aula_id}",
                "professor_id": f"eq.{professor_id}",
                "status": "in.(pendente,transcrevendo,transcrito,erro)",
                "atualizado_em": f"gte.{since}",
                "order": "atualizado_em.desc",
                "limit": "5",
            },
            timeout=_HTTP_TIMEOUT,
        )
        q_data = _safe_json_response(q_resp)
        if q_resp.status_code >= 400 or not isinstance(q_data, list):
            return "", q_data

        candidates = []
        for row in q_data:
            audio_id = str(row.get("id") or "")
            if not audio_id:
                continue
            existing_resp = requests.get(
                f"{_supabase_url()}/rest/v1/fabio_registros_aula",
                headers=_headers(),
                params={"audio_id": f"eq.{audio_id}", "select": "id", "limit": "1"},
                timeout=_HTTP_TIMEOUT,
            )
            existing_data = _safe_json_response(existing_resp)
            if existing_resp.status_code < 400 and not existing_data:
                candidates.append(row)

        pool = candidates or q_data
        if len(pool) == 1:
            return str(pool[0].get("id") or ""), pool

        # Same aula/professor can have multiple retrying queue rows. When that
        # happens, disambiguate by the transcription/content the model placed in
        # the final payload; never pick by timestamp alone if text identifies the
        # row.
        payload_text = json.dumps(p_payload, ensure_ascii=False).lower()
        text_matches = []
        for row in pool:
            tr = str(row.get("transcricao") or "").strip().lower()
            if not tr:
                continue
            probes = [tr[:80], tr[:50], tr[:32]]
            if any(probe and probe in payload_text for probe in probes):
                text_matches.append(row)
        if len(text_matches) == 1:
            return str(text_matches[0].get("id") or ""), text_matches

        # Fallback only for the common case where a new recording is being
        # processed while an old retry from the same aula/professor is still in
        # erro. If exactly one candidate was created very recently, use it.
        recent_created = []
        recent_cutoff = _dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(hours=4)
        for row in pool:
            try:
                created = _dt.datetime.fromisoformat(str(row.get("criado_em")).replace("Z", "+00:00"))
            except Exception:
                continue
            if created >= recent_cutoff:
                recent_created.append(row)
        if len(recent_created) == 1:
            return str(recent_created[0].get("id") or ""), recent_created

        return "", pool
    except Exception as exc:
        return "", {"error": str(exc)}


def fabio_criar_registro_aula(p_payload: Dict[str, Any]) -> str:
    """Call only public.fabio_criar_registro(p_payload jsonb) via Supabase REST."""
    if not isinstance(p_payload, dict):
        return json.dumps({"ok": False, "error": "p_payload must be an object"}, ensure_ascii=False)
    required = ["aula_id", "professor_id", "origem", "molde", "tronco", "fatias"]
    missing = [k for k in required if k not in p_payload]
    if missing:
        return json.dumps({"ok": False, "error": "missing required keys", "missing": missing}, ensure_ascii=False)
    if p_payload.get("origem") != "app":
        return json.dumps({"ok": False, "error": "origem must be 'app' for this route"}, ensure_ascii=False)

    audio_id = str(p_payload.get("audio_id") or "")
    if not audio_id and p_payload.get("origem") == "app":
        # Safety net for webhook turns: the model occasionally omitted audio_id
        # from p_payload even though the webhook message had it and used it in
        # previous tool calls. The queue may already be transcrito/erro here.
        audio_id, candidates = _infer_audio_id_for_payload(p_payload)
        if audio_id:
            p_payload["audio_id"] = audio_id
        else:
            return json.dumps({
                "ok": False,
                "error": "audio_id obrigatório para origem app",
                "debug": {
                    "aula_id": p_payload.get("aula_id"),
                    "professor_id": p_payload.get("professor_id"),
                    "payload_has_transcricao": bool(p_payload.get("transcricao") or p_payload.get("texto_consolidado")),
                },
                "candidates": candidates,
            }, ensure_ascii=False)
    if audio_id:
        existing_resp = requests.get(
            f"{_supabase_url()}/rest/v1/fabio_registros_aula",
            headers=_headers(),
            params={"audio_id": f"eq.{audio_id}", "select": "id", "limit": "1"},
            timeout=_HTTP_TIMEOUT,
        )
        existing_data = _safe_json_response(existing_resp)
        if existing_resp.status_code >= 400:
            return json.dumps({"ok": False, "status_code": existing_resp.status_code, "error": existing_data}, ensure_ascii=False)
        if existing_data:
            fabio_atualizar_status_audio(audio_id, "normalizado", None, p_payload.get("transcricao"))
            return json.dumps({"ok": True, "status_code": 200, "result": {"status": "ja_existia", "registro_id": existing_data[0].get("id"), "fatias": None}}, ensure_ascii=False)

    content_probe = {
        "tronco": p_payload.get("tronco"),
        "fatias": p_payload.get("fatias"),
        "texto_consolidado": p_payload.get("texto_consolidado"),
    }
    if not _has_pedagogical_content(content_probe):
        if audio_id:
            fabio_atualizar_status_audio(audio_id, "erro", "transcricao vazia; professor precisa regravar")
        return json.dumps({"ok": False, "error": "sem conteúdo pedagógico real; registro não criado", "audio_id": audio_id or None}, ensure_ascii=False)

    p_payload, shape_error = _normalizar_shape_com_roster(p_payload)
    if shape_error:
        if audio_id:
            fabio_atualizar_status_audio(audio_id, "erro", shape_error.get("error", "shape inválido"))
        return json.dumps({"ok": False, **shape_error, "audio_id": audio_id or None}, ensure_ascii=False)

    url = f"{_supabase_url()}/rest/v1/rpc/fabio_criar_registro"
    body = {"p_payload": p_payload}
    resp = requests.post(url, headers=_headers(), json=body, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        if audio_id:
            fabio_atualizar_status_audio(audio_id, "erro", f"rpc fabio_criar_registro {resp.status_code}")
        return json.dumps({"ok": False, "status_code": resp.status_code, "error": data}, ensure_ascii=False)
    if audio_id:
        fabio_atualizar_status_audio(audio_id, "normalizado", None, p_payload.get("transcricao"))
    return json.dumps({"ok": True, "status_code": resp.status_code, "result": data}, ensure_ascii=False)


registry.register(
    name="fabio_buscar_contexto_aula",
    toolset=_TOOLSET,
    description="Busca contexto pedagógico restrito de uma aula na view vw_fabio_aulas_contexto.",
    emoji="🎼",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_buscar_contexto_aula",
        "description": "Busca, por aula_id, os alunos e metadados necessários para montar tronco/fatias do registro de aula. Não executa SQL livre.",
        "parameters": {
            "type": "object",
            "properties": {
                "aula_id": {"type": "integer", "description": "aula_local_id / PK da aula no LA Report"},
                "professor_id": {"type": "integer", "description": "ID interno do professor, opcional para validação"},
            },
            "required": ["aula_id"],
        },
    },
    handler=lambda args, **kw: fabio_buscar_contexto_aula(args.get("aula_id"), args.get("professor_id")),
)

registry.register(
    name="fabio_buscar_roster_aula",
    toolset=_TOOLSET,
    description="Resolve o roster real da aula usando contexto e fallback seguro na carteira do professor.",
    emoji="👥",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_buscar_roster_aula",
        "description": "Busca alunos reais da aula para decidir shape individual/turma. Não executa SQL livre.",
        "parameters": {
            "type": "object",
            "properties": {
                "aula_id": {"type": "integer", "description": "aula_local_id / PK da aula no LA Report"},
                "professor_id": {"type": "integer", "description": "ID interno do professor, opcional para validação"},
            },
            "required": ["aula_id"],
        },
    },
    handler=lambda args, **kw: fabio_buscar_roster_aula(args.get("aula_id"), args.get("professor_id")),
)


registry.register(
    name="fabio_buscar_presencas_pendentes_professor",
    toolset=_TOOLSET,
    description="Busca pendências de presença forte por professor via RPC read-only fabio_presencas_pendentes_professor.",
    emoji="📋",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_buscar_presencas_pendentes_professor",
        "description": "Retorna JSON com dentro_janela (dias<=3, detalhado por aluno) e escalar_coordenacao (dias>3, resumo por aula), sem escrever e sem enviar mensagem.",
        "parameters": {
            "type": "object",
            "properties": {
                "professor_id": {"type": "integer", "description": "ID interno do professor no LA Report"}
            },
            "required": ["professor_id"],
        },
    },
    handler=lambda args, **kw: fabio_buscar_presencas_pendentes_professor(args.get("professor_id")),
)

registry.register(
    name="fabio_transcrever_audio_url",
    toolset=_TOOLSET,
    description="Transcreve áudio temporário do Supabase Storage usando Whisper local.",
    emoji="🎙️",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_transcrever_audio_url",
        "description": "Baixa e transcreve um audio_url HTTPS temporário (Supabase Storage). Retorna texto transcrito; não expõe acesso genérico a arquivos ou terminal.",
        "parameters": {
            "type": "object",
            "properties": {
                "audio_url": {"type": "string", "description": "URL HTTPS temporária do áudio"},
                "language": {"type": "string", "description": "Código do idioma para Whisper; padrão pt"},
            },
            "required": ["audio_url"],
        },
    },
    handler=lambda args, **kw: fabio_transcrever_audio_url(args.get("audio_url", ""), args.get("language", "pt")),
)

registry.register(
    name="fabio_atualizar_status_audio",
    toolset=_TOOLSET,
    description="Atualiza status e, quando disponível, persiste a transcrição de um áudio na fila Fábio.",
    emoji="🧾",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_atualizar_status_audio",
        "description": "Marca um audio_id da fabio_fila_audios e persiste transcricao quando disponível. Use transcricao logo após transcrever e também ao encerrar como normalizado.",
        "parameters": {
            "type": "object",
            "properties": {
                "audio_id": {"type": "string", "description": "UUID do áudio na fila"},
                "status": {"type": "string", "enum": ["pendente", "transcrevendo", "transcrito", "normalizado", "erro"]},
                "erro": {"type": "string", "description": "Mensagem curta quando status=erro"},
                "transcricao": {"type": "string", "description": "Texto integral transcrito do áudio; obrigatório quando status=transcrito e recomendado ao normalizar"},
            },
            "required": ["audio_id", "status"],
        },
    },
    handler=lambda args, **kw: fabio_atualizar_status_audio(args.get("audio_id", ""), args.get("status", ""), args.get("erro"), args.get("transcricao")),
)

registry.register(
    name="fabio_criar_registro_aula",
    toolset=_TOOLSET,
    description="Chama exclusivamente a RPC Supabase fabio_criar_registro para criar registro aguardando confirmação.",
    emoji="✅",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_criar_registro_aula",
        "description": "Grava o registro normalizado chamando somente public.fabio_criar_registro(p_payload). Use status aguardando_confirmacao via RPC; não escreve direto em tabelas.",
        "parameters": {
            "type": "object",
            "properties": {
                "audio_id": {"type": "string", "description": "UUID do áudio na fila; opcional no topo, o tool injeta no p_payload se faltar."},
                "p_payload": {
                    "type": "object",
                    "description": "Payload completo com audio_id, aula_id, professor_id, origem='app', molde, tronco, fatias e, quando origem áudio, transcricao integral.",
                }
            },
            "required": ["p_payload"],
        },
    },
    handler=lambda args, **kw: fabio_criar_registro_aula({
        **(args.get("p_payload") or {}),
        **({"audio_id": args.get("audio_id")} if args.get("audio_id") else {}),
    }),
)
