"""Teste do escalonamento das 9h depois que ele deixou de ser uma parede.

O caso real: em 09/08/2026 a mensagem única do grupo da coordenação tinha
**36 professores, 20.951 caracteres e 1.032 linhas**. Ela é entregue todo dia
às 12:00 UTC (9h BRT) e ninguém lê — governança que ninguém lê não é
governança, é log.

O que este teste guarda são as três coisas que podiam quebrar ao dividir:

1. **Ninguém some.** Racionar detalhe é aceitável; sumir da lista não é. Corte
   silencioso lê como "acabou" e é pior que a parede.
2. **Um número só.** 13 dos 36 professores dão aula em mais de uma unidade.
   Contar "professores que têm aula na unidade" dá 50 pra 36 pessoas. O índice
   e as mensagens têm que sair do MESMO agrupamento — é o defeito que a
   migration 080 consertou na tela do semáforo, e ele cabia inteiro aqui.
3. **O bloco continua encaminhável.** Formato A, escolhido pelo Alf: a
   coordenação copia o bloco de um professor e manda pra ele. Se o bloco
   perder hora, curso ou o nome completo do aluno, a mensagem vira aviso e
   deixa de ser trabalho feito.

Rodar: python teste_escalonamento_por_unidade.py
"""
import os
import sys

os.environ.setdefault("SUPABASE_URL", "https://exemplo.invalid")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "fake")
os.environ.setdefault("UAZAPI_URL", "https://exemplo.invalid")
os.environ.setdefault("UAZAPI_TOKEN", "fake")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fabio_notification_worker as W  # noqa: E402

falhas = []


def checar(nome, esperado, obtido):
    if esperado != obtido:
        falhas.append(f"{nome}: esperado {esperado!r}, obtido {obtido!r}")


def prof(pid, nome, aulas_por_unidade, total=None, pior=3):
    """Uma linha do `fn_pendencias_escalonadas`, no shape real.

    Shape conferido na VPS em 09/08/2026: a linha tem
    professor_id/professor_nome/unidades/aulas/total_aulas/pior_atraso, e cada
    aula tem aula_id/data_aula/hora/curso/unidade/alunos/dias. `total_aulas`
    pode ser MAIOR que len(aulas): a RPC corta em p_max_aulas (12).
    """
    aulas = []
    for u, n in aulas_por_unidade.items():
        for i in range(n):
            aulas.append({
                "aula_id": pid * 100 + len(aulas),
                "data_aula": f"2026-08-0{3 + (i % 5)}",
                "hora": f"{9 + (i % 10):02d}:00",
                "curso": "Canto",
                "unidade": u,
                "alunos": [f"Aluno {pid}-{i} Sobrenome"],
                "dias": 4,
            })
    return {
        "professor_id": pid,
        "professor_nome": nome,
        "unidades": sorted(aulas_por_unidade.keys()),
        "aulas": aulas,
        "total_aulas": len(aulas) if total is None else total,
        "pior_atraso": pior,
    }


# ===== fixture: 11 professores em 3 unidades, com os dois casos chatos ======
# - "Lohana" dá aula nas três unidades E tem total_aulas > len(aulas) (o corte
#   da RPC). É a linha que prova por que o professor vai INTEIRO pra uma
#   unidade: fatiar as aulas dele deixaria o "+N aulas" sem dono.
# - "Bruno" empata 2×2 entre duas unidades — o desempate tem que ser estável.
LINHAS = [
    prof(20, "Lohana Leopoldo", {"Campo Grande": 5, "Recreio": 2, "Barra": 1},
         total=19, pior=9),
    prof(32, "Rafael Dias", {"Recreio": 9}, total=14, pior=10),
    prof(19, "Leonardo Muniz", {"Barra": 8}, pior=7),
    prof(3, "Daiana Alves", {"Campo Grande": 7}, pior=6),
    prof(41, "Bruno Sales", {"Barra": 2, "Recreio": 2}, pior=5),
    prof(42, "Carla Nunes", {"Campo Grande": 5}, pior=5),
    prof(43, "Diego Prado", {"Campo Grande": 4}, pior=4),
    prof(44, "Elisa Rocha", {"Campo Grande": 3}, pior=4),
    prof(45, "Fábio Lopes", {"Campo Grande": 2}, pior=3),
    prof(46, "Gisele Amaro", {"Campo Grande": 1}, pior=3),
    prof(47, "Hugo Serra", {"Recreio": 1}, pior=1),
]

# A divisão só entra quando há parede: com a lista curta, uma mensagem basta.
# A fixture de 11 professores passa do limite de propósito — é o caso "parede".
W.ESCALONAMENTO_MENSAGEM_UNICA_MAX = 1500

msgs = W.montar_escalonamento(LINHAS)
juntas = "\n".join(msgs)

# ===== 1. a fila tem capa e um corpo por unidade =====
checar("1a. índice + 3 unidades = 4 mensagens", 4, len(msgs))
checar("1b. a primeira é o índice (não tem unidade no título)", True,
       msgs[0].startswith("*Registro atrasado*"))
checar("1c. as outras três se anunciam pela unidade", True,
       all(m.startswith("*Registro atrasado · ") for m in msgs[1:]))

# ===== 2. NINGUÉM SOME =====
# Racionar detalhe, sim. Sumir da lista, não: quem lê tomaria a lista curta
# por completa e o professor cortado nunca seria cobrado.
for linha in LINHAS:
    checar(f"2. '{linha['professor_nome']}' continua na lista", True,
           linha["professor_nome"] in juntas)

# ===== 3. UM NÚMERO SÓ: o índice promete o que as mensagens entregam ========
# Lohana dá aula nas 3 unidades. Se o índice contasse "quem tem aula aqui",
# ela entraria 3 vezes e a soma daria 13 pra 11 professores.
import re  # noqa: E402

linha_unidades = msgs[0].split("\n")[3]
por_unidade_indice = dict(
    (m.group(1).strip(), int(m.group(2)))
    for m in re.finditer(r"([^·]+?)\s(\d+)(?:\s·|$)", linha_unidades))
checar("3a. a soma do índice é o total de professores", len(LINHAS),
       sum(por_unidade_indice.values()))
for corpo in msgs[1:]:
    unidade = corpo.split("\n")[0].split("·")[1].strip().rstrip("*")
    quantos = int(re.search(r"_(\d+) professor", corpo).group(1))
    checar(f"3b. índice e mensagem de {unidade} contam o mesmo",
           por_unidade_indice.get(unidade), quantos)

# ===== 4. o professor vai INTEIRO pra uma unidade só =====
aparicoes = sum(1 for m in msgs[1:] if "Lohana Leopoldo" in m)
checar("4a. quem dá aula em 3 unidades aparece em UMA mensagem", 1, aparicoes)
# 5 aulas em Campo Grande contra 2 e 1: é lá que ela é cobrada.
checar("4b. e vai pra unidade onde tem mais aula parada", True,
       any(m.startswith("*Registro atrasado · Campo Grande*")
           and "Lohana Leopoldo" in m for m in msgs[1:]))
# O cabeçalho tem que denunciar as outras unidades, senão quem encaminha
# manda achando que é só da casa dele.
checar("4c. o cabeçalho dela lista as três unidades", True,
       "*Lohana Leopoldo* · Barra, Campo Grande, Recreio" in juntas)

# ===== 5. o corte da RPC não vira mentira =====
# total_aulas 19, aulas mostradas 8 -> tem que sobrar rodapé de 11.
checar("5. o '+N aulas atrasadas' sobrevive à divisão", True,
       "_+11 aulas atrasadas deste professor_" in juntas)

# ===== 6. o racionamento por gravidade =====
cg = next(m for m in msgs if m.startswith("*Registro atrasado · Campo Grande*"))
checar("6a. Campo Grande tem 7 professores", 7,
       int(re.search(r"_(\d+) professor", cg).group(1)))
# blocos=8 por padrão e CG tem 7: ninguém cai no rodapé aqui.
checar("6b. com 7 <= 8, nenhum vira linha de rodapé", False,
       "*Também atrasados*" in cg)

curto = W.format_escalonamento([l for l in LINHAS], unidade="Teste", blocos=3)
checar("6c. com blocos=3, os 8 restantes viram rodapé", True,
       "*Também atrasados*" in curto)
checar("6d. e o rodapé traz nome, aulas e dias (não só o nome)", True,
       "· Hugo Serra — 1 aula, 1 dia" in curto)
rodape = [l for l in curto.split("\n") if l.startswith("· ") and " — " in l]
checar("6e. o menos grave fecha o rodapé", "· Hugo Serra — 1 aula, 1 dia",
       rodape[-1] if rodape else None)
# 19 aulas > 14 aulas: ordena por aula parada, não por pior_atraso (Rafael tem
# 10 dias contra 9 dela). Trocar os dois critérios passa despercebido sem isto.
checar("6f. ordena por aula parada, não por dias de atraso", True,
       curto.index("Lohana Leopoldo") < curto.index("Rafael Dias"))
# Racionar detalhe é uma coisa; sumir é outra. Este é o passo que separa as
# duas — sem ele, "cortar os 8 restantes" passaria verde.
for linha in LINHAS:
    checar(f"6g. racionado, '{linha['professor_nome']}' continua na lista", True,
           linha["professor_nome"] in curto)

# ===== 7. o bloco continua ENCAMINHÁVEL (formato A) =====
checar("7a. o bloco leva a hora em negrito", True, "*09:00*" in juntas)
checar("7b. e o nome COMPLETO do aluno em itálico", True,
       "_Aluno 3-0 Sobrenome_" in juntas)
checar("7c. e o dia por extenso", True, "segunda, 03/08" in juntas)
checar("7d. o rodapé de cada unidade explica o que fazer", True,
       all("Segue pra encaminhar" in m for m in msgs[1:]))

# ===== 8. a parede sumiu de verdade (o motivo de tudo isto) ================
antiga = W.format_escalonamento(LINHAS, blocos=0)
checar("8a. a maior mensagem nova é bem menor que a antiga", True,
       max(len(m) for m in msgs) < len(antiga) * 0.7)
checar("8b. e nenhuma passa de 4.096 caracteres", True,
       all(len(m) <= 4096 for m in msgs))

# ===== 9. casos de borda =====
checar("9a. sem pendência, nenhuma mensagem", [], W.montar_escalonamento([]))
# Força o caso "parede" (max=0) pra exercitar a divisão: com UMA unidade, a
# capa não entra — ela existe pra dar rumo a uma fila, e fila de um item não
# precisa de capa. Sem o max=0 a lista caberia numa mensagem e este passo
# estaria medindo a regra do passo 11, não esta.
W.ESCALONAMENTO_MENSAGEM_UNICA_MAX = 0
so_uma = [l for l in LINHAS if l["professor_id"] in (42, 43)]
uma = W.montar_escalonamento(so_uma)
checar("9b. com uma unidade só, não entra capa", 1, len(uma))
checar("9c. e essa mensagem é a da unidade", True,
       uma[0].startswith("*Registro atrasado · Campo Grande*"))
W.ESCALONAMENTO_MENSAGEM_UNICA_MAX = 1500
checar("9d. desempate 2×2 é estável (mesma entrada, mesma saída)",
       W._unidade_de_cobranca(LINHAS[4]), W._unidade_de_cobranca(LINHAS[4]))

# ===== 10. A COORTE: só escala quem o Fábio já cobra no particular ==========
# Em 10/08/2026 a coordenação recebeu 36 professores num sistema que ela ainda
# não conhece — sendo que a cobrança individual só ia pra 6. O escalonamento
# não aplicava o mesmo recorte que o `active_professors` já aplicava.
coorte = {20, 32, 3}
dentro = W.filtrar_coorte(LINHAS, coorte)
checar("10a. sobra só quem está no app", 3, len(dentro))
checar("10b. e são exatamente os do app", {20, 32, 3},
       {l["professor_id"] for l in dentro})
checar("10c. quem não entrou no app não é denunciado", False,
       any(l["professor_id"] == 19 for l in dentro))
# Coorte vazia (ninguém liberado) tem que dar lista vazia, não lista cheia —
# um `if not ids: return linhas` de "conveniência" mandaria a escola inteira.
checar("10d. coorte vazia não libera a escola inteira", [],
       W.filtrar_coorte(LINHAS, set()))
# E o resto do pipeline continua funcionando com a lista recortada.
checar("10e. a fila da coorte ainda monta mensagem", True,
       len(W.montar_escalonamento(dentro)) >= 1)

# ===== 11. Dividir é remédio de parede, não cerimônia =====
# Com a coorte, o escalonamento real caiu de 36 professores pra 5 (2.058
# chars). Mandar índice + 3 unidades pra uma lista que cabe numa tela é pedir
# quatro notificações onde bastava uma.
W.ESCALONAMENTO_MENSAGEM_UNICA_MAX = 8000   # a fixture inteira agora cabe
uma_so = W.montar_escalonamento(LINHAS)
checar("11a. lista que cabe vai numa mensagem só", 1, len(uma_so))
checar("11b. e ela leva todo mundo", True,
       all(l["professor_nome"] in uma_so[0] for l in LINHAS))
checar("11c. sem título de unidade, porque não foi dividida", False,
       uma_so[0].startswith("*Registro atrasado · "))
W.ESCALONAMENTO_MENSAGEM_UNICA_MAX = 1500   # volta pro caso "parede"


# ===== resultado =====
if falhas:
    print(f"FALHOU ({len(falhas)}):")
    for f in falhas:
        print(f"  - {f}")
    raise SystemExit(1)
print(f"OK: {len(msgs)} mensagens, a maior com "
      f"{max(len(m) for m in msgs)} chars (a parede tinha {len(antiga)}).")
