#!/usr/bin/env python3
"""Transforma o áudio da aula experimental nos quatro campos do registro.

O QUE ESTE WORKER É
Uma esteira determinística com UM passo de modelo no meio:

    1. fabio_claim_audio_experimental        pega da fila (marca transcrevendo)
    2. GET /storage/v1/object/fabio-audios   baixa o que o professor gravou
    3. ffmpeg -> wav 16k mono -> faster-whisper   transcreve
    4. skill `registro_experimental_audio` + run_hermes_api   divide em 4 campos
    5. fabio_gravar_registro_experimental_de_audio   grava e fecha a fila

Falhou em qualquer ponto: fabio_falhou_audio_experimental devolve pra fila.
Na terceira, para de circular — fila que retenta pra sempre nunca acusa nada.

POR QUE ELE NÃO PASSA PELO HERMES
O agente monta registro de aula pelo ROSTER de alunos. A experimental não tem
aluno: tem lead. Desde a 050 o gatilho da fila só chama a edge do Hermes quando
`vinculo_id` é nulo — este worker atende o resto.

POR QUE O PROMPT NÃO ESTÁ AQUI
Ele mora em `fabio_skills` (migration 052). Texto pedagógico que só muda com
deploy é texto que ninguém revisa, e quem sabe afinar é a coordenação.

O QUE ELE NUNCA FAZ
Não envia WhatsApp e não confirma nada. O registro nasce (ou continua) em
`aguardando_confirmacao`: quem manda mensagem pra outra pessoa é o professor,
tocando em Confirmar. A esteira só deixa os campos preenchidos esperando.

USO
    python3 fabio_audio_experimental_worker.py [--lote N] [--dry-run] [--json]

    --dry-run NÃO reivindica: só lê a fila. Ensaio que pega o lease é ensaio
    que trava produção.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests

import fabio_chat_bridge as bridge

WORKER = os.getenv("FABIO_AUDIO_EXP_WORKER", f"audio-experimental@{socket.gethostname()}")
LOTE = int(os.getenv("FABIO_AUDIO_EXP_LOTE", "3"))
BUCKET = os.getenv("FABIO_AUDIO_BUCKET", "fabio-audios")
MODELO_WHISPER = os.getenv("FABIO_WHISPER_MODEL") or os.getenv("HERMES_STT_LOCAL_MODEL") or "base"
MAX_BYTES = int(os.getenv("FABIO_AUDIO_EXP_MAX_BYTES", str(40 * 1024 * 1024)))
SKILL = "registro_experimental_audio"

CAMPOS = ("anotacao_pedagogica", "devolutiva_familia", "proximos_passos", "leitura_de_conversao")

_modelo = None


def log(msg: str, **fields: Any) -> None:
    bridge.log(f"audio_experimental_{msg}", **fields)


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:500]}")
    return r.json() if r.text else None


# ── A skill ────────────────────────────────────────────────────────────────
def skill_ativa() -> str:
    linhas = bridge.sb_get(
        "/rest/v1/fabio_skills",
        {"nome": f"eq.{SKILL}", "ativa": "is.true", "select": "conteudo,versao", "limit": "1"},
    )
    if not linhas:
        # Sem skill não há como dividir sem inventar critério aqui dentro —
        # que é exatamente o que a 052 existe pra impedir.
        raise RuntimeError(f"nenhuma skill '{SKILL}' ativa")
    return linhas[0]["conteudo"]


# ── O áudio ────────────────────────────────────────────────────────────────
def baixar(storage_path: str) -> Path:
    url = f"{bridge.SUPABASE_URL}/storage/v1/object/{BUCKET}/{storage_path}"
    sufixo = Path(storage_path).suffix or ".audio"
    with requests.get(url, headers=bridge.sb_headers(), stream=True, timeout=60) as r:
        if r.status_code >= 400:
            raise RuntimeError(f"storage {r.status_code}: {r.text[:200]}")
        total = 0
        with tempfile.NamedTemporaryFile(prefix="fabio_exp_", suffix=sufixo, delete=False) as f:
            destino = Path(f.name)
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                total += len(chunk)
                if total > MAX_BYTES:
                    raise RuntimeError(f"audio grande demais (> {MAX_BYTES} bytes)")
                f.write(chunk)
    return destino


def transcrever(caminho: Path) -> str:
    """Mesmo caminho do Hermes: normaliza pra WAV mono 16k e passa no whisper.

    O fallback sem VAD não é zelo: WebM/Opus do MediaRecorder às vezes é
    classificado como não-fala e o VAD devolve vazio com áudio válido. Sem essa
    segunda passada, o professor grava, o worker "funciona", e o registro sai
    em branco.
    """
    global _modelo
    from faster_whisper import WhisperModel

    wav = caminho.with_suffix(caminho.suffix + ".wav")
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-i", str(caminho), "-ac", "1", "-ar", "16000", "-vn", str(wav)],
        check=True, timeout=180,
    )
    try:
        if _modelo is None:
            _modelo = WhisperModel(MODELO_WHISPER, device="cpu", compute_type="int8")
        for usar_vad in (True, False):
            segs, _info = _modelo.transcribe(str(wav), language="pt", vad_filter=usar_vad)
            texto = " ".join((getattr(s, "text", "") or "").strip() for s in segs).strip()
            if texto:
                return texto
        return ""
    finally:
        wav.unlink(missing_ok=True)


# ── O modelo divide ────────────────────────────────────────────────────────
def montar_prompt(skill: str, item: Dict[str, Any], transcricao: str) -> str:
    aluno = item.get("nome_aluno") or "(nome não cadastrado)"
    curso = item.get("curso")
    ja = {k: v for k, v in (item.get("ja_escrito") or {}).items() if v}
    partes = [
        skill,
        "",
        f"ALUNO DA EXPERIMENTAL: {aluno}" + (f" · curso: {curso}" if curso else ""),
    ]
    if ja:
        # O professor já digitou algo. O modelo precisa saber pra não repetir o
        # que já está lá — e o banco preserva o que ele deixar em null.
        partes += [
            "",
            "O PROFESSOR JÁ TINHA ESCRITO ISTO (não repita, não contradiga; "
            "deixe null o campo que o áudio não cobriu):",
            json.dumps(ja, ensure_ascii=False, indent=1),
        ]
    partes += [
        "",
        "TRANSCRIÇÃO DO ÁUDIO (só isto foi dito — não acrescente nada):",
        transcricao,
        "",
        "Responda SOMENTE com o JSON das quatro chaves.",
    ]
    return "\n".join(partes)


def extrair_json(bruto: str) -> Optional[Dict[str, Optional[str]]]:
    """O modelo às vezes embrulha em ```json. Pega o primeiro objeto válido."""
    txt = re.sub(r"^```(?:json)?|```$", "", (bruto or "").strip(), flags=re.M).strip()
    inicio = txt.find("{")
    if inicio < 0:
        return None
    for fim in range(len(txt), inicio, -1):
        try:
            obj = json.loads(txt[inicio:fim])
        except Exception:
            continue
        if not isinstance(obj, dict):
            return None
        # Lista branca aqui também: chave que eu não conheço não viaja pro
        # banco (que também tem a dele — a fronteira vale nos dois lados).
        saida: Dict[str, Optional[str]] = {}
        for campo in CAMPOS:
            valor = obj.get(campo)
            saida[campo] = str(valor).strip() if isinstance(valor, str) and valor.strip() else None
        return saida if any(saida.values()) else None
    return None


# ── A esteira ──────────────────────────────────────────────────────────────
def processar(item: Dict[str, Any], skill: str) -> Dict[str, Any]:
    audio_id = item["audio_id"]
    caminho: Optional[Path] = None
    try:
        caminho = baixar(item["storage_path"])
        transcricao = transcrever(caminho)
        if not transcricao:
            raise RuntimeError("transcricao vazia (audio mudo ou ilegivel)")

        bruto = bridge.run_hermes_api(
            montar_prompt(skill, item, transcricao),
            professor_id=item.get("professor_id"),
            channel="registro_experimental_audio",
        )
        campos = extrair_json(bruto)
        if not campos:
            raise RuntimeError(f"resposta fora do formato: {(bruto or '')[:200]}")

        res = rpc("fabio_gravar_registro_experimental_de_audio", {
            "p_audio_id": audio_id,
            "p_transcricao": transcricao,
            "p_campos": campos,
        }) or {}
        log("gravado", audio_id=audio_id, vinculo_id=item.get("vinculo_id"),
            registro_id=res.get("registro_id"), chars=len(transcricao),
            campos=[c for c in CAMPOS if campos.get(c)])
        return {"audio_id": audio_id, "status": "gravado",
                "registro_id": res.get("registro_id"),
                "campos_preenchidos": [c for c in CAMPOS if campos.get(c)]}

    except Exception as e:  # noqa: BLE001
        motivo = f"{type(e).__name__}: {e}"[:900]
        try:
            fim = rpc("fabio_falhou_audio_experimental",
                      {"p_audio_id": audio_id, "p_erro": motivo}) or {}
        except Exception as e2:  # noqa: BLE001
            # Falhei e não consegui nem registrar a falha: a linha fica presa em
            # 'transcrevendo' até a retomada de 15 min. Grita, porque daqui não
            # dá pra consertar.
            log("falha_nao_registrada", audio_id=audio_id, erro=motivo, erro2=str(e2)[:200])
            return {"audio_id": audio_id, "status": "falha_nao_registrada", "erro": motivo}
        log("falhou", audio_id=audio_id, erro=motivo, novo_status=fim.get("status"))
        return {"audio_id": audio_id, "status": fim.get("status", "falhou"), "erro": motivo[:200]}
    finally:
        if caminho:
            caminho.unlink(missing_ok=True)


def espiar(lote: int) -> List[Dict[str, Any]]:
    """Leitura pura da fila — não reivindica, não conta tentativa."""
    return bridge.sb_get("/rest/v1/fabio_fila_audios", {
        "vinculo_id": "not.is.null",
        "status": "in.(pendente,transcrevendo)",
        "select": "id,vinculo_id,status,tentativas,duracao_segundos,criado_em,atualizado_em",
        "order": "criado_em.asc",
        "limit": str(lote),
    }) or []


def rodar(lote: int, dry_run: bool) -> Dict[str, Any]:
    if dry_run:
        fila = espiar(lote)
        return {"ok": True, "dry_run": True, "na_fila": len(fila), "fila": fila,
                "skill_ativa": bool(skill_ativa())}

    itens: List[Dict[str, Any]] = rpc("fabio_claim_audio_experimental", {"p_max": lote}) or []
    if not itens:
        return {"ok": True, "dry_run": False, "pegos": 0, "resultados": []}

    # A skill é lida UMA vez por rodada: se ela sumir no meio, o lote inteiro
    # falha junto e volta pra fila — melhor que metade gravada por um critério
    # e metade por outro.
    skill = skill_ativa()

    resultados = [processar(i, skill) for i in itens]
    resumo: Dict[str, int] = {}
    for r in resultados:
        resumo[r["status"]] = resumo.get(r["status"], 0) + 1
    return {"ok": True, "dry_run": False, "pegos": len(itens),
            "resumo": resumo, "resultados": resultados}


def main() -> int:
    ap = argparse.ArgumentParser(description="Áudio da experimental -> os quatro campos do registro.")
    ap.add_argument("--lote", type=int, default=LOTE)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    saida = rodar(args.lote, args.dry_run)
    print(json.dumps(saida, ensure_ascii=False, default=str) if args.json else saida)
    return 0


if __name__ == "__main__":
    sys.exit(main())
