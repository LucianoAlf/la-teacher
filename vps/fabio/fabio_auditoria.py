#!/usr/bin/env python3
"""
Auditoria do Fábio — diagnostica, CONSERTA o que dá, e reporta o resto.

Filosofia (Alf, 02/08/2026): "já conserta e traz o que foi corrigido e o que
precisa de decisão minha". O relatório nunca é uma lista de tarefas pro Alf —
é o que já foi resolvido + o que só um humano pode decidir.

Rodar:
  python3 fabio_auditoria.py                 # audita, conserta, IMPRIME (não envia)
  python3 fabio_auditoria.py --send          # ... e envia pelo WhatsApp
  python3 fabio_auditoria.py --no-fix        # só diagnostica, não conserta

Segurança: os únicos "consertos" são reinício de serviço e retry de fila —
ambos idempotentes e reversíveis. Nada destrutivo, nada de apagar dado.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fabio_chat_bridge as bridge  # noqa: E402

TZ = ZoneInfo("America/Sao_Paulo")
PROF_PILOTO = int(os.getenv("FABIO_AUDIT_PROFESSOR", "25"))
SERVICOS = ["fabio-hermes-gateway", "fabio-chat-bridge"]

# Acumuladores do relatório
ok: List[str] = []          # o que está saudável (vira 1 linha só)
consertado: List[str] = []  # o que quebrou E foi corrigido automaticamente
decisao: List[str] = []     # o que precisa de humano
falhou: List[str] = []      # tentei consertar e não consegui


def sh(*args: str, timeout: int = 30) -> str:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception as e:  # pragma: no cover
        return f"__erro__: {e}"


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:300]}")
    return r.json() if r.text else None


def tabela(path: str, params: Dict[str, str]) -> List[Dict[str, Any]]:
    """bridge.sb_get já devolve o JSON decodificado (lista); tolera as duas formas."""
    r = bridge.sb_get(path, params)
    if isinstance(r, list):
        return r
    if hasattr(r, "status_code"):
        if r.status_code >= 400:
            raise RuntimeError(f"get {path} {r.status_code}: {r.text[:300]}")
        return r.json() if r.text else []
    return []


# ---------------------------------------------------------------- checagens

def check_servicos(fix: bool) -> None:
    for svc in SERVICOS:
        estado = sh("systemctl", "--user", "is-active", svc)
        if estado == "active":
            continue
        if not fix:
            decisao.append(f"Serviço *{svc}* está `{estado}`")
            continue
        sh("systemctl", "--user", "restart", svc)
        novo = sh("systemctl", "--user", "is-active", svc)
        if novo == "active":
            consertado.append(f"Serviço *{svc}* estava `{estado}` → reiniciado, de pé ✅")
        else:
            falhou.append(f"Serviço *{svc}* caído (`{novo}`) — reinício não resolveu")
    # o MCP de presença roda como processo filho do gateway, não como unit
    if "fabio_presence_mcp" not in sh("ps", "-eo", "args"):
        decisao.append("MCP de presença (`fabio_presence_mcp.py`) não aparece nos processos")


def check_briefing() -> None:
    """O timer do briefing é o compromisso das 8h — nunca pode estar desarmado."""
    if sh("systemctl", "--user", "is-enabled", "fabio-briefing-matheus.timer") != "enabled":
        decisao.append("⏰ Timer do briefing *desarmado* — o professor não recebe amanhã")
        return
    if sh("systemctl", "--user", "is-failed", "fabio-briefing-matheus.service") == "failed":
        erro = sh("systemctl", "--user", "status", "fabio-briefing-matheus.service")[-200:]
        decisao.append(f"❌ Último briefing *falhou*: …{erro}")
        return
    linha = sh("systemctl", "--user", "list-timers", "fabio-briefing-matheus.timer", "--all")
    prox = "horário não lido"
    for l in linha.splitlines():
        if "fabio-briefing" in l:
            prox = " ".join(l.split()[:3])
    ok.append(f"briefing armado ({prox} UTC)")


def check_agenda_do_dia() -> None:
    """O briefing só faz sentido se a RPC devolver aula. Confere ANTES das 8h."""
    hoje = datetime.now(TZ).date().isoformat()
    try:
        r = rpc("fabio_briefing_matinal", {"p_professor_id": PROF_PILOTO, "p_data": hoje})
    except Exception as e:
        decisao.append(f"RPC do briefing com erro: {str(e)[:120]}")
        return
    if not r or not r.get("ok"):
        decisao.append(f"RPC do briefing devolveu `{(r or {}).get('motivo', 'vazio')}`")
        return
    n_aulas = r.get("total_aulas", 0)
    if n_aulas == 0:
        ok.append("prof. piloto sem aula hoje (briefing não sai — correto)")
    else:
        ok.append(f"agenda de hoje: {n_aulas} aulas / {r.get('total_alunos', 0)} alunos")


def check_fila_audios(fix: bool) -> None:
    limite = (datetime.now(timezone.utc) - timedelta(hours=3)).isoformat()
    try:
        presos = tabela("/rest/v1/fabio_fila_audios", {
            "select": "id,status,tentativas,atualizado_em",
            "status": "in.(pendente,erro,transcrevendo)",
            "atualizado_em": f"lt.{limite}",
            "limit": "20",
        })
    except Exception as e:
        decisao.append(f"Não consegui ler a fila de áudios: {str(e)[:120]}")
        return
    if not presos:
        ok.append("fila de áudios limpa")
        return
    retriaveis = [p for p in presos if p["status"] in ("pendente", "erro")]
    if retriaveis and fix:
        try:
            n = rpc("fn_fabio_retry_fila", {})
            consertado.append(f"{len(retriaveis)} áudio(s) parado(s) → reenfileirados ({n} retomados)")
        except Exception as e:
            falhou.append(f"Retry da fila falhou: {str(e)[:120]}")
    elif retriaveis:
        decisao.append(f"{len(retriaveis)} áudio(s) parado(s) em pendente/erro")
    travados = [p for p in presos if p["status"] == "transcrevendo"]
    if travados:
        ids = ", ".join(p["id"][:8] for p in travados[:3])
        decisao.append(f"{len(travados)} áudio(s) preso(s) em *transcrevendo* há +3h ({ids}) — o retry não pega esse status")


def check_pipeline_presenca() -> None:
    """O teste que nunca rodou: gravar áudio tem que virar presença."""
    desde = (datetime.now(timezone.utc) - timedelta(hours=26)).isoformat()
    try:
        regs = tabela("/rest/v1/fabio_registros_aula", {
            "select": "id,status,campos,criado_em",
            "parent_id": "is.null",
            "criado_em": f"gte.{desde}",
            "limit": "50",
        })
    except Exception as e:
        decisao.append(f"Não consegui ler os registros: {str(e)[:120]}")
        return
    regs = [r for r in regs if r.get("status") != "descartado"]
    if not regs:
        ok.append("nenhum registro novo nas últimas 24h")
        return
    emitidos = [r for r in regs if (r.get("campos") or {}).get("presenca_aplicado") is True]
    sem_sinal = [r for r in regs if (r.get("campos") or {}).get("presenca_erro")
                 or ((r.get("campos") or {}).get("presenca_emitida") and not (r.get("campos") or {}).get("presenca_aplicado"))]
    if emitidos:
        ok.append(f"{len(emitidos)} registro(s) viraram presença automática ✅")
    if sem_sinal:
        motivos = {(r.get("campos") or {}).get("presenca_erro") or "sem sinal de presença" for r in sem_sinal}
        decisao.append(f"🎙️ {len(sem_sinal)} registro(s) NÃO viraram presença — motivo: {', '.join(list(motivos)[:2])}")
    if regs and not emitidos and not sem_sinal:
        decisao.append(f"{len(regs)} registro(s) novos, nenhum emitiu presença ainda (aguardando confirmação?)")


def check_governanca() -> None:
    """Cobrança é de CONTEÚDO, nunca de presença (regra do Alf)."""
    try:
        r = rpc("fabio_pendencias_professor", {"p_professor_id": PROF_PILOTO})
    except Exception:
        return
    atraso = (r or {}).get("pior_atraso_dias", 0) or 0
    n = (r or {}).get("total_aulas", 0) or 0
    if n and atraso > 3:
        decisao.append(f"📋 Prof. piloto: {n} aula(s) sem conteúdo, pior atraso {atraso}d — passou da régua de 3 dias")
    elif n:
        ok.append(f"prof. piloto: {n} aula(s) sem conteúdo (dentro da janela)")
    else:
        ok.append("prof. piloto com conteúdo em dia")


def check_recursos() -> None:
    total, usado, livre = shutil.disk_usage("/")
    pct = usado * 100 // total
    if pct >= 85:
        decisao.append(f"💾 Disco em {pct}% — liberar espaço")
    else:
        ok.append(f"disco {pct}%")
    try:
        with open("/proc/meminfo") as f:
            info = {l.split(":")[0]: int(l.split()[1]) for l in f if ":" in l}
        disp_pct = info.get("MemAvailable", 0) * 100 // max(info.get("MemTotal", 1), 1)
        if disp_pct < 12:
            decisao.append(f"🧠 RAM disponível em {disp_pct}%")
        else:
            ok.append(f"RAM livre {disp_pct}%")
    except Exception:
        pass


# ---------------------------------------------------------------- relatório

def montar(janela: str) -> str:
    agora = datetime.now(TZ).strftime("%d/%m %H:%M")
    L = [f"🩺 *Fábio — auditoria {janela}* · {agora}", ""]
    if not consertado and not decisao and not falhou:
        L.append("✅ *Tudo certo.* Nenhum problema encontrado.")
    if consertado:
        L.append("🔧 *Corrigi sozinho:*")
        L += [f"• {c}" for c in consertado]
        L.append("")
    if falhou:
        L.append("🚨 *Tentei corrigir e não consegui:*")
        L += [f"• {f}" for f in falhou]
        L.append("")
    if decisao:
        L.append("⚠️ *Precisa de você:*")
        L += [f"• {d}" for d in decisao]
        L.append("")
    if ok:
        L.append("_Saudável: " + " · ".join(ok) + "._")
    return "\n".join(L).strip()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--send", action="store_true", help="envia pelo WhatsApp (default: só imprime)")
    p.add_argument("--no-fix", action="store_true", help="só diagnostica, não conserta")
    p.add_argument("--janela", default=None, help="rótulo (ex.: 7h, 21h)")
    a = p.parse_args()
    fix = not a.no_fix
    janela = a.janela or ("7h" if datetime.now(TZ).hour < 12 else "21h")

    for etapa in (lambda: check_servicos(fix), check_briefing, check_agenda_do_dia,
                  lambda: check_fila_audios(fix), check_pipeline_presenca,
                  check_governanca, check_recursos):
        try:
            etapa()
        except Exception as e:  # uma checagem quebrada não derruba a auditoria
            falhou.append(f"Checagem falhou: {str(e)[:120]}")

    texto = montar(janela)
    print(texto)

    if a.send:
        destino = os.getenv("FABIO_AUDIT_WHATSAPP")  # número do Alf, via env
        if not destino:
            print("\n[aviso] FABIO_AUDIT_WHATSAPP não definido — nada enviado.", file=sys.stderr)
            return 0
        try:
            bridge.send_whatsapp_text_to_phone(destino, texto)  # type: ignore[attr-defined]
        except AttributeError:
            bridge.send_whatsapp_text(int(os.getenv("FABIO_AUDIT_PROFESSOR_DEST", PROF_PILOTO)), texto)
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
