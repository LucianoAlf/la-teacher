#!/usr/bin/env python3
"""Teste do relato honesto da fila de áudios (fabio_auditoria).

POR QUE ELE EXISTE. Todo dia 22/08 o relatório das 7h dizia, no bloco
*"Corrigi sozinho"*:

    • 4 áudio(s) parado(s) → reenfileirados (0 retomados)

Nada tinha sido reenfileirado. O código anunciava `len(retriaveis)` como
conserto e jogava o retorno REAL do RPC entre parênteses. Os 4 eram de
10–15/08 com 3/3/11/11 tentativas, e `fn_fabio_retry_fila` exige
`tentativas < 3` E `criado_em > now() - 3 days` — ele não podia tocá-los nem
em teoria. O relatório se elogiava por um trabalho impossível.

Alarme que mente todo dia ensina o leitor a ignorar o alarme — e aí o alarme
verdadeiro morre junto. Os casos NEGATIVOS aqui são o que segura isso: sem
eles, `_fora_do_alcance_do_retry` vira `return True` e passa a chamar de
encalhado o áudio que o retry vai pegar daqui a 5 minutos.

Rodar:  python3 teste_auditoria_encalhe.py
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_auditoria import _fora_do_alcance_do_retry, _motivo_encalhe  # noqa: E402

falhas: list[str] = []
total = 0


def checar(nome: str, esperado, obtido) -> None:
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


def iso(dias_atras: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=dias_atras)).isoformat()


# ── casos REAIS: os 4 do relatório de 22/08 ────────────────────────────────
# (ids e datas conferidos no banco antes de virar fixture)
REAIS = [
    {"id": "be63b8c6-eef0-4227-898e-61beaaebb2c5", "tentativas": 11, "criado_em": iso(12)},
    {"id": "292f9739-7327-4d3c-8d81-ade5edfdc04f", "tentativas": 11, "criado_em": iso(11)},
    {"id": "3c47cf22-074a-4ea4-a4c9-cdb3c291d338", "tentativas": 3,  "criado_em": iso(9)},
    {"id": "7893ce03-eb70-4f64-bc91-186f09198691", "tentativas": 3,  "criado_em": iso(7)},
]
checar("1. os 4 do relatório são TODOS fora do alcance do retry",
       [True, True, True, True], [_fora_do_alcance_do_retry(p) for p in REAIS])

# ── NEGATIVOS: quem o retry AINDA vai pegar não pode virar alarme ──────────
checar("2. recém-criado com 0 tentativas está no alcance", False,
       _fora_do_alcance_do_retry({"tentativas": 0, "criado_em": iso(0.1)}))
checar("2b. 2 tentativas e 1 dia ainda está no alcance", False,
       _fora_do_alcance_do_retry({"tentativas": 2, "criado_em": iso(1)}))

# ── as duas bordas, uma de cada vez (senão um dos dois cortes some sem teste)
checar("3. tentativas na borda (3) já está FORA", True,
       _fora_do_alcance_do_retry({"tentativas": 3, "criado_em": iso(0.1)}))
checar("3b. só a IDADE (velho, poucas tentativas) já põe fora", True,
       _fora_do_alcance_do_retry({"tentativas": 0, "criado_em": iso(5)}))

# ── formas degeneradas não podem explodir a auditoria ─────────────────────
checar("4. sem criado_em, decide só pelas tentativas (0 = dentro)", False,
       _fora_do_alcance_do_retry({"tentativas": 0}))
checar("4b. criado_em com Z (formato do PostgREST) é entendido", True,
       _fora_do_alcance_do_retry({"tentativas": 0,
                                  "criado_em": iso(5).replace("+00:00", "Z")}))
checar("4c. criado_em ilegível não vira alarme falso", False,
       _fora_do_alcance_do_retry({"tentativas": 0, "criado_em": "nao-e-data"}))
checar("4d. tentativas ausente conta como 0", False,
       _fora_do_alcance_do_retry({"criado_em": iso(0.1)}))

# ── o motivo tem que dizer a verdade sobre o CONJUNTO ──────────────────────
checar("5. motivo dos 4 reais cita tentativas esgotadas", True,
       "tentativas esgotadas" in _motivo_encalhe(REAIS))
checar("5b. só velhos (poucas tentativas) → fala de dias, não de tentativas",
       "mais de 3 dias", _motivo_encalhe([{"tentativas": 0, "criado_em": iso(9)}]))
checar("5c. só tentativas esgotadas → não inventa 'dias'",
       "tentativas esgotadas", _motivo_encalhe([{"tentativas": 5, "criado_em": iso(0.1)}]))
checar("5d. mistura dos dois cita os dois", True,
       all(t in _motivo_encalhe([{"tentativas": 5, "criado_em": iso(0.1)},
                                 {"tentativas": 0, "criado_em": iso(9)}])
           for t in ("tentativas esgotadas", "mais de 3 dias")))

# ── nome que identifica quem é (a casa tem dois Matheus) ──────────────────
from fabio_auditoria import _nome_no_relatorio  # noqa: E402

DOIS_MATHEUS = ["Matheus Felipe Lourenço", "Matheus Reis", "Daiana Pacifico da Silva dos Anjos"]
checar("6. com dois Matheus, desempata pelo sobrenome",
       ["Matheus L.", "Matheus R."],
       [_nome_no_relatorio(n, DOIS_MATHEUS) for n in DOIS_MATHEUS[:2]])
checar("6b. nome único continua só o primeiro (sem poluir)",
       "Daiana", _nome_no_relatorio(DOIS_MATHEUS[2], DOIS_MATHEUS))
checar("6c. lista sem repetição não ganha inicial",
       "Isaque", _nome_no_relatorio("Isaque Mendes da Silva", ["Isaque Mendes da Silva", "Valdo Delfino"]))
checar("6d. nome de uma palavra só não explode",
       "Akeem", _nome_no_relatorio("Akeem", ["Akeem", "Akeem"]))
checar("6e. nome vazio/None não explode", "?", _nome_no_relatorio(None, [None]))

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  ✗ {f}")
    sys.exit(1)
print("tudo verde ✅")
