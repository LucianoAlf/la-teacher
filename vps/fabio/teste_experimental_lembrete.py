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
from unittest.mock import patch

# O corpo das mensagens carrega emoji (🎓🎤). Sem isto, um console que não
# fala UTF-8 (cp1252 do Windows, por exemplo) morre com UnicodeEncodeError
# NO MEIO do print das FALHAS — o exit code continua != 0 (o CI não mente),
# mas quem revisa perde a lista de falhas bem na hora que mais precisa dela.
# Aconteceu de verdade na revisão desta task.
sys.stdout.reconfigure(errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fabio_notification_worker as worker  # noqa: E402
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

# ============================================================================
# CASOS 7+ — orquestração (run_experimental_lembrete), não só o literal.
#
# POR QUE ISTO EXISTE. Os casos 1-6 só testam format_lembrete_experimental e
# a constante REFERENCIA_TIPO_EXPERIMENTAL — nada ali exercita QUEM USA a
# trava. Revisão da Task 3 achou 2 mutantes sobrevivendo 14/14 verde por
# causa disso: referencia_id trocado por aula_id (cobra por AULA, não por
# vínculo — numa experimental em grupo o segundo lead nunca é cobrado) e
# referencia_id constante (o primeiro vínculo da história queima a chave pra
# sempre). Nenhum dos dois aparece testando só a string. Aproveitando a
# bancada, também cobrimos --dry-run vazando efeito colateral, a janela de
# minutos sendo trocada, e as duas travas que a Task 3 tinha esquecido de
# espelhar dos irmãos (can_notify e telefone) — cada trava nova pede o
# próprio mutante morto, não só a que o revisor nomeou.
#
# Todo RPC do worker (claim, mark_sent, mark_failed, can_notify e a própria
# busca de alvos) passa por `rpc()`; só `active_professors()` fala direto
# com `bridge.sb_get`. Por isso os testes substituem `worker.rpc`,
# `worker.deliver` e `worker.active_professors` — nada disto toca rede nem
# WhatsApp de verdade.
# ============================================================================


class FakeBackend:
    """Dublê do lado servidor: registra toda chamada, nunca toca a rede."""

    def __init__(self, alvos, *, pode_notificar=True, falhar_claim_para=None,
                 falhar_claim_sempre=False):
        self.alvos = alvos
        self.pode_notificar = pode_notificar
        # referencia_id que deve explodir o claim (simula 502 transitório) —
        # usado só no caso de isolamento por alvo (I4).
        self.falhar_claim_para = falhar_claim_para
        # simula o C1 real: TODO claim morre com 23514 (tipo fora da
        # allowlist) — usado no caso 14 (N1: journal por alvo).
        self.falhar_claim_sempre = falhar_claim_sempre
        self.chamadas_alvos = []   # corpo de cada chamada a fn_experimental_lembrete_alvos
        self.claims = []           # corpo de cada chamada de claim
        self._claimadas = set()    # (tipo, referencia_id, canal) já entregues
        self.entregues = []        # (pid, channel, corpo)
        self.marcadas_enviadas = []
        self.marcadas_falhas = []

    def rpc(self, name, body):
        if name == "fn_experimental_lembrete_alvos":
            self.chamadas_alvos.append(dict(body))
            return {"ok": True, "linhas": self.alvos}
        if name == "fn_fabio_pode_notificar":
            return self.pode_notificar
        if name == "fabio_claim_notificacao_por_referencia":
            self.claims.append(dict(body))
            ref_id = body.get("p_referencia_id")
            if self.falhar_claim_sempre:
                raise RuntimeError(
                    'rpc fabio_claim_notificacao_por_referencia 400: '
                    '{"code":"23514","message":"new row for relation '
                    '\\"fabio_notificacoes\\" violates check constraint '
                    '\\"fabio_notificacoes_tipo_check\\""}')
            if self.falhar_claim_para is not None and ref_id == self.falhar_claim_para:
                raise RuntimeError("rpc fabio_claim_notificacao_por_referencia 502: bad gateway")
            chave = (body.get("p_referencia_tipo"), ref_id, body.get("p_canal"))
            if chave in self._claimadas:
                return {"ok": True, "claimed": False}
            self._claimadas.add(chave)
            return {"ok": True, "claimed": True,
                    "notificacao_id": f"notif-{len(self.claims)}",
                    "lease_token": f"lease-{len(self.claims)}"}
        if name == "fabio_marcar_notificacao_enviada":
            self.marcadas_enviadas.append(dict(body))
            return True
        if name == "fabio_marcar_notificacao_falhou":
            self.marcadas_falhas.append(dict(body))
            return True
        raise AssertionError(f"rpc inesperado no fake: {name} {body}")

    def deliver(self, pid, channel, content):
        self.entregues.append((pid, channel, content))
        return {"ok": True}


PROFESSORES_FAKE = [
    {"id": 10, "nome": "Isaque", "telefone_whatsapp": "5521999990010", "ativo": True},
    {"id": 11, "nome": "Outro Professor", "telefone_whatsapp": "", "ativo": True},
]


def rodar(backend, *, dry_run=False):
    with patch.object(worker, "rpc", side_effect=backend.rpc), \
         patch.object(worker, "deliver", side_effect=backend.deliver), \
         patch.object(worker, "active_professors", return_value=PROFESSORES_FAKE):
        return worker.run_experimental_lembrete("whatsapp", dry_run=dry_run)


ALVO_1 = {"vinculo_id": 700, "aula_id": 555, "professor_id": 10,
          "nome_aluno": "Aluno A", "curso_nome": "Violão", "unidade_nome": "Barra",
          "hora_fim": "10:00", "horas_em_atraso": 0}

# ── 7. caminho feliz: referência do claim é o VÍNCULO, não a aula ──────────
# Mata M5 (referencia_id vira aula_id): aula_id=555 e vinculo_id=700 são
# DIFERENTES de propósito — se o mutante trocar a fonte, este caso pega.
backend7 = FakeBackend([ALVO_1])
r7 = rodar(backend7)
checar("7. resultado ok", True, r7.get("ok"))
checar("7. um alvo processado", 1, r7.get("alvos"))
checar("7. status enviada", "enviada", r7["resultados"][0]["status"])
checar("7. claim referencia = vinculo_id (nao aula_id)",
       "700", backend7.claims[0]["p_referencia_id"])
checar("7. claim referencia_tipo correto",
       "experimental_vinculo", backend7.claims[0]["p_referencia_tipo"])
checar("7. entregou pro professor certo", 10, backend7.entregues[0][0])

# ── 8. dois leads na MESMA aula (grupo): referência não pode ser constante ─
# Mata M6 (referencia_id constante): se o claim usasse uma string fixa em
# vez do vinculo, o segundo lead cairia em "ja_avisado" pelo dedupe do
# próprio índice — o professor nunca é cobrado pelo segundo aluno.
ALVO_2A = {"vinculo_id": 701, "aula_id": 555, "professor_id": 10,
           "nome_aluno": "Aluno B1", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "10:00", "horas_em_atraso": 0}
ALVO_2B = {"vinculo_id": 702, "aula_id": 555, "professor_id": 10,
           "nome_aluno": "Aluno B2", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "10:00", "horas_em_atraso": 0}
backend8 = FakeBackend([ALVO_2A, ALVO_2B])
r8 = rodar(backend8)
checar("8. dois alvos, duas referencias diferentes", True,
       backend8.claims[0]["p_referencia_id"] != backend8.claims[1]["p_referencia_id"])
checar("8. os DOIS leads da mesma aula sao cobrados", ["enviada", "enviada"],
       [x["status"] for x in r8["resultados"]])

# ── 9. --dry-run não pode ter efeito colateral nenhum ──────────────────────
# Mata M7 (bypass do --dry-run): se o dry_run for ignorado em algum ramo,
# claims/entregues deixam de estar vazios.
backend9 = FakeBackend([ALVO_1])
r9 = rodar(backend9, dry_run=True)
checar("9. dry_run nao reserva claim", [], backend9.claims)
checar("9. dry_run nao entrega mensagem", [], backend9.entregues)
checar("9. status dry_run_ready", "dry_run_ready", r9["resultados"][0]["status"])

# ── 10. a janela de minutos que vai pra RPC é exatamente 20 ────────────────
# Mata M8 (janela 20 -> 2000, ou qualquer outro valor): 2000 minutos alcança
# aula de dias atrás e o lembrete "logo após a experimental" perde o sentido.
backend10 = FakeBackend([])
rodar(backend10)
checar("10. janela pedida ao banco e 20min",
       {"p_minutos": 20}, backend10.chamadas_alvos[0])

# ── 11. professor que desligou governança não é furado por este evento ────
# Mata a remoção do can_notify() (I3): sem a chamada, isto sai "enviada".
backend11 = FakeBackend([ALVO_1], pode_notificar=False)
r11 = rodar(backend11)
checar("11. bloqueado por preferencia", "blocked_by_preferences", r11["resultados"][0]["status"])
checar("11. preferencia desligada nao gera claim", [], backend11.claims)

# ── 12. sem telefone, o vínculo NÃO pode virar 'enviada' mentiroso ─────────
# Mata a remoção do check de telefone (I5): bridge.send_whatsapp_text não
# levanta quando falta telefone — sem o skip explícito, o claim grava a
# linha, deliver volta em silêncio e mark_sent marca 'enviada' pra sempre
# (chave sem data, nunca mais re-tentada).
ALVO_SEM_TEL = {**ALVO_1, "vinculo_id": 703, "professor_id": 11}
backend12 = FakeBackend([ALVO_SEM_TEL])
r12 = rodar(backend12)
checar("12. sem telefone -> missing_phone_skip",
       "missing_phone_skip", r12["resultados"][0]["status"])
checar("12. sem telefone nao gera claim nem 'enviada' falso", [], backend12.claims)

# ── 13. um 502 no claim do 1º alvo não pode engolir os alvos seguintes ─────
# Mata a remoção do isolamento por alvo (I4): montagem+claim precisam estar
# DENTRO do try de cada alvo — do jeito antigo, a exceção do primeiro
# vazava pra fora do laço inteiro e o segundo alvo nunca era tentado.
ALVO_3A = {"vinculo_id": 704, "aula_id": 900, "professor_id": 10,
           "nome_aluno": "Aluno C1", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "11:00", "horas_em_atraso": 0}
ALVO_3B = {"vinculo_id": 705, "aula_id": 901, "professor_id": 10,
           "nome_aluno": "Aluno C2", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "11:05", "horas_em_atraso": 0}
backend13 = FakeBackend([ALVO_3A, ALVO_3B], falhar_claim_para="704")
r13 = rodar(backend13)
checar("13. run nao propaga a excecao do 1o alvo", True, r13.get("ok"))
checar("13. 1o alvo registra erro isolado", "erro", r13["resultados"][0]["status"])
checar("13. 2o alvo AINDA e processado (nao foi engolido)",
       "enviada", r13["resultados"][1]["status"])

# ── 14. cenário C1 real: TODO claim morre com 23514 — o journal tem que ────
# mostrar o erro por alvo, não "ok" com tudo falhando. Mata a regressão do
# N1: agregar um log só por rodada e descartar o `erro` de cada resultado
# (foi exatamente o isolamento por alvo do I4 que tornou isto alcançável —
# antes, a exceção vazava pra fora do laço inteiro e o `except` do main()
# era quem preenchia "error"; isolado por alvo, aquele `except` nunca mais
# roda, e o campo "error" do topo do retorno nunca existiu).
#
# Replica literalmente o laço novo de main(): `for r in resultados: log(...)`.
ALVO_4A = {"vinculo_id": 900, "aula_id": 1, "professor_id": 10,
           "nome_aluno": "Aluno D1", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "09:00", "horas_em_atraso": 0}
ALVO_4B = {"vinculo_id": 901, "aula_id": 2, "professor_id": 10,
           "nome_aluno": "Aluno D2", "curso_nome": "Violão", "unidade_nome": "Barra",
           "hora_fim": "09:10", "horas_em_atraso": 0}
backend14 = FakeBackend([ALVO_4A, ALVO_4B], falhar_claim_sempre=True)
r14 = rodar(backend14)

logadas: list[dict] = []
with patch.object(worker, "log", side_effect=lambda msg, **f: logadas.append(f)):
    for _r in r14.get("resultados") or []:
        worker.log("event_result", **_r)

checar("14. retorno.ok continua True (nao propaga)", True, r14.get("ok"))
checar("14. 'error' no TOPO do retorno nao existe (a forma e por resultado)",
       False, "error" in r14)
checar("14. os DOIS alvos falharam de verdade", ["erro", "erro"],
       [x["status"] for x in r14["resultados"]])
checar("14. o journal tem UMA linha por alvo", 2, len(logadas))
checar("14. NENHUMA linha do journal diz status=ok", True,
       all(linha.get("status") != "ok" for linha in logadas))
checar("14. cada linha carrega o erro de verdade (nao None)", True,
       all(linha.get("erro") for linha in logadas))
checar("14. cada linha carrega o vinculo (pra saber QUAL alvo falhou)",
       {900, 901}, {linha.get("vinculo_id") for linha in logadas})

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
