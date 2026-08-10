#!/usr/bin/env python3
"""Mutantes do casador de carimbo (fabio_auditoria.carimba_escrita).

O teste sozinho não prova nada: 22 casos verdes podem vir de um `return True`
com a lista de negativos errada, ou de um `return False` com a lista de
positivos errada. Estes mutantes existem pra provar que cada peneira do casador
está segurando alguma coisa de verdade.

M6 e M7 são os dois jeitos preguiçosos de "consertar" um alarme barulhento:
calar ele (sempre False) ou deixar ele gritar sempre (sempre True). Os dois
passariam num teste que só tivesse um dos lados.

Rodar:  python3 mutantes_auditoria_carimbo.py
"""
from __future__ import annotations

import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
ALVO = os.path.join(AQUI, "fabio_auditoria.py")
TESTE = os.path.join(AQUI, "teste_auditoria_carimbo.py")

FONTE = open(ALVO, encoding="utf-8").read()

MUTANTES = [
    {
        "nome": "M1 — a peneira de negacao cai (relato de estado vira acusacao)",
        "pega": '"4 aulas SEM presenca marcada" e "ainda NAO consigo gravar"',
        "de": '        if not frase or _INOCENTA.search(frase):',
        "para": '        if not frase:',
    },
    {
        "nome": "M2 — para de quebrar em frases (negacao de uma inocenta a outra)",
        "pega": '"hoje nao tem aula. Registrei a aula de ontem."',
        "de": '    for frase in _FRASE.split(texto or ""):',
        "para": '    for frase in [texto or ""]:',
    },
    {
        "nome": "M3 — pergunta deixa de ser inocentada",
        "pega": '"Posso deixar esse registro salvo?" e "Quer que eu deixe...?"',
        "de": 'r"\\b(n[aã]o|sem|nunca|ainda|preciso|precisa|quer que|posso|poderia|"',
        "para": 'r"\\b(n[aã]o|sem|nunca|ainda|preciso|precisa|"',
    },
    {
        "nome": "M4 — o carimbo por 'confirmado + objeto' some",
        "pega": '"Confirmado: o Eduardo compareceu a aula de 06/08"',
        "de": 'r"|\\bconfirmad[oa]\\b.{0,70}?\\b(compareceu|presen[cç]a|falta|aus[eê]ncia|registro)"',
        "para": 'r"|\\bnuncaissoaqui\\b"',
    },
    {
        "nome": "M5 — o carimbo 'deixei ... salvo' some (o caso original da Daiana)",
        "pega": '"Deixei o registro da Beatriz organizado e salvo"',
        "de": 'r"|deixei\\b.{0,80}?\\b(salv[oa]|registrad|gravad|encaminhad|marcad)"',
        "para": 'r"|deixei\\b.{0,3}?\\b(salv[oa]|registrad|gravad|encaminhad|marcad)"',
    },
    {
        "nome": "M6 — o alarme e calado (o jeito preguicoso de parar o barulho)",
        "pega": "todos os positivos",
        "de": '    """True quando o Fábio AFIRMA, ao professor, que gravou algo no sistema."""',
        "para": '    """True quando o Fábio AFIRMA, ao professor, que gravou algo no sistema."""\n    return False',
    },
    {
        "nome": "M7 — o alarme grita sempre (o outro jeito preguicoso)",
        "pega": "todos os negativos",
        "de": '        if _CARIMBO.search(frase):\n            return True\n    return False',
        "para": '        if _CARIMBO.search(frase):\n            return True\n    return bool((texto or "").strip())',
    },
]


def main() -> int:
    mortos = 0
    podres = 0
    for m in MUTANTES:
        n = FONTE.count(m["de"])
        if n != 1:
            print(f'STALE  {m["nome"]} — ancora aparece {n} vez(es), esperava 1')
            print(f'       procurava: {m["de"][:90]!r}')
            podres += 1
            continue
        open(ALVO, "w", encoding="utf-8", newline="\n").write(FONTE.replace(m["de"], m["para"]))
        try:
            r = subprocess.run([sys.executable, TESTE], capture_output=True, text=True, timeout=120)
            passou = r.returncode == 0
        except Exception:
            passou = False
        if passou:
            print(f'FALHA  SOBREVIVEU: {m["nome"]}  ({m["pega"]})')
        else:
            mortos += 1
            print(f'OK     morto: {m["nome"]}  ({m["pega"]})')

    open(ALVO, "w", encoding="utf-8", newline="\n").write(FONTE)  # sempre restaura
    print(f'\n{mortos}/{len(MUTANTES)} mutantes mortos'
          + (f'  —  {podres} ANCORA(S) PODRE(S)' if podres else ''))
    return 0 if mortos == len(MUTANTES) and not podres else 1


if __name__ == "__main__":
    sys.exit(main())
