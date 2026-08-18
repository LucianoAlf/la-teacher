#!/usr/bin/env python3
"""Lê o shadow da passada A e responde as três perguntas do Alf.

    ssh ... 'cd ~/fabio-chat-bridge && python3 medir_passada_a.py'
    ssh ... 'cd ~/fabio-chat-bridge && python3 medir_passada_a.py --dias 3'

As três perguntas (18/08/2026):
  1. quantas vezes A acordou;
  2. quantas foram válidas;
  3. quantas realmente resolveriam algo que o determinístico não pegou.

A (3) é a que decide se liga ou não, e é a única que não sai do log sozinha:
para cada evento, este script RE-RODA o extrator determinístico de hoje em cima
do mesmo texto. "A acordou" e "A serviu" são coisas diferentes — o gate pode
abrir num texto que o determinístico já resolveria numa versão mais nova.

⚠️ JANELA: `journald` aqui está com `MaxRetentionSec=7day`. Depois disso o
evento some. Se a medição precisar de mais tempo, o log tem que virar tabela.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_intents import extrair_consulta_letiva  # noqa: E402

UNIDADES_PADRAO = ["Campo Grande", "Recreio", "Barra", "Freguesia"]


def eventos(dias: int) -> list[dict]:
    saida = subprocess.run(
        ["journalctl", "--user", "-u", "fabio-chat-bridge.service",
         "-o", "cat", "--since", f"-{dias}d"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    ).stdout
    achados = []
    for linha in saida.splitlines():
        if '"consulta_fallback"' not in linha:
            continue
        try:
            dado = json.loads(linha[linha.index("{"):])
        except (ValueError, TypeError):
            continue
        if dado.get("msg") == "consulta_fallback":
            achados.append(dado)
    return achados


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--dias", type=int, default=7)
    args = p.parse_args()

    achados = eventos(args.dias)
    if not achados:
        print(f"nenhum evento de consulta_fallback em {args.dias} dia(s).")
        print("shadow ligado e ninguem tropecou no gate — ou o journal ja rodou.")
        return 0

    aceitos = [e for e in achados if e.get("aceito")]
    motivos = Counter(e.get("motivo") for e in achados if not e.get("aceito"))

    # (3) A pergunta que decide: o deterministico de HOJE pegaria isso sozinho?
    hoje = date.today()
    ja_pegava, so_o_A = [], []
    for e in aceitos:
        texto = e.get("texto") or ""
        (ja_pegava if extrair_consulta_letiva(texto, hoje, UNIDADES_PADRAO)
         else so_o_A).append(e)

    print(f"janela: ultimos {args.dias} dia(s)   (journald guarda 7)")
    print(f"1. A acordou ................ {len(achados)}")
    print(f"2. pedidos validos .......... {len(aceitos)}")
    print(f"3. SO o A resolveria ........ {len(so_o_A)}   <- e este numero que decide ligar")
    if ja_pegava:
        print(f"   (o deterministico de hoje ja pegaria {len(ja_pegava)} deles)")
    if motivos:
        print("\nrecusas:")
        for motivo, n in motivos.most_common():
            print(f"  {n:>3}x  {motivo}")
    if so_o_A:
        print("\nas que so o A pegaria (confira se sao MESMO consulta):")
        for e in so_o_A[:15]:
            ped = e.get("pedido") or {}
            print(f"  prof {e.get('professor_id')}: {(e.get('texto') or '')[:70]!r}")
            print(f"      -> {ped.get('metrica')} {ped.get('inicio')}..{ped.get('fim')}"
                  f" unidade={ped.get('unidade')}")
    print("\nLembrete: numero alto aqui NAO basta. Ler as frases acima e decidir se")
    print("eram consulta de verdade — o gate e largo de proposito.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
