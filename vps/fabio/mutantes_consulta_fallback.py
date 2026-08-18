#!/usr/bin/env python3
"""Mutantes da fronteira da passada A.

Cada um reintroduz um atalho plausível — vários deles são exatamente o que eu
faria com pressa — e tem que deixar o teste vermelho POR ASSERÇÃO. O mais
importante é o nº 2: "limpa o campo e segue" faz tudo funcionar e ESCONDE que o
modelo saiu do schema, que é o oposto do item 9 do contrato.

Não toca em rede, banco nem VPS: reescreve o arquivo local e restaura no finally.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ALVO = "fabio_consulta_fallback.py"
TESTE = "teste_consulta_fallback.py"

MUTANTES = [
    {
        "nome": "1. schema fechado deixa de existir",
        "porque": "campo inventado e professor_id passariam direto",
        "old": "    if set(dados) - CAMPOS_PERMITIDOS:\n        return None",
        "new": "    pass",
    },
    {
        "nome": "2. 'limpa o campo extra e segue' em vez de rejeitar",
        "porque": "o atalho tentador: funciona e esconde que o modelo desobedeceu",
        "old": "    if set(dados) - CAMPOS_PERMITIDOS:\n        return None",
        "new": "    dados = {c: v for c, v in dados.items() if c in CAMPOS_PERMITIDOS}",
    },
    {
        "nome": "3. o prompt volta a pedir identidade",
        "porque": "prompt cheio ja fez o modelo devolver professor_id, medido em 18/08",
        "old": "    'Mensagem: {texto}'",
        "new": "    'Inclua também professor_id. Mensagem: {texto}'",
    },
    {
        "nome": "4. unidade inventada pelo modelo vira filtro da RPC",
        "porque": "consulta com recorte errado mente; sem recorte so e incompleta",
        "old": "        for nome in unidades or []:\n            if _norm(nome) == pedida:\n                unidade = nome\n                break",
        "new": "        unidade = dados.get('unidade')",
    },
    {
        "nome": "5. gate abre para registro de aula",
        "porque": "7s de custo no exato momento em que o professor quer gravar",
        "old": "    if _E_REGISTRO.search(hay) or _E_PEDIDO_PEDAGOGICO.search(hay):\n        return False",
        "new": "    pass",
    },
    {
        "nome": "6. data alucinada e janela gigante passam",
        "porque": "1999 ou 8 meses de janela viram consulta em vez de virar pergunta",
        "old": "    if (fim - inicio).days + 1 > _JANELA_MAXIMA_DIAS:\n        return None",
        "new": "    pass",
    },
    {
        "nome": "7. 'nenhuma' vira consulta em vez de silencio",
        "porque": "A dizendo 'nao era consulta' viraria bloco injetado sem periodo",
        "old": '    if consulta == "nenhuma":\n        return None',
        "new": '    if consulta == "nenhuma":\n        consulta = "aulas_periodo"',
    },
]


def rodar_teste() -> tuple[bool, str]:
    r = subprocess.run([sys.executable, "-B", TESTE], cwd=HERE,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, env=os.environ.copy())
    return r.returncode == 0, r.stdout


def main() -> int:
    caminho = HERE / ALVO
    original = caminho.read_text(encoding="utf-8")

    ok, saida = rodar_teste()
    if not ok:
        print("BASELINE VERMELHO — nao da pra medir mutante assim:\n" + saida[-1200:])
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

        mal = "SyntaxError" in saida or "ImportError" in saida or "IndentationError" in saida
        if vivo:
            print(f"[SOBREVIVEU] {m['nome']}\n             {m['porque']}")
            falhas += 1
        elif mal:
            print(f"[MORREU MAL] {m['nome']} — caiu de sintaxe, nao de assercao")
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
