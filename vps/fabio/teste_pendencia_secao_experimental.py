#!/usr/bin/env python3
"""Teste da secao carimbada da experimental dentro da cobranca de pendencias.

POR QUE ELE EXISTE. O Alf pediu UMA mensagem com lead e aluno SEPARADOS —
"pra nao misturar". Duas mensagens no mesmo horario viram ruido e ele ignora
as duas; misturar sem carimbo apaga a diferenca entre lead e aluno, que e
exatamente o que ele nao quer.

Rodar:  python3 teste_pendencia_secao_experimental.py
"""
from __future__ import annotations

import os
import sys
from unittest.mock import patch

# O corpo das mensagens carrega emoji (🎓). Sem isto, um console que não fala
# UTF-8 (cp1252 do Windows, por exemplo) morre com UnicodeEncodeError no meio
# do print das FALHAS — o exit code continua != 0, mas quem revisa perde a
# lista de falhas bem na hora que mais precisa dela.
sys.stdout.reconfigure(errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fabio_notification_worker as worker  # noqa: E402
from fabio_notification_worker import format_secao_experimental  # noqa: E402

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


LINHAS = [{"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
           "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
           "quando": "21/08 18:00", "dias_em_atraso": 1}]

texto = format_secao_experimental(LINHAS)

checar("1. tem cabecalho proprio de experimental", True, "Experimentais" in texto)
checar("2. cita o lead pelo nome", True, "Davi" in texto)
checar("3. diz que o comercial espera (a urgencia e comercial)", True,
       "comercial" in texto.lower())

# NEGATIVO: sem pendencia a secao NAO existe — secao vazia polui a mensagem
# do professor que esta em dia e ensina a ignorar o resto.
checar("4. lista vazia devolve None", None, format_secao_experimental([]))
checar("4b. None devolve None", None, format_secao_experimental(None))

# NEGATIVO: a secao NAO pode falar de aula de aluno — e o "nao misturar"
checar("5. nao usa a palavra 'aluno' no cabecalho", False,
       "aluno" in texto.split("\n")[0].lower())


# ---------------------------------------------------------------------------
# format_pendencias — o ponto de USO. Confirmar que a constante existe não
# prova nada (ver mutante-vivo-e-trava-sem-teste na memória); o que importa é
# exercitar a função que decide se a mensagem sai ou não.
#
# format_pendencias busca a experimental chamando `rpc(...)` ela mesma, então
# os testes substituem `worker.rpc` — o mesmo padrão de
# teste_experimental_lembrete.py.
# ---------------------------------------------------------------------------

PROF = {"id": 42, "nome": "Ana Beatriz", "telefone_whatsapp": "5521999999999"}


def fake_rpc_com_experimental(name, body):
    assert name == "fn_experimental_pendencia_do_professor"
    assert body == {"p_professor_id": 42}, "professor_id errado (prof['id'], nao prof['professor_id']!)"
    return {"ok": True, "linhas": [
        {"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
         "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
         "quando": "21/08 18:00", "dias_em_atraso": 1}
    ]}


def fake_rpc_sem_experimental(name, body):
    assert name == "fn_experimental_pendencia_do_professor"
    return {"ok": True, "linhas": []}


# CASO PRINCIPAL: professor com ZERO aulas de aluno e UMA experimental
# pendente — o mais comum hoje (2 pendencias, nenhuma de aluno). Do jeito
# que a funcao nasceu, `if total_aulas <= 0: return None` matava a mensagem
# antes de a secao nova ser considerada.
with patch.object(worker, "rpc", side_effect=fake_rpc_com_experimental):
    msg_so_experimental = worker.format_pendencias(PROF, {"total_aulas": 0})
checar("6. so experimental pendente ainda assim manda mensagem", True,
       msg_so_experimental is not None)
checar("6b. mensagem so-experimental cita o lead", True,
       msg_so_experimental is not None and "Davi" in msg_so_experimental)

# NEGATIVO: zero aulas e zero experimental — ninguem deve ser cobrado.
with patch.object(worker, "rpc", side_effect=fake_rpc_sem_experimental):
    msg_nada = worker.format_pendencias(PROF, {"total_aulas": 0})
checar("7. sem aula e sem experimental devolve None", None, msg_nada)

# A REGUA DE ALUNO NAO PODE MUDAR: professor com aula de aluno pendente e
# SEM experimental tem que receber exatamente a mensagem de antes — sem a
# secao nova aparecendo vazia ou com ruido.
DATA_COM_AULA = {
    "total_aulas": 1,
    "aulas": [{"data": "2026-08-21", "hora": "14:00", "curso": "Violão",
               "alunos": [{"primeiro_nome": "Rafael", "nome": "Rafael Souza"}],
               "dias_em_atraso": 1}],
}
with patch.object(worker, "rpc", side_effect=fake_rpc_sem_experimental):
    msg_so_aluno = worker.format_pendencias(PROF, DATA_COM_AULA)
checar("8. aula de aluno sem experimental nao ganha secao", False,
       msg_so_aluno is not None and "Experimentais" in msg_so_aluno)
checar("8b. aula de aluno sem experimental continua mandando a mensagem", True,
       msg_so_aluno is not None and "Ana" in msg_so_aluno)

# Os dois juntos: aula de aluno pendente E experimental pendente — a mensagem
# tem as duas secoes, sem misturar uma na outra.
with patch.object(worker, "rpc", side_effect=fake_rpc_com_experimental):
    msg_os_dois = worker.format_pendencias(PROF, DATA_COM_AULA)
checar("9. aula + experimental: as duas secoes aparecem", True,
       msg_os_dois is not None and "Rafael" in msg_os_dois and "Davi" in msg_os_dois)

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
