#!/usr/bin/env python3
"""Teste do escalonamento da experimental para a coordenacao.

POR QUE ELE EXISTE. Escalonamento e a mensagem que chega em quem NAO deu a
aula. Se ela nao disser de quem e a aula, qual unidade e ha quanto tempo, a
coordenacao nao consegue agir e a mensagem vira ruido — e ruido em canal de
coordenacao mata a credibilidade de todo o resto.

Ruling 10 (22/08/2026): fn_experimental_escalonadas() nao tem teto de
proposito (a regua fecha so com devolutiva CONFIRMADA — lead nunca
confirmado nunca sai da lista). Quem corta e a MENSAGEM, nao a RPC — os
casos 7-9 provam isso: abaixo do teto mostra tudo, acima mostra N e
"e mais X." com o numero certo, e teto<=0 desliga o corte (mesma convencao
de format_escalonamento(blocos=0)).

Os casos 10-13 cobrem o ponto de despacho: a fila do aluno nao pode mudar
quando nao ha experimental pendente (nada que ja funciona muda de
comportamento), o bloco entra como mensagem PROPRIA no fim da fila, e uma
falha na busca da experimental nao pode derrubar o escalonamento do aluno.

Rodar:  python3 teste_escalonamento_experimental.py
"""
from __future__ import annotations

import os
import sys
from unittest.mock import patch

# O corpo das mensagens carrega emoji (🎓). Sem isto, um console que nao fala
# UTF-8 (cp1252 do Windows) morre com UnicodeEncodeError no meio do print das
# FALHAS — o exit code continua != 0, mas quem revisa perde a lista bem na
# hora que mais precisa dela.
sys.stdout.reconfigure(errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fabio_notification_worker as worker  # noqa: E402
from fabio_notification_worker import (  # noqa: E402
    format_escalonamento_experimental,
    linhas_experimental_escalonadas,
    montar_mensagens_escalonamento,
)

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


# ---------------------------------------------------------------------------
# Casos 1-6 — verbatim do brief (task-5-brief.md)
# ---------------------------------------------------------------------------

LINHAS = [{"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
           "professor_nome": "Isaque Mendes da Silva", "unidade_nome": "Barra",
           "curso_nome": "Aula Experimental", "quando": "13/08 18:00",
           "dias_em_atraso": 3}]

texto = format_escalonamento_experimental(LINHAS)

# quem age precisa dos quatro: quem, onde, quando, quem devia ter feito
checar("1. cita o lead", True, "Davi Nakashima" in texto)
checar("2. cita a unidade", True, "Barra" in texto)
checar("3. cita quando foi a aula", True, "13/08" in texto)
checar("4. cita o professor", True, "Isaque" in texto)
checar("5. diz o custo (o comercial nao recebeu)", True, "comercial" in texto.lower())

checar("6. lista vazia devolve None", None, format_escalonamento_experimental([]))


# ---------------------------------------------------------------------------
# Casos 7-9 — Ruling 10: o teto fica na montagem da mensagem
# ---------------------------------------------------------------------------

def _linha(n: int, dias: int = 5) -> dict:
    return {"vinculo_id": 3000 + n, "nome_aluno": f"Lead {n}",
            "professor_nome": f"Prof {n}", "unidade_nome": "Barra",
            "curso_nome": "Aula Experimental", "quando": "10/08 10:00",
            "dias_em_atraso": dias}


TRES = [_linha(1), _linha(2), _linha(3)]
DOZE = [_linha(n) for n in range(1, 13)]

# 7. abaixo do teto (default 10): mostra todo mundo, sem sufixo de corte
texto_abaixo = format_escalonamento_experimental(TRES)
checar("7a. abaixo do teto cita os 3 leads", True,
       all(f"Lead {n}" in texto_abaixo for n in (1, 2, 3)))
checar("7b. abaixo do teto nao tem sufixo de corte", False,
       "e mais" in texto_abaixo)

# 8. acima do teto (12 linhas, teto explicito 10 = default): mostra 10,
#    diz "e mais 2." com o numero CERTO, e os 2 que ficaram de fora nao
#    aparecem nominalmente.
texto_acima = format_escalonamento_experimental(DOZE)
checar("8a. acima do teto mostra os 10 primeiros", True,
       all(f"Lead {n}" in texto_acima for n in range(1, 11)))
checar("8b. acima do teto NAO cita quem ficou de fora", True,
       "Lead 11" not in texto_acima and "Lead 12" not in texto_acima)
checar("8c. acima do teto diz 'e mais 2.' (numero certo)", True,
       "e mais 2." in texto_acima)

# 9. teto explicito menor, pra nao depender do valor do env var/default
texto_teto2 = format_escalonamento_experimental(TRES, teto=2)
checar("9a. teto=2 com 3 linhas mostra so 2", True,
       "Lead 1" in texto_teto2 and "Lead 2" in texto_teto2 and "Lead 3" not in texto_teto2)
checar("9b. teto=2 com 3 linhas diz 'e mais 1.'", True, "e mais 1." in texto_teto2)

# 10. teto<=0 desliga o corte (mesma convencao de format_escalonamento(blocos=0))
texto_sem_teto = format_escalonamento_experimental(DOZE, teto=0)
checar("10a. teto=0 mostra as 12 linhas", True,
       all(f"Lead {n}" in texto_sem_teto for n in range(1, 13)))
checar("10b. teto=0 nao tem sufixo de corte", False, "e mais" in texto_sem_teto)


# ---------------------------------------------------------------------------
# Casos 11-12 — montar_mensagens_escalonamento: intocavel + anexado por ultimo
# ---------------------------------------------------------------------------

MENSAGENS_ALUNO = ["*Registro atrasado*\n_2 professores_"]

# 11. sem pendencia experimental: a fila do aluno sai IDENTICA (mesma lista,
#     mesmo conteudo) — nada que ja funciona muda de comportamento.
sem_exp = montar_mensagens_escalonamento(MENSAGENS_ALUNO, [])
checar("11. sem experimental, fila do aluno intocada", MENSAGENS_ALUNO, sem_exp)

# 12. com pendencia experimental: bloco entra como mensagem PROPRIA no fim,
#     sem alterar as mensagens do aluno que ja existiam.
com_exp = montar_mensagens_escalonamento(MENSAGENS_ALUNO, LINHAS)
checar("12a. com experimental, mensagens do aluno continuam as mesmas",
       MENSAGENS_ALUNO, com_exp[:-1])
checar("12b. com experimental, uma mensagem a mais no fim", len(MENSAGENS_ALUNO) + 1,
       len(com_exp))
checar("12c. a mensagem extra cita o lead", True, "Davi Nakashima" in com_exp[-1])


# ---------------------------------------------------------------------------
# Casos 13-14 — linhas_experimental_escalonadas: isolamento de falha
# ---------------------------------------------------------------------------

with patch.object(worker, "rpc", return_value={"ok": True, "linhas": LINHAS}):
    linhas_ok = linhas_experimental_escalonadas()
checar("13. sucesso repassa as linhas da RPC", LINHAS, linhas_ok)

logadas: list[dict] = []


def _fake_log(nome, **campos):
    logadas.append({"nome": nome, **campos})


def _rpc_explode(name, body):
    raise RuntimeError("uazapi 502: bad gateway")


with patch.object(worker, "rpc", side_effect=_rpc_explode), \
     patch.object(worker, "log", side_effect=_fake_log):
    linhas_falha = linhas_experimental_escalonadas()
checar("14a. falha na RPC devolve lista vazia (nao propaga)", [], linhas_falha)
checar("14b. a falha chega ao journal", True,
       any("falhou" in l["nome"] and "502" in str(l.get("error", "")) for l in logadas))


print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
