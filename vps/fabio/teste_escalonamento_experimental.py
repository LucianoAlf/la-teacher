#!/usr/bin/env python3
"""Teste do escalonamento da experimental para a coordenacao.

POR QUE ELE EXISTE. Escalonamento e a mensagem que chega em quem NAO deu a
aula. Se ela nao disser de quem e a aula, qual unidade, ha quanto tempo e
QUANDO ela aconteceu (com hora, nao so data), a coordenacao nao consegue
agir e a mensagem vira ruido — e ruido em canal de coordenacao mata a
credibilidade de todo o resto.

Ruling 18 (22/08/2026, revisao pos-Ruling-10): o teto corta DETALHE, nao
corta GENTE. fn_experimental_escalonadas() ordena por dias_em_atraso desc
e nunca tira um lead nao-confirmado da lista — sem rodape, os N primeiros
lugares ficariam PERMANENTEMENTE ocupados pelos leads mais velhos, e os que
acabaram de passar da janela (as experimentais "quentes") virariam so um
numero em "e mais X.", todo dia as 9h. Os casos 8-10 provam que ninguem
some, inclusive bem acima do teto.

Casos 12-19 cobrem o PONTO DE DESPACHO (rodar_escalonamento, extraida de
dentro de main() na revisao — I1): a fila do aluno nao pode mudar quando
nao ha experimental pendente, o bloco entra como mensagem PROPRIA no fim
da fila com evento proprio no journal (I4), --professor-id nao pode vazar
a experimental da escola inteira pro grupo (I5), e uma falha na busca ou
no envio nao pode apagar em silencio que a coordenacao ficou sem a lista.

O caso 20 e a guarda do FIO DE LIGACAO: le o codigo-fonte de main() e
confere que ele realmente chama rodar_escalonamento — e exatamente o
mutante que sobreviveu 22/22 na primeira rodada (apagar as duas linhas de
despacho dentro de main() nao quebrava nenhum teste, porque cada peca
isolada continuava certa sozinha).

Rodar:  python3 teste_escalonamento_experimental.py
"""
from __future__ import annotations

import inspect
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
    rodar_escalonamento,
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
# Caso 3b (minor) — a HORA do "quando" tambem tem que estar la, nao so a data.
# A coordenacao usa a hora pra achar a aula na agenda; um mutante que
# trunca "quando" pra so a data (l.get('quando')[:5]) passava no caso 3
# (que so olha "13/08") e sobrevivia.
# ---------------------------------------------------------------------------
checar("3b. cita a hora completa (quando), nao so a data", True, "13/08 18:00" in texto)


# ---------------------------------------------------------------------------
# Caso 7 — I2: "ha quanto tempo" e requisito declarado no docstring do
# proprio teste, mas nenhum caso cobria dias_em_atraso ate esta rodada. Um
# mutante que apaga o segmento inteiro sobrevivia 22/22.
# ---------------------------------------------------------------------------
checar("7a. cita ha quantos dias (dias_em_atraso)", True, "há 3 dia(s)" in texto)

LINHA_SEM_DIAS = [{"vinculo_id": 9999, "nome_aluno": "Sem Dias",
                   "unidade_nome": "CG", "professor_nome": "Fulano",
                   "quando": "01/01 10:00"}]  # sem 'dias_em_atraso' de proposito
texto_sem_dias = format_escalonamento_experimental(LINHA_SEM_DIAS)
checar("7b. chave ausente renderiza '?', nao 'None'", True, "há ? dia(s)" in texto_sem_dias)
checar("7c. chave ausente NUNCA renderiza a string None", False, "None" in texto_sem_dias)


# ---------------------------------------------------------------------------
# Casos 8-10 — Ruling 18: o teto corta DETALHE, nunca corta GENTE
# ---------------------------------------------------------------------------

def _linha(n: int, dias: int = 5) -> dict:
    return {"vinculo_id": 3000 + n, "nome_aluno": f"Lead {n}",
            "professor_nome": f"Prof {n}", "unidade_nome": "Barra",
            "curso_nome": "Aula Experimental", "quando": "10/08 10:00",
            "dias_em_atraso": dias}


TRES = [_linha(1), _linha(2), _linha(3)]
DOZE = [_linha(n) for n in range(1, 13)]
TRINTA = [_linha(n) for n in range(1, 31)]

# 8. abaixo do teto (default 10): todo mundo em detalhe completo, sem rodape.
texto_abaixo = format_escalonamento_experimental(TRES)
checar("8a. abaixo do teto cita os 3 leads em detalhe", True,
       all(f"Lead {n}" in texto_abaixo for n in (1, 2, 3)))
checar("8b. abaixo do teto nao tem rodape 'Tambem atrasados'", False,
       "Também atrasados" in texto_abaixo)

# 9. acima do teto (12 linhas, teto default = 10): os 10 primeiros em
#    detalhe completo (unidade/quando/professor); os 2 que passaram do teto
#    NAO desaparecem -- entram no rodape, so que so com nome + dias.
texto_acima = format_escalonamento_experimental(DOZE)
checar("9a. acima do teto mostra os 10 primeiros em detalhe", True,
       all(f"Lead {n}" in texto_acima for n in range(1, 11)))
checar("9b. acima do teto tem o rodape 'Tambem atrasados'", True,
       "Também atrasados" in texto_acima)
checar("9c. NINGUEM some: lead 11 e 12 aparecem (no rodape)", True,
       "Lead 11" in texto_acima and "Lead 12" in texto_acima)
# o rodape e so nome + dias -- sem unidade/professor -- entao a linha do
# lead 11 no rodape nao deve carregar "Barra"/"Prof" coladas ao nome dele
checar("9d. rodape cita os dias de quem sobrou", True,
       "Lead 11 — há 5 dia(s)" in texto_acima)

# 9e. bem ACIMA do teto (30 linhas): ninguem some, nem o ultimo da fila.
texto_trinta = format_escalonamento_experimental(TRINTA)
checar("9e. 30 leads, teto 10: os 30 nomes aparecem em algum lugar", True,
       all(f"Lead {n}" in texto_trinta for n in range(1, 31)))

# 10. teto explicito menor, pra nao depender do valor do env var/default
texto_teto2 = format_escalonamento_experimental(TRES, teto=2)
checar("10a. teto=2 com 3 linhas: 2 em detalhe, 1 no rodape (nao some)", True,
       "Lead 1" in texto_teto2 and "Lead 2" in texto_teto2 and "Lead 3" in texto_teto2)
checar("10b. teto=2 com 3 linhas: lead 3 esta no rodape, nao em detalhe", True,
       "Lead 3 — há 5 dia(s)" in texto_teto2)

# 10c. teto<=0 desliga o corte por completo (mesma convencao de
#      format_escalonamento(blocos=0)): tudo em detalhe, sem rodape.
texto_sem_teto = format_escalonamento_experimental(DOZE, teto=0)
checar("10c. teto=0 mostra as 12 em detalhe", True,
       all(f"Lead {n}" in texto_sem_teto for n in range(1, 13)))
checar("10d. teto=0 nao tem rodape (nada sobrou pra racionar)", False,
       "Também atrasados" in texto_sem_teto)


# ---------------------------------------------------------------------------
# Caso 11 — montar_mensagens_escalonamento: intocavel + anexado por ultimo
# ---------------------------------------------------------------------------

MENSAGENS_ALUNO = ["*Registro atrasado*\n_2 professores_"]

sem_exp = montar_mensagens_escalonamento(MENSAGENS_ALUNO, [])
checar("11a. sem experimental, fila do aluno intocada", MENSAGENS_ALUNO, sem_exp)

com_exp = montar_mensagens_escalonamento(MENSAGENS_ALUNO, LINHAS)
checar("11b. com experimental, mensagens do aluno continuam as mesmas",
       MENSAGENS_ALUNO, com_exp[:-1])
checar("11c. com experimental, uma mensagem a mais no fim", len(MENSAGENS_ALUNO) + 1,
       len(com_exp))
checar("11d. a mensagem extra cita o lead", True, "Davi Nakashima" in com_exp[-1])


# ---------------------------------------------------------------------------
# Caso 12 — linhas_experimental_escalonadas: isolamento de falha (Ruling 15)
# e o desempacotamento tem que estar DENTRO do try (minor)
# ---------------------------------------------------------------------------

with patch.object(worker, "rpc", return_value={"ok": True, "linhas": LINHAS}):
    linhas_ok = linhas_experimental_escalonadas()
checar("12a. sucesso repassa as linhas da RPC", LINHAS, linhas_ok)

logadas: list[dict] = []


def _fake_log(nome, **campos):
    logadas.append({"nome": nome, **campos})


def _rpc_explode(name, body):
    raise RuntimeError("uazapi 502: bad gateway")


with patch.object(worker, "rpc", side_effect=_rpc_explode), \
     patch.object(worker, "log", side_effect=_fake_log):
    linhas_falha = linhas_experimental_escalonadas()
checar("12b. falha na RPC devolve lista vazia (nao propaga)", [], linhas_falha)
checar("12c. a falha chega ao journal", True,
       any("falhou" in l["nome"] and "502" in str(l.get("error", "")) for l in logadas))

logadas.clear()
with patch.object(worker, "rpc", return_value=["nao", "e", "dict"]), \
     patch.object(worker, "log", side_effect=_fake_log):
    linhas_malformada = linhas_experimental_escalonadas()
checar("12d. resposta malformada (nao-dict) tambem cai no isolamento", [], linhas_malformada)
checar("12e. resposta malformada tambem chega ao journal", True,
       any("falhou" in l["nome"] for l in logadas))


# ---------------------------------------------------------------------------
# Casos 13-19 — rodar_escalonamento: o PONTO DE DESPACHO de verdade
# ---------------------------------------------------------------------------

def _rpc_so_experimental(linhas_exp):
    def _rpc(name, body):
        if name == "fn_experimental_escalonadas":
            return {"ok": True, "linhas": linhas_exp}
        raise AssertionError(f"rpc inesperada nesta arena: {name}")
    return _rpc


# 13. dry_run + com experimental: nao envia nada, preview mostra as duas
#     origens, contagem de "experimentais" correta.
enviados: list[tuple] = []


def _fake_enviar_grupo(texto, evento="escalonamento"):
    enviados.append((texto, evento))
    return {"ok": True}


with patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    r13 = rodar_escalonamento(None, dry_run=True)
checar("13a. dry_run: status dry_run_ready", "dry_run_ready", r13["status"])
checar("13b. dry_run: conta 1 experimental", 1, r13["experimentais"])
checar("13c. dry_run: preview tem as duas origens", True,
       "MSG_ALUNO" in r13["content_preview"] and "Davi Nakashima" in r13["content_preview"])
checar("13d. dry_run: nao chama enviar_grupo", [], enviados)

# 14. envio real, professor_id=None, com experimental: duas mensagens saem,
#     a do aluno com evento default, a experimental com evento PROPRIO (I4).
with patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    r14 = rodar_escalonamento(None, dry_run=False)
checar("14a. envio real: status sent", "sent", r14["status"])
checar("14b. envio real: 2 mensagens enviadas", 2, r14["mensagens"])
checar("14c. mensagem do aluno vai com evento 'escalonamento'",
       ("MSG_ALUNO", "escalonamento"), enviados[0])
checar("14d. bloco da experimental vai com evento PROPRIO (nao generico)",
       "escalonamento_experimental", enviados[1][1])
checar("14e. bloco da experimental cita o lead", True, "Davi Nakashima" in enviados[1][0])

# 15. I5: --professor-id setado NAO pode buscar/vazar a experimental da
#     escola inteira pro grupo.
rpc_chamadas: list[str] = []


def _rpc_registra_chamada(name, body):
    rpc_chamadas.append(name)
    return {"ok": True, "linhas": LINHAS}


with patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 25}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_registra_chamada), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    rpc_chamadas.clear()
    logadas.clear()
    r15 = rodar_escalonamento(25, dry_run=False)
checar("15a. professor_id setado: RPC da experimental NUNCA chamada", [], rpc_chamadas)
checar("15b. professor_id setado: so a mensagem do aluno sai", 1, r15["mensagens"])
checar("15c. professor_id setado: 0 experimentais no resultado", 0, r15["experimentais"])
checar("15d. professor_id setado: o motivo do pulo chega ao journal", True,
       any("pulado" in l["nome"] for l in logadas))
checar("15e. nenhuma mensagem sai com evento experimental", True,
       all(ev != "escalonamento_experimental" for _, ev in enviados))

# 16. sem pendencia nenhuma (aluno vazio, experimental vazia): resultado
#     continua sendo "sem_pendencia_escalonada" -- comportamento antigo
#     intocado.
with patch.object(worker, "pendencias_escalonadas", return_value=[]), \
     patch.object(worker, "montar_escalonamento", return_value=[]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental([])), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo):
    enviados.clear()
    r16 = rodar_escalonamento(None, dry_run=False)
checar("16. sem pendencia nenhuma: sem_pendencia_escalonada", "sem_pendencia_escalonada", r16["status"])

# 17. so experimental (aluno sem pendencia nenhuma): a mensagem sai mesmo
#     assim -- a coordenacao nao pode perder a experimental so porque
#     nenhum professor esta atrasado no registro.
with patch.object(worker, "pendencias_escalonadas", return_value=[]), \
     patch.object(worker, "montar_escalonamento", return_value=[]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo):
    enviados.clear()
    r17 = rodar_escalonamento(None, dry_run=False)
checar("17a. so experimental: sai mesmo sem pendencia de aluno", "sent", r17["status"])
checar("17b. so experimental: 1 mensagem, a experimental", 1, len(enviados))
checar("17c. so experimental: evento correto mesmo sendo a UNICA mensagem",
       "escalonamento_experimental", enviados[0][1])

# 18. I4 (falha parcial): o envio da mensagem do ALUNO explode ANTES do
#     bloco da experimental sair -- a coordenacao ficou sem a lista, e o
#     resultado tem que dizer isso explicitamente.


def _enviar_explode_no_aluno(texto, evento="escalonamento"):
    if evento == "escalonamento":
        raise RuntimeError("uazapi 500: fora do ar")
    enviados.append((texto, evento))
    return {"ok": True}


with patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_enviar_explode_no_aluno):
    enviados.clear()
    r18 = rodar_escalonamento(None, dry_run=False)
checar("18a. falha antes do bloco experimental: status error", "error", r18["status"])
checar("18b. falha antes do bloco experimental: 0 enviadas", 0, r18["enviadas"])
checar("18c. o journal sabe que a experimental se perdeu", True, r18.get("experimental_perdida"))

# 19. contraste do 18: quando NAO havia experimental pra perder, o erro nao
#     inventa a chave "experimental_perdida".
with patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental([])), \
     patch.object(worker, "enviar_grupo", side_effect=_enviar_explode_no_aluno):
    enviados.clear()
    r19 = rodar_escalonamento(None, dry_run=False)
checar("19a. sem experimental pra perder: status error do mesmo jeito", "error", r19["status"])
checar("19b. sem experimental pra perder: chave nao aparece", False,
       "experimental_perdida" in r19)


# ---------------------------------------------------------------------------
# Caso 20 — I1: guarda do fio de ligacao. main() precisa CHAMAR
# rodar_escalonamento; e exatamente o mutante que sobreviveu 22/22 na
# primeira rodada (apagar as duas linhas de despacho dentro de main() nao
# quebrava nenhum teste, porque cada peca isolada continuava certa).
# ---------------------------------------------------------------------------
fonte_main = inspect.getsource(worker.main)
# A checagem tem que ser a ASSINATURA da chamada, nao so o nome da funcao --
# o comentario logo acima da chamada em main() explica "mora em
# rodar_escalonamento()" em prosa, e essa mesma substring sobreviveria
# mesmo que a chamada de verdade fosse apagada (foi exatamente o que
# aconteceu na primeira versao deste caso: o mutante M7 apagava so a
# chamada e o teste continuava vendo o nome da funcao... no comentario).
checar("20. main() despacha o evento 'escalonamento' via rodar_escalonamento",
       True, "rodar_escalonamento(args.professor_id, args.dry_run)" in fonte_main)


print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
