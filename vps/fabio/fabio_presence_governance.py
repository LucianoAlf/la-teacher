#!/usr/bin/env python3
"""Preview-first governance for pending attendance in Fabio.

Read-only by design: calls Supabase RPCs and renders WhatsApp-ready previews.
Does not send messages and does not write to Supabase.
"""
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

import requests

HERMES_HOME = Path(os.getenv("HERMES_HOME", "/home/fabio/.hermes"))
ENV_FILE = HERMES_HOME / ".env"
SUPABASE_URL = ""
SUPABASE_KEY = ""
COORDENACAO_PEDAGOGICA_JID = os.getenv("FABIO_COORDENACAO_PEDAGOGICA_JID", "120363304349910605@g.us")
HTTP_TIMEOUT = (10, 60)


def _load_env_file(path: Path = ENV_FILE) -> None:
    if not path.exists():
        return
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, val = line.split("=", 1)
        os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def _init_env() -> None:
    global SUPABASE_URL, SUPABASE_KEY
    _load_env_file()
    SUPABASE_URL = (os.getenv("LAREPORT_SUPABASE_URL") or "").rstrip("/")
    SUPABASE_KEY = os.getenv("LAREPORT_SUPABASE_SERVICE_ROLE") or os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise RuntimeError("LAREPORT_SUPABASE_URL/LAREPORT_SUPABASE_SERVICE_ROLE missing")


def _headers() -> Dict[str, str]:
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }


def _rpc(name: str, body: Dict[str, Any]) -> Any:
    r = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}", headers=_headers(), json=body, timeout=HTTP_TIMEOUT)
    if r.status_code >= 400:
        raise RuntimeError(f"RPC {name} failed {r.status_code}: {r.text[:500]}")
    return r.json()


def fabio_buscar_presencas_pendentes_professor(professor_id: int) -> Dict[str, Any]:
    """Read-only Hermes-facing tool: pending attendance for one professor."""
    data = _rpc("fabio_presencas_pendentes_professor", {"p_professor_id": int(professor_id)})
    return data if isinstance(data, dict) else {"professor_id": professor_id, "resultado": data}


def fabio_buscar_registros_pendentes_professor(professor_id: int) -> Dict[str, Any]:
    """Read-only companion: pending class records for one professor."""
    data = _rpc("fabio_pendencias_professor", {"p_professor_id": int(professor_id)})
    return data if isinstance(data, dict) else {"professor_id": professor_id, "resultado": data}


def buscar_professor(professor_id: int) -> Dict[str, Any]:
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/professores",
        headers=_headers(),
        params={"select": "id,nome", "id": f"eq.{int(professor_id)}", "limit": "1"},
        timeout=HTTP_TIMEOUT,
    )
    if r.status_code >= 400:
        return {"id": professor_id, "nome": f"Professor {professor_id}"}
    rows = r.json() or []
    return rows[0] if rows else {"id": professor_id, "nome": f"Professor {professor_id}"}


def listar_professores_ativos(limit: int = 200) -> List[Dict[str, Any]]:
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/professores",
        headers=_headers(),
        params={"select": "id,nome", "ativo": "eq.true", "order": "nome.asc", "limit": str(limit)},
        timeout=HTTP_TIMEOUT,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"professores lookup failed {r.status_code}: {r.text[:300]}")
    return r.json() or []


def curso_base(curso: Any) -> str:
    s = str(curso or "Aula").strip()
    for suffix in (" IND", " T", " Kids", " KIDS"):
        if s.endswith(suffix):
            s = s[: -len(suffix)].strip()
    return s or "Aula"


def primeiro_nome(nome: Any) -> str:
    s = str(nome or "").strip()
    return s.split()[0] if s else "Aluno"


def nomes_alunos(alunos: Iterable[Dict[str, Any]], max_names: int = 3) -> str:
    nomes = [primeiro_nome(a.get("nome")) for a in alunos if isinstance(a, dict)]
    if not nomes:
        return "aluno(s)"
    if len(nomes) == 1:
        return nomes[0]
    if len(nomes) <= max_names:
        return ", ".join(nomes[:-1]) + " e " + nomes[-1]
    return ", ".join(nomes[:max_names]) + f" e mais {len(nomes) - max_names}"


def atraso_label(dias: Any) -> str:
    try:
        d = int(dias or 0)
    except Exception:
        d = 0
    if d <= 0:
        return "recente"
    if d == 1:
        return "há 1 dia"
    return f"há {d} dias"


def plural(n: int, singular: str, plural_form: str) -> str:
    return f"{n} {singular if n == 1 else plural_form}"


def nome_curto_professor(nome: Any) -> str:
    partes = str(nome or "Professor").strip().split()
    if not partes:
        return "Professor"
    if len(partes) == 1:
        return partes[0]
    conectores = {"da", "de", "do", "das", "dos", "e"}
    sobrenomes = [p for p in partes[1:] if p.lower() not in conectores]
    return f"{partes[0]} {sobrenomes[0]}" if sobrenomes else partes[0]


def total_alunos_aulas(aulas: List[Dict[str, Any]]) -> tuple[int, int, int]:
    total_alunos = 0
    pior = 0
    for aula in aulas:
        alunos = aula.get("alunos") if isinstance(aula, dict) else []
        if isinstance(alunos, list):
            total_alunos += len(alunos)
            for aluno in alunos:
                if isinstance(aluno, dict):
                    try:
                        pior = max(pior, int(aluno.get("dias_em_atraso") or aula.get("dias_em_atraso") or 0))
                    except Exception:
                        pass
        elif isinstance(aula, dict):
            total_alunos += int(aula.get("qtd_alunos") or 0)
            pior = max(pior, int(aula.get("dias_em_atraso") or 0))
    return len(aulas), total_alunos, pior


def montar_preview_dm(professor_nome: str, presencas: Dict[str, Any], registros: Optional[Dict[str, Any]] = None, max_aulas: int = 6) -> str:
    dentro = presencas.get("dentro_janela") if isinstance(presencas, dict) else []
    dentro = dentro if isinstance(dentro, list) else []
    total_aulas, total_alunos, _ = total_alunos_aulas(dentro)
    if total_aulas == 0:
        return f"E aí, {primeiro_nome(professor_nome)}! Tudo certo por aqui ✅\nNão encontrei aula recente sem lançamento de presença."

    linhas = []
    for aula in dentro[:max_aulas]:
        alunos = aula.get("alunos") if isinstance(aula, dict) else []
        alunos = alunos if isinstance(alunos, list) else []
        dias = 0
        for aluno in alunos:
            if isinstance(aluno, dict):
                dias = max(dias, int(aluno.get("dias_em_atraso") or aula.get("dias_em_atraso") or 0))
        linhas.append(f"• {aula.get('data_aula','')} · {aula.get('hora','')} · {curso_base(aula.get('curso_nome'))} — {nomes_alunos(alunos)} ({atraso_label(dias)})")
    if total_aulas > max_aulas:
        linhas.append(f"…e mais {total_aulas - max_aulas} aula(s).")

    qtd = plural(total_aulas, "aula", "aulas")
    alunos_txt = plural(total_alunos, "aluno", "alunos")
    return "\n".join([
        f"E aí, {primeiro_nome(professor_nome)}! Essas {qtd} ficaram sem lançamento — {alunos_txt} no total.",
        "",
        *linhas,
        "",
        "Grava um áudio de 30s contando como foi cada aula que eu organizo o registro e já deixo a presença encaminhada pra você. 😉",
    ])


def montar_linha_escala(professor_nome: str, escalas: List[Dict[str, Any]]) -> Optional[str]:
    if not escalas:
        return None
    total_alunos = sum(int(e.get("qtd_alunos") or 0) for e in escalas if isinstance(e, dict))
    pior = max((int(e.get("dias_em_atraso") or 0) for e in escalas if isinstance(e, dict)), default=0)
    alunos_txt = plural(total_alunos, "aluno", "alunos")
    dias_txt = plural(pior, "dia", "dias")
    return f"• Prof. {nome_curto_professor(professor_nome)} — {alunos_txt} sem presença há até {dias_txt}."


def _escala_sort_key(item: Dict[str, Any]) -> tuple[int, int]:
    escalas = item.get("escalar_coordenacao") or []
    total_alunos = sum(int(e.get("qtd_alunos") or 0) for e in escalas if isinstance(e, dict))
    pior = max((int(e.get("dias_em_atraso") or 0) for e in escalas if isinstance(e, dict)), default=0)
    return (pior, total_alunos)


def montar_preview_escala(itens: List[Dict[str, Any]], max_professores: int = 12) -> str:
    linhas = []
    ordenados = sorted(itens, key=_escala_sort_key, reverse=True)
    for item in ordenados[:max_professores]:
        linha = montar_linha_escala(item.get("professor_nome") or f"{item.get('professor_id')}", item.get("escalar_coordenacao") or [])
        if linha:
            linhas.append(linha)
    restantes = max(0, len(ordenados) - len(linhas))
    if restantes:
        linhas.append(f"…e mais {plural(restantes, 'professor', 'professores')} no digest completo.")
    if not linhas:
        return "Coordenação, por enquanto não apareceu presença fora da janela de apoio. ✅"
    return "\n".join([
        "Pessoal, passando pro radar de vocês — sem dedo, só pra gente apoiar o fechamento das presenças antigas:",
        "",
        *linhas,
        "",
        "Sugestão: acionar em tom de apoio e pedir áudio curto pro Fábio organizar o conteúdo com o professor.",
    ])


def gerar_preview(professor_ids: Optional[List[int]] = None, limit: int = 80) -> Dict[str, Any]:
    if professor_ids:
        professores = [buscar_professor(pid) for pid in professor_ids]
    else:
        professores = listar_professores_ativos(limit=limit)
    dms = []
    escala_itens = []
    for prof in professores:
        pid = int(prof["id"])
        nome = prof.get("nome") or f"Professor {pid}"
        pres = fabio_buscar_presencas_pendentes_professor(pid)
        reg = fabio_buscar_registros_pendentes_professor(pid)
        dentro = pres.get("dentro_janela") if isinstance(pres, dict) else []
        escalar = pres.get("escalar_coordenacao") if isinstance(pres, dict) else []
        if dentro:
            dms.append({"professor_id": pid, "professor_nome": nome, "texto": montar_preview_dm(nome, pres, reg)})
        if escalar:
            escala_itens.append({"professor_id": pid, "professor_nome": nome, "escalar_coordenacao": escalar})
    return {
        "modo": "preview_first_sem_envio",
        "grupo_coordenacao_jid": COORDENACAO_PEDAGOGICA_JID,
        "gerado_em": datetime.now().isoformat(timespec="seconds"),
        "dm_professores": dms,
        "escala_coordenacao": montar_preview_escala(escala_itens),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Preview read-only de governança de presença do Fábio")
    parser.add_argument("--professor-id", type=int, action="append", dest="professor_ids", help="Professor específico; pode repetir")
    parser.add_argument("--limit", type=int, default=80, help="Limite de professores ativos no preview geral")
    parser.add_argument("--json", action="store_true", help="Emitir JSON completo")
    args = parser.parse_args()
    _init_env()
    preview = gerar_preview(args.professor_ids, args.limit)
    if args.json:
        print(json.dumps(preview, ensure_ascii=False, indent=2))
    else:
        print("# PREVIEW DM PROFESSORES")
        for item in preview["dm_professores"][:10]:
            print(f"\n## {item['professor_nome']} (id {item['professor_id']})\n{item['texto']}")
        if len(preview["dm_professores"]) > 10:
            print(f"\n... e mais {len(preview['dm_professores']) - 10} DM(s) no JSON.")
        print("\n# PREVIEW ESCALA COORDENAÇÃO")
        print(preview["escala_coordenacao"])
        print(f"\nDestino configurado para validação futura: {preview['grupo_coordenacao_jid']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
