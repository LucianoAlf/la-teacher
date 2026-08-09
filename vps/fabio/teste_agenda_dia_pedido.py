"""Teste do conserto: o fast_path da agenda tem que responder o DIA PEDIDO.

Caso real: 09/08/2026 23:29 UTC, Matheus perguntou "como esta minha agenda de
amanha?" e o Fabio respondeu, pelo atalho, "nao encontrei aulas na sua agenda
de hoje". Era domingo (0 aulas); na segunda ele tinha 5. O professor que se
planeja com isso chega achando que nao tem aula.

A causa: `asks_today` aceitava "minhas aulas"/"minha agenda" -- frases que NAO
falam de dia nenhum -- como prova de que a pergunta era sobre hoje. Nao existia
extracao de dia. Qualquer dia pedido (amanha, segunda, dia 12) era respondido
com a agenda de hoje, e ainda por cima rotulado "de hoje".

Regra que fica: ou o atalho responde o dia pedido, ou ele nao responde. Chutar
hoje e pior do que demorar, porque "nao encontrei aulas" e uma negativa
afirmada -- o pior formato pra estar errado.

Rodar: python teste_agenda_dia_pedido.py
"""
import os
import sys

os.environ.setdefault("SUPABASE_URL", "https://exemplo.invalid")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "fake")
os.environ.setdefault("UAZAPI_URL", "https://exemplo.invalid")
os.environ.setdefault("UAZAPI_TOKEN", "fake")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fabio_chat_bridge as B  # noqa: E402

falhas = []


def checar(nome, esperado, obtido):
    if esperado != obtido:
        falhas.append(f"{nome}: esperado {esperado!r}, obtido {obtido!r}")


# ===== harness: hoje congelado em 09/08/2026 (domingo), igual ao caso real ====
HOJE = "2026-08-09"
B.today_brt = lambda: HOJE

# Agenda real do professor 25 (Matheus), medida na VPS em 09/08/2026.
AGENDA = {
    "2026-08-09": [],  # domingo: vazio -- foi essa a resposta errada
    "2026-08-10": [    # segunda: 5 aulas
        {"hora": "11:00", "curso": "Canto", "alunos": ["Valentina Mendes Rodrigues Aleixo"]},
        {"hora": "15:00", "curso": "Canto", "alunos": ["Amanda Ozório de Barros"]},
        {"hora": "16:00", "curso": "Canto", "alunos": ["Luiz Henrique Ribeiro Gomes"]},
        {"hora": "17:00", "curso": "Musicalização Preparatória",
         "alunos": ["Gustavo Morley Grieco", "Maria Isabel Madureira Gouvêa"]},
        {"hora": "18:00", "curso": "Musicalização Preparatória",
         "alunos": ["Arthur de Carvalho Rodrigues Frota Almeida"]},
    ],
    "2026-08-12": [
        {"hora": "09:00", "curso": "Violão", "alunos": ["Pedro Teste"]},
    ],
}


def fake_professor_context(professor_id, data=None):
    dia = data or B.today_brt()
    aulas = AGENDA.get(dia, [])
    return {
        "ok": True,
        "primeiro_nome": "Matheus",
        "nome": "Matheus Felipe",
        "hoje": {"data": dia, "aulas": aulas, "total_aulas": len(aulas)},
    }


B.professor_context = fake_professor_context
B.recent_history_for_row = lambda row, limit=10: []


def perguntar(texto):
    return B.try_fast_response({
        "identidade_tipo": "professor",
        "professor_id": 25,
        "channel": "whatsapp",
        "content": texto,
    })


# ===== 1. O CASO REAL: a pergunta que quebrou =====
r = perguntar("como esta minha agenda de amanha?")
checar("1a. amanha nao pode cair no vazio de hoje", False,
       r is not None and "nao encontrei" in B._norm_text(r))
checar("1b. amanha tem que trazer as 5 aulas da segunda", True,
       r is not None and "11:00" in r and "18:00" in r)
checar("1c. amanha nao pode ser rotulado 'de hoje'", False,
       r is not None and "de hoje" in B._norm_text(r))
checar("1d. a resposta tem que dizer amanha", True,
       r is not None and "amanh" in B._norm_text(r))
checar("1e. os alunos da segunda tem que aparecer", True,
       r is not None and "Valentina Mendes Rodrigues Aleixo" in r)

# ===== 2. hoje continua funcionando (nao quebrar o que estava certo) =====
r = perguntar("minha agenda de hoje")
checar("2a. hoje vazio responde a negativa de HOJE", True,
       r is not None and "de hoje" in B._norm_text(r) and "nao encontrei" in B._norm_text(r))

r = perguntar("quais minhas aulas")  # sem marcador de dia -> hoje, como antes
checar("2b. sem dito nenhum, o padrao segue sendo hoje", True,
       r is not None and "de hoje" in B._norm_text(r))

# ===== 3. dia que o atalho NAO sabe resolver: cair fora, nunca chutar hoje ====
for frase, motivo in [
    ("minha agenda da semana", "periodo, nao e um dia"),
    ("minha agenda do mes", "periodo, nao e um dia"),
    ("quantas aulas eu tenho por semana", "periodo, nao e um dia"),
    ("minha agenda de hoje e amanha", "dois dias -> ambiguo"),
    ("minhas aulas de domingo", "hoje E domingo -> hoje ou o proximo?"),
    ("minha agenda do dia 45", "dia inexistente"),
]:
    checar(f"3. '{frase}' ({motivo}) tem que cair pro Hermes", None, perguntar(frase))

# ===== 4. dias que ele SABE resolver =====
r = perguntar("minhas aulas de segunda")
checar("4a. segunda (10/08) traz as aulas da segunda", True,
       r is not None and "11:00" in r and "10/08" in r)

r = perguntar("como fica minha agenda do dia 12?")
checar("4b. 'dia 12' traz o dia 12", True,
       r is not None and "09:00" in r and "12/08" in r)

r = perguntar("minha agenda de depois de amanha")
checar("4c. depois de amanha (11/08) nao tem aula -- negativa do DIA CERTO", True,
       r is not None and "nao encontrei" in B._norm_text(r) and "depois de amanha" in B._norm_text(r))

r = perguntar("minha agenda de ontem")
checar("4d. ontem fala no passado, nao no presente", True,
       r is not None and "ontem" in B._norm_text(r))

# ===== 5. contagem: so conta o dia pedido =====
r = perguntar("quantos alunos eu tenho amanha?")
checar("5a. contagem de amanha conta os 6 atendimentos da segunda", True,
       r is not None and "6" in r and "amanh" in B._norm_text(r))
checar("5b. contagem de amanha nao pode dizer 'hoje'", False,
       r is not None and "hoje" in B._norm_text(r))

# "quantos alunos eu tenho" sem dia = carteira, NAO agenda de hoje.
checar("5c. 'quantos alunos eu tenho' (sem dia) fica com o Hermes", None,
       perguntar("quantos alunos eu tenho"))

# ===== 6. a trava de seguranca: se o banco devolver outro dia, nao responder ==
def contexto_teimoso(professor_id, data=None):
    """Simula RPC que ignora p_data e devolve hoje de qualquer jeito."""
    return {
        "ok": True, "primeiro_nome": "Matheus",
        "hoje": {"data": HOJE, "aulas": AGENDA[HOJE], "total_aulas": 0},
    }


B.professor_context = contexto_teimoso
checar("6. se o dado voltar de outro dia, o atalho se cala", None,
       perguntar("minha agenda de amanha"))
B.professor_context = fake_professor_context


# ===== resultado =====
if falhas:
    print(f"FALHOU ({len(falhas)}):")
    for f in falhas:
        print(f"  - {f}")
    raise SystemExit(1)
print("OK: o atalho da agenda respeita o dia pedido (ou se cala).")
