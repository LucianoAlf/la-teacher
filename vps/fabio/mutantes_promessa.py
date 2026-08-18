#!/usr/bin/env python3
"""Mutantes do detector de promessa.

As duas metades precisam morrer: deixar promessa passar (o Fábio volta a
prometer) e matar frase honesta (o Fábio cala onde tem fila de verdade). A
segunda é a que costuma faltar — 5 das 8 frases do corpus que "parecem
promessa" são verdadeiras.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ALVO = "fabio_promessa.py"
TESTE = "teste_promessa.py"

MUTANTES = [
    {
        "nome": "1. objeto de consulta deixa de contar",
        "porque": "as 3 promessas reais do corpus voltam a passar",
        "old": "    if _OBJETO_DE_CONSULTA.search(hay):",
        "new": "    if False:",
    },
    {
        "nome": "2. fila viva passa a inocentar TUDO",
        "porque": "'te passo o total' viraria honesto so por ter audio na fila",
        "old": '        return {"tipo": CONSULTA_DEPOIS, "gatilho": compromisso.group(0)}',
        "new": '        return None if ha_fluxo_pendente else {"tipo": CONSULTA_DEPOIS, "gatilho": compromisso.group(0)}',
    },
    {
        "nome": "3. o estado da fila deixa de importar no caso de fluxo",
        "porque": "prometer preview sem fila nenhuma passaria batido",
        "old": "    if _OBJETO_DE_FLUXO.search(hay) and not ha_fluxo_pendente:",
        "new": "    if False:",
    },
    {
        "nome": "4. 'pode deixar' entra na lista de compromisso",
        "porque": "'karaoke pode deixar a Fernanda mais a vontade' viraria promessa",
        "old": r'    r"|\bfico\s+de\s+(?:te\s+)?(?:trazer|passar|avisar)\b")',
        "new": r'    r"|\bfico\s+de\s+(?:te\s+)?(?:trazer|passar|avisar)\b|\bpode deixar\b")',
    },
    {
        "nome": "5. detector cego a frase sem acento normalizado",
        "porque": "o corpus vem com acento; sem _norm o detector nao ve nada",
        "old": "    hay = _norm(resposta)",
        "new": "    hay = str(resposta or '').lower()",
    },
]


def rodar() -> tuple[bool, str]:
    r = subprocess.run([sys.executable, "-B", TESTE], cwd=HERE,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, env=os.environ.copy())
    return r.returncode == 0, r.stdout


def main() -> int:
    caminho = HERE / ALVO
    original = caminho.read_text(encoding="utf-8")
    ok, saida = rodar()
    if not ok:
        print("BASELINE VERMELHO:\n" + saida[-1200:])
        return 1
    print(f"baseline verde ({TESTE})\n")

    falhas = 0
    for m in MUTANTES:
        vezes = original.count(m["old"])
        if vezes != 1:
            print(f"[ERRO] {m['nome']}: ancora {vezes}x")
            falhas += 1
            continue
        try:
            caminho.write_text(original.replace(m["old"], m["new"], 1), encoding="utf-8")
            vivo, saida = rodar()
        finally:
            caminho.write_text(original, encoding="utf-8")
        mal = any(e in saida for e in ("SyntaxError", "ImportError", "IndentationError"))
        if vivo:
            print(f"[SOBREVIVEU] {m['nome']}\n             {m['porque']}")
            falhas += 1
        elif mal:
            print(f"[MORREU MAL] {m['nome']} — sintaxe, nao assercao")
            falhas += 1
        else:
            quais = [l.split("(")[0].strip() for l in saida.splitlines() if l.startswith("FAIL:")]
            print(f"[morreu] {m['nome']}")
            for q in quais[:2]:
                print(f"          {q}")

    print()
    if falhas:
        print(f"{falhas} mutante(s) nao provaram nada")
        return 1
    print(f"{len(MUTANTES)}/{len(MUTANTES)} mutantes mortos por assercao")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
