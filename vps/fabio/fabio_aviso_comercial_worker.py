#!/usr/bin/env python3
"""Entrega ao comercial a devolutiva da aula experimental.

POR QUE ESTE WORKER É MAGRO
Diferente do worker da devolutiva, aqui NÃO tem LLM. O corpo da mensagem já
nasce pronto no banco, dentro de `fabio_claim_aviso_comercial` (036) — é o
único lugar do sistema onde o bloco family-safe e a leitura de conversão
aparecem juntos, porque aqui o destinatário É o círculo interno. Este processo
só tira da fila, entrega e fecha.

O CICLO
    1. fabio_avisos_comerciais_pendentes   o que há pra fazer (não reivindica)
    2. fabio_claim_aviso_comercial         pega o lease de verdade
    3. fabio_aviso_comercial_para_envio    corpo + destinatário, só com o token
    4. UAZAPI /send/text
    5. fabio_marcar_notificacao_enviada    fecha com o mesmo token

QUEM PEGA O LEASE É QUEM TRABALHA
A confirmação (038) enfileira com lease ZERO — ela não trabalha, só deixa na
fila. Isso foi conserto da 042: antes ela saía segurando 10 minutos e este
worker recebia `claimed=false / lease_vivo_ou_enviada`. O aviso só sairia 10
minutos depois da aula, registrado como recuperação de lease abandonado. Nada
dava erro; fila com dono errado não levanta exceção, só não entrega.

UNIDADE SEM COMERCIAL NÃO SOME
Fica na fila como `pulada_sem_destinatario`, com o motivo escrito, e volta a
ser tentada a cada varredura. No dia em que alguém cadastrar o contato, a
devolutiva sai sozinha. É por isso que este worker varre esse status também —
a 036 promete a retomada, e promessa que ninguém varre é gancho sem chamador.

USO
    python3 fabio_aviso_comercial_worker.py [--lote N] [--dry-run] [--json]

    --dry-run NÃO reivindica nada. Só mostra a fila. Um ensaio que pega o lease
    é um ensaio que trava produção — foi assim que o worker da devolutiva
    precisou aprender a devolver o que pegava.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from typing import Any, Dict, List

import fabio_chat_bridge as bridge

WORKER = os.getenv("FABIO_AVISO_COMERCIAL_WORKER", f"aviso-comercial@{socket.gethostname()}")
LOTE = int(os.getenv("FABIO_AVISO_COMERCIAL_LOTE", "10"))
LEASE_MIN = int(os.getenv("FABIO_AVISO_COMERCIAL_LEASE_MIN", "5"))
BACKOFF_SEG = int(os.getenv("FABIO_AVISO_COMERCIAL_BACKOFF_SEG", "300"))


def log(msg: str, **fields: Any) -> None:
    bridge.log(f"aviso_comercial_{msg}", **fields)


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:500]}")
    return r.json() if r.text else None


def enviar(destinatario: str, corpo: str) -> None:
    import requests

    if not bridge.UAZAPI_TOKEN:
        raise RuntimeError("UAZAPI_TOKEN ausente — sem canal pra entregar")
    r = requests.post(
        f"{bridge.UAZAPI_URL}/send/text",
        headers={"Content-Type": "application/json", "token": bridge.UAZAPI_TOKEN},
        json=bridge.whatsapp_send_payload(destinatario, corpo),
        timeout=30,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"uazapi send/text {r.status_code}: {r.text[:300]}")


def processar(item: Dict[str, Any]) -> Dict[str, Any]:
    registro_id = item.get("registro_id")
    resultado: Dict[str, Any] = {"registro_id": registro_id, "status": "?"}

    claim = rpc("fabio_claim_aviso_comercial",
                {"p_registro_id": registro_id, "p_lease_minutos": LEASE_MIN}) or {}
    if not claim.get("claimed"):
        motivo = claim.get("motivo") or "desconhecido"
        # `sem_destinatario` NÃO é erro: é a unidade sem comercial cadastrado.
        # Fica logado em toda varredura de propósito — silêncio aqui é como a
        # devolutiva de uma família some sem ninguém perceber.
        resultado["status"] = "pulado"
        resultado["motivo"] = motivo
        log("pulado", registro_id=registro_id, motivo=motivo)
        return resultado

    notificacao_id = claim.get("notificacao_id")
    lease_token = claim.get("lease_token")

    pronto = rpc("fabio_aviso_comercial_para_envio",
                 {"p_notificacao_id": notificacao_id, "p_lease_token": lease_token}) or {}
    if not pronto.get("ok"):
        # Reivindiquei e não consigo ler: alguém tomou o lease no meio, ou a
        # linha mudou de estado. Não marco como falha — não houve falha de
        # entrega, houve perda de corrida.
        resultado["status"] = "lease_perdido"
        log("lease_perdido", registro_id=registro_id, notificacao_id=notificacao_id)
        return resultado

    destinatario = pronto.get("destinatario")
    corpo = pronto.get("corpo") or ""
    try:
        enviar(destinatario, corpo)
    except Exception as e:  # noqa: BLE001
        rpc("fabio_marcar_notificacao_falhou", {
            "p_notificacao_id": notificacao_id,
            "p_erro": str(e)[:1000],
            "p_lease_token": lease_token,
            "p_backoff_segundos": BACKOFF_SEG,
        })
        resultado["status"] = "falhou"
        resultado["erro"] = str(e)[:200]
        log("falhou", registro_id=registro_id, erro=str(e)[:300])
        return resultado

    fechou = rpc("fabio_marcar_notificacao_enviada", {
        "p_notificacao_id": notificacao_id,
        "p_lease_token": lease_token,
        "p_recibo": WORKER,
    })
    if not fechou:
        # A mensagem SAIU e a linha não fechou. É o pior estado da fila: na
        # próxima varredura ela é reivindicada de novo e o comercial recebe a
        # mesma devolutiva duas vezes. Grita alto — não dá pra desfazer envio.
        log("entregue_mas_nao_fechada",
            registro_id=registro_id, notificacao_id=notificacao_id,
            destinatario_final=str(destinatario)[-4:])
        resultado["status"] = "entregue_mas_nao_fechada"
        return resultado

    resultado["status"] = "enviada"
    resultado["destinatario_final"] = str(destinatario)[-4:]
    log("enviada", registro_id=registro_id, notificacao_id=notificacao_id,
        destinatario_final=str(destinatario)[-4:])
    return resultado


def rodar(lote: int, dry_run: bool) -> Dict[str, Any]:
    fila: List[Dict[str, Any]] = rpc("fabio_avisos_comerciais_pendentes", {"p_lote": lote}) or []
    if not fila:
        return {"ok": True, "dry_run": dry_run, "na_fila": 0, "resultados": []}

    if dry_run:
        # Ensaio não reivindica: sem lease, sem tentativa incrementada, sem
        # corpo lido. O que ele mostra é exatamente o que a fila mostra.
        return {"ok": True, "dry_run": True, "na_fila": len(fila),
                "resultados": [{"registro_id": i.get("registro_id"),
                                "status_na_fila": i.get("status"),
                                "tentativas": i.get("tentativas")} for i in fila]}

    resultados = []
    for item in fila:
        try:
            resultados.append(processar(item))
        except Exception as e:  # noqa: BLE001 — uma linha ruim não derruba o lote
            log("erro", registro_id=item.get("registro_id"), erro=str(e)[:300])
            resultados.append({"registro_id": item.get("registro_id"),
                               "status": "erro", "erro": str(e)[:200]})

    resumo: Dict[str, int] = {}
    for r in resultados:
        resumo[r["status"]] = resumo.get(r["status"], 0) + 1
    return {"ok": True, "dry_run": False, "na_fila": len(fila),
            "resumo": resumo, "resultados": resultados}


def main() -> int:
    ap = argparse.ArgumentParser(description="Entrega ao comercial a devolutiva da experimental.")
    ap.add_argument("--lote", type=int, default=LOTE)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    saida = rodar(args.lote, args.dry_run)
    if args.json:
        print(json.dumps(saida, ensure_ascii=False))
    else:
        print(saida)
    return 0


if __name__ == "__main__":
    sys.exit(main())
