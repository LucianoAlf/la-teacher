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
                 falhar_claim_sempre=False, falhar_mark_sent_sempre=False):
        self.alvos = alvos
        self.pode_notificar = pode_notificar
        # referencia_id que deve explodir o claim (simula 502 transitório) —
        # usado só no caso de isolamento por alvo (I4).
        self.falhar_claim_para = falhar_claim_para
        # simula o C1 real: TODO claim morre com 23514 (tipo fora da
        # allowlist) — usado no caso 14 (N1: journal por alvo).
        self.falhar_claim_sempre = falhar_claim_sempre
        # C1 (revisão 22/08/2026): força a RPC de marcar-enviada a devolver
        # False sempre, não importa o corpo — usado pra provar que o worker
        # RESPEITA o retorno (status vira 'entregue_mas_nao_fechada'), seja
        # qual for o motivo da cerca ter recusado.
        self.falhar_mark_sent_sempre = falhar_mark_sent_sempre
        self.chamadas_alvos = []   # corpo de cada chamada a fn_experimental_lembrete_alvos
        self.claims = []           # corpo de cada chamada de claim
        self._claimadas = set()    # (tipo, referencia_id, canal) já entregues
        self.entregues = []        # (pid, channel, corpo)
        self.marcadas_enviadas = []
        self.marcadas_falhas = []
        self.overrides_enviados = []  # (destino, corpo) — Task 6, Passo 1

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
            if self.falhar_mark_sent_sempre:
                return False
            # Mesma cerca da 018: o claim POR REFERENCIA escreve lease_token,
            # entao mark_sent SEM p_lease_token no corpo nao casa com nenhum
            # lado da cerca no banco real — a RPC devolve False (zero
            # linhas), nunca True. Sem esta simulacao, o mutante "trocar
            # mark_sent(notificacao_id, lease_token) por
            # mark_sent(notificacao_id)" (C1) passa 100% verde neste fake,
            # porque nada aqui reagia a token ausente.
            if "p_lease_token" not in body:
                return False
            return True
        if name == "fabio_marcar_notificacao_falhou":
            self.marcadas_falhas.append(dict(body))
            return True
        raise AssertionError(f"rpc inesperado no fake: {name} {body}")

    def deliver(self, pid, channel, content):
        self.entregues.append((pid, channel, content))
        return {"ok": True}

    def enviar_override(self, destino, corpo):
        self.overrides_enviados.append((destino, corpo))


PROFESSORES_FAKE = [
    {"id": 10, "nome": "Isaque", "telefone_whatsapp": "5521999990010", "ativo": True},
    {"id": 11, "nome": "Outro Professor", "telefone_whatsapp": "", "ativo": True},
]


def rodar(backend, *, dry_run=False, override=""):
    with patch.object(worker, "rpc", side_effect=backend.rpc), \
         patch.object(worker, "deliver", side_effect=backend.deliver), \
         patch.object(worker, "enviar_uazapi_direto", side_effect=backend.enviar_override), \
         patch.object(worker, "active_professors", return_value=PROFESSORES_FAKE), \
         patch.object(worker, "EXPERIMENTAL_DEST_OVERRIDE", override):
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

# ============================================================================
# CASOS 15+ — Task 6, Passo 1: override de destinatário para o rollout.
#
# POR QUE ISTO EXISTE. Ensaio que monta a mensagem e para antes de gravar
# passa verde e não prova nada — CHECK do banco, índice único e resposta da
# UAZAPI só aparecem na execução real. O override deixa a máquina rodar
# INTEIRA (claim de verdade, grava na fila, envia de verdade) só que o envio
# cai num número só, com um carimbo explícito de teste no corpo — sem isso,
# quem lê no celular acha que é cobrança real. Os 3 riscos que a spec do
# rollout marcou como mutante-que-tem-que-morrer: (a) override desligado não
# muda nada do caminho existente (16); (b) override ligado desvia o envio do
# professor de verdade pro destino configurado (17); (c) o corpo carrega o
# aviso de teste com QUEM seria o destinatário real (18); (d) o log registra
# o destino ORIGINAL, não só que houve override (19) — sem isso a auditoria
# do banco mentiria que o professor foi avisado.
# ============================================================================

# ── 15. override vazio (padrão) não muda o caminho feliz já provado no 7 ──
backend15 = FakeBackend([ALVO_1])
r15 = rodar(backend15, override="")
checar("15. override vazio: status ainda 'enviada'", "enviada", r15["resultados"][0]["status"])
checar("15. override vazio: continua indo por deliver()", 1, len(backend15.entregues))
checar("15. override vazio: NADA sai pelo caminho de override", [], backend15.overrides_enviados)

# ── 16. override ligado desvia o envio — deliver() NUNCA é chamado ────────
# Mata o mutante "remove o override" (manda pro professor de verdade mesmo
# com a env var setada): sem o desvio, backend16.entregues teria 1 item e
# overrides_enviados ficaria vazio.
backend16 = FakeBackend([ALVO_1])
r16 = rodar(backend16, override="5521777770000")
checar("16. override ligado: status ainda 'enviada' (fila fecha normalmente)",
       "enviada", r16["resultados"][0]["status"])
checar("16. override ligado: deliver() NAO e chamado", [], backend16.entregues)
checar("16. override ligado: o envio saiu pelo caminho de override", 1,
       len(backend16.overrides_enviados))
checar("16. override ligado: foi pro numero configurado, nao pro professor",
       "5521777770000", backend16.overrides_enviados[0][0])

# ── 17. o corpo enviado carrega o aviso de teste + quem seria o real ──────
# Mata o mutante "remove o aviso de teste do corpo": sem ele, alguém lendo a
# mensagem no celular do destino de override acha que é cobrança de verdade.
corpo_enviado_17 = backend16.overrides_enviados[0][1]
checar("17. corpo carrega aviso de TESTE", True, "TESTE" in corpo_enviado_17)
checar("17. corpo cita o nome do professor que seria o destinatario real",
       True, "Isaque" in corpo_enviado_17)
checar("17. corpo cita o professor_id de quem seria o destinatario real",
       True, "10" in corpo_enviado_17)
checar("17. o texto ORIGINAL do lembrete continua dentro do corpo (nao foi substituido)",
       True, "Davi Nakashima" not in corpo_enviado_17 and "Aluno A" in corpo_enviado_17)

# ── 18. o log registra o destino ORIGINAL, não só "houve override" ───────
# Mata o mutante "loga o override sem o destino original": sem o destino
# original no log, a auditoria não distingue "professor avisado de verdade"
# de "foi tudo pro destino de teste" — a mesma mentira do balde de conserto.
logadas18: list[dict] = []
backend18 = FakeBackend([ALVO_1])
with patch.object(worker, "rpc", side_effect=backend18.rpc), \
     patch.object(worker, "deliver", side_effect=backend18.deliver), \
     patch.object(worker, "enviar_uazapi_direto", side_effect=backend18.enviar_override), \
     patch.object(worker, "active_professors", return_value=PROFESSORES_FAKE), \
     patch.object(worker, "EXPERIMENTAL_DEST_OVERRIDE", "5521777770000"), \
     patch.object(worker, "log", side_effect=lambda msg, **f: logadas18.append({"msg": msg, **f})):
    worker.run_experimental_lembrete("whatsapp", dry_run=False)

logs_override = [l for l in logadas18 if l["msg"] == "experimental_override_ativo"]
checar("18. o log de override foi emitido exatamente 1x", 1, len(logs_override))
checar("18. o log carrega o destino do override", "5521777770000",
       (logs_override[0] if logs_override else {}).get("destino_override"))
checar("18. o log carrega o destino ORIGINAL (telefone do professor de verdade)",
       "5521999990010", (logs_override[0] if logs_override else {}).get("destino_original"))
checar("18. o log carrega o professor_id de verdade", 10,
       (logs_override[0] if logs_override else {}).get("professor_id"))

# ── 19. --dry-run continua sem efeito colateral, mesmo com override ligado ─
backend19 = FakeBackend([ALVO_1])
r19 = rodar(backend19, dry_run=True, override="5521777770000")
checar("19. dry_run + override: nenhum envio de override sai", [], backend19.overrides_enviados)
checar("19. dry_run + override: nenhum deliver sai", [], backend19.entregues)
checar("19. dry_run + override: status dry_run_ready", "dry_run_ready",
       r19["resultados"][0]["status"])

# ============================================================================
# CASOS 20+ — C2 (revisão 22/08/2026): o override também cobre run_event().
#
# POR QUE ISTO EXISTE. Os casos 15-19 só provam o desvio dentro de
# `run_experimental_lembrete` (o lembrete imediato). As DUAS units de
# recobrança já ativas em produção (fabio-pendencia-noite/-manha, 20:50 e
# 08:30 BRT) chamam `run_event("pendencia", ...)` direto — outro caminho de
# código inteiro, com `claim_notification`/`mark_sent` diferentes do claim
# por referência. Sem o gate em `run_event`, a primeira cobrança real da
# trilha (a que carrega a seção 🎓 *Experimentais*) cairia direto no
# professor mesmo com o override ligado — a partição do rollout valeria só
# pra 1 das 4 mensagens.
#
# O gate é por CONTEÚDO (`contem_secao_experimental`), não por evento:
# cobrança de aluno pura (sem a seção) tem que continuar indo pro próprio
# número do professor mesmo com o override ligado, porque o override é da
# trilha experimental — não um mudo geral do worker inteiro.
# ============================================================================

PROF_RUN_EVENT = {"id": 42, "nome": "Ana Beatriz",
                   "telefone_whatsapp": "5521999999999", "ativo": True}

DATA_SO_ALUNO_RUN_EVENT = {
    "total_aulas": 1,
    "aulas": [{"data": "2026-08-21", "hora": "14:00", "curso": "Violão",
               "alunos": [{"primeiro_nome": "Rafael", "nome": "Rafael Souza"}],
               "dias_em_atraso": 1}],
}

LINHA_EXPERIMENTAL_RUN_EVENT = {
    "vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
    "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
    "quando": "21/08 18:00", "dias_em_atraso": 1,
}


def fazer_rpc_run_event(*, com_experimental: bool, estado: dict):
    """Dublê de `rpc()` pro caminho de `run_event` (evento 'pendencia').

    Nomes DIFERENTES do claim por referência: `fabio_claim_notificacao` (sem
    lease) e `fabio_marcar_notificacao_enviada` sem `p_lease_token` — é
    exatamente o caminho que as units de recobrança usam.
    """
    def rpc(name, body):
        if name == "fn_fabio_pode_notificar":
            return True
        if name == "fabio_pendencias_professor":
            return {"total_aulas": 0} if com_experimental else DATA_SO_ALUNO_RUN_EVENT
        if name == "fn_experimental_pendencia_do_professor":
            if com_experimental:
                return {"ok": True, "linhas": [LINHA_EXPERIMENTAL_RUN_EVENT]}
            return {"ok": True, "linhas": []}
        if name == "fabio_claim_notificacao":
            estado["claims"].append(dict(body))
            return {"ok": True, "claimed": True,
                    "notificacao_id": f"notif-run-event-{len(estado['claims'])}"}
        if name == "fabio_marcar_notificacao_enviada":
            estado["marcadas"].append(dict(body))
            return True
        raise AssertionError(f"rpc inesperado no fake de run_event: {name} {body}")
    return rpc


def rodar_run_event(event, prof, *, com_experimental, override, dry_run=False):
    estado = {"claims": [], "marcadas": []}
    entregues: list = []
    overrides_enviados: list = []
    logadas: list = []
    with patch.object(worker, "rpc", side_effect=fazer_rpc_run_event(
            com_experimental=com_experimental, estado=estado)), \
         patch.object(worker, "deliver",
                      side_effect=lambda pid, ch, corpo: entregues.append((pid, ch, corpo)) or {"ok": True}), \
         patch.object(worker, "enviar_uazapi_direto",
                      side_effect=lambda destino, corpo: overrides_enviados.append((destino, corpo))), \
         patch.object(worker, "EXPERIMENTAL_DEST_OVERRIDE", override), \
         patch.object(worker, "log", side_effect=lambda msg, **f: logadas.append({"msg": msg, **f})):
        resultado = worker.run_event(event, prof, "whatsapp", dry_run)
    return resultado, entregues, overrides_enviados, estado, logadas


TELEFONE_CANONICO_PROF_RUN_EVENT = worker.bridge.canonical_phone(
    PROF_RUN_EVENT["telefone_whatsapp"])

# ── 20. cobrança de aluno PURA (sem seção experimental) ignora o override ──
# É o caso que a spec pede por nome: "professor sem seção experimental tem
# que continuar recebendo a cobrança de aluno normalmente, no próprio
# número, mesmo com o override ligado". Sem o gate por conteúdo, este caso
# vazaria pro destino de teste também.
r20, entregues20, overrides20, estado20, _ = rodar_run_event(
    "pendencia", PROF_RUN_EVENT, com_experimental=False, override="5521777770000")
checar("20. sem secao experimental: status sent", "sent", r20.get("status"))
checar("20. sem secao experimental: deliver() E chamado (nao desvia)", 1, len(entregues20))
checar("20. sem secao experimental: NADA sai pelo caminho de override", [], overrides20)
checar("20. sem secao experimental: foi pro professor de verdade", 42,
       entregues20[0][0] if entregues20 else None)

# ── 21. regressão: com experimental, override DESLIGADO segue normal ──────
r21, entregues21, overrides21, _, _ = rodar_run_event(
    "pendencia", PROF_RUN_EVENT, com_experimental=True, override="")
checar("21. override vazio + com experimental: ainda vai por deliver()", 1, len(entregues21))
checar("21. override vazio + com experimental: nada de override", [], overrides21)

# ── 22. C2: com a seção experimental, override ligado DESVIA ──────────────
# Mata o buraco relatado: a recobrança (run_event) tinha que respeitar o
# MESMO desvio do lembrete imediato — antes deste conserto, run_event nem
# olhava pra EXPERIMENTAL_DEST_OVERRIDE.
r22, entregues22, overrides22, estado22, logadas22 = rodar_run_event(
    "pendencia", PROF_RUN_EVENT, com_experimental=True, override="5521777770000")
checar("22. com secao experimental + override: status sent", "sent", r22.get("status"))
checar("22. com secao experimental + override: deliver() NAO e chamado", [], entregues22)
checar("22. com secao experimental + override: saiu pelo caminho de override", 1, len(overrides22))
checar("22. com secao experimental + override: foi pro numero configurado",
       "5521777770000", overrides22[0][0] if overrides22 else None)

corpo_enviado_22 = overrides22[0][1] if overrides22 else ""
checar("22b. corpo carrega aviso de TESTE", True, "TESTE" in corpo_enviado_22)
checar("22c. corpo cita o professor que seria o destinatario real", True,
       "Ana Beatriz" in corpo_enviado_22)
checar("22d. o texto ORIGINAL da cobranca (secao experimental) continua dentro",
       True, "Davi" in corpo_enviado_22)

# ── 23. o log carrega o destino ORIGINAL e o EVENTO, não só "houve override" ─
logs_override_23 = [l for l in logadas22 if l["msg"] == "experimental_override_ativo"]
checar("23. log de override emitido exatamente 1x", 1, len(logs_override_23))
checar("23. log carrega o destino do override", "5521777770000",
       (logs_override_23[0] if logs_override_23 else {}).get("destino_override"))
checar("23. log carrega o destino ORIGINAL (telefone canonico do professor)",
       TELEFONE_CANONICO_PROF_RUN_EVENT,
       (logs_override_23[0] if logs_override_23 else {}).get("destino_original"))
checar("23. log carrega o evento (pendencia)", "pendencia",
       (logs_override_23[0] if logs_override_23 else {}).get("evento"))

# ── 24. a fila fecha do mesmo jeito com override ligado (mark_sent chamado) ─
checar("24. claim reservado normalmente mesmo com override", 1, len(estado22["claims"]))
checar("24. mark_sent chamado (fila fecha, nao fica presa em 'processando')",
       1, len(estado22["marcadas"]))

# ============================================================================
# CASOS 25+ — C1 (revisão 22/08/2026): invariante 4 sem teste, dois mutantes
# vivos 58/58 verde.
#
# A spec diz "mutante vivo = trava sem teste". O CÓDIGO está certo — dois
# ticks seguidos dão 'enviada' e depois 'ja_avisado', com uma entrega só.
# O que faltava era o teste que DISTINGUE isso de um código sem a guarda.
#
# Nenhum dos fakes até o caso 24 exercitava `claimed=False` (o retorno do
# SEGUNDO tick pro MESMO vínculo) nem um `mark_sent` que devolve False — por
# isso os dois mutantes abaixo passavam 58/58. `FakeBackend.rpc` foi
# ajustado (fabio_marcar_notificacao_enviada) pra simular a cerca real da
# 018: corpo sem `p_lease_token` devolve False, nunca True — sem isso o
# mutante "mark_sent(notificacao_id, lease_token) -> mark_sent(notificacao_id)"
# não tinha como ser detectado por NENHUM caso desta bancada, nem os antigos.
# ============================================================================

# ── 25. dois ticks no MESMO FakeBackend = UMA entrega só ──────────────────
# Mata a remoção da guarda `if not claim.get("claimed"): status='ja_avisado';
# continue` (~:241): sem ela, o segundo tick reenviaria a MESMA cobrança —
# e o timer roda de 5 em 5 minutos numa janela de 20, então o professor
# levaria o mesmo lembrete pra sempre, sem erro nenhum no journal.
backend25 = FakeBackend([ALVO_1])
r25_tick1 = rodar(backend25)
r25_tick2 = rodar(backend25)
checar("25. tick 1: enviada", "enviada", r25_tick1["resultados"][0]["status"])
checar("25. tick 2 (mesmo vinculo, mesmo backend): ja_avisado",
       "ja_avisado", r25_tick2["resultados"][0]["status"])
checar("25. EXATAMENTE uma entrega nos dois ticks somados", 1, len(backend25.entregues))
checar("25. os dois ticks tentaram o claim (1 reservou, 1 foi recusado)",
       2, len(backend25.claims))
checar("25. so existe UMA notificacao marcada como enviada", 1,
       len(backend25.marcadas_enviadas))

# ── 26. mark_sent SEM p_lease_token não pode virar 'enviada' mentiroso ────
# Mata a troca `mark_sent(notificacao_id, lease_token)` ->
# `mark_sent(notificacao_id)` (~:264): o claim POR REFERÊNCIA sempre escreve
# lease_token, então chamar mark_sent sem ele não casa com NENHUM lado da
# cerca 018 no banco real — zero linhas afetadas, RPC devolve False, e a
# notificação fica presa em 'processando' com a mensagem JÁ entregue. Pior
# que "preso": a `fabio_claim_notificacao_por_referencia` re-reivindica
# linha em 'processando' com lease vencido (lease de 10min contra janela de
# 20) — SEGUNDA entrega no próximo tick.
backend26 = FakeBackend([ALVO_1], falhar_mark_sent_sempre=True)
r26 = rodar(backend26)
checar("26. RPC de marcar-enviada recusa -> status NAO fecha como 'enviada'",
       "entregue_mas_nao_fechada", r26["resultados"][0]["status"])
checar("26. mesmo sem fechar, a mensagem FOI entregue (nao se perde silenciosamente)",
       1, len(backend26.entregues))

logadas26: list[dict] = []
backend26b = FakeBackend([ALVO_1], falhar_mark_sent_sempre=True)
with patch.object(worker, "rpc", side_effect=backend26b.rpc), \
     patch.object(worker, "deliver", side_effect=backend26b.deliver), \
     patch.object(worker, "enviar_uazapi_direto", side_effect=backend26b.enviar_override), \
     patch.object(worker, "active_professors", return_value=PROFESSORES_FAKE), \
     patch.object(worker, "EXPERIMENTAL_DEST_OVERRIDE", ""), \
     patch.object(worker, "log", side_effect=lambda msg, **f: logadas26.append({"msg": msg, **f})):
    worker.run_experimental_lembrete("whatsapp", dry_run=False)
checar("26b. journal recebe 'notificacao_enviada_mas_nao_fechada' (nao fica calado)",
       True, any(l["msg"] == "notificacao_enviada_mas_nao_fechada" for l in logadas26))

# ── 27. a cerca simulada (018) pega o mutante de verdade: corpo sem token ──
# Prova que o AJUSTE do fake (não só o caso novo) é o que fecha o buraco: se
# o corpo do mark_sent não carregar p_lease_token, a RPC simulada já devolve
# False sozinha — é essa reação que o mutante de código vai acionar quando a
# arena rodar (ver mutantes_trava_experimental_lembrete.py).
backend27 = FakeBackend([ALVO_1])
with patch.object(worker, "rpc", side_effect=backend27.rpc), \
     patch.object(worker, "deliver", side_effect=backend27.deliver), \
     patch.object(worker, "enviar_uazapi_direto", side_effect=backend27.enviar_override), \
     patch.object(worker, "active_professors", return_value=PROFESSORES_FAKE), \
     patch.object(worker, "EXPERIMENTAL_DEST_OVERRIDE", ""):
    # Chama mark_sent diretamente, do jeito que o mutante chamaria: sem token.
    ok_sem_token = worker.mark_sent("notif-x")
    ok_com_token = worker.mark_sent("notif-y", "lease-y")
checar("27. mark_sent SEM lease_token: corpo simulado nao fecha (False)",
       False, ok_sem_token)
checar("27. mark_sent COM lease_token: corpo simulado fecha (True)",
       True, ok_com_token)

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
