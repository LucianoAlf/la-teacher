#!/usr/bin/env python3
"""Fábio — worker da devolutiva de aula.

Consome a fila `fabio_devolutivas`: pega o que está pendente, resolve PRA QUEM o
texto fala, gera as DUAS versões pelo Hermes e grava. É fila, não janela de
horário — por isso não tem `is_due` como o worker de notificação.

Contratos que este arquivo respeita (spec 2026-08-03-devolutiva-aula-design):

* **Fronteira family-safe** — ele NUNCA lê `campos` cru. O contexto vem de
  `fabio_devolutiva_contexto`, que já passou por `fn_devolutiva_fonte`. Se a
  fronteira dependesse deste script lembrar de filtrar, não seria fronteira:
  bastaria uma linha nova pra "Observação" (onde o professor escreve o que não
  diria pra mãe) entrar no prompt.

* **Cerca de lease** — toda conclusão manda o token. Se a RPC devolver False, o
  trabalho não é mais nosso: DESCARTA o que gerou, não insiste. Sem isso um
  worker que travou volta do timeout e escreve por cima de quem já concluiu.

* **Destinatário antes do prompt** — idade impossível não gera texto: para em
  `aguardando_destinatario`. Gerar primeiro e perguntar depois produziria uma
  mensagem com vocativo inventado ("Oi, mãe do Tiago") que só piora se enviada.

* **Idade sai de `data_nascimento`**, nunca de `idade_atual` — que é cache e
  fica parado enquanto o aluno faz aniversário.

Uso:
    python3 fabio_devolutiva_worker.py --dry-run        # não grava nada
    python3 fabio_devolutiva_worker.py --lote 5
"""
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
from typing import Any, Dict, List, Optional

import fabio_chat_bridge as bridge

WORKER = os.getenv("FABIO_DEVOLUTIVA_WORKER", f"devolutiva@{socket.gethostname()}")
LOTE = int(os.getenv("FABIO_DEVOLUTIVA_LOTE", "5"))
LEASE_MIN = int(os.getenv("FABIO_DEVOLUTIVA_LEASE_MIN", "5"))

# Idade fora disso não é idade de aluno — é dado corrompido. Apareceu de
# verdade: o Tiago estava com nascimento em 2026 (era 1989), o que o faria um
# bebê de 5 meses matriculado em Canto. Nesses casos a gente PERGUNTA.
IDADE_MIN, IDADE_MAX = 2, 100
IDADE_CORTE_RESPONSAVEL = 15


def log(msg: str, **fields: Any) -> None:
    bridge.log(f"devolutiva_worker_{msg}", **fields)


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:500]}")
    return r.json() if r.text else None


# ---------------------------------------------------------------------------
# destinatário
# ---------------------------------------------------------------------------

def decidir_destinatario(aluno: Dict[str, Any], override: Optional[str]) -> Dict[str, Any]:
    """Pra quem o texto fala. Devolve {destinatario, nome, idade} ou {parar: motivo}.

    A decisão do professor (override) manda sobre a inferência por idade — e
    fica em campo separado no banco justamente pra um reprocessamento não
    sobrescrever ela com a idade de novo.
    """
    idade = aluno.get("idade")
    if override in ("responsavel", "aluno"):
        nome = aluno.get("responsavel_nome") if override == "responsavel" else aluno.get("primeiro_nome")
        return {"destinatario": override, "nome": nome, "idade": idade, "origem": "professor"}

    if idade is None:
        return {"parar": "sem data de nascimento — não sei se falo com o aluno ou com o responsável"}
    if idade < IDADE_MIN or idade > IDADE_MAX:
        return {"parar": f"idade improvável ({idade}) — data de nascimento parece corrompida"}

    if idade < IDADE_CORTE_RESPONSAVEL:
        # Sem nome do responsável o texto ainda vai pra família, só que sem
        # vocativo nominal. Nunca inventa nome, nunca "Sr(a). Responsável".
        return {"destinatario": "responsavel", "nome": aluno.get("responsavel_nome"),
                "idade": idade, "origem": "idade"}
    return {"destinatario": "aluno", "nome": aluno.get("primeiro_nome"),
            "idade": idade, "origem": "idade"}


# ---------------------------------------------------------------------------
# geração
# ---------------------------------------------------------------------------

def montar_prompt(ctx: Dict[str, Any], alvo: Dict[str, Any]) -> str:
    aluno = ctx["aluno"]
    skill = ctx["skill"]["conteudo"]
    quem = (
        f'responsavel (nome: {alvo["nome"]})' if alvo["destinatario"] == "responsavel" and alvo.get("nome")
        else "responsavel (SEM nome cadastrado — fale com a família sem vocativo nominal)"
        if alvo["destinatario"] == "responsavel"
        else f'aluno (nome: {alvo["nome"]})'
    )
    return (
        f"{skill}\n\n"
        f"DESTINATÁRIO: {quem}\n"
        f"ALUNO: {aluno['primeiro_nome']}"
        + (f" · curso: {aluno['curso']}" if aluno.get("curso") else "")
        + "\n\nFONTE (só isto aconteceu — não acrescente nada):\n"
        + json.dumps(ctx["fonte"], ensure_ascii=False, indent=1)
        + "\n\nResponda SOMENTE com JSON, sem cercas de código:\n"
          '{"normal": "...", "apoio_casa": "..."}'
    )


def extrair_json(bruto: str) -> Optional[Dict[str, str]]:
    """O modelo às vezes embrulha em ```json. Pega o primeiro objeto válido."""
    txt = (bruto or "").strip()
    txt = re.sub(r"^```(?:json)?|```$", "", txt, flags=re.M).strip()
    inicio = txt.find("{")
    if inicio < 0:
        return None
    for fim in range(len(txt), inicio, -1):
        try:
            obj = json.loads(txt[inicio:fim])
        except Exception:
            continue
        if isinstance(obj, dict) and obj.get("normal") and obj.get("apoio_casa"):
            return {"normal": str(obj["normal"]).strip(), "apoio_casa": str(obj["apoio_casa"]).strip()}
        return None
    return None


def processar(item: Dict[str, Any], token: str, dry_run: bool) -> Dict[str, Any]:
    dev_id = item["id"]
    ctx = rpc("fabio_devolutiva_contexto", {"p_devolutiva_id": dev_id})
    if not ctx or not ctx.get("ok"):
        raise RuntimeError((ctx or {}).get("erro", "contexto indisponível"))
    if not ctx.get("skill"):
        raise RuntimeError("nenhuma skill devolutiva_aula ativa")
    if not ctx.get("fonte"):
        # Registro sem nada liberado pra família (ex.: só tinha observação).
        # Não é erro de sistema: é devolutiva que não deve existir.
        if not dry_run:
            rpc("fabio_devolutiva_falhou", {
                "p_id": dev_id, "p_lease_token": token,
                "p_erro": "sem conteúdo liberado para a família", "p_backoff_segundos": 86400})
        return {"id": dev_id, "status": "sem_fonte"}

    alvo = decidir_destinatario(ctx["aluno"], ctx.get("destinatario_override"))
    if "parar" in alvo:
        # ANTES do prompt: não queima LLM pra produzir texto que não pode sair.
        if not dry_run:
            rpc("fabio_devolutiva_aguardar_destinatario", {
                "p_id": dev_id, "p_lease_token": token, "p_motivo": alvo["parar"]})
        return {"id": dev_id, "status": "aguardando_destinatario", "motivo": alvo["parar"]}

    prompt = montar_prompt(ctx, alvo)
    if dry_run:
        return {"id": dev_id, "status": "dry_run", "destinatario": alvo["destinatario"],
                "destinatario_nome": alvo.get("nome"), "idade": alvo.get("idade"),
                "fonte": ctx["fonte"], "prompt_preview": prompt[:900]}

    bruto = bridge.run_hermes_api(prompt, professor_id=ctx.get("professor_id"), channel="devolutiva")
    textos = extrair_json(bruto)
    if not textos:
        rpc("fabio_devolutiva_falhou", {
            "p_id": dev_id, "p_lease_token": token,
            "p_erro": f"resposta fora do formato: {(bruto or '')[:300]}", "p_backoff_segundos": 300})
        return {"id": dev_id, "status": "formato_invalido"}

    ok = rpc("fabio_devolutiva_gerada", {
        "p_id": dev_id, "p_lease_token": token,
        "p_texto_normal": textos["normal"], "p_texto_apoio_casa": textos["apoio_casa"],
        "p_destinatario": alvo["destinatario"], "p_destinatario_nome": alvo.get("nome"),
        "p_idade": alvo.get("idade"),
        "p_skill_id": ctx["skill"]["id"], "p_skill_versao": ctx["skill"]["versao"]})
    if not ok:
        # Zero linhas: o lease venceu e outro worker assumiu. O texto que eu
        # acabei de gerar vira lixo — e é isso mesmo. Insistir seria escrever
        # por cima de quem está com o trabalho agora.
        log("lease_perdido", devolutiva_id=dev_id)
        return {"id": dev_id, "status": "lease_perdido"}
    return {"id": dev_id, "status": "gerada", "destinatario": alvo["destinatario"]}


def rodar(lote: int, dry_run: bool) -> Dict[str, Any]:
    claim = rpc("fabio_devolutiva_claim", {
        "p_worker": WORKER, "p_lote": lote, "p_lease_minutos": LEASE_MIN})
    itens: List[Dict[str, Any]] = (claim or {}).get("itens") or []
    token = (claim or {}).get("lease_token")
    if not itens:
        return {"ok": True, "reivindicadas": 0, "resultados": []}

    resultados = []
    for item in itens:
        try:
            resultados.append(processar(item, token, dry_run))
        except Exception as e:  # noqa: BLE001 — uma linha ruim não derruba o lote
            log("erro", devolutiva_id=item.get("id"), erro=str(e)[:300])
            if not dry_run:
                try:
                    rpc("fabio_devolutiva_falhou", {
                        "p_id": item["id"], "p_lease_token": token,
                        "p_erro": str(e)[:1000], "p_backoff_segundos": 300})
                except Exception:
                    pass
            resultados.append({"id": item.get("id"), "status": "erro", "erro": str(e)[:200]})
        finally:
            # O ensaio DEVOLVE o que pegou. Sem isto ele deixava a linha em
            # 'gerando' com lease de 5 min, e a execucao de verdade logo depois
            # encontrava a fila vazia -- um ensaio que trava producao.
            if dry_run:
                try:
                    rpc("fabio_devolutiva_devolver",
                        {"p_id": item["id"], "p_lease_token": token})
                except Exception as e:  # noqa: BLE001
                    log("devolver_falhou", devolutiva_id=item.get("id"), erro=str(e)[:200])

    return {"ok": True, "dry_run": dry_run, "reivindicadas": len(itens), "resultados": resultados}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lote", type=int, default=LOTE)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    saida = rodar(args.lote, args.dry_run)
    print(json.dumps(saida, ensure_ascii=False, indent=None if args.json else 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
