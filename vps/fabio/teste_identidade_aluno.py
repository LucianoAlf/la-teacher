"""Teste do conserto: "quem e esse aluno?" precisa acionar o prontuario
e o bloco `cadastro` da migration 026 precisa chegar no prompt.

Caso real: 04/08/2026 13:21, Matheus perguntou "quem e a aluna fernanda?
eu nao faco ideia de que seja" e o Fabio respondeu que nao sabia dizer se ela
era nova. Nos logs: tool_turns=1, so skill_view -- o prontuario nunca foi
consultado.

Rodar: python teste_identidade_aluno.py
"""
import os
import sys

os.environ.setdefault("SUPABASE_URL", "https://exemplo.invalid")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "fake")
os.environ.setdefault("UAZAPI_URL", "https://exemplo.invalid")
os.environ.setdefault("UAZAPI_TOKEN", "fake")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "..", "..", "d", "la-teacher", "vps", "fabio"))
sys.path.insert(0, r"D:\la-teacher\vps\fabio")

import fabio_chat_bridge as B  # noqa: E402

falhas = []


def checar(nome, esperado, obtido):
    if esperado != obtido:
        falhas.append(f"{nome}: esperado {esperado!r}, obtido {obtido!r}")


# ===== 1. o caso real =====
MSG_REAL = "fala irmao .. e ai, tu consegue me ajudar num lance? quem e a aluna fernanda? eu nao faco ideia de que seja"
checar("1. a pergunta real do Matheus aciona identidade", True,
       B._has_student_identity_intent(MSG_REAL, []))
checar("2. e NAO aciona historico (por isso nada rodava)", False,
       B._has_pedagogical_history_intent(MSG_REAL, []))

# ===== 2. variantes que devem acionar =====
for frase in [
    "quem e a Fernanda?",
    "quem sao esses alunos novos?",
    "nao conheco essa aluna",
    "me fala da Julia antes da aula",
    "essa e aluna nova?",
    "ela e nova na escola?",
    "hoje e a primeira aula dela",
    "nunca vi esse nome",
]:
    if not B._has_student_identity_intent(frase, []):
        falhas.append(f"3. deveria acionar e nao acionou: {frase!r}")

# ===== 3. o gatilho nao pode ser guloso =====
# Regex com \b em vez de substring: "quem e" solto casaria em "quem escreveu".
for frase in [
    "quem escreveu essa musica?",
    "quem estava na aula ontem nao lembro",
    "bom dia Fabio, tudo certo?",
    "consegue gerar o backing track?",
    "vou registrar a aula agora",
]:
    if B._has_student_identity_intent(frase, []):
        falhas.append(f"4. NAO deveria acionar e acionou: {frase!r}")

# ===== 4. historico continua funcionando =====
checar("5. pergunta de historico segue acionando", True,
       B._has_pedagogical_history_intent("o que ela trabalhou na ultima aula?", []))

# ===== 5. _latest_registered_content agora recebe o dict =====
PRONTUARIO = {
    "cadastro": {
        "nome": "Fernanda Goncalves Freire", "curso": "Canto", "idade": 17,
        "e_aluno_novo": True, "data_matricula": "2026-08-03",
        "dias_desde_matricula": 1, "aulas_registradas": 0,
    },
    "linha_do_tempo": [
        {"data": "2026-07-14", "curso": "Canto", "texto": "trabalhou afinacao",
         "origem": "app", "presenca": "presente", "professor": "Matheus", "nr_da_aula": 3},
    ],
}
achado = B._latest_registered_content(PRONTUARIO, "Canto T")
checar("6. le a linha do tempo do dict recebido", "trabalhou afinacao",
       (achado or {}).get("texto"))
checar("7. linha do tempo vazia devolve None", None,
       B._latest_registered_content({"linha_do_tempo": []}, "Canto"))
checar("8. prontuario sem a chave nao explode", None,
       B._latest_registered_content({}, "Canto"))

# ===== 6. o fluxo inteiro: cadastro tem que chegar no contexto =====
B._resolve_student_course_from_chat = lambda p, t, h: {
    "aluno_id": 1897, "aluno_nome": "Fernanda Goncalves Freire", "curso_nome": "Canto",
}
B._fetch_prontuario = lambda p, a, limite=30: PRONTUARIO
B._latest_chronological_class = lambda p, a, c: None

ctx = B.pedagogical_prefetch(25, MSG_REAL, [])
checar("9. o prefetch roda para 'quem e'", "identidade_aluno", (ctx or {}).get("intent"))
checar("10. e leva o bloco cadastro", True, bool((ctx or {}).get("cadastro")))
checar("11. dizendo que ela e nova", True, (ctx or {}).get("cadastro", {}).get("e_aluno_novo"))
checar("12. e ha quantos dias", 1, (ctx or {}).get("cadastro", {}).get("dias_desde_matricula"))

# o cadastro tambem vai quando a pergunta e de historico
ctx2 = B.pedagogical_prefetch(25, "o que ela trabalhou na ultima aula?", [])
checar("13. historico tambem recebe cadastro", True, bool((ctx2 or {}).get("cadastro")))
checar("14. com o intent de historico", "historico_pedagogico", (ctx2 or {}).get("intent"))

# ===== 7. conversa comum nao pode acionar prefetch =====
checar("15. conversa comum nao aciona nada", None,
       B.pedagogical_prefetch(25, "bom dia Fabio, tudo certo?", []))

# ===== 8. o texto compactado que vai pro prompt precisa conter o cadastro =====
compacto = B.compact_pedagogical_context(ctx)
checar("16. o cadastro sobrevive a compactacao", True, "e_aluno_novo" in compacto)

if falhas:
    print(f"FALHOU ({len(falhas)}):")
    for f in falhas:
        print("  -", f)
    sys.exit(1)
print("OK - 16 verificacoes passaram")
