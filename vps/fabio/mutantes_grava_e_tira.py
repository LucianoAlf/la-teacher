#!/usr/bin/env python3
"""Mutantes do conserto "a maquina ouve GRAVA e TIRA X" (incidente 18/08, prof 10).

Cada mutante reintroduz uma das duas mentiras do Fabio (o LLM inventando
"gravei"/"corrigi") OU a corrupcao latente do objetivo, e tem que morrer POR
ASSERCAO no arquivo de teste indicado. Restaura no finally; nao toca banco/VPS.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
INTENTS = "fabio_whatsapp_intents.py"
ACTIONS = "fabio_whatsapp_actions.py"
TESTE_INTENTS = "teste_whatsapp_intents.py"
TESTE_ACTIONS = "teste_whatsapp_actions.py"

MUTANTES = [
    {
        "nome": "1. 'grava' sai da lista afirmativa (volta a cair no LLM)",
        "porque": "'Grava' vira conversa e o LLM inventa 'a confirmacao esta com a maquina'",
        "alvo": INTENTS, "teste": TESTE_INTENTS,
        "old": '    "grava", "grave", "gravar",',
        "new": '    "xxx_mutante_sem_grava_xxx",',
    },
    {
        "nome": "2. a branch de correcao de conteudo morre (tira X vira conversa)",
        "porque": "'Tira solfejo' cai no LLM, que inventa 'entra como repertorio'",
        "alvo": INTENTS, "teste": TESTE_INTENTS,
        "old": (
            '    if tipo in {"confirmar_registro", "confirmar_chamada"} and any(\n'
            '        re.search(rf"\\b{verbo}\\b", hay) for verbo in _CORRECAO_CONTEUDO_WORDS\n'
            '    ):\n'
            '        return {"tipo": "correcao", "texto": texto.strip()}'
        ),
        "new": (
            '    if False:\n'
            '        return {"tipo": "correcao", "texto": texto.strip()}'
        ),
    },
    {
        "nome": "3. _correction_output volta a despejar o texto no objetivo",
        "porque": "a correcao de conteudo CORROMPE o rascunho (objetivo = texto da correcao)",
        "alvo": ACTIONS, "teste": TESTE_ACTIONS,
        "old": '        return {"registro_id": draft.get("id"), "aluno_id": draft.get("aluno_id"), "campos": {}}',
        "new": '        return {"registro_id": draft.get("id"), "aluno_id": draft.get("aluno_id"), "campos": {"objetivo": text}}',
    },
    {
        "nome": "4. a trava do 'sim seguro' some do confirmar (grava inseguro grava)",
        "porque": "'grava' 8min depois do LLM voltaria a gravar a aula errada",
        "alvo": ACTIONS, "teste": TESTE_ACTIONS,
        "old": "        if not _confirmacao_responde_a_maquina(backend, context, action):\n            return _pedir_confirmacao_de_novo(backend, context, action)",
        "new": "        if False and not _confirmacao_responde_a_maquina(backend, context, action):\n            return _pedir_confirmacao_de_novo(backend, context, action)",
    },
]


def rodar(teste: str) -> tuple[bool, str]:
    r = subprocess.run([sys.executable, "-B", teste], cwd=HERE,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, env=os.environ.copy())
    return r.returncode == 0, r.stdout


def main() -> int:
    for teste in (TESTE_INTENTS, TESTE_ACTIONS):
        ok, saida = rodar(teste)
        if not ok:
            print(f"BASELINE VERMELHO ({teste}):\n" + saida[-1200:])
            return 1
        print(f"baseline verde ({teste})")
    print()

    falhas = 0
    for m in MUTANTES:
        caminho = HERE / m["alvo"]
        original = caminho.read_text(encoding="utf-8")
        vezes = original.count(m["old"])
        if vezes != 1:
            print(f"[ERRO] {m['nome']}: ancora {vezes}x (esperado 1)")
            falhas += 1
            continue
        try:
            caminho.write_text(original.replace(m["old"], m["new"], 1), encoding="utf-8")
            vivo, saida = rodar(m["teste"])
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
            quais = [l.split("(")[0].strip() for l in saida.splitlines() if l.startswith(("FAIL:", "ERROR:"))]
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
