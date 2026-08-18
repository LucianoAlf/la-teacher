#!/usr/bin/env python3
"""Mutantes do intervalo com o mês dito uma vez ("de 11 a 15 de agosto").

Cada mutante reintroduz UM atalho e tem que deixar o teste focado vermelho —
por asserção, não por erro de sintaxe. Verde não falsificado é decoração.

O defeito original (medido em produção em 18/08/2026): a pergunta canônica
resolvia para 15/08–15/08 e o Fábio respondia a conta de um dia. Os mutantes 2,
3 e 4 são as três formas de "consertar" que quebram outra coisa em silêncio —
duas delas eu escrevi de verdade no caminho, e um teste antigo pegou.

Não toca em Supabase, UAZAPI nem na VPS: só reescreve o arquivo local e
restaura no finally.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ALVO = "fabio_whatsapp_intents.py"
TESTE = "teste_whatsapp_intents.py"

MUTANTES = [
    {
        "nome": "1. o intervalo com mes dito uma vez volta a nao existir",
        "porque": "e o defeito original: sobra so a data final e inicio == fim",
        "old": "    for m in _INTERVALO_MES_UMA_VEZ.finditer(hay):",
        "new": "    for m in []:",
    },
    {
        "nome": "2. sem a trava do lookbehind de data digitada",
        "porque": '"de 11/08 a 15/08" passa a ler o "08" como dia inicial',
        "old": '_INTERVALO_MES_UMA_VEZ = re.compile(\n    rf"(?<![\\d/-])\\b(\\d{{1,2}})\\s+(?:a|ate|ao|e)\\s+(?:o\\s+)?(?:dia\\s+)?"',
        "new": '_INTERVALO_MES_UMA_VEZ = re.compile(\n    rf"\\b(\\d{{1,2}})\\s+(?:a|ate|ao|e)\\s+(?:o\\s+)?(?:dia\\s+)?"',
    },
    {
        "nome": "3. sem a guarda do mes da data anterior",
        "porque": '"de 11 de 8 ate 15 de 8" volta a virar 08/08-15/08',
        "old": "    return bool(_MES_DE_DATA_ANTERIOR.search(hay[:inicio]))",
        "new": "    return False",
    },
    {
        "nome": "4. o conector 'as' entra na lista",
        "porque": '"das 8 as 10 da manha" e HORARIO e viraria periodo de dias',
        "old": 'rf"(?<![\\d/-])\\b(\\d{{1,2}})\\s+(?:a|ate|ao|e)\\s+(?:o\\s+)?(?:dia\\s+)?"',
        "new": 'rf"(?<![\\d/-])\\b(\\d{{1,2}})\\s+(?:a|as|ate|ao|e)\\s+(?:o\\s+)?(?:dia\\s+)?"',
    },
]


def rodar_teste() -> tuple[bool, str]:
    r = subprocess.run(
        [sys.executable, "-B", "-m", "unittest", TESTE.removesuffix(".py")],
        cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env=os.environ.copy(),
    )
    return r.returncode == 0, r.stdout


def main() -> int:
    caminho = HERE / ALVO
    original = caminho.read_text(encoding="utf-8")

    ok, saida = rodar_teste()
    if not ok:
        print("BASELINE VERMELHO — nao da pra medir mutante assim:\n" + saida[-1500:])
        return 1
    print(f"baseline verde ({TESTE})\n")

    falhas = 0
    for m in MUTANTES:
        vezes = original.count(m["old"])
        if vezes != 1:
            print(f"[ERRO] {m['nome']}: ancora aparece {vezes}x (esperado 1)")
            falhas += 1
            continue
        try:
            caminho.write_text(original.replace(m["old"], m["new"], 1), encoding="utf-8")
            vivo, saida = rodar_teste()
        finally:
            caminho.write_text(original, encoding="utf-8")

        # Morrer de SyntaxError nao prova nada: o mutante tem que cair na
        # assercao. Ver `teste-sql-so-vale-com-mutante` na memoria.
        por_sintaxe = "SyntaxError" in saida or "ImportError" in saida
        if vivo:
            print(f"[SOBREVIVEU] {m['nome']}\n             {m['porque']}")
            falhas += 1
        elif por_sintaxe:
            print(f"[MORREU MAL] {m['nome']} — caiu de sintaxe, nao de assercao")
            falhas += 1
        else:
            quais = [l.strip() for l in saida.splitlines() if l.startswith("FAIL:")]
            print(f"[morreu] {m['nome']}")
            for q in quais[:3]:
                print(f"          {q}")

    print()
    if falhas:
        print(f"{falhas} mutante(s) nao provaram nada")
        return 1
    print(f"{len(MUTANTES)}/{len(MUTANTES)} mutantes mortos por assercao")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
