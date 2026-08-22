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
    # N2: o id errado nao vira AssertionError (fixture opinando), vira dado —
    # o professor_id trocado passa a nao achar nada, e quem mata o mutante M4
    # e um checar() de verdade, nao um assert de teste que some sob -OO.
    if body != {"p_professor_id": 42}:
        return {"ok": True, "linhas": []}
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


# ---------------------------------------------------------------------------
# I2 (revisao): "parecida" nao e "identica". Um mutante que tira o
# `lines.append("")` de dentro da guarda `if secao_exp:` (passando a inserir
# uma linha em branco a mais em TODA mensagem, inclusive de quem nao tem
# experimental) sai 15/15 nos casos 1-9 porque nenhum deles compara a string
# inteira — so trechos. Aqui a comparacao e byte a byte contra a mensagem de
# aluno-so (sem experimental), a mesma que a Task 4 promete nao mudar.
# ---------------------------------------------------------------------------

MSG_ALUNO_SO_ESPERADO = (
    "*Ana, ficou 1 aula de ontem sem registro.*\n"
    "\n"
    "sexta, 21/08\n"
    "*14:00*  Violão · Rafael\n"
    "\n"
    f"{worker.FECHO_ABRIR_APP}"
)

checar("8c. mensagem aluno-so e IDENTICA byte a byte (nao so 'parecida')",
       MSG_ALUNO_SO_ESPERADO, msg_so_aluno)


# ---------------------------------------------------------------------------
# Ruling 16 (Alf): a secao experimental respeita o MESMO corte de
# ESCALONAMENTO_DIAS que a regua do aluno ja usa — quem passou da janela e
# problema da coordenacao (Task 5), cobrar aqui tambem seria a cobranca em
# dobro que o comentario do filtro de aulas ja existe pra evitar.
# ---------------------------------------------------------------------------

DENTRO_DA_JANELA = worker.ESCALONAMENTO_DIAS       # limite inclusivo: <= ainda cobra
FORA_DA_JANELA = worker.ESCALONAMENTO_DIAS + 1     # passou: escalonou, nao cobra mais aqui


def fake_rpc_janela_mista(name, body):
    assert name == "fn_experimental_pendencia_do_professor"
    return {"ok": True, "linhas": [
        {"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
         "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
         "quando": "21/08 18:00", "dias_em_atraso": DENTRO_DA_JANELA},
        {"vinculo_id": 2280, "nome_aluno": "Raquel Prado",
         "curso_nome": "Aula Experimental", "unidade_nome": "Tijuca",
         "quando": "18/08 19:00", "dias_em_atraso": FORA_DA_JANELA},
    ]}


def fake_rpc_so_fora_da_janela(name, body):
    assert name == "fn_experimental_pendencia_do_professor"
    return {"ok": True, "linhas": [
        {"vinculo_id": 2280, "nome_aluno": "Raquel Prado",
         "curso_nome": "Aula Experimental", "unidade_nome": "Tijuca",
         "quando": "18/08 19:00", "dias_em_atraso": FORA_DA_JANELA},
    ]}


with patch.object(worker, "rpc", side_effect=fake_rpc_janela_mista):
    msg_janela_mista = worker.format_pendencias(PROF, {"total_aulas": 0})
checar("11. lead DENTRO da janela aparece", True,
       msg_janela_mista is not None and "Davi" in msg_janela_mista)
checar("11b. lead FORA da janela (ja escalonado) NAO aparece", False,
       msg_janela_mista is not None and "Raquel" in msg_janela_mista)

# NEGATIVO: so tem lead fora da janela e nenhuma aula — ninguem sobra pra
# cobrar, e a mensagem inteira tem que sumir (nao so a secao).
with patch.object(worker, "rpc", side_effect=fake_rpc_so_fora_da_janela):
    msg_so_fora = worker.format_pendencias(PROF, {"total_aulas": 0})
checar("12. so lead escalonado e zero aulas: mensagem inteira e None", None,
       msg_so_fora)


# ---------------------------------------------------------------------------
# Ruling 15 (Alf): a busca da experimental nao pode DERRUBAR a cobranca do
# aluno (que ja funciona ha muito tempo) nem falhar CALADA (o mesmo defeito
# que esta entrega inteira existe pra consertar). As duas metades juntas:
# degradar SEM a secao experimental, e registrar a falha em log alto que
# chega ao journal — nunca um `pass` mudo. A Task 3 ja levou essa mordida
# uma vez (journal dizendo status=ok com 100% dos alvos falhando porque o
# erro era montado e descartado); aqui o log e chamado direto de dentro da
# funcao, mesmo padrao ja usado em devolutiva_carimbo_falhou/
# sem_roster_retomada_falhou.
# ---------------------------------------------------------------------------

def fake_rpc_explode(name, body):
    assert name == "fn_experimental_pendencia_do_professor"
    raise RuntimeError("rpc fn_experimental_pendencia_do_professor 502: bad gateway")


log_chamadas: list[tuple] = []


def fake_log(msg, **fields):
    log_chamadas.append((msg, fields))


with patch.object(worker, "rpc", side_effect=fake_rpc_explode), \
     patch.object(worker, "log", side_effect=fake_log):
    msg_rpc_explodiu = worker.format_pendencias(PROF, DATA_COM_AULA)

checar("10. RPC da experimental explode: aluno AINDA recebe a cobranca", True,
       msg_rpc_explodiu is not None and "Rafael" in msg_rpc_explodiu)
checar("10b. sem secao experimental quando a busca falhou", False,
       msg_rpc_explodiu is not None and "Experimentais" in msg_rpc_explodiu)
checar("10c. a falha chega ao journal (log chamado com o erro)", True,
       any("falhou" in m.lower() and "error" in f and "502" in str(f.get("error"))
           for m, f in log_chamadas))

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
