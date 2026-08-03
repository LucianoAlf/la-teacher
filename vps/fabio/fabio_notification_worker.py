#!/usr/bin/env python3
"""Fábio notification worker.

Cron-friendly dispatcher for simple recurring notifications:
- morning briefing (briefing_matinal)
- daily class-record pending reminder (pendencia_registro)

This is intentionally NOT a generic job queue. Recurring idempotency lives in
public.fabio_notificacoes via fabio_claim_notificacao/status RPCs.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, time as dtime
from typing import Any, Dict, Iterable, Optional
from zoneinfo import ZoneInfo

import fabio_chat_bridge as bridge

BRT = ZoneInfo("America/Sao_Paulo")
DEFAULT_BRIEFING_TIME = os.getenv("FABIO_NOTIFY_BRIEFING_TIME", "08:00")
DEFAULT_PENDENCIA_TIME = os.getenv("FABIO_NOTIFY_PENDENCIA_TIME", "18:30")
DEFAULT_WINDOW_MINUTES = int(os.getenv("FABIO_NOTIFY_WINDOW_MINUTES", "15"))
DEFAULT_CHANNEL = os.getenv("FABIO_NOTIFY_CHANNEL", "whatsapp")
SEND_EMPTY_BRIEFING = os.getenv("FABIO_NOTIFY_EMPTY_BRIEFING", "false").lower() in {"1", "true", "yes", "sim"}
MAX_PROFESSORS = int(os.getenv("FABIO_NOTIFY_MAX_PROFESSORS", "0"))


@dataclass(frozen=True)
class EventSpec:
    tipo: str
    categoria: str
    target_time: str


EVENTS = {
    "briefing": EventSpec("briefing_matinal", "informativa", DEFAULT_BRIEFING_TIME),
    "pendencia": EventSpec("pendencia_registro", "governanca", DEFAULT_PENDENCIA_TIME),
}


def log(msg: str, **fields: Any) -> None:
    bridge.log(f"notify_worker_{msg}", **fields)


def parse_hhmm(value: str) -> dtime:
    h, m = str(value).split(":", 1)
    return dtime(hour=int(h), minute=int(m[:2]))


def minutes_of_day(dt: datetime) -> int:
    return dt.hour * 60 + dt.minute


def is_due(now: datetime, target_hhmm: str, window_min: int) -> bool:
    target = parse_hhmm(target_hhmm)
    start = target.hour * 60 + target.minute
    cur = minutes_of_day(now)
    return start <= cur < start + max(1, window_min)


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:500]}")
    if not r.text:
        return None
    return r.json()


def active_professors(professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    params = {
        "select": "id,nome,telefone_whatsapp,ativo",
        "ativo": "eq.true",
        "order": "id.asc",
    }
    if professor_id is not None:
        params["id"] = f"eq.{int(professor_id)}"
    if MAX_PROFESSORS > 0 and professor_id is None:
        params["limit"] = str(MAX_PROFESSORS)
    rows = bridge.sb_get("/rest/v1/professores", params)
    return rows or []


def first_name(prof: Dict[str, Any], fallback: str = "professor") -> str:
    nome = (prof.get("nome") or "").strip()
    return nome.split()[0] if nome else fallback


def compact_summary(text: str, max_len: int = 115) -> str:
    text = " ".join(str(text or "").split())
    if len(text) <= max_len:
        return text
    return text[: max_len - 1].rstrip() + "…"


def display_student_name(aluno: Dict[str, Any]) -> str:
    first = (aluno.get("primeiro_nome") or "").strip()
    full = " ".join(str(aluno.get("nome") or "").split()).strip()
    if not first:
        return full.split()[0] if full else "Aluno"
    parts = full.split()
    composite_first_names = {"Maria", "Ana", "João", "Jose", "José", "Luiz", "Luís"}
    if len(parts) >= 2 and parts[0].lower() == first.lower() and parts[0] in composite_first_names:
        return f"{parts[0]} {parts[1]}"
    return first


def student_names(alunos: Iterable[Dict[str, Any]], max_names: int = 5) -> str:
    names = []
    for a in alunos or []:
        names.append(display_student_name(a))
    if not names:
        return "aluno(s)"
    if len(names) > max_names:
        names = names[:max_names] + [f"mais {len(names) - max_names}"]
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + " e " + names[-1]


def _format_date_br(value: Any) -> Optional[str]:
    text = str(value or "").strip()
    if not text:
        return None
    # Expected from RPC: YYYY-MM-DD. Keep defensive fallback for already-formatted text.
    try:
        return datetime.fromisoformat(text[:10]).strftime("%d/%m")
    except Exception:
        return text


def _clean_text(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


# --------------------------------------------------------------------------
# Apresentação no WhatsApp. O professor lê isso correndo, de manhã, no celular:
# o nome do aluno tem que saltar, e cada seção tem que ser achável sem ler.
# --------------------------------------------------------------------------

# Rótulos que o Fábio e o Emusys já usam DENTRO de um texto corrido. Quando o
# campo estruturado falta, a RPC cai no texto consolidado inteiro e ele desaba
# num campo só — aconteceu com a Amanda em 03/08, cujo "Trabalho feito" trazia
# "Objetivo: … Conteúdo: … Progresso: …" tudo grudado. Aqui a gente devolve
# esse texto para as seções às quais ele já pertencia.
_ROTULOS = [
    ("objetivo", "foco"),
    ("foco", "foco"),
    ("conteudo", "trabalho_feito"),
    ("conteúdo", "trabalho_feito"),
    ("atividades", "trabalho_feito"),
    ("trabalho feito", "trabalho_feito"),
    ("progresso", "trabalho_feito"),
    ("repertorio", "repertorio"),
    ("repertório", "repertorio"),
    ("musica", "repertorio"),
    ("música", "repertorio"),
    ("dever de casa", "dever_casa"),
    ("proximo passo", "proximo_passo"),
    ("próximo passo", "proximo_passo"),
    ("observacao", "observacao"),
    ("observação", "observacao"),
]
_RE_ROTULO = re.compile(
    r"(?i)(?:^|[\s;.])(" + "|".join(re.escape(r) for r, _ in _ROTULOS) + r")\s*:\s*"
)


def _despejar_em_secoes(texto: str) -> Dict[str, str]:
    """Quebra um texto corrido pelos rótulos que ele mesmo carrega.

    Só age quando encontra 2+ rótulos — com um só, o texto provavelmente É o
    conteúdo daquele campo, e quebrar seria pior que deixar quieto.
    """
    texto = _clean_text(texto)
    achados = list(_RE_ROTULO.finditer(texto))
    if len(achados) < 2:
        return {}
    destino = {rotulo: campo for rotulo, campo in _ROTULOS}
    secoes: Dict[str, str] = {}
    for i, m in enumerate(achados):
        campo = destino.get(m.group(1).lower())
        fim = achados[i + 1].start() if i + 1 < len(achados) else len(texto)
        valor = texto[m.end():fim].strip(" ;,")  # o ponto final fica: é pontuação, não separador
        if not campo or not valor:
            continue
        if campo in secoes:
            anterior = secoes[campo]
            emenda = "" if anterior.endswith((".", "!", "?", ";")) else "."
            secoes[campo] = f"{anterior}{emenda} {valor}".strip()
        else:
            secoes[campo] = valor
    return secoes


_LIMITE_CAMPO = 200


def _encurtar(valor: Any, limite: int = _LIMITE_CAMPO) -> str:
    """Corta em fronteira de frase, ou de palavra. Riqueza de detalhe sim,
    parede de texto não (pedido do Alf: 'resumir sem enxugar muito')."""
    texto = _clean_text(valor)
    if len(texto) <= limite:
        return texto
    corte = texto[:limite]
    frase = max(corte.rfind(". "), corte.rfind("; "))
    if frase > limite * 0.5:
        return corte[: frase + 1].strip()
    espaco = corte.rfind(" ")
    return (corte[:espaco] if espaco > 0 else corte).rstrip(" ,;:") + "…"


# Um relógio por hora: o olho acha o horário antes de ler a linha.
_RELOGIOS = ["🕛", "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚"]


def _relogio(hora: Any) -> str:
    try:
        return _RELOGIOS[int(str(hora).split(":")[0]) % 12]
    except Exception:
        return "🕐"


_CAMPOS = [
    ("foco", "🎯", "Foco"),
    ("trabalho_feito", "✅", "Trabalho feito"),
    ("repertorio", "🎵", "Repertório"),
    ("dever_casa", "🏠", "Dever de casa"),
    ("proximo_passo", "➡️", "Próximo passo"),
    ("observacao", "💬", "Observação"),
]


def _ultima_aula_lines(aluno: Dict[str, Any]) -> list[str]:
    """Bloco de um aluno. O nome vem em negrito e sozinho na linha — antes ele
    ficava no meio de 'Aluno(a): fulano' e se perdia na rolagem."""
    linhas = [f"👤 *{display_student_name(aluno)}*"]
    ultima = aluno.get("ultima_aula") if isinstance(aluno, dict) else None

    if not isinstance(ultima, dict) or not ultima:
        resumo = _encurtar(aluno.get("resumo_ultima_aula") if isinstance(aluno, dict) else "")
        linhas.append(f"✅ *Trabalho feito:* {resumo}" if resumo
                      else "_Sem conteúdo registrado da última aula._")
        return linhas

    dados = {chave: _clean_text(ultima.get(chave)) for chave, _, _ in _CAMPOS}
    for chave in ("trabalho_feito", "foco"):
        secoes = _despejar_em_secoes(dados.get(chave, ""))
        if not secoes:
            continue
        dados[chave] = ""
        for campo, valor in secoes.items():
            if not dados.get(campo):
                dados[campo] = valor

    data_br = _format_date_br(ultima.get("data"))
    if data_br:
        linhas.append(f"_última aula · {data_br}_")
    for chave, emoji, rotulo in _CAMPOS:
        valor = _encurtar(dados.get(chave, ""))
        if valor:
            linhas.append(f"{emoji} *{rotulo}:* {valor}")
    if len(linhas) <= 2:
        linhas.append("_Sem conteúdo registrado da última aula._")
    return linhas


def _summary_lines_for_class(alunos: list[Dict[str, Any]]) -> list[str]:
    alunos = alunos or []
    if not alunos:
        return ["_Sem alunos na chamada desta aula._"]
    linhas: list[str] = []
    for idx, aluno in enumerate(alunos):
        if idx:
            linhas.append("")
        linhas.extend(_ultima_aula_lines(aluno))
    return linhas


def format_briefing(prof: Dict[str, Any], data: Dict[str, Any]) -> Optional[str]:
    aulas = data.get("aulas") or []
    nome = data.get("primeiro_nome") or first_name(prof)
    if not aulas and not SEND_EMPTY_BRIEFING:
        return None
    if not aulas:
        return None

    total_aulas = int(data.get("total_aulas") or len(aulas))
    total_alunos = int(data.get("total_alunos") or sum(len(a.get("alunos") or []) for a in aulas))
    aula_label = "aula" if total_aulas == 1 else "aulas"
    aluno_label = "aluno" if total_alunos == 1 else "alunos"
    lines = [
        f"Bom dia, {nome}! 🎵",
        "",
        f"Hoje você tem *{total_aulas} {aula_label}* com *{total_alunos} {aluno_label}*.",
        "",
        "📅 *Agenda de hoje*",
    ]
    for aula in aulas:
        hora = aula.get("hora") or "--:--"
        curso = aula.get("curso") or "Aula"
        lines.append("")
        lines.append(f"{_relogio(hora)} *{hora} — {curso}*")
        lines.extend(_summary_lines_for_class(aula.get("alunos") or []))
    lines.append("")
    lines.append("Se quiser preparar alguma aula específica, me manda o nome do aluno.")
    return "\n".join(lines)


def format_pendencias(prof: Dict[str, Any], data: Dict[str, Any]) -> Optional[str]:
    total = int(data.get("total_aulas") or 0)
    if total <= 0:
        return None
    nome = first_name(prof)
    total_alunos = int(data.get("total_alunos") or 0)
    pior = int(data.get("pior_atraso_dias") or 0)
    aulas = data.get("aulas") or []
    plural = "aula pendente" if total == 1 else "aulas pendentes"
    head = f"{nome}, passando pra te ajudar a fechar os registros. Você tem {total} {plural}"
    if total_alunos:
        head += f" envolvendo {total_alunos} aluno(s)"
    if pior:
        head += f" — a mais antiga está há {pior} dia(s)."
    else:
        head += "."
    lines = [head, "", "Pendências:"]
    for aula in aulas[:8]:
        data_aula = aula.get("data") or aula.get("data_aula") or "data não informada"
        hora = aula.get("hora") or aula.get("horario") or ""
        curso = aula.get("curso") or "Aula"
        atraso = aula.get("dias_atraso") or aula.get("atraso_dias")
        alunos = aula.get("alunos") or []
        when = f"{data_aula} {hora}".strip()
        line = f"• {when} — {curso}: {student_names(alunos)}"
        if atraso:
            line += f" ({atraso}d)"
        lines.append(line)
    if len(aulas) > 8:
        lines.append(f"• +{len(aulas) - 8} aula(s) pendente(s).")
    lines.append("\nQuando registrar, eu paro de te cobrar essa pendência.")
    return "\n".join(lines)


def build_content(event: str, prof: Dict[str, Any], target_date: Optional[str] = None) -> tuple[Optional[str], Dict[str, Any]]:
    pid = int(prof["id"])
    if event == "briefing":
        body = {"p_professor_id": pid}
        if target_date:
            body["p_data"] = target_date
        data = rpc("fabio_briefing_matinal", body)
        return format_briefing(prof, data or {}), data or {}
    if event == "pendencia":
        data = rpc("fabio_pendencias_professor", {"p_professor_id": pid})
        return format_pendencias(prof, data or {}), data or {}
    raise ValueError(f"unknown event {event}")


def can_notify(pid: int, categoria: str) -> bool:
    return bool(rpc("fn_fabio_pode_notificar", {"p_professor_id": int(pid), "p_categoria": categoria}))


def claim_notification(pid: int, spec: EventSpec, channel: str, content: str, title: str) -> Dict[str, Any]:
    data = rpc("fabio_claim_notificacao", {
        "p_professor_id": int(pid),
        "p_tipo": spec.tipo,
        "p_categoria": spec.categoria,
        "p_canal": channel,
        "p_corpo": content,
        "p_titulo": title,
    })
    return data or {"ok": False, "claimed": False}


def mark_sent(notification_id: str) -> None:
    rpc("fabio_marcar_notificacao_enviada", {"p_notificacao_id": notification_id})


def mark_failed(notification_id: str, error: str) -> None:
    rpc("fabio_marcar_notificacao_falhou", {"p_notificacao_id": notification_id, "p_erro": error[:1000]})


def deliver(pid: int, channel: str, content: str) -> None:
    if channel == "whatsapp":
        bridge.send_whatsapp_text(pid, content)
        return
    if channel == "app":
        bridge.insert_fabio_response(pid, content, "app")
        return
    raise ValueError(f"unsupported channel: {channel}")


def run_event(event: str, prof: Dict[str, Any], channel: str, dry_run: bool, target_date: Optional[str] = None) -> Dict[str, Any]:
    spec = EVENTS[event]
    pid = int(prof["id"])
    result = {"professor_id": pid, "event": event, "tipo": spec.tipo, "status": "init"}
    preferences_allowed = can_notify(pid, spec.categoria)
    result["preferences_allowed"] = preferences_allowed
    if not preferences_allowed and not dry_run:
        result["status"] = "blocked_by_preferences"
        return result
    content, raw = build_content(event, prof, target_date=target_date)
    result["raw_totals"] = {k: raw.get(k) for k in ("total_aulas", "total_alunos", "pior_atraso_dias") if isinstance(raw, dict) and k in raw}
    if not content:
        result["status"] = "empty_skip"
        return result
    result["content_preview"] = content
    if dry_run:
        result["status"] = "dry_run_ready"
        return result
    title = "Briefing matinal" if event == "briefing" else "Pendência de registro"
    claim = claim_notification(pid, spec, channel, content, title)
    result["claim"] = claim
    if not claim.get("claimed"):
        result["status"] = "already_claimed_or_sent"
        return result
    notification_id = claim.get("notificacao_id")
    try:
        deliver(pid, channel, content)
        mark_sent(notification_id)
        result["status"] = "sent"
    except Exception as exc:
        try:
            mark_failed(notification_id, str(exc))
        finally:
            result["status"] = "failed"
            result["error"] = str(exc)[:500]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", choices=["briefing", "pendencia", "all"], default="all")
    parser.add_argument("--professor-id", type=int)
    parser.add_argument("--channel", choices=["whatsapp", "app"], default=DEFAULT_CHANNEL)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true", help="ignore time window")
    parser.add_argument("--window-minutes", type=int, default=DEFAULT_WINDOW_MINUTES)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--date", help="BRT date YYYY-MM-DD for briefing; defaults to today")
    args = parser.parse_args()

    now = datetime.now(BRT)
    target_date = args.date or now.date().isoformat()
    selected = ["briefing", "pendencia"] if args.event == "all" else [args.event]
    due_events = []
    for event in selected:
        spec = EVENTS[event]
        if args.force or is_due(now, spec.target_time, args.window_minutes):
            due_events.append(event)
    if not due_events:
        payload = {"ok": True, "status": "nothing_due", "now_brt": now.isoformat(), "events_checked": selected}
        print(json.dumps(payload, ensure_ascii=False) if args.json else payload)
        return 0

    rows = active_professors(args.professor_id)
    results = []
    for prof in rows:
        # WhatsApp delivery needs a phone. App delivery can work without phone.
        if args.channel == "whatsapp" and not bridge.canonical_phone(prof.get("telefone_whatsapp") or ""):
            results.append({"professor_id": prof.get("id"), "status": "missing_phone_skip"})
            continue
        for event in due_events:
            try:
                res = run_event(event, prof, args.channel, args.dry_run, target_date=target_date)
            except Exception as exc:
                res = {"professor_id": prof.get("id"), "event": event, "status": "error", "error": str(exc)[:500]}
            results.append(res)
            log("event_result", **res)

    summary = {}
    for r in results:
        summary[r.get("status", "unknown")] = summary.get(r.get("status", "unknown"), 0) + 1
    payload = {"ok": True, "dry_run": args.dry_run, "now_brt": now.isoformat(), "target_date": target_date, "due_events": due_events, "summary": summary, "results": results}
    print(json.dumps(payload, ensure_ascii=False, indent=2) if args.json else payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
