#!/usr/bin/env python3
"""Teste do lembrete imediato da experimental (fabio_notification_worker).

POR QUE ELE EXISTE. O lembrete roda de 5 em 5 minutos. Sem trava, o mesmo
professor recebe a mesma cobranca 12 vezes por hora — e cobranca repetida
ensina a ignorar. A trava real e o indice uq_fabio_notif_por_referencia, que
so morde se a referencia for (experimental_vinculo, vinculo_id): errar o
carimbo aqui desliga a trava sem nenhum erro aparecer.

Rodar:  python3 teste_experimental_lembrete.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_notification_worker import (  # noqa: E402
    format_lembrete_experimental, REFERENCIA_TIPO_EXPERIMENTAL,
)

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


LINHA = {"vinculo_id": 2275, "professor_id": 10, "nome_aluno": "Davi Nakashima",
         "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
         "hora_fim": "19:00", "horas_em_atraso": 0}

texto = format_lembrete_experimental(LINHA)

# 1. o que o professor precisa pra saber DE QUEM se trata
checar("1. cita o nome do lead", True, "Davi Nakashima" in texto)
checar("1b. cita o horario", True, "19:00" in texto)

# 2. o lembrete VENDE a ferramenta (e o habito que o Alf quer criar).
#    Sem isso vira mais uma cobranca e o professor nao entende pra que serve.
checar("2. explica que o comercial usa", True, "comercial" in texto.lower())

# 3. NEGATIVO: nao pode vazar jargao de sistema pro professor
for termo in ("vinculo", "vinculo_id", "lead_experimental", "None", "null"):
    checar(f"3. nao vaza '{termo}'", False, termo in texto)

# 4. a referencia da trava e o VINCULO — se virar 'devolutiva' ou o id da aula,
#    o indice unico deixa de morder e o professor leva 12 mensagens por hora
checar("4. carimbo da referencia e experimental_vinculo",
       "experimental_vinculo", REFERENCIA_TIPO_EXPERIMENTAL)

# 5. formas degeneradas nao podem explodir o worker no meio do lote
checar("5. sem nome nao explode", True, isinstance(
    format_lembrete_experimental({**LINHA, "nome_aluno": None}), str))
checar("5b. sem hora nao explode", True, isinstance(
    format_lembrete_experimental({**LINHA, "hora_fim": None}), str))

# 6. o caso 3 so olha o texto com NOME REAL — o fallback "o lead" nunca roda
#    nesse caminho, entao trocar o fallback por algo com jargao (ex.:
#    f"vinculo {vinculo_id}") passa pelo caso 3 sem ser notado. Quem exercita
#    o fallback e o proprio caso degenerado (sem nome); testar so
#    isinstance() ali deixava esse mutante vivo.
texto_sem_nome = format_lembrete_experimental({**LINHA, "nome_aluno": None})
for termo in ("vinculo", "vinculo_id", str(LINHA["vinculo_id"])):
    checar(f"6. fallback sem nome nao vaza '{termo}'", False, termo in texto_sem_nome)

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
