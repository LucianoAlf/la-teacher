"""Restricted LA Music lesson-registration tools for Fábio webhook routes.

These tools intentionally expose only the minimum capabilities needed by the
LA Teacher app webhook: fetch aula context, transcribe a trusted Supabase audio
URL, and create a pending lesson record through the dedicated Supabase RPC.
They do NOT expose arbitrary SQL, shell, filesystem, or generic HTTP writes.
"""

from __future__ import annotations

import importlib.util
import difflib
import json
import os
import re
import tempfile
import unicodedata
from pathlib import Path
from typing import Any, Dict, List
from urllib.parse import quote, urlparse
from datetime import datetime

import requests

from tools.registry import registry

# A tool roda fora do checkout. Carregamos exatamente o arquivo versionado do
# bridge; o espelho local existe somente para os testes e desenvolvimento.
_CONTRACT_FILENAME = "fabio_registro_normalization_contract.py"


def _contract_path(
    *,
    runtime_root: Path | None = None,
    local_file: Path | None = None,
) -> Path:
    runtime_file = (
        runtime_root
        if runtime_root is not None
        else Path(os.getenv("FABIO_CHAT_BRIDGE_DIR", "/home/fabio/fabio-chat-bridge"))
    ) / _CONTRACT_FILENAME
    fallback_file = (
        local_file
        if local_file is not None
        else Path(__file__).resolve().parents[1] / _CONTRACT_FILENAME
    )
    for candidate in (runtime_file, fallback_file):
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError("fabio_registro_normalization_contract_missing")


def _load_contract_module(contract_file: Path) -> Any:
    spec = importlib.util.spec_from_file_location("fabio_registro_normalization_contract", contract_file)
    if spec is None or spec.loader is None:
        raise RuntimeError("fabio_registro_normalization_contract_unloadable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_CONTRACT_PATH = _contract_path()
_CONTRACT_MODULE = _load_contract_module(_CONTRACT_PATH)
NormalizationContractError = _CONTRACT_MODULE.NormalizationContractError
adaptar_contrato_para_payload_rpc = _CONTRACT_MODULE.adaptar_contrato_para_payload_rpc
adaptar_payload_legado_para_contrato = _CONTRACT_MODULE.adaptar_payload_legado_para_contrato
validar_e_sanear_normalizacao = _CONTRACT_MODULE.validar_e_sanear_normalizacao

_TOOLSET = "fabio_registro_aula"
_DEFAULT_SUPABASE_URL = "https://ouqwbbermlzqqvtqwlul.supabase.co"
_MAX_AUDIO_BYTES = int(os.getenv("FABIO_AUDIO_MAX_BYTES", str(80 * 1024 * 1024)))
_HTTP_TIMEOUT = (10, 120)
_DEFAULT_WHISPER_MODEL = "large-v3-turbo"
_MAX_TRANSCRIPTION_TITLES = 24
_MAX_INITIAL_PROMPT_CHARS = 700
_MAX_HOTWORDS_CHARS = 350


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


def _clean_transcription_hint(value: Any, max_chars: int = 80) -> str:
    """Keep vocabulary hints short, single-line and inert for Whisper."""
    raw = str(value or "")
    safe = "".join(
        ch if (ch.isalnum() or ch.isspace() or ch in " _-'&./()") else " "
        for ch in raw
    )
    return re.sub(r"\s+", " ", safe).strip()[:max_chars].strip()


def _repertoire_titles(annotations: Any) -> list[str]:
    text = str(annotations or "")
    titles: list[str] = []
    for match in re.finditer(r"(?im)^\s*repert[oó]rio\s*:\s*(.+)$", text):
        for candidate in re.split(r"[,;]", match.group(1)):
            title = _clean_transcription_hint(candidate)
            if title:
                titles.append(title)
    return titles


def _normalized_hint_token(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch)).casefold()


def _apply_contextual_title_corrections(text: str, titles: list[str] | None) -> str:
    """Correct only a close phrase that shares an exact token with a known title."""
    corrected = str(text or "")
    for title in titles or []:
        title_matches = list(re.finditer(r"\b\w+\b", title, flags=re.UNICODE))
        title_tokens = [_normalized_hint_token(match.group(0)) for match in title_matches]
        if len(title_tokens) < 2:
            continue

        words = list(re.finditer(r"\b\w+\b", corrected, flags=re.UNICODE))
        tokens = [_normalized_hint_token(match.group(0)) for match in words]
        width = len(title_tokens)
        if len(tokens) < width:
            continue
        if any(tokens[i:i + width] == title_tokens for i in range(len(tokens) - width + 1)):
            continue

        title_key = " ".join(title_tokens)
        best: tuple[float, int] | None = None
        for index in range(len(tokens) - width + 1):
            candidate_tokens = tokens[index:index + width]
            if not set(candidate_tokens).intersection(title_tokens):
                continue
            score = difflib.SequenceMatcher(
                None,
                " ".join(candidate_tokens),
                title_key,
            ).ratio()
            if score >= 0.78 and (best is None or score > best[0]):
                best = (score, index)
        if best is None:
            continue

        index = best[1]
        start = words[index].start()
        end = words[index + width - 1].end()
        corrected = f"{corrected[:start]}{title}{corrected[end:]}"
    return corrected


def _transcription_hints(aula_id: int, professor_id: int) -> dict[str, Any]:
    """Build bounded STT vocabulary from the authoritative class context.

    Hints are resolved server-side. Only repertoire lines from recent history
    are used, so free-form annotations never become an instruction channel.
    Failure to obtain hints must never prevent transcription.
    """
    empty = {"initial_prompt": None, "hotwords": None, "titles": [], "titles_count": 0}
    try:
        aula_int = int(aula_id)
        professor_int = int(professor_id)
    except Exception:
        return empty

    try:
        rows, err = _context_rows(aula_int, professor_int)
    except Exception:
        return empty
    if err or not rows:
        return empty

    base = rows[0]
    turma_nome = _clean_transcription_hint(base.get("turma_nome"), 120)
    params: Dict[str, str] = {
        "select": "data_aula,turma_nome,anotacoes",
        "professor_id": f"eq.{professor_int}",
        "anotacoes": "not.is.null",
        "order": "data_aula.desc",
        "limit": "20",
    }
    if turma_nome:
        params["turma_nome"] = f"eq.{turma_nome}"

    history: list[dict[str, Any]] = []
    try:
        resp = requests.get(
            f"{_supabase_url()}/rest/v1/aulas_emusys",
            headers=_headers(),
            params=params,
            timeout=_HTTP_TIMEOUT,
        )
        data = _safe_json_response(resp)
        if resp.status_code < 400 and isinstance(data, list):
            history = [item for item in data if isinstance(item, dict)]
    except Exception:
        history = []

    titles: list[str] = []
    seen_titles: set[str] = set()
    latest_history_date = str(history[0].get("data_aula") or "") if history else ""
    for item in history:
        if latest_history_date and str(item.get("data_aula") or "") != latest_history_date:
            break
        for title in _repertoire_titles(item.get("anotacoes")):
            key = title.casefold()
            if key in seen_titles:
                continue
            seen_titles.add(key)
            titles.append(title)
            if len(titles) >= _MAX_TRANSCRIPTION_TITLES:
                break
        if len(titles) >= _MAX_TRANSCRIPTION_TITLES:
            break

    students: list[str] = []
    seen_students: set[str] = set()
    for row in rows:
        name = _clean_transcription_hint(row.get("aluno_nome"), 100)
        if not name or name.casefold() in seen_students:
            continue
        seen_students.add(name.casefold())
        students.append(name)
        if len(students) >= 8:
            break

    course = _clean_transcription_hint(base.get("curso_nome"), 100)
    teacher = _clean_transcription_hint(base.get("professor_nome"), 100)
    prompt_parts = ["Transcricao de uma aula de musica em portugues."]
    if titles:
        prompt_parts.append(
            f"Preserve estes nomes exatos se forem pronunciados: {'; '.join(titles)}."
        )
    if course:
        prompt_parts.append(f"Curso: {course}.")
    if teacher:
        prompt_parts.append(f"Professor: {teacher}.")
    if students:
        prompt_parts.append(f"Alunos: {', '.join(students)}.")
    initial_prompt = " ".join(prompt_parts)[:_MAX_INITIAL_PROMPT_CHARS].strip()

    hotword_parts = [title for title in titles for _ in range(2)] + students
    hotwords = ", ".join(hotword_parts)[:_MAX_HOTWORDS_CHARS].rstrip(" ,") or None
    return {
        "initial_prompt": initial_prompt or None,
        "hotwords": hotwords,
        "titles": titles,
        "titles_count": len(titles),
    }


def fabio_transcrever_audio_url(
    audio_url: str,
    language: str | None = "pt",
    *,
    initial_prompt: str | None = None,
    hotwords: str | None = None,
    context_titles: list[str] | None = None,
) -> str:
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

        model_name = os.getenv("FABIO_WHISPER_MODEL") or os.getenv("HERMES_STT_LOCAL_MODEL") or _DEFAULT_WHISPER_MODEL
        model = WhisperModel(model_name, device="cpu", compute_type="int8")
        transcription_options = {
            "language": language or None,
            "beam_size": 5,
            "condition_on_previous_text": False,
            "initial_prompt": initial_prompt or None,
            "hotwords": hotwords or None,
        }
        segments, info = model.transcribe(wav_path, vad_filter=True, **transcription_options)
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
            segments, info = model.transcribe(wav_path, vad_filter=False, **transcription_options)
            parts = []
            for seg in segments:
                text = (getattr(seg, "text", "") or "").strip()
                if text:
                    parts.append(text)
            text = " ".join(parts).strip()
            used_vad = False

        text = _apply_contextual_title_corrections(text, context_titles)

        return json.dumps({
            "ok": True,
            "text": text,
            "language": getattr(info, "language", None),
            "duration": getattr(info, "duration", None),
            "bytes": total,
            "vad_filter": used_vad,
            "model": model_name,
            "context_hints": bool(initial_prompt or hotwords),
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


def fabio_transcrever_audio_fila(audio_id: str, language: str | None = "pt") -> str:
    """Resolve the queue object by audio_id, signs it internally, and transcribes it."""
    audio_id = str(audio_id or "").strip()
    if not audio_id:
        return json.dumps({"ok": False, "error": "audio_id_obrigatorio"}, ensure_ascii=False)

    queue_resp = requests.get(
        f"{_supabase_url()}/rest/v1/fabio_fila_audios",
        headers=_headers(),
        params={"id": f"eq.{audio_id}", "select": "id,storage_path,aula_id,professor_id", "limit": "1"},
        timeout=_HTTP_TIMEOUT,
    )
    queue_data = _safe_json_response(queue_resp)
    if queue_resp.status_code >= 400:
        return json.dumps(
            {"ok": False, "status_code": queue_resp.status_code, "error": queue_data},
            ensure_ascii=False,
        )
    if not isinstance(queue_data, list) or len(queue_data) != 1:
        return json.dumps({"ok": False, "error": "audio_nao_encontrado"}, ensure_ascii=False)

    storage_path = str(queue_data[0].get("storage_path") or "").strip().replace("\\", "/")
    path_parts = [part for part in storage_path.split("/") if part]
    if not storage_path or storage_path.startswith("/") or ".." in path_parts:
        return json.dumps({"ok": False, "error": "storage_path_invalido"}, ensure_ascii=False)

    sign_resp = requests.post(
        f"{_supabase_url()}/storage/v1/object/sign/fabio-audios/{quote(storage_path, safe='/')}",
        headers=_headers(),
        json={"expiresIn": 600},
        timeout=_HTTP_TIMEOUT,
    )
    sign_data = _safe_json_response(sign_resp)
    if sign_resp.status_code >= 400:
        return json.dumps(
            {"ok": False, "status_code": sign_resp.status_code, "error": sign_data},
            ensure_ascii=False,
        )

    signed_path = None
    if isinstance(sign_data, dict):
        signed_path = sign_data.get("signedURL") or sign_data.get("signedUrl")
    if not isinstance(signed_path, str) or not signed_path.strip():
        return json.dumps({"ok": False, "error": "signed_url_ausente"}, ensure_ascii=False)
    signed_path = signed_path.strip()
    signed_url = signed_path if signed_path.startswith("https://") else f"{_supabase_url()}/storage/v1{signed_path}"
    queue_row = queue_data[0]
    hints = _transcription_hints(queue_row.get("aula_id"), queue_row.get("professor_id"))
    return fabio_transcrever_audio_url(
        signed_url,
        language,
        initial_prompt=hints.get("initial_prompt"),
        hotwords=hints.get("hotwords"),
        context_titles=hints.get("titles"),
    )


_TERMINAL_AUDIO_CODES = ("sem_conteudo_pedagogico", "transcricao_incompativel")


def fabio_marcar_audio_erro_terminal(
    audio_id: str,
    codigo: str,
    detalhe: str | None = None,
) -> str:
    """Stop retries for a typed semantic failure through the audited RPC."""
    audio_id = str(audio_id or "").strip()
    if not audio_id:
        return json.dumps({"ok": False, "error": "audio_id_obrigatorio"}, ensure_ascii=False)
    if codigo not in _TERMINAL_AUDIO_CODES:
        return json.dumps({"ok": False, "error": "codigo_terminal_invalido"}, ensure_ascii=False)

    resp = requests.post(
        f"{_supabase_url()}/rest/v1/rpc/fabio_marcar_audio_erro_terminal",
        headers=_headers(),
        json={
            "p_audio_id": audio_id,
            "p_codigo": codigo,
            "p_detalhe": str(detalhe or "").strip()[:360] or None,
        },
        timeout=_HTTP_TIMEOUT,
    )
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        return json.dumps(
            {"ok": False, "status_code": resp.status_code, "error": data},
            ensure_ascii=False,
        )
    return json.dumps(
        {"ok": True, "status_code": resp.status_code, "result": data},
        ensure_ascii=False,
    )


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


def _codigo_do_erro(erro: BaseException) -> str:
    """Motivo curto e inerte do erro de contrato, para viajar junto do `error`.

    O `NormalizationContractError` ja nasce com o codigo no argumento
    (`roster_invalido`, `roster_incompleto`, ...). Para os erros de tipo/chave,
    que nao carregam codigo proprio, vale o nome da excecao. Sanitiza porque
    isto acaba PERSISTIDO no campo `erro` da fila: nada de texto livre longo
    virando pseudo-diagnostico depois.
    """
    bruto = str(erro).strip() or type(erro).__name__
    limpo = re.sub(r"[^A-Za-z0-9_.:-]+", "_", bruto).strip("_")
    return limpo[:80] or type(erro).__name__


def _buscar_audio_fila(audio_id: str) -> Dict[str, Any]:
    """Resolve registration authority from the durable queue row."""
    response = requests.get(
        f"{_supabase_url()}/rest/v1/fabio_fila_audios",
        headers=_headers(),
        params={
            "id": f"eq.{audio_id}",
            "select": "id,aula_id,professor_id,origem",
            "limit": "1",
        },
        timeout=_HTTP_TIMEOUT,
    )
    data = _safe_json_response(response)
    if response.status_code >= 400:
        raise requests.RequestException(f"audio_fila_http_{response.status_code}")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise ValueError("audio_fila_invalida")
    row = data[0]
    if (
        isinstance(row.get("aula_id"), bool)
        or not isinstance(row.get("aula_id"), int)
        or isinstance(row.get("professor_id"), bool)
        or not isinstance(row.get("professor_id"), int)
        or row.get("origem") not in {"app", "whatsapp"}
    ):
        raise ValueError("audio_fila_invalida")
    return row


def fabio_criar_registro_aula(p_payload: Dict[str, Any]) -> str:
    """Call only public.fabio_criar_registro(p_payload jsonb) via Supabase REST."""
    if not isinstance(p_payload, dict):
        return json.dumps({"ok": False, "error": "p_payload must be an object"}, ensure_ascii=False)
    required = ["molde", "tronco", "fatias"]
    missing = [k for k in required if k not in p_payload]
    if missing:
        return json.dumps({"ok": False, "error": "missing required keys", "missing": missing}, ensure_ascii=False)
    raw_audio_id = p_payload.get("audio_id")
    if not isinstance(raw_audio_id, str) or not raw_audio_id.strip():
        return json.dumps({"ok": False, "error": "audio_id_obrigatorio"}, ensure_ascii=False)
    audio_id = raw_audio_id.strip()
    transcricao = p_payload.get("transcricao") if isinstance(p_payload.get("transcricao"), str) else None
    if not isinstance(p_payload.get("fatias"), list) or not p_payload["fatias"]:
        return json.dumps({"ok": False, "error": "normalizacao_invalida"}, ensure_ascii=False)

    try:
        queue_row = _buscar_audio_fila(audio_id)
        # The model organizes pedagogy; queue data owns identity and channel.
        p_payload = {
            **p_payload,
            "aula_id": queue_row["aula_id"],
            "professor_id": queue_row["professor_id"],
            "origem": queue_row["origem"],
        }
        aula_id = p_payload.get("aula_id")
        professor_id = p_payload.get("professor_id")
        if (
            isinstance(aula_id, bool)
            or not isinstance(aula_id, int)
            or isinstance(professor_id, bool)
            or not isinstance(professor_id, int)
        ):
            raise NormalizationContractError("ids_resolvidos_invalidos")

        roster, roster_meta = _buscar_roster_aula(aula_id, professor_id)
        if not isinstance(roster_meta, dict) or roster_meta.get("ok") is not True or not roster:
            raise NormalizationContractError("roster_invalido")
        expected_roster_size = roster_meta.get("qtd_contexto")
        if expected_roster_size is not None and (
            isinstance(expected_roster_size, bool)
            or not isinstance(expected_roster_size, int)
            or expected_roster_size <= 0
            or len(roster) != expected_roster_size
        ):
            raise NormalizationContractError("roster_incompleto")
        roster_ids: set[int] = set()
        for aluno in roster:
            if not isinstance(aluno, dict):
                raise NormalizationContractError("roster_invalido")
            aluno_id = aluno.get("aluno_id")
            if isinstance(aluno_id, bool) or not isinstance(aluno_id, int):
                raise NormalizationContractError("roster_invalido")
            if aluno.get("aula_id") is not None and aluno["aula_id"] != aula_id:
                raise NormalizationContractError("roster_aula_divergente")
            roster_ids.add(aluno_id)
        if not roster_ids:
            raise NormalizationContractError("roster_invalido")

        canonical = validar_e_sanear_normalizacao(
            adaptar_payload_legado_para_contrato(p_payload),
            aula_id=aula_id,
            professor_id=professor_id,
            roster_ids=roster_ids,
        )
    except requests.RequestException:
        return json.dumps({"ok": False, "error": "fila_ou_roster_indisponivel"}, ensure_ascii=False)
    except (NormalizationContractError, TypeError, ValueError) as erro:
        # `codigo` carrega o motivo REAL (roster_invalido, roster_incompleto,
        # roster_aula_divergente...). Achatar tudo num `normalizacao_invalida`
        # mudo custou caro em 15/08/2026: sem o motivo, um agente preencheu o
        # vazio com explicacao inventada ("contexto sem roster canonico e
        # transcricao cita nome divergente"), ela foi GRAVADA no campo `erro` da
        # fila, e mandou duas investigacoes atras da causa errada. A causa real
        # era roster VAZIO, nao divergente. `error` fica estavel para quem ja
        # depende dele; o motivo entra ao lado.
        return json.dumps(
            {"ok": False, "error": "normalizacao_invalida", "codigo": _codigo_do_erro(erro)},
            ensure_ascii=False,
        )

    try:
        rpc_payload = adaptar_contrato_para_payload_rpc(
            canonical,
            origem=p_payload["origem"],
            molde=p_payload["molde"],
            audio_id=audio_id or None,
        )
    except (NormalizationContractError, KeyError, TypeError, ValueError) as erro:
        return json.dumps(
            {"ok": False, "error": "normalizacao_invalida", "codigo": _codigo_do_erro(erro)},
            ensure_ascii=False,
        )

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
            fabio_atualizar_status_audio(audio_id, "normalizado", None, transcricao)
            return json.dumps({
                "ok": True,
                "status_code": 200,
                "result": {"status": "ja_existia", "registro_id": existing_data[0].get("id"), "fatias": None},
                "incertezas": canonical["incertezas"],
                "aguardando_confirmacao": bool(canonical["incertezas"]),
            }, ensure_ascii=False)

    if not _has_pedagogical_content(canonical):
        if audio_id:
            fabio_marcar_audio_erro_terminal(
                audio_id,
                "sem_conteudo_pedagogico",
                "transcricao vazia; professor precisa regravar",
            )
        return json.dumps({"ok": False, "error": "sem conteúdo pedagógico real; registro não criado", "audio_id": audio_id or None}, ensure_ascii=False)

    url = f"{_supabase_url()}/rest/v1/rpc/fabio_criar_registro"
    body = {"p_payload": rpc_payload}
    resp = requests.post(url, headers=_headers(), json=body, timeout=_HTTP_TIMEOUT)
    data = _safe_json_response(resp)
    if resp.status_code >= 400:
        if audio_id:
            fabio_atualizar_status_audio(audio_id, "erro", f"rpc fabio_criar_registro {resp.status_code}")
        return json.dumps({"ok": False, "status_code": resp.status_code, "error": data}, ensure_ascii=False)
    if audio_id:
        fabio_atualizar_status_audio(audio_id, "normalizado", None, transcricao)
    return json.dumps({
        "ok": True,
        "status_code": resp.status_code,
        "result": data,
        "incertezas": canonical["incertezas"],
        "aguardando_confirmacao": bool(canonical["incertezas"]),
    }, ensure_ascii=False)


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
    name="fabio_transcrever_audio_fila",
    toolset=_TOOLSET,
    description="Transcreve um audio da fila pelo audio_id; resolve storage_path e URL assinada internamente.",
    emoji="audio",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_transcrever_audio_fila",
        "description": "Busca exclusivamente o objeto de fabio_fila_audios pelo audio_id e o transcreve sem receber ou expor audio_url.",
        "parameters": {
            "type": "object",
            "properties": {
                "audio_id": {"type": "string", "description": "UUID exato do audio na fabio_fila_audios"},
                "language": {"type": "string", "description": "Codigo do idioma para Whisper; padrao pt"},
            },
            "required": ["audio_id"],
        },
    },
    handler=lambda args, **kw: fabio_transcrever_audio_fila(args.get("audio_id", ""), args.get("language", "pt")),
)

registry.register(
    name="fabio_marcar_audio_erro_terminal",
    toolset=_TOOLSET,
    description="Encerra uma falha semantica tipificada de audio pela RPC auditada, sem retry automatico.",
    emoji="stop",
    requires_env=["LAREPORT_SUPABASE_SERVICE_ROLE"],
    check_fn=check_requirements,
    schema={
        "name": "fabio_marcar_audio_erro_terminal",
        "description": "Use somente quando o audio nao tem conteudo pedagogico ou e incompativel com a aula. Nao use para falhas transitorias de rede ou servico.",
        "parameters": {
            "type": "object",
            "properties": {
                "audio_id": {"type": "string", "description": "UUID exato do audio na fila"},
                "codigo": {
                    "type": "string",
                    "enum": ["sem_conteudo_pedagogico", "transcricao_incompativel"],
                },
                "detalhe": {"type": "string", "description": "Resumo curto da evidencia semantica"},
            },
            "required": ["audio_id", "codigo"],
        },
    },
    handler=lambda args, **kw: fabio_marcar_audio_erro_terminal(
        args.get("audio_id", ""),
        args.get("codigo", ""),
        args.get("detalhe"),
    ),
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
                "audio_id": {
                    "type": "string",
                    "description": (
                        "UUID exato do áudio na fabio_fila_audios recebido no payload bruto; "
                        "nunca use registro_id como audio_id. O tool injeta este valor no p_payload."
                    ),
                },
                "p_payload": {
                    "type": "object",
                    "description": "Payload pedagogico com molde, tronco, fatias e transcricao. Aula, professor e origem sao derivados da linha autoritativa de fabio_fila_audios.",
                }
            },
            "required": ["audio_id", "p_payload"],
        },
    },
    handler=lambda args, **kw: fabio_criar_registro_aula({
        **(args.get("p_payload") or {}),
        **({"audio_id": args.get("audio_id")} if args.get("audio_id") else {}),
    }),
)
