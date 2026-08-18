#!/usr/bin/env python3
"""Mutantes da fatia da acao fantasma (incidente de 18/08/2026, professor 10).

Cada mutante reintroduz um pedaco do incidente e tem que morrer POR ASSERCAO
em teste_whatsapp_actions.py. Restaura no finally; nao toca banco nem VPS.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ALVO = "fabio_whatsapp_actions.py"
TESTE = "teste_whatsapp_actions.py"

MUTANTES = [
    {
        "nome": "1. confirmar intencao volta a abrir SEGUNDA acao",
        "porque": "a raiz do crash: fabio_iniciar_acao_recusado derrubava o poller",
        "old": "        return _continuar_apos_intencao(backend, next_context, fluxo, action)",
        "new": "        return _start_from_candidates(backend, next_context, fluxo, _pool(backend, next_context, fluxo), action.get(\"storage_path\") if fluxo == \"registro\" else None)",
    },
    {
        "nome": "2. a trava de seguranca some do confirmar_intencao",
        "porque": "o Confirma tudo fora de hora volta a confirmar a pergunta de ontem",
        "old": "        if not _confirmacao_responde_a_maquina(backend, context, action):\n            return _result(\n                \"confirm_intent_restate\",",
        "new": "        if False:\n            return _result(\n                \"confirm_intent_restate\",",
    },
    {
        "nome": "3. shortlist vazia deixa a acao ABERTA (a fantasma renasce)",
        "porque": "pergunta sem candidata e pergunta que nenhuma resposta fecha",
        "old": "        _event(backend, action, context, \"cancelado\", {\"motivo\": \"sem_candidata_apos_intencao\"})",
        "new": "        pass",
    },
    {
        "nome": "4. audio parqueado volta a virar conversa muda",
        "porque": "o professor nunca fica sabendo que o audio foi guardado",
        "old": "        if guardado and resultado.get(\"code\") == \"conversation\":",
        "new": "        if False:",
    },
    {
        "nome": "5. erro de maquina abre a porta do LLM",
        "porque": "LLM em cima de estado meio-mutado e a receita das duas bocas",
        "old": "        return _result(\n            \"machine_error\",\n            reply=(\"Tive um erro aqui do meu lado ao processar essa mensagem e \"\n                   \"não gravei nada. Me manda de novo em um instante?\"),\n            erro=str(exc)[:300],\n        )",
        "new": "        return _result(\n            \"machine_error\", handled=False, forward=True,\n            reply=(\"Tive um erro aqui do meu lado ao processar essa mensagem e \"\n                   \"não gravei nada. Me manda de novo em um instante?\"),\n            erro=str(exc)[:300],\n        )",
    },
    {
        "nome": "6. a repergunta para de citar o audio em jogo",
        "porque": "sem citacao o professor segue no escuro — a ferida original",
        "old": "    previa = str((action.get(\"payload\") or {}).get(\"transcricao\") or \"\").strip()[:140]\n    return f' (\"{previa}…\")' if previa else \"\"",
        "new": "    return \"\"",
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
            print(f"[ERRO] {m['nome']}: ancora {vezes}x (esperado 1)")
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
