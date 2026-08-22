#!/usr/bin/env python3
"""Teste do escalonamento da experimental para a coordenacao.

POR QUE ELE EXISTE. Escalonamento e a mensagem que chega em quem NAO deu a
aula. Se ela nao disser de quem e a aula, qual unidade, ha quanto tempo e
QUANDO ela aconteceu (com hora, nao so data), a coordenacao nao consegue
agir e a mensagem vira ruido — e ruido em canal de coordenacao mata a
credibilidade de todo o resto.

Ruling 18 (revisao 1): o teto corta DETALHE, nao corta GENTE. Casos 8-10
provam que ninguem some, inclusive bem acima do teto.

Ruling 19 (revisao 2): o bloco da experimental tem interruptor PROPRIO
(ESCALONAMENTO_EXPERIMENTAL_ATIVO), desligado por padrao. Casos 22-24
provam os dois estados: desligado (o real hoje, ate a Task 6 decidir
ativar) nao busca nem manda nada da experimental; ligado, funciona como
antes.

Important 2 (revisao 2): o rodape do Ruling 18 tira o corte de gente, mas
sozinho deixa o bloco crescer sem limite. Casos 16-17 provam que, acima do
mesmo tamanho que o irmao (aluno) usa pra dividir, a experimental tambem
se divide por unidade — e ninguem some NA DIVISAO tambem.

I1 (revisao 1 e 2): o fio que liga rodar_escalonamento a main() nao tinha
NENHUM teste que provasse EXECUCAO — so um `in inspect.getsource`, que uma
chamada comentada (texto ainda presente, codigo morto) engana. Casos 25-28
rodam main() de verdade (sys.argv + patch), com asserção sobre a SEQUENCIA
de enviar_grupo, sobre o payload de resultado, e sobre o log — os tres
jeitos como um mutante plausivel de refatoracao pode matar o despacho em
silencio.

Minors: hora do "quando" (caso 3b), fronteira exata do teto (caso 15),
_dias_em_atraso_txt com dias=0 (caso 14), subtitulo com o total honesto
(caso 13).

Rodar:  python3 teste_escalonamento_experimental.py
"""
from __future__ import annotations

import contextlib
import inspect
import io
import json as _json
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
    ESCALONAMENTO_MENSAGEM_UNICA_MAX,
    format_escalonamento_experimental,
    linhas_experimental_escalonadas,
    montar_blocos_escalonamento_experimental,
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

def _linha(n: int, dias: int = 5, unidade: str = "Barra") -> dict:
    return {"vinculo_id": 3000 + n, "nome_aluno": f"Lead {n}",
            "professor_nome": f"Prof {n}", "unidade_nome": unidade,
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
# Caso 13 (minor) — subtitulo com o total honesto. A versao anterior nao
# dizia total nenhum; quem le as 9h tinha que contar linha pra saber se
# eram 8 ou 80.
# ---------------------------------------------------------------------------
checar("13a. subtitulo com o total (singular)", True, "_1 lead_" in texto)
checar("13b. subtitulo com o total (plural)", True, "_12 leads_" in texto_acima)


# ---------------------------------------------------------------------------
# Caso 14 (minor) — _dias_em_atraso_txt(0): a propria docstring da funcao
# explica por que `l.get(...) or '?'` estaria errado com zero (falsy mas
# valido); trava descrita sem teste e o padrao que mais custou nesta
# entrega, entao o caso existe por nome.
# ---------------------------------------------------------------------------
checar("14. dias_em_atraso=0 renderiza '0', nao '?' (0 e valor valido)",
       "0", worker._dias_em_atraso_txt({"dias_em_atraso": 0}))


# ---------------------------------------------------------------------------
# Caso 15 (minor) — fronteira EXATA do teto. `linhas[:limite]` vs
# `linhas[:limite + 1]` passavam os casos 8-10 do mesmo jeito (eles nunca
# contam quantos blocos de DETALHE saem, so verificam presenca/ausencia de
# nomes). Aqui conto os marcadores "• *" (bullet do detalhe, distinto do
# "· " do rodape) e exijo o numero EXATO.
# ---------------------------------------------------------------------------
SEIS_TETO5 = [_linha(n) for n in range(1, 7)]
texto_teto5 = format_escalonamento_experimental(SEIS_TETO5, teto=5)
checar("15. fronteira do teto: EXATAMENTE `teto` blocos detalhados (nao teto+1)",
       5, texto_teto5.count("• *"))


# ---------------------------------------------------------------------------
# Casos 16-17 — Important 2: o rodape do Ruling 18 nao pode virar parede.
# Medido pelo revisor: 100 leads = 5.239 chars, 200 = 9.839 -- perto de 130
# cruza os mesmos 6.000 chars que o aluno usa pra dividir por unidade.
# ---------------------------------------------------------------------------

# 16. abaixo do limiar de uma mensagem: continua uma mensagem so (nao muda
#     o comportamento de quem ja tinha poucos leads).
blocos_pequeno = montar_blocos_escalonamento_experimental(DOZE)
checar("16a. poucos leads (12): uma mensagem so", 1, len(blocos_pequeno))
checar("16b. poucos leads: e o mesmo texto de format_escalonamento_experimental",
       format_escalonamento_experimental(DOZE), blocos_pequeno[0])

# 17. acima do limiar: divide por unidade, e ninguem some NA DIVISAO
#     tambem. Construo o cenario medindo o proprio limiar (em vez de
#     cravar um N arbitrario) pra nao depender de um numero magico que
#     pode ficar errado se o formato do bloco mudar de novo no futuro.
#
# ATENCAO quem for mexer aqui: este `while` PRECISA de teto (`_BUSCA_MAX`).
# Descoberto ao vivo (revisao 3, 22/08/2026): sem ele, o mutante M4 (Ruling
# 18 regride -- `resto = []` sempre) capa `detalhados` em
# ESCALONAMENTO_EXPERIMENTAL_TETO (10) pra sempre e ZERA o crescimento do
# rodape -- o texto para de crescer com `_n` e a busca vira loop infinito
# de verdade (travou a arena de mutantes rodando em background ate ela
# precisar ser morta na mao). Com o teto, o mesmo mutante faz `_n` bater no
# limite sem achar o cruzamento -- e ai o proprio caso 17a (abaixo) falha
# rapido em vez do processo travar pra sempre.
_BUSCA_MAX = 2000
_n = 1
while (_n < _BUSCA_MAX and
       len(format_escalonamento_experimental([_linha(i) for i in range(1, _n + 1)])) <= ESCALONAMENTO_MENSAGEM_UNICA_MAX):
    _n += 1
# _n agora e o menor N que sozinho, numa unidade so, passaria do limiar
# (ou _BUSCA_MAX, se a busca nao achou -- e sinal de regressao, nao de
# limiar realista; o caso 17a abaixo capta isso como FALHA, nao trava).
# Split em DUAS unidades com esse N cada garante que o combinado passe do
# limiar (por construcao) e prova a divisao.
GRANDE_BARRA = [_linha(i, unidade="Barra") for i in range(1, _n + 1)]
GRANDE_CG = [_linha(1000 + i, unidade="CG") for i in range(1, _n + 1)]
GRANDE_MISTO = GRANDE_BARRA + GRANDE_CG

unico_grande = format_escalonamento_experimental(GRANDE_MISTO)
checar("17a. o combinado realmente passa do limiar de uma mensagem (pre-condicao do teste)",
       True, len(unico_grande) > ESCALONAMENTO_MENSAGEM_UNICA_MAX)

blocos_grande = montar_blocos_escalonamento_experimental(GRANDE_MISTO)
checar("17b. acima do limiar: divide em uma mensagem POR UNIDADE (2)", 2, len(blocos_grande))
checar("17c. cada mensagem carrega so a unidade dela no titulo", True,
       any("Barra" in b and "CG" not in b.split("\n")[0] for b in blocos_grande)
       and any("CG" in b and "Barra" not in b.split("\n")[0] for b in blocos_grande))
# Ruling 18 + Important 2 juntos: ninguem some NEM na divisao. Cada lead
# tem um vinculo_id unico (Barra: 3001.., CG: 4001..) -- basta achar o nome
# de cada um em ALGUM dos blocos combinados.
todos_nomes_barra = [f"Lead {i}" for i in range(1, _n + 1)]
texto_combinado_grande = "\n".join(blocos_grande)
checar("17d. ninguem some na divisao por unidade (todos os nomes aparecem)", True,
       all(nome in texto_combinado_grande for nome in todos_nomes_barra))


# ---------------------------------------------------------------------------
# Casos 18-21 — rodar_escalonamento: o PONTO DE DESPACHO de verdade.
# ESCALONAMENTO_EXPERIMENTAL_ATIVO tem que estar LIGADO nestes casos pra
# isolar o comportamento que eles testam (Ruling 19 e testado em 22-24).
# ---------------------------------------------------------------------------

def _rpc_so_experimental(linhas_exp):
    def _rpc(name, body):
        if name == "fn_experimental_escalonadas":
            return {"ok": True, "linhas": linhas_exp}
        raise AssertionError(f"rpc inesperada nesta arena: {name}")
    return _rpc


enviados: list[tuple] = []


def _fake_enviar_grupo(texto, evento="escalonamento"):
    enviados.append((texto, evento))
    return {"ok": True}


# 18. dry_run + com experimental: nao envia nada, preview mostra as duas
#     origens, contagem de "experimentais" correta.
with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    r18 = rodar_escalonamento(None, dry_run=True)
checar("18a. dry_run: status dry_run_ready", "dry_run_ready", r18["status"])
checar("18b. dry_run: conta 1 experimental", 1, r18["experimentais"])
checar("18c. dry_run: preview tem as duas origens", True,
       "MSG_ALUNO" in r18["content_preview"] and "Davi Nakashima" in r18["content_preview"])
checar("18d. dry_run: nao chama enviar_grupo", [], enviados)

# 19. envio real, professor_id=None, com experimental: duas mensagens saem,
#     a do aluno com evento default, a experimental com evento PROPRIO (I4).
with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    r19 = rodar_escalonamento(None, dry_run=False)
checar("19a. envio real: status sent", "sent", r19["status"])
checar("19b. envio real: 2 mensagens enviadas", 2, r19["mensagens"])
checar("19c. mensagem do aluno vai com evento 'escalonamento'",
       ("MSG_ALUNO", "escalonamento"), enviados[0])
checar("19d. bloco da experimental vai com evento PROPRIO (nao generico)",
       "escalonamento_experimental", enviados[1][1])
checar("19e. bloco da experimental cita o lead", True, "Davi Nakashima" in enviados[1][0])

# 20. I5: --professor-id setado NAO pode buscar/vazar a experimental da
#     escola inteira pro grupo (mesmo com o interruptor ligado).
rpc_chamadas: list[str] = []


def _rpc_registra_chamada(name, body):
    rpc_chamadas.append(name)
    return {"ok": True, "linhas": LINHAS}


with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 25}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_registra_chamada), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    rpc_chamadas.clear()
    logadas.clear()
    r20 = rodar_escalonamento(25, dry_run=False)
checar("20a. professor_id setado: RPC da experimental NUNCA chamada", [], rpc_chamadas)
checar("20b. professor_id setado: so a mensagem do aluno sai", 1, r20["mensagens"])
checar("20c. professor_id setado: 0 experimentais no resultado", 0, r20["experimentais"])
checar("20d. professor_id setado: o motivo do pulo chega ao journal", True,
       any("pulado" in l["nome"] for l in logadas))
checar("20e. nenhuma mensagem sai com evento experimental", True,
       all(ev != "escalonamento_experimental" for _, ev in enviados))

# 21. I4 (falha parcial): o envio da mensagem do ALUNO explode ANTES do
#     bloco da experimental sair -- a coordenacao ficou sem a lista, e o
#     resultado tem que dizer isso explicitamente.


def _enviar_explode_no_aluno(texto, evento="escalonamento"):
    if evento == "escalonamento":
        raise RuntimeError("uazapi 500: fora do ar")
    enviados.append((texto, evento))
    return {"ok": True}


with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_enviar_explode_no_aluno):
    enviados.clear()
    r21 = rodar_escalonamento(None, dry_run=False)
checar("21a. falha antes do bloco experimental: status error", "error", r21["status"])
checar("21b. falha antes do bloco experimental: 0 enviadas", 0, r21["enviadas"])
checar("21c. o journal sabe que a experimental se perdeu", True, r21.get("experimental_perdida"))

with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental([])), \
     patch.object(worker, "enviar_grupo", side_effect=_enviar_explode_no_aluno):
    enviados.clear()
    r21b = rodar_escalonamento(None, dry_run=False)
checar("21d. sem experimental pra perder: status error do mesmo jeito", "error", r21b["status"])
checar("21e. sem experimental pra perder: chave nao aparece", False,
       "experimental_perdida" in r21b)


# ---------------------------------------------------------------------------
# Casos 22-24 — Ruling 19: interruptor proprio, DESLIGADO por padrao
# ---------------------------------------------------------------------------

# 22. o padrao (nenhum patch, ambiente limpo) e DESLIGADO -- e o estado
#     real hoje, antes de qualquer decisao humana de ativar.
checar("22. por padrao (sem ativar nada), o interruptor esta DESLIGADO",
       False, worker.ESCALONAMENTO_EXPERIMENTAL_ATIVO)

# 23. desligado (explicito, nao so o default): a experimental NUNCA e
#     buscada, mesmo com professor_id=None e RPC pronta pra responder. So
#     a mensagem do aluno sai, e o journal sabe o motivo.
with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", False), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_registra_chamada), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    rpc_chamadas.clear()
    logadas.clear()
    r23 = rodar_escalonamento(None, dry_run=False)
checar("23a. desligado: RPC da experimental NUNCA chamada", [], rpc_chamadas)
checar("23b. desligado: so a mensagem do aluno sai", 1, r23["mensagens"])
checar("23c. desligado: 0 experimentais no resultado", 0, r23["experimentais"])
checar("23d. desligado: o motivo chega ao journal", True,
       any("desativado" in l["nome"] for l in logadas))
checar("23e. desligado: nenhuma mensagem com evento experimental", True,
       all(ev != "escalonamento_experimental" for _, ev in enviados))

# 24. ligado: volta a funcionar como os casos 18-19 -- prova que o
#     interruptor de fato CONTROLA o comportamento (nao e so decorativo).
with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo), \
     patch.object(worker, "log", side_effect=_fake_log):
    enviados.clear()
    r24 = rodar_escalonamento(None, dry_run=False)
checar("24. ligado: a experimental volta a sair (2 mensagens)", 2, r24["mensagens"])


# ---------------------------------------------------------------------------
# Casos 25-28 — I1: teste COMPORTAMENTAL de main(). O caso 29
# (inspect.getsource) so prova que o TEXTO existe -- uma chamada comentada
# ainda contem o texto e o guard passaria mesmo com o codigo morto. So
# rodando main() de verdade (sys.argv real, patch nos colaboradores) prova
# EXECUCAO. Mata os 3 mutantes que a revisao mediu sobreviverem 54/54:
# chamada apagada (nenhuma mensagem sai), retorno descartado (nao aparece
# no payload), log tirado (nao aparece no journal).
# ---------------------------------------------------------------------------

def _rodar_main(argv):
    argv_antigo = sys.argv
    sys.argv = argv
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = worker.main()
    finally:
        sys.argv = argv_antigo
    return rc, buf.getvalue()


ARGV_ESCALONAMENTO = ["fabio_notification_worker.py", "--event", "escalonamento",
                      "--force", "--json"]

enviados_main: list[tuple] = []


def _fake_enviar_grupo_main(texto, evento="escalonamento"):
    enviados_main.append((texto, evento))
    return {"ok": True}


logadas_main: list[dict] = []


def _fake_log_main(nome, **campos):
    logadas_main.append({"nome": nome, **campos})


with patch.object(worker, "ESCALONAMENTO_EXPERIMENTAL_ATIVO", True), \
     patch.object(worker, "pendencias_escalonadas", return_value=[{"professor_id": 7}]), \
     patch.object(worker, "montar_escalonamento", return_value=["MSG_ALUNO"]), \
     patch.object(worker, "rpc", side_effect=_rpc_so_experimental(LINHAS)), \
     patch.object(worker, "enviar_grupo", side_effect=_fake_enviar_grupo_main), \
     patch.object(worker, "log", side_effect=_fake_log_main), \
     patch.object(worker._time, "sleep", return_value=None):
    enviados_main.clear()
    logadas_main.clear()
    rc25, saida25 = _rodar_main(list(ARGV_ESCALONAMENTO))

payload25 = _json.loads(saida25)
bloco_exp_esperado = format_escalonamento_experimental(LINHAS)

checar("25. main() --event escalonamento retorna 0", 0, rc25)

# 26 — SEQUENCIA de enviar_grupo: pega a chamada apagada/comentada (0
#      mensagens saem, o escalonamento inteiro, aluno e experimental,
#      morre em silencio).
checar("26a. main() manda exatamente 2 mensagens (aluno + experimental)",
       2, len(enviados_main))
checar("26b. primeira mensagem e a do aluno, evento default",
       ("MSG_ALUNO", "escalonamento"), enviados_main[0] if enviados_main else None)
checar("26c. segunda mensagem e o bloco experimental, evento proprio",
       (bloco_exp_esperado, "escalonamento_experimental"),
       enviados_main[1] if len(enviados_main) > 1 else None)

# 27 — payload final (o que o JSON de fato entrega pra quem le o resultado
#      do cron): pega a chamada mantida mas com o RETORNO descartado (o
#      envio acontece, mas o resultado nunca chega no relatorio).
resultado_no_payload = next(
    (r for r in payload25.get("results", []) if r.get("event") == "escalonamento"), None)
checar("27a. o payload final traz o resultado do escalonamento", True,
       resultado_no_payload is not None)
checar("27b. o resultado no payload diz 'sent'", "sent",
       (resultado_no_payload or {}).get("status"))
checar("27c. o resultado no payload conta as 2 mensagens", 2,
       (resultado_no_payload or {}).get("mensagens"))

# 28 — journal: pega a chamada e o append mantidos, mas o log() tirado.
logs_escalonamento = [l for l in logadas_main
                      if l.get("nome") == "event_result" and l.get("event") == "escalonamento"]
checar("28. o log event_result foi chamado para o escalonamento (1x)",
       1, len(logs_escalonamento))


# ---------------------------------------------------------------------------
# Caso 29 — guarda por inspect.getsource. CINTO EXTRA, nao prova (revisao
# 22/08/2026): so garante que a ASSINATURA da chamada esta no texto-fonte
# de main(); uma chamada comentada ainda contem esse texto e passaria
# aqui do mesmo jeito -- por isso os casos 25-28 acima sao a prova de
# verdade (executam main() de fato).
# ---------------------------------------------------------------------------
fonte_main = inspect.getsource(worker.main)
checar("29. main() cita a assinatura de rodar_escalonamento no fonte (cinto extra)",
       True, "rodar_escalonamento(args.professor_id, args.dry_run)" in fonte_main)


print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
