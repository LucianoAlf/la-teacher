#!/usr/bin/env python3
"""Fábio notification worker.

Cron-friendly dispatcher for simple recurring notifications:
- morning briefing (briefing_matinal)
- daily class-record pending reminder (pendencia_registro)

This is intentionally NOT a generic job queue. Recurring idempotency lives in
public.fabio_notificacoes via fabio_claim_notificacao/status RPCs.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time as _time

import requests
from dataclasses import dataclass
from datetime import datetime, time as dtime
from typing import Any, Dict, Iterable, Optional
from zoneinfo import ZoneInfo

import fabio_chat_bridge as bridge

BRT = ZoneInfo("America/Sao_Paulo")
DEFAULT_BRIEFING_TIME = os.getenv("FABIO_NOTIFY_BRIEFING_TIME", "08:00")
DEFAULT_PENDENCIA_TIME = os.getenv("FABIO_NOTIFY_PENDENCIA_TIME", "18:30")
# Depois de 3 dias o Fabio PARA de cutucar o professor por aquelas aulas e a
# bola passa pra coordenacao. Desenho do Alfredo em
# docs/2026-07-18-fabio-governanca-presenca-professor-alfredo.md.
ESCALONAMENTO_DIAS = int(os.getenv("FABIO_ESCALONAMENTO_DIAS", "3"))
# Quantos professores levam BLOCO INTEIRO em cada mensagem de unidade. Os
# demais entram numa linha cada, no rodape — ninguem some, o detalhe e que e
# racionado por gravidade. 0 desliga o racionamento (todo mundo com bloco).
ESCALONAMENTO_BLOCOS_POR_UNIDADE = int(os.getenv("FABIO_ESCALONAMENTO_BLOCOS", "8"))
# Abaixo deste tamanho a lista cabe numa mensagem só e não se divide por
# unidade — 4 notificações pra uma lista de 5 professores é cerimônia.
ESCALONAMENTO_MENSAGEM_UNICA_MAX = int(os.getenv("FABIO_ESCALONAMENTO_UNICA_MAX", "6000"))
# COORDENACAO PEDAGOGICA (Marcos Quintela, Juliane, Fabio). Puxado da UAZAPI.
GRUPO_COORDENACAO_JID = os.getenv("FABIO_GRUPO_COORDENACAO_JID", "120363304349910605@g.us")
DEFAULT_ESCALONAMENTO_TIME = os.getenv("FABIO_NOTIFY_ESCALONAMENTO_TIME", "09:00")
DEFAULT_FEEDBACK_TIME = os.getenv("FABIO_NOTIFY_FEEDBACK_TIME", "09:30")
DEFAULT_WINDOW_MINUTES = int(os.getenv("FABIO_NOTIFY_WINDOW_MINUTES", "15"))
DEFAULT_CHANNEL = os.getenv("FABIO_NOTIFY_CHANNEL", "whatsapp")
SEND_EMPTY_BRIEFING = os.getenv("FABIO_NOTIFY_EMPTY_BRIEFING", "false").lower() in {"1", "true", "yes", "sim"}
MAX_PROFESSORS = int(os.getenv("FABIO_NOTIFY_MAX_PROFESSORS", "0"))
REGISTRO_RECIBO_MODE = os.getenv("FABIO_REGISTRO_RECIBO_MODE", "off").strip().lower()
REGISTRO_RECIBO_PILOT_IDS = {
    int(value.strip())
    for value in os.getenv("FABIO_REGISTRO_RECIBO_PILOT_IDS", "").split(",")
    if value.strip().isdigit()
}


@dataclass(frozen=True)
class EventSpec:
    tipo: str
    categoria: str
    target_time: str


EVENTS = {
    "briefing": EventSpec("briefing_matinal", "informativa", DEFAULT_BRIEFING_TIME),
    "pendencia": EventSpec("pendencia_registro", "governanca", DEFAULT_PENDENCIA_TIME),
    "escalonamento": EventSpec("pendencia_escalonada", "governanca", DEFAULT_ESCALONAMENTO_TIME),
    # Só o target_time é lido pra "feedback" (decide is_due em main()). tipo=
    # "feedback_lembrete" e categoria="governanca" aqui NUNCA chegam a
    # claim_notification nem a can_notify com este spec: "feedback" sai de
    # due_events antes do laço que chamaria run_event/claim_notification (ver
    # main()), e run_feedback() compõe o próprio p_tipo como f"feedback_{fase}"
    # (lembrete/reforco/coordenacao) direto nas chamadas a
    # fn_reservar_cobranca_feedback[_coordenacao] — sem passar por aqui. Não
    # renomeie tipo/categoria pensando que isso muda o que sai no WhatsApp.
    "feedback": EventSpec("feedback_lembrete", "governanca", DEFAULT_FEEDBACK_TIME),
}


def log(msg: str, **fields: Any) -> None:
    bridge.log(f"notify_worker_{msg}", **fields)


def parse_hhmm(value: str) -> dtime:
    h, m = str(value).split(":", 1)
    return dtime(hour=int(h), minute=int(m[:2]))


def minutes_of_day(dt: datetime) -> int:
    return dt.hour * 60 + dt.minute


def is_due(now: datetime, target_hhmm: str, window_min: int) -> bool:
    target = parse_hhmm(target_hhmm)
    start = target.hour * 60 + target.minute
    cur = minutes_of_day(now)
    return start <= cur < start + max(1, window_min)


def rpc(name: str, body: Dict[str, Any]) -> Any:
    r = bridge.sb_post(f"/rest/v1/rpc/{name}", body)
    if r.status_code >= 400:
        raise RuntimeError(f"rpc {name} {r.status_code}: {r.text[:500]}")
    if not r.text:
        return None
    return r.json()


def active_professors(professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    """Professores ATIVOS **e com login liberado**.

    O `usuario_id=not.is.null` é o que tira o Fábio do piloto de uma pessoa só.
    Até 08/08/2026 o recorte era `--professor-id 25` cravado em quatro units do
    systemd: pra abrir pra mais gente, alguém teria que lembrar de editar
    arquivo na VPS — e o normal seria não lembrar.

    Agora o recorte é o próprio acesso: liberou no painel, passa a receber
    briefing e cobrança; não liberou, não é cobrado por uma tela que não
    consegue abrir. Cobrar quem não tem como registrar é o jeito mais rápido de
    o professor aprender a ignorar o Fábio.
    """
    params = {
        "select": "id,nome,telefone_whatsapp,ativo",
        "ativo": "eq.true",
        "usuario_id": "not.is.null",
        "order": "id.asc",
    }
    if professor_id is not None:
        params["id"] = f"eq.{int(professor_id)}"
    if MAX_PROFESSORS > 0 and professor_id is None:
        params["limit"] = str(MAX_PROFESSORS)
    rows = bridge.sb_get("/rest/v1/professores", params)
    return rows or []


def first_name(prof: Dict[str, Any], fallback: str = "professor") -> str:
    nome = (prof.get("nome") or "").strip()
    return nome.split()[0] if nome else fallback


def compact_summary(text: str, max_len: int = 115) -> str:
    text = " ".join(str(text or "").split())
    if len(text) <= max_len:
        return text
    return text[: max_len - 1].rstrip() + "…"


def display_student_name(aluno: Dict[str, Any]) -> str:
    first = (aluno.get("primeiro_nome") or "").strip()
    full = " ".join(str(aluno.get("nome") or "").split()).strip()
    if not first:
        return full.split()[0] if full else "Aluno"
    parts = full.split()
    composite_first_names = {"Maria", "Ana", "João", "Jose", "José", "Luiz", "Luís"}
    if len(parts) >= 2 and parts[0].lower() == first.lower() and parts[0] in composite_first_names:
        return f"{parts[0]} {parts[1]}"
    return first


def student_names(alunos: Iterable[Dict[str, Any]], max_names: int = 5) -> str:
    names = []
    for a in alunos or []:
        names.append(display_student_name(a))
    if not names:
        return "aluno(s)"
    if len(names) > max_names:
        names = names[:max_names] + [f"mais {len(names) - max_names}"]
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + " e " + names[-1]


def _format_date_br(value: Any) -> Optional[str]:
    text = str(value or "").strip()
    if not text:
        return None
    # Expected from RPC: YYYY-MM-DD. Keep defensive fallback for already-formatted text.
    try:
        return datetime.fromisoformat(text[:10]).strftime("%d/%m")
    except Exception:
        return text


def _clean_text(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


# --------------------------------------------------------------------------
# Apresentação no WhatsApp. O professor lê isso correndo, de manhã, no celular:
# o nome do aluno tem que saltar, e cada seção tem que ser achável sem ler.
# --------------------------------------------------------------------------

# Rótulos que o Fábio e o Emusys já usam DENTRO de um texto corrido. Quando o
# campo estruturado falta, a RPC cai no texto consolidado inteiro e ele desaba
# num campo só — aconteceu com a Amanda em 03/08, cujo "Trabalho feito" trazia
# "Objetivo: … Conteúdo: … Progresso: …" tudo grudado. Aqui a gente devolve
# esse texto para as seções às quais ele já pertencia.
_ROTULOS = [
    ("objetivo", "foco"),
    ("foco", "foco"),
    ("conteudo", "trabalho_feito"),
    ("conteúdo", "trabalho_feito"),
    ("atividades", "trabalho_feito"),
    ("trabalho feito", "trabalho_feito"),
    ("progresso", "trabalho_feito"),
    ("repertorio", "repertorio"),
    ("repertório", "repertorio"),
    ("musica", "repertorio"),
    ("música", "repertorio"),
    ("dever de casa", "dever_casa"),
    ("proximo passo", "proximo_passo"),
    ("próximo passo", "proximo_passo"),
    ("observacao", "observacao"),
    ("observação", "observacao"),
]
_RE_ROTULO = re.compile(
    r"(?i)(?:^|[\s;.])(" + "|".join(re.escape(r) for r, _ in _ROTULOS) + r")\s*:\s*"
)


def _despejar_em_secoes(texto: str) -> Dict[str, str]:
    """Quebra um texto corrido pelos rótulos que ele mesmo carrega.

    Só age quando encontra 2+ rótulos — com um só, o texto provavelmente É o
    conteúdo daquele campo, e quebrar seria pior que deixar quieto.
    """
    texto = _clean_text(texto)
    achados = list(_RE_ROTULO.finditer(texto))
    if len(achados) < 2:
        return {}
    destino = {rotulo: campo for rotulo, campo in _ROTULOS}
    secoes: Dict[str, str] = {}
    for i, m in enumerate(achados):
        campo = destino.get(m.group(1).lower())
        fim = achados[i + 1].start() if i + 1 < len(achados) else len(texto)
        valor = texto[m.end():fim].strip(" ;,")  # o ponto final fica: é pontuação, não separador
        if not campo or not valor:
            continue
        if campo in secoes:
            anterior = secoes[campo]
            emenda = "" if anterior.endswith((".", "!", "?", ";")) else "."
            secoes[campo] = f"{anterior}{emenda} {valor}".strip()
        else:
            secoes[campo] = valor
    return secoes


_LIMITE_CAMPO = 200


def _encurtar(valor: Any, limite: int = _LIMITE_CAMPO) -> str:
    """Corta em fronteira de frase, ou de palavra. Riqueza de detalhe sim,
    parede de texto não (pedido do Alf: 'resumir sem enxugar muito')."""
    texto = _clean_text(valor)
    if len(texto) <= limite:
        return texto
    corte = texto[:limite]
    frase = max(corte.rfind(". "), corte.rfind("; "))
    if frase > limite * 0.5:
        return corte[: frase + 1].strip()
    espaco = corte.rfind(" ")
    return (corte[:espaco] if espaco > 0 else corte).rstrip(" ,;:") + "…"


# Um relógio por hora: o olho acha o horário antes de ler a linha.
_RELOGIOS = ["🕛", "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚"]


def _relogio(hora: Any) -> str:
    try:
        return _RELOGIOS[int(str(hora).split(":")[0]) % 12]
    except Exception:
        return "🕐"


_CAMPOS = [
    ("foco", "🎯", "Foco"),
    ("trabalho_feito", "✅", "Trabalho feito"),
    ("repertorio", "🎵", "Repertório"),
    ("dever_casa", "🏠", "Dever de casa"),
    ("proximo_passo", "➡️", "Próximo passo"),
    ("observacao", "💬", "Observação"),
]


def _ultima_aula_lines(aluno: Dict[str, Any]) -> list[str]:
    """Bloco de um aluno. O nome vem em negrito, sozinho na linha e com um
    respiro embaixo (pedido do Alf) — antes ele ficava no meio de
    'Aluno(a): fulano' e se perdia na rolagem."""
    cabecalho = [f"👤 *{display_student_name(aluno)}*", ""]
    ultima = aluno.get("ultima_aula") if isinstance(aluno, dict) else None

    if not isinstance(ultima, dict) or not ultima:
        resumo = _encurtar(aluno.get("resumo_ultima_aula") if isinstance(aluno, dict) else "")
        return cabecalho + ([f"✅ *Trabalho feito:* {resumo}"] if resumo
                            else ["_Sem conteúdo registrado da última aula._"])

    dados = {chave: _clean_text(ultima.get(chave)) for chave, _, _ in _CAMPOS}
    for chave in ("trabalho_feito", "foco"):
        secoes = _despejar_em_secoes(dados.get(chave, ""))
        if not secoes:
            continue
        dados[chave] = ""
        for campo, valor in secoes.items():
            if not dados.get(campo):
                dados[campo] = valor

    corpo: list[str] = []
    data_br = _format_date_br(ultima.get("data"))
    if data_br:
        corpo.append(f"_última aula · {data_br}_")
    campos_com_texto = 0
    for chave, emoji, rotulo in _CAMPOS:
        valor = _encurtar(dados.get(chave, ""))
        if valor:
            corpo.append(f"{emoji} *{rotulo}:* {valor}")
            campos_com_texto += 1
    if not campos_com_texto:
        corpo.append("_Sem conteúdo registrado da última aula._")
    return cabecalho + corpo


def _summary_lines_for_class(alunos: list[Dict[str, Any]]) -> list[str]:
    alunos = alunos or []
    if not alunos:
        return ["_Sem alunos na chamada desta aula._"]
    linhas: list[str] = []
    for idx, aluno in enumerate(alunos):
        if idx:
            linhas.append("")
        linhas.extend(_ultima_aula_lines(aluno))
    return linhas


def format_briefing(prof: Dict[str, Any], data: Dict[str, Any]) -> Optional[str]:
    aulas = data.get("aulas") or []
    nome = data.get("primeiro_nome") or first_name(prof)
    if not aulas and not SEND_EMPTY_BRIEFING:
        return None
    if not aulas:
        return None

    total_aulas = int(data.get("total_aulas") or len(aulas))
    total_alunos = int(data.get("total_alunos") or sum(len(a.get("alunos") or []) for a in aulas))
    aula_label = "aula" if total_aulas == 1 else "aulas"
    aluno_label = "aluno" if total_alunos == 1 else "alunos"
    lines = [
        f"Bom dia, {nome}! 🎵",
        "",
        f"Hoje você tem *{total_aulas} {aula_label}* com *{total_alunos} {aluno_label}*.",
        "",
        "📅 *Agenda de hoje*",
    ]
    for aula in aulas:
        hora = aula.get("hora") or "--:--"
        curso = _curso_limpo(aula.get("curso"))
        lines.append("")
        lines.append(f"{_relogio(hora)} *{hora} — {curso}*")
        lines.extend(_summary_lines_for_class(aula.get("alunos") or []))
    lines.append("")
    lines.append("Se quiser preparar alguma aula específica, me manda o nome do aluno.")
    return "\n".join(lines)


def _curso_limpo(nome: Optional[str]) -> str:
    """Tira o sufixo de turma do Emusys ("Canto T" -> "Canto").

    O "T" nao significa nada pra quem le no zap e repete em toda linha.
    """
    txt = (nome or "Aula").strip()
    for suf in (" T", " I", " -"):
        if txt.endswith(suf):
            txt = txt[: -len(suf)].strip()
    return txt or "Aula"


DIAS_PT = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]


def _dia_label(iso: str) -> str:
    """2026-08-04 -> 'terça, 04/08'. Se vier fora do padrão, devolve como veio."""
    try:
        d = datetime.strptime(iso[:10], "%Y-%m-%d").date()
    except Exception:
        return iso
    return f"{DIAS_PT[d.weekday()]}, {d.strftime('%d/%m')}"


def _dias_em_atraso(aula: Dict[str, Any]) -> int:
    """Dias de atraso de UMA aula, do jeito que a RPC devolve.

    A chave canonica e `dias_em_atraso` — conferida em 09/08/2026 nos
    `jsonb_object_keys` da `fabio_pendencias_professor`. Os nomes antigos
    (`dias_atraso`, `atraso_dias`) ficam como rede porque ja estiveram
    espalhados pelo codigo, mas nenhum dos dois existe no payload de hoje.

    Devolve 0 quando nao acha nenhuma — e esse 0 e a razao pela qual o defeito
    passou despercebido: ele nao levanta erro, so faz toda aula parecer de
    hoje. Se um dia a RPC renomear a chave de novo, o sintoma sera silencioso
    de novo; e por isso que a chave certa vem PRIMEIRO e esta documentada aqui.
    """
    for chave in ("dias_em_atraso", "dias_atraso", "atraso_dias"):
        valor = aula.get(chave)
        if valor is not None:
            return int(valor)
    return 0


def format_pendencias(prof: Dict[str, Any], data: Dict[str, Any]) -> Optional[str]:
    """Cobrança do professor.

    Diagramação decidida com o Alf em 05/08/2026: a HORA é a âncora (o professor
    percorre o próprio dia na ordem em que aconteceu), data em pt-BR (ninguém lê
    ISO no zap) e o fecho diz COMO resolver, não que a cobrança vai parar.

    O fecho manda abrir o APP de propósito: o registro por áudio no WhatsApp
    ainda não está ligado, e mandar áudio pro Fabio aqui não registra nada.
    """
    if int(data.get("total_aulas") or 0) <= 0:
        return None
    nome = first_name(prof)
    aulas = data.get("aulas") or []

    # O que passou de ESCALONAMENTO_DIAS nao e mais cobranca do professor: subiu
    # pra coordenacao. Continuar cobrando aqui seria cobrar duas vezes a mesma
    # coisa, em dois lugares, sem ninguem assumir.
    #
    # ⚠️ Este filtro NUNCA filtrou. Ele lia `dias_atraso`/`atraso_dias` e a
    # chave que a `fabio_pendencias_professor` devolve e `dias_em_atraso` —
    # nenhuma das duas existia, `int(None or None or 0)` dava 0, e 0 <= 3
    # sempre. Resultado medido em 09/08/2026: o Rafael era cobrado por aulas
    # de 29/07 (11 dias) que o escalonamento das 9h ja tinha mandado pra
    # coordenacao no mesmo dia. Exatamente a cobranca em dobro que o
    # paragrafo acima diz evitar.
    aulas = [a for a in aulas if _dias_em_atraso(a) <= ESCALONAMENTO_DIAS]
    if not aulas:
        return None

    # Titulo e janela saem do conjunto JA FILTRADO. Antes o cabecalho era
    # montado com o total bruto, entao ele podia anunciar um numero maior do
    # que a lista logo abaixo sustentava — a mesma armadilha da 070, em que a
    # cobranca dizia "50 lancamentos" pra quem tinha 21 aulas.
    total = len(aulas)
    pior = max((_dias_em_atraso(a) for a in aulas), default=0)
    plural = "aula" if total == 1 else "aulas"
    verbo = "ficou" if total == 1 else "ficaram"
    quando = "de ontem" if pior <= 1 else f"dos últimos {pior} dias"
    lines = [f"*{nome}, {verbo} {total} {plural} {quando} sem registro.*"]

    por_dia: Dict[str, list] = {}
    for aula in aulas:
        dia = (aula.get("data") or aula.get("data_aula") or "")[:10]
        por_dia.setdefault(dia, []).append(aula)

    mostradas = 0
    for dia in sorted(por_dia.keys()):
        if mostradas >= 8:
            break
        lines.append("")
        lines.append(_dia_label(dia))
        for aula in sorted(por_dia[dia], key=lambda a: (a.get("hora") or a.get("horario") or "")):
            if mostradas >= 8:
                break
            hora = (aula.get("hora") or aula.get("horario") or "")[:5]
            curso = aula.get("curso") or "Aula"
            alunos = student_names(aula.get("alunos") or [])
            lines.append(f"*{hora}*  {curso} · {alunos}" if hora else f"{curso} · {alunos}")
            mostradas += 1

    if len(aulas) > mostradas:
        lines.append("")
        lines.append(f"e mais {len(aulas) - mostradas}.")

    lines.append("")
    lines.append("É só abrir o app do LA Teacher e mandar o áudio de cada aula "
                 "— eu escrevo o resto. Se preferir, dá pra fechar tudo por lá mesmo.")
    return "\n".join(lines)


def pendencias_escalonadas(professor_id: Optional[int] = None) -> list:
    """Quem passou do prazo de lancar CONTEUDO, agregado no banco.

    Le vw_registro_pendencia (cobravel) pela fn_pendencias_escalonadas (041) —
    a MESMA fonte da cobranca do professor. Presenca nao entra: ela nasce do
    lancamento do conteudo ou da secretaria marcando no Emusys, entao cobrar
    por ela acusava o professor de 18 aulas que ele tinha dado e que estavam
    marcadas. Enquanto as duas mensagens tinham fontes diferentes, elas podiam
    discordar — e discordaram na primeira que foi pro grupo.
    """
    data = rpc("fn_pendencias_escalonadas", {
        "p_dias": ESCALONAMENTO_DIAS,
        "p_professor_id": professor_id,
        "p_max_aulas": int(os.getenv("FABIO_ESCALONAMENTO_MAX_AULAS", "12")),
    })
    if not data:
        return []
    linhas = data.get("linhas") or []
    if professor_id is not None:
        linhas = [l for l in linhas
                  if int(l.get("professor_id") or 0) == int(professor_id)]
    if ESCALONAMENTO_SO_COORTE and professor_id is None:
        linhas = filtrar_coorte(linhas, {int(p["id"]) for p in active_professors()})
    return linhas


ESCALONAMENTO_SO_COORTE = os.getenv(
    "FABIO_ESCALONAMENTO_SO_COORTE", "true").lower() in {"1", "true", "yes", "sim"}


def filtrar_coorte(linhas: list, ids_no_app: set) -> list:
    """Só escala quem o Fábio já cobrou no particular.

    O `active_professors` já recorta a cobrança individual em "ativo E com login
    liberado" — 6 professores em 10/08/2026, de 44 ativos. O escalonamento pro
    grupo NÃO aplicava esse recorte e varria a escola: em 10/08 a coordenação
    recebeu **36 professores** de um sistema que ela ainda não conhece e pra qual
    não tem painel.

    Duas coisas quebravam aí. A primeira é coerência: o mesmo Fábio cobrava 6 no
    particular e denunciava 36 pra coordenação — quem não recebeu aviso nenhum
    aparecia na lista de inadimplentes. A segunda é adoção, e foi o Alf quem
    apontou: pessoa trava com lista longa. Uma governança que estreia pedindo 36
    cobranças recebe "não vou fazer" de resposta, e aí não é a lista que morre, é
    o hábito.

    Cresce sozinho — liberou professor no painel, ele entra na cobrança
    individual E no escalonamento no mesmo dia. Ninguém edita nada.
    """
    return [l for l in linhas if int(l.get("professor_id") or 0) in ids_no_app]


REGUA_ESCALONAMENTO = "━━━━━━━━━━━━━━"


def _nome_professor(row: Dict[str, Any]) -> str:
    return row.get("professor_nome") or f"professor {row.get('professor_id')}"


def _unidade_de_cobranca(row: Dict[str, Any]) -> str:
    """A unidade que fica com o professor quando a mensagem se divide.

    13 dos 36 professores atrasados (medido em 09/08/2026) dao aula em mais de
    uma unidade. Havia duas saidas: FATIAR as aulas do professor por unidade,
    ou mandar o professor INTEIRO pra uma unidade so.

    Fatiar quebra a contagem. A RPC ja corta as aulas em `p_max_aulas` (12), e
    8 professores tem `total_aulas` maior que a lista que vem — depois de
    fatiar nao da pra saber de qual unidade sao as aulas escondidas, e o
    rodape "+N aulas atrasadas" viraria chute. Entao o professor vai inteiro,
    pra unidade onde ele tem MAIS aula parada, e o cabecalho do bloco lista
    todas as unidades dele. Quem encaminha manda a relacao completa; o
    professor recebe uma cobranca, nao tres pela metade.
    """
    contagem: Dict[str, int] = {}
    for a in row.get("aulas") or []:
        u = a.get("unidade")
        if u:
            contagem[u] = contagem.get(u, 0) + 1
    if contagem:
        # Empate resolvido pelo nome da unidade: mesma entrada, mesma saida.
        return sorted(contagem.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    unidades = row.get("unidades") or []
    return unidades[0] if unidades else "Sem unidade"


def _gravidade(row: Dict[str, Any]) -> tuple:
    """Ordem de leitura: mais aula parada primeiro, empate no pior atraso."""
    return (-int(row.get("total_aulas") or 0),
            -int(row.get("pior_atraso") or 0),
            _nome_professor(row).lower())


def _por_unidade(rows: list) -> Dict[str, list]:
    """Agrupa por `_unidade_de_cobranca`, unidade maior primeiro.

    Este agrupamento e a FONTE UNICA da divisao: o indice conta daqui e as
    mensagens saem daqui. Contar "professores que tem aula na unidade" daria
    50 pra 36 professores — dois numeros pra mesma pergunta, que foi
    exatamente o defeito que a 080 consertou na tela do semaforo.
    """
    grupos: Dict[str, list] = {}
    for r in rows:
        grupos.setdefault(_unidade_de_cobranca(r), []).append(r)
    ordem = sorted(grupos, key=lambda u: (-len(grupos[u]), u))
    return {u: sorted(grupos[u], key=_gravidade) for u in ordem}


def _bloco_professor(r: Dict[str, Any]) -> list:
    """O bloco encaminhavel de UM professor — o formato A escolhido pelo Alf.

    Hierarquia com o que o WhatsApp respeita: *negrito* na hora (a ancora),
    _italico_ no aluno (apoio, um nivel abaixo), regua abrindo o bloco de
    cada professor — que e onde a coordenacao vai cortar pra copiar. A linha
    em branco entre aulas impede que os horarios grudem quando a lista de
    alunos quebra em duas linhas no celular.
    """
    unidades = r.get("unidades") or []
    aulas = r.get("aulas") or []
    total = int(r.get("total_aulas") or len(aulas))
    uma_unidade = len(unidades) == 1

    out: list = [REGUA_ESCALONAMENTO]
    # Com mais de uma unidade o cabecalho lista TODAS: quem le precisa saber
    # antes de encaminhar que aquele professor nao e so da unidade dele.
    out.append(f"*{_nome_professor(r)}*"
               + (f" · {', '.join(unidades)}" if unidades else ""))

    por_dia: Dict[str, list] = {}
    for a in aulas:
        por_dia.setdefault((a.get("data_aula") or "")[:10], []).append(a)

    for dia in sorted(por_dia.keys(), reverse=True):
        out.append("")
        out.append(f"*{_dia_label(dia)}*")
        for a in sorted(por_dia[dia], key=lambda x: (x.get("hora") or "")):
            hora = (a.get("hora") or "")[:5]
            curso = _curso_limpo(a.get("curso"))
            if not uma_unidade and a.get("unidade"):
                curso += f" · {a['unidade']}"
            alunos = ", ".join(a.get("alunos") or []) or "sem aluno na lista"
            out.append("")
            out.append(f"*{hora}* · {curso}" if hora else f"· {curso}")
            out.append(f"_{alunos}_")

    if total > len(aulas):
        out.append("")
        out.append(f"_+{total - len(aulas)} aulas atrasadas deste professor_")
    return out


def _plural(n: int, singular: str, plural: str) -> str:
    return f"{n} {singular if n == 1 else plural}"


def format_escalonamento(rows: list, unidade: Optional[str] = None,
                         blocos: Optional[int] = None) -> Optional[str]:
    """UMA mensagem do escalonamento — a de uma unidade, ou a lista inteira.

    Continua no formato A: ENCAMINHAVEL. A coordenacao copia o bloco de um
    professor e manda pra ele, entao vai a relacao completa (dia, hora, curso,
    nome COMPLETO do aluno) e nao um resumo — resumo nao diz a ninguem o que
    fazer.

    O que mudou em 10/08/2026: a mensagem unica tinha 36 professores, 20.951
    caracteres e 1.032 linhas, todo dia as 9h. Ninguem le uma parede dessas, e
    governanca que ninguem le nao e governanca. Agora o detalhe e RACIONADO
    por gravidade — bloco inteiro pros mais atrasados, uma linha pros demais.
    Ninguem some da lista: o que muda e quanto detalhe cada um leva. Corte
    silencioso seria pior que a parede, porque leria como "acabou".
    """
    if not rows:
        return None

    limite = ESCALONAMENTO_BLOCOS_POR_UNIDADE if blocos is None else blocos
    ordenados = sorted(rows, key=_gravidade)
    total_aulas = sum(int(r.get("total_aulas") or 0) for r in ordenados)

    titulo = f"*Registro atrasado · {unidade}*" if unidade else "*Registro atrasado*"
    out: list = [titulo,
                 f"_{_plural(len(ordenados), 'professor', 'professores')}"
                 f" · {_plural(total_aulas, 'aula', 'aulas')}_"]

    detalhados = ordenados if limite <= 0 else ordenados[:limite]
    resto = [] if limite <= 0 else ordenados[limite:]

    for r in detalhados:
        out.extend(_bloco_professor(r))

    if resto:
        out.append(REGUA_ESCALONAMENTO)
        out.append("*Também atrasados* _(menos aulas paradas)_")
        for r in resto:
            n = int(r.get("total_aulas") or 0)
            d = int(r.get("pior_atraso") or 0)
            out.append(f"· {_nome_professor(r)} — {_plural(n, 'aula', 'aulas')},"
                       f" {_plural(d, 'dia', 'dias')}")

    out.append(REGUA_ESCALONAMENTO)
    out.append("Passei do prazo de cobrar no particular. Segue pra encaminhar — "
               "assim que registrar, some daqui.")
    return "\n".join(out)


def format_escalonamento_indice(rows: list, top: int = 5) -> Optional[str]:
    """O cartao de 5 segundos que abre a fila.

    Nao substitui a relacao — abre ela. Quem le as 9h precisa saber, sem
    rolar, se o problema piorou e quem esta pior. A contagem por unidade sai
    do MESMO `_por_unidade` que monta as mensagens seguintes, senao o indice
    promete um numero que a lista nao entrega.
    """
    if not rows:
        return None
    grupos = _por_unidade(rows)
    total_aulas = sum(int(r.get("total_aulas") or 0) for r in rows)

    out: list = ["*Registro atrasado*",
                 f"_{_plural(len(rows), 'professor', 'professores')}"
                 f" · {_plural(total_aulas, 'aula', 'aulas')}_",
                 "",
                 " · ".join(f"{u} {len(linhas)}" for u, linhas in grupos.items()),
                 "",
                 "*Quem está mais atrás*"]
    for r in sorted(rows, key=_gravidade)[:top]:
        n = int(r.get("total_aulas") or 0)
        d = int(r.get("pior_atraso") or 0)
        out.append(f"· {_nome_professor(r)} — {_plural(n, 'aula', 'aulas')},"
                   f" {_plural(d, 'dia', 'dias')}")
    out.append("")
    out.append("Segue a lista por unidade. Cada bloco dá pra copiar e mandar "
               "direto pro professor.")
    return "\n".join(out)


def montar_escalonamento(rows: list) -> list:
    """A fila de mensagens das 9h: indice + uma por unidade.

    Com uma unidade so o indice nao entra — ele existe pra dar rumo a uma fila,
    e uma fila de um item nao precisa de capa.
    """
    if not rows:
        return []

    # Dividir é remédio de parede, não cerimônia. Depois que o escalonamento
    # passou a respeitar a coorte, ele caiu de 36 professores (20.951 chars)
    # pra 5 (2.058) — e mandar índice + 3 unidades pra uma lista que cabe numa
    # tela só é pedir quatro notificações onde bastava uma. Se o texto inteiro
    # couber no limite, vai inteiro.
    unico = format_escalonamento(rows)
    if unico and len(unico) <= ESCALONAMENTO_MENSAGEM_UNICA_MAX:
        return [unico]

    grupos = _por_unidade(rows)
    mensagens: list = []
    if len(grupos) > 1:
        indice = format_escalonamento_indice(rows)
        if indice:
            mensagens.append(indice)
    for unidade, linhas in grupos.items():
        corpo = format_escalonamento(linhas, unidade=unidade)
        if corpo:
            mensagens.append(corpo)
    return mensagens


MESES_PT = ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
            "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]


def _competencia_label(iso: str) -> str:
    """2026-08-01 -> 'agosto/2026'."""
    try:
        d = datetime.strptime(str(iso)[:10], "%Y-%m-%d").date()
    except Exception:
        return str(iso)
    return f"{MESES_PT[d.month - 1]}/{d.year}"


def feedback_cobranca_do_dia(dia: Optional[str] = None) -> Dict[str, Any]:
    return rpc("fn_feedback_cobranca_do_dia", {"p_dia": dia}) or {}


def format_feedback_professor(prof: Dict[str, Any], item: Dict[str, Any], fase: str) -> str:
    """O lembrete carrega QUANTOS FALTAM — a razão X de Y, pedido do Alf — e o
    PORQUÊ. (Docstring corrigida no fix round 1, MINOR 8: dizia PERCENTUAL,
    mas a mensagem sempre renderizou razão, nunca "%" — o texto estava certo,
    a palavra na docstring que mentia.)

    O reforço não repete o porquê: quem chegou até ele já leu uma vez, e
    repetir o discurso inteiro é o jeito rápido de virar ruído.

    Assume fase in ("lembrete", "reforco") — run_feedback já filtrou
    qualquer outra fase antes de chegar aqui (fix round 1, MINOR 14).
    """
    nome = first_name(prof)
    ok = int(item.get("ok") or 0)
    total = int(item.get("total") or 0)
    faltam = int(item.get("faltam") or max(total - ok, 0))

    if fase == "lembrete":
        # ok==0 é o caso do primeiro dia: "você já respondeu 0" lê como
        # cobrança sarcástica, e no lançamento é a mensagem que TODOS os
        # professores recebem (fix round 1, MINOR 6) — abre em vez de cobrar.
        aluno_total = "aluno" if total == 1 else "alunos"
        abertura = (f"São *{total} {aluno_total}* pra responder este mês."
                   if ok == 0 else
                   f"Você já respondeu *{ok} de {total}*.")
        return "\n".join([
            f"*{nome}, é semana do feedback dos alunos.*",
            "",
            abertura,
            "",
            "É com isso que a coordenação enxerga o aluno antes da evasão — "
            "e tem gente chegando na renovação.",
            "",
            "Abre o app em *Alunos* e fecha o mês. Leva poucos minutos.",
        ])

    plural = "aluno" if faltam == 1 else "alunos"
    verbo = "falta" if faltam == 1 else "faltam"
    return "\n".join([
        f"*{nome}, {verbo} {faltam} {plural} no seu feedback do mês.*",
        "",
        f"Você fechou {ok} de {total}.",
        "",
        "Dá pra terminar em poucos minutos pelo app, em *Alunos*.",
    ])


def format_feedback_coordenacao(competencia: str, professores: list,
                                fecharam: int, elegiveis: int) -> Optional[str]:
    """A lista do dia 1º. Cada bloco tem que ser ENCAMINHÁVEL SOZINHO — o
    coordenador copia só aquele bloco e manda pro professor, sem escrever
    nada a mais. Até o fix round 1 (IMPORTANT 5) o bloco só tinha nome,
    unidade e um número: enviado ao próprio professor, virava só o nome dele
    e uma contagem, sem mês nem instrução — quem lia tinha que escrever a
    cobrança de verdade. `format_escalonamento` nunca teve esse problema
    porque os blocos dele já carregam a aula concreta.
    """
    if not professores:
        return None

    mes = _competencia_label(competencia)
    REGUA = "━━━━━━━━━━━━━━"
    out = [f"*Feedback dos alunos — {mes}*",
           f"_{fecharam} de {elegiveis} professores fecharam o mês_"]

    for p in professores:
        nome = p.get("nome") or f"professor {p.get('professor_id')}"
        # Mesmo fallback do `nome` acima, passado pro helper (fix round 2)
        # em vez do default "professor" sem id: sem isso, um professor com
        # `nome` vazio virava um bloco com cabeçalho "*professor 42*" mas
        # fecho "professor, faltou o seu feedback..." — a frase acionável
        # perdia justamente o número que identifica quem é.
        primeiro = first_name(p, fallback=f"professor {p.get('professor_id')}")
        # Junta TODAS as unidades (fix round 1, MINOR 9) — antes só a
        # unidade ÚNICA aparecia (`len(unidades) == 1`), e professor com 2+
        # unidades saía sem nenhuma no bloco.
        unidades = p.get("unidades") or []
        ok = int(p.get("ok") or 0)
        total = int(p.get("total") or 0)
        faltam = int(p.get("faltam") or max(total - ok, 0))
        plural = "aluno" if faltam == 1 else "alunos"
        verbo = "faltou" if faltam == 1 else "faltaram"
        out.append(REGUA)
        out.append(f"*{nome}*" + (f" · {' · '.join(unidades)}" if unidades else ""))
        out.append(f"_{verbo} {faltam} de {total} alunos_")
        # A linha que falta antes do fix: quem recebe o bloco encaminhado
        # precisa do mês, do número e do que fazer, sem precisar ler o
        # cabeçalho do topo (que não viaja se só este bloco for copiado).
        out.append(f"{primeiro}, faltou o seu feedback de {mes} — {faltam} {plural}. "
                   "Dá pra fechar em poucos minutos no app, em *Alunos*.")

    out.append(REGUA)
    # "feedback", não "semáforo" (fix round 1, MINOR 10) — o app só usa a
    # palavra "feedback"; "semáforo" é vocabulário interno que o professor
    # nunca viu.
    out.append("Quem está na lista não fechou o feedback dos alunos no mês. "
               "Dá pra copiar o bloco e mandar direto pro professor.")
    return "\n".join(out)


def run_feedback(channel: str, dry_run: bool,
                 professor_id: Optional[int] = None,
                 dia: Optional[str] = None) -> list[Dict[str, Any]]:
    """RESERVA → envia → CONCLUI, o mesmo desenho da 066.

    Nada é enfileirado para outro processo buscar depois: a fabio_notificacoes
    não tem estado de entrada, então linha reservada e não enviada no mesmo
    ciclo é linha que MENTE que está em voo.

    Cada professor do laço abaixo tem seu try/except PRÓPRIO (fix round 1,
    IMPORTANT 4): antes, o rpc de reserva vivia fora de qualquer try, então
    a falha de UM professor derrubava a função inteira — main() trocava a
    lista de resultados inteira por um único {"status":"error"}, os
    professores já processados antes dele desapareciam do relatório, e os de
    depois nunca eram tentados. Sem retry aqui de propósito: o re-claim já
    vive no banco (076) e o timer agora passa três vezes por dia — ver
    fabio-feedback.systemd.txt.
    """
    resultados: list[Dict[str, Any]] = []
    data = feedback_cobranca_do_dia(dia)
    fase = (data.get("fase") or "nenhuma")
    if fase == "nenhuma":
        return [{"event": "feedback", "status": "fora_da_regua", "dia": data.get("dia")}]
    if fase not in ("lembrete", "reforco", "coordenacao"):
        # Defesa contra o banco devolver uma fase que este worker ainda não
        # conhece: falha explícita e barata aqui, em vez de compor
        # "feedback_<fase desconhecida>" e deixar a RPC de reserva rejeitar
        # com tipo_invalido pra CADA professor do laço (fix round 1, MINOR 14).
        return [{"event": "feedback", "status": "fase_desconhecida", "fase": fase}]

    professores = data.get("professores") or []
    competencia = data.get("competencia")

    # ── Dia 1º: uma mensagem só, pro grupo da coordenação ──────────────────
    if fase == "coordenacao":
        # --professor-id NÃO filtra a lista da coordenação — ela é UMA
        # mensagem pro GRUPO, não por professor; filtrar ainda mandaria a
        # lista INTEIRA pro grupo (fix round 1, IMPORTANT 2). Este repo já
        # registrou o mesmo acidente de classe: fabio-pendencia.systemd.txt
        # prende o escalonamento a --professor-id 25 porque, sem ele, o
        # primeiro disparo levaria 75 professores-unidade pro grupo de uma
        # vez. Recusa alto em vez de filtrar; quem quiser ver o texto usa
        # --dry-run, que já funciona sem tocar no grupo.
        if professor_id is not None:
            return [{"event": "feedback", "fase": fase,
                     "status": "coordenacao_ignora_professor_id"}]
        # `elegiveis` é o total de professores com carteira; a lista traz só
        # quem NÃO fechou, então quem fechou é a diferença.
        elegiveis = int(data.get("elegiveis") or 0)
        fecharam = max(elegiveis - len(professores), 0)
        corpo = format_feedback_coordenacao(competencia, professores, fecharam, elegiveis)
        if not corpo:
            return [{"event": "feedback", "fase": fase, "status": "todos_fecharam"}]
        if dry_run:
            return [{"event": "feedback", "fase": fase, "status": "dry_run_ready",
                     "professores": len(professores), "content_preview": corpo}]
        # Reserva agora DENTRO do mesmo try do envio (fix round 2, residual
        # do IMPORTANT 4 da rodada anterior): eu tinha protegido só o envio e
        # a conclusão, deixando a chamada de reserva exposta — um erro dela
        # escapava de run_feedback inteiro e main() reportava o handler
        # genérico {"status":"error"}, sem a chave `fase` nem o vocabulário
        # de status deste ramo. `nid`/`token` nascem None e só viram algo se
        # a reserva de fato devolver uma linha — mesmo padrão do laço por
        # professor logo abaixo.
        nid, token = None, None
        try:
            reserva = rpc("fn_reservar_cobranca_feedback_coordenacao", {
                "p_corpo": corpo, "p_whatsapp": GRUPO_COORDENACAO_JID, "p_dia": dia,
            }) or {}
            if not reserva.get("reservado"):
                return [{"event": "feedback", "fase": fase, "status": "ja_entregue",
                         "motivo": reserva.get("motivo")}]
            nid, token = reserva.get("notificacao_id"), reserva.get("lease_token")
            enviar_grupo(corpo, evento="feedback_coordenacao")
            resultado_coord: Dict[str, Any] = {"event": "feedback", "fase": fase,
                                               "status": "sent", "professores": len(professores)}
            if not mark_sent(nid, token):
                log("feedback_coordenacao_entregue_mas_nao_fechada", notificacao_id=str(nid))
                # Mesma chave "aviso" do ramo por professor (fix round 1,
                # MINOR 11) — sem isso o JSON dizia "sent" limpo enquanto o
                # journal gritava que a conclusão não fechou.
                resultado_coord["aviso"] = "entregue_mas_nao_fechada"
            return [resultado_coord]
        except Exception as exc:
            if nid is not None:
                try:
                    mark_failed(nid, str(exc), token)
                except Exception as exc2:
                    log("feedback_coordenacao_mark_failed_falhou", notificacao_id=str(nid),
                        error=str(exc2)[:300])
            return [{"event": "feedback", "fase": fase, "status": "failed",
                     "error": str(exc)[:500]}]

    # ── Janela do mês: um por professor ────────────────────────────────────
    if professor_id is not None:
        professores = [p for p in professores
                       if int(p.get("professor_id") or 0) == int(professor_id)]
    if not professores:
        # Sem isso, lista vazia (todo mundo já respondeu, ou o
        # --professor-id pedido não está na régua hoje) devolvia `[]` — e o
        # payload final ficava indistinguível de um bug que não achou nada
        # pra processar (fix round 1, MINOR 12). Coordenação já tinha
        # `todos_fecharam`; escalonamento já tinha `sem_pendencia_escalonada`.
        return [{"event": "feedback", "fase": fase, "status": "nenhum_professor_a_cobrar"}]
    por_id = {int(p["id"]): p for p in active_professors()}

    for item in professores:
        pid = int(item.get("professor_id") or 0)
        resultado: Dict[str, Any] = {"event": "feedback", "fase": fase,
                                     "professor_id": pid, "status": "init"}
        prof = por_id.get(pid)
        if not prof:
            resultado["status"] = "professor_sem_acesso_skip"
            resultados.append(resultado)
            continue
        corpo = format_feedback_professor(prof, item, fase)
        if dry_run:
            resultado["status"] = "dry_run_ready"
            resultado["content_preview"] = corpo
            resultados.append(resultado)
            continue

        # Tudo daqui pra baixo é DESTE professor: reserva, telefone, entrega
        # e conclusão inteiros num try só, pra que a falha de um não derrube
        # o laço e apague quem já foi processado (fix round 1, IMPORTANT 4 —
        # o rpc de reserva vivia fora de qualquer try).
        nid, token = None, None
        try:
            reserva = rpc("fn_reservar_cobranca_feedback", {
                "p_professor_id": pid,
                "p_tipo": f"feedback_{fase}",
                "p_corpo": corpo,
                "p_dia": dia,
            }) or {}
            if not reserva.get("reservado"):
                resultado["status"] = "nao_reservado"
                resultado["motivo"] = reserva.get("motivo")
                resultados.append(resultado)
                continue

            nid, token = reserva.get("notificacao_id"), reserva.get("lease_token")
            # A reserva já devolveu o telefone resolvido; conferir de novo
            # ANTES de entregar em vez de deixar deliver()->send_whatsapp_text
            # refazer o GET (fix round 1, MINOR 13). Não fecha a corrida
            # inteira — entre este check e o envio de fato o telefone ainda
            # pode ser limpo — mas cobre o caso degenerado sem mudar a
            # assinatura de deliver(), que é compartilhada com os outros
            # eventos (briefing, pendência, devolutiva).
            if channel == "whatsapp" and not reserva.get("telefone"):
                raise RuntimeError("telefone_ausente_na_reserva")
            deliver(pid, channel, corpo)
            if not mark_sent(nid, token):
                log("feedback_entregue_mas_nao_fechada",
                    notificacao_id=str(nid), professor_id=pid)
                resultado["aviso"] = "entregue_mas_nao_fechada"
            resultado["status"] = "sent"
        except Exception as exc:
            resultado["status"] = "failed"
            resultado["error"] = str(exc)[:500]
            if nid is not None:
                try:
                    mark_failed(nid, str(exc), token)
                except Exception as exc2:
                    log("feedback_mark_failed_falhou", professor_id=pid,
                        notificacao_id=str(nid), error=str(exc2)[:300])
        resultados.append(resultado)

    return resultados


def enviar_grupo(texto: str, evento: str = "escalonamento") -> Dict[str, Any]:
    """Envia pro grupo da coordenacao pela UAZAPI.

    O caminho normal do worker resolve telefone de PROFESSOR; grupo e um JID e
    nao passa por canonical_phone. Por isso posta direto, com o mesmo token.

    `evento` so entra no LOG. Escalonamento e feedback_coordenacao dividem
    esta funcao (mesmo grupo, mesmo token); sem o parametro, o log gravava
    sempre "escalonamento_enviado" e qualquer contagem por esse nome no
    journal incluia os dois eventos em silencio (fix round 1, IMPORTANT 3 —
    esta casa ja registrou um incidente de contar OCORRENCIA de string em vez
    de EVENTO, e quase decidiu arquitetura errada por causa disso).
    """
    r = requests.post(
        f"{bridge.UAZAPI_URL}/send/text",
        headers={"Content-Type": "application/json", "token": bridge.UAZAPI_TOKEN},
        json={"number": GRUPO_COORDENACAO_JID, "text": texto},
        timeout=30,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"uazapi grupo {r.status_code}: {r.text[:300]}")
    log(f"{evento}_enviado", grupo=GRUPO_COORDENACAO_JID[:18] + "...")
    return {"ok": True}


def build_content(event: str, prof: Dict[str, Any], target_date: Optional[str] = None) -> tuple[Optional[str], Dict[str, Any]]:
    pid = int(prof["id"])
    if event == "briefing":
        body = {"p_professor_id": pid}
        if target_date:
            body["p_data"] = target_date
        data = rpc("fabio_briefing_matinal", body)
        return format_briefing(prof, data or {}), data or {}
    if event == "pendencia":
        data = rpc("fabio_pendencias_professor", {"p_professor_id": pid})
        return format_pendencias(prof, data or {}), data or {}
    raise ValueError(f"unknown event {event}")


def can_notify(pid: int, categoria: str) -> bool:
    return bool(rpc("fn_fabio_pode_notificar", {"p_professor_id": int(pid), "p_categoria": categoria}))


def claim_notification(pid: int, spec: EventSpec, channel: str, content: str, title: str) -> Dict[str, Any]:
    data = rpc("fabio_claim_notificacao", {
        "p_professor_id": int(pid),
        "p_tipo": spec.tipo,
        "p_categoria": spec.categoria,
        "p_canal": channel,
        "p_corpo": content,
        "p_titulo": title,
    })
    return data or {"ok": False, "claimed": False}


def mark_sent(notification_id: str, lease_token: Optional[str] = None) -> bool:
    """Fecha a notificação. Devolve False se a cerca recusou.

    A 018 exige que o token bata: `(p_lease_token is null AND lease_token is
    null) OR (token confere E lease vivo)`. O claim ANTIGO não escreve token,
    então chamar sem token funciona lá. O claim POR REFERÊNCIA escreve — e aí
    chamar sem token não casa com nenhum dos dois lados: zero linhas, e a
    notificação fica presa em `processando` com a mensagem já entregue.
    Aconteceu na primeira oferta real (03/08/2026). Por isso o retorno agora é
    verificado em vez de ignorado.
    """
    corpo: Dict[str, Any] = {"p_notificacao_id": notification_id}
    if lease_token:
        corpo["p_lease_token"] = lease_token
    return bool(rpc("fabio_marcar_notificacao_enviada", corpo))


def mark_failed(notification_id: str, error: str, lease_token: Optional[str] = None) -> bool:
    corpo: Dict[str, Any] = {"p_notificacao_id": notification_id, "p_erro": error[:1000]}
    if lease_token:
        corpo["p_lease_token"] = lease_token
    return bool(rpc("fabio_marcar_notificacao_falhou", corpo))


def deliver(pid: int, channel: str, content: str) -> Any:
    if channel == "whatsapp":
        return bridge.send_whatsapp_text(pid, content)
    if channel == "app":
        return bridge.insert_fabio_response(pid, content, "app")
    raise ValueError(f"unsupported channel: {channel}")


def _recibo_field(row: Dict[str, Any], key: str) -> Any:
    fields = row.get("campos") if isinstance(row.get("campos"), dict) else {}
    return row.get(key) if row.get(key) not in (None, "") else fields.get(key)


def _recibo_presence(row: Dict[str, Any]) -> str:
    value = str(_recibo_field(row, "presenca") or "").strip().lower()
    if value in {"ausente", "faltou", "falta", "nao", "não"}:
        return "❌ Falta"
    if value in {"presente", "veio", "sim", ""}:
        return "✅ Presença" if value else "⚠️ Presença não informada"
    return "⚠️ Presença não informada"


def _recibo_content(row: Dict[str, Any]) -> str:
    fields = row.get("campos") if isinstance(row.get("campos"), dict) else {}
    for value in (
        row.get("texto_consolidado"),
        fields.get("conteudo"),
        fields.get("atividades"),
    ):
        cleaned = _clean_text(value)
        if cleaned:
            return _encurtar(cleaned, 360)
    return ""


def _recibo_student_content(row: Dict[str, Any]) -> str:
    """Renderiza apenas a fatia individual, sem repetir o tronco comum."""
    fields = row.get("campos") if isinstance(row.get("campos"), dict) else {}
    parts = []
    for key, label in (
        ("progresso", "Progresso"),
        ("observacao", "Observação"),
        ("proximo_passo", "Próximo passo"),
        ("repertorio", "Repertório"),
    ):
        cleaned = _clean_text(fields.get(key))
        if cleaned:
            parts.append(f"{label}: {_encurtar(cleaned, 300)}")
    return "\n   ".join(parts)


def _recibo_draft(row: Dict[str, Any]) -> str:
    raw = row.get("devolutiva")
    if raw is None:
        raw = row.get("devolutivas")
    if isinstance(raw, list):
        raw = raw[0] if raw else None
    if isinstance(raw, dict):
        raw = raw.get("texto_normal") or raw.get("texto") or raw.get("corpo")
    return _encurtar(_clean_text(raw), 420)


def format_registro_recibo(registro: Dict[str, Any], titulo: str = "Registro confirmado") -> str:
    """Renderiza o read-back canônico; não inventa campos ausentes."""
    aula = registro.get("aula") if isinstance(registro.get("aula"), dict) else {}
    data = _format_date_br(aula.get("data") or aula.get("data_aula") or aula.get("dia")) or "data não informada"
    hora_raw = _clean_text(aula.get("hora") or aula.get("horario")) or "horário não informado"
    hora = f"{_relogio(hora_raw)} {hora_raw}"
    curso = _clean_text(aula.get("curso") or aula.get("nome") or "Aula")
    turma = _clean_text(aula.get("turma") or aula.get("turma_nome"))
    linhas = [f"✅ {titulo}", f"📚 {curso}{f' • {turma}' if turma else ''}", f"🕒 {data} • {hora}"]

    tronco = registro.get("tronco") if isinstance(registro.get("tronco"), dict) else {}
    comum = _recibo_content(tronco)
    if comum:
        linhas.extend(["", "📖 Conteúdo comum", comum])

    linhas.extend(["", "👥 Por aluno"])
    fatias = registro.get("fatias") if isinstance(registro.get("fatias"), list) else []
    for fatia in fatias:
        if not isinstance(fatia, dict):
            continue
        nome = _clean_text(fatia.get("aluno_nome") or fatia.get("nome") or "Aluno")
        linhas.append(f"👤 *{nome}* — {_recibo_presence(fatia)}")
        conteudo = _recibo_student_content(fatia)
        if conteudo:
            linhas.append(f"   {conteudo}")
        devolutiva = _recibo_draft(fatia)
        if devolutiva:
            linhas.append(f"   📝 Rascunho de devolutiva: {devolutiva}")
    return "\n".join(linhas)


def _transport_receipt(value: Any) -> Optional[str]:
    if isinstance(value, str) and value.strip():
        return value.strip()
    if isinstance(value, dict):
        for key in ("id", "message_id", "messageid", "wa_message_id"):
            candidate = value.get(key)
            if candidate:
                return str(candidate)
        nested = value.get("key")
        if isinstance(nested, dict) and nested.get("id"):
            return str(nested["id"])
    return None


def _concluir_recibo_com_retry(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Retry only the idempotent close, never the WhatsApp send."""
    last_error: Exception | None = None
    for _ in range(2):
        try:
            result = rpc("fabio_concluir_registro_recibo", payload) or {}
            if result.get("ok") is True or result.get("ja_enviado") is True:
                return result
            last_error = RuntimeError(str(result.get("codigo") or "recibo_nao_concluido"))
        except Exception as exc:
            last_error = exc
    raise last_error or RuntimeError("recibo_nao_concluido")


def _registro_recibo_habilitado(professor_id: Optional[int]) -> bool:
    if REGISTRO_RECIBO_MODE == "on":
        return True
    if REGISTRO_RECIBO_MODE == "pilot":
        return professor_id is not None and int(professor_id) in REGISTRO_RECIBO_PILOT_IDS
    return False


def _run_registro_recibos_for_professor(channel: str, dry_run: bool, professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    """Claim, deliver and close receipt outbox items exactly once per lease."""
    if not _registro_recibo_habilitado(professor_id):
        return [{"event": "registro_recibo", "status": "disabled", "claimed": 0, "sent": 0}]
    if dry_run:
        return [{"event": "registro_recibo", "status": "dry_run_skipped", "reason": "claim cria lease"}]
    claim_payload: Dict[str, Any] = {"p_limite": 20}
    if professor_id is not None:
        claim_payload["p_professor_id"] = int(professor_id)
    claim = rpc("fabio_claim_registro_recibo", claim_payload) or {}
    if isinstance(claim, list):
        claim = claim[0] if claim and isinstance(claim[0], dict) else {}
    if claim.get("ok") is False:
        return [{"event": "registro_recibo", "status": "claim_failed", "error": str(claim.get("codigo") or "claim_falhou")[:500]}]

    lease_token = claim.get("lease_token")
    itens = claim.get("itens") if isinstance(claim.get("itens"), list) else []
    resultados: list[Dict[str, Any]] = []
    for item in itens:
        if not isinstance(item, dict):
            continue
        pid = int(item.get("professor_id") or professor_id or 0)
        registro_id = item.get("registro_id")
        notificacao_id = item.get("notificacao_id")
        resultado: Dict[str, Any] = {
            "event": "registro_recibo",
            "professor_id": pid,
            "registro_id": registro_id,
            "notificacao_id": notificacao_id,
            "status": "init",
        }
        if not pid or not registro_id or not notificacao_id or not lease_token:
            resultado.update(status="failed", error="claim_incompleto")
            resultados.append(resultado)
            continue
        entregue = False
        try:
            registro = rpc("fabio_registro_recibo_dados", {
                "p_professor_id": pid,
                "p_registro_id": registro_id,
            }) or {}
            if isinstance(registro, list):
                registro = registro[0] if registro and isinstance(registro[0], dict) else {}
            if not registro or registro.get("ok") is False:
                raise RuntimeError("registro_completo_indisponivel")
            devolutivas = registro.get("devolutivas") if isinstance(registro.get("devolutivas"), list) else []
            por_fatia = {
                str(item.get("registro_fatia_id")): item
                for item in devolutivas
                if isinstance(item, dict) and item.get("registro_fatia_id")
            }
            for fatia in registro.get("fatias") if isinstance(registro.get("fatias"), list) else []:
                if isinstance(fatia, dict) and not fatia.get("devolutiva"):
                    fatia_devolutiva = por_fatia.get(str(fatia.get("id")))
                    if fatia_devolutiva:
                        fatia["devolutiva"] = fatia_devolutiva
            corpo = format_registro_recibo(registro, str(item.get("titulo") or "Registro confirmado"))
            resposta_transporte = deliver(pid, channel, corpo)
            entregue = True
            envio = _transport_receipt(resposta_transporte)
            if not envio:
                raise RuntimeError("recibo_transporte_sem_id")
            concluido = _concluir_recibo_com_retry({
                "p_notificacao_id": notificacao_id,
                "p_lease_token": lease_token,
                "p_envio_recibo": envio,
                "p_corpo": corpo,
            })
            resultado.update(status="sent", envio_recibo=envio)
        except Exception as exc:
            if entregue:
                log("registro_recibo_entregue_mas_nao_fechado", professor_id=pid,
                    notificacao_id=str(notificacao_id), error=str(exc)[:300])
                resultado.update(status="delivered_unclosed", error=str(exc)[:500])
                resultados.append(resultado)
                continue
            try:
                rpc("fabio_falhar_registro_recibo", {
                    "p_notificacao_id": notificacao_id,
                    "p_lease_token": lease_token,
                    "p_erro": str(exc)[:1000],
                })
            except Exception as failure_exc:
                log("registro_recibo_falha_nao_carimbada", professor_id=pid,
                    notificacao_id=str(notificacao_id), error=str(failure_exc)[:300])
            finally:
                resultado.update(status="failed", error=str(exc)[:500])
        resultados.append(resultado)
    return resultados


def run_registro_recibos(channel: str, dry_run: bool, professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    """Run the receipt worker for one target or every explicitly allowlisted pilot."""
    if REGISTRO_RECIBO_MODE == "off":
        return [{"event": "registro_recibo", "status": "disabled", "claimed": 0, "sent": 0}]
    if REGISTRO_RECIBO_MODE == "pilot":
        if professor_id is not None:
            targets = [int(professor_id)] if int(professor_id) in REGISTRO_RECIBO_PILOT_IDS else []
        else:
            targets = sorted(REGISTRO_RECIBO_PILOT_IDS)
    else:
        targets = [professor_id]
    if not targets:
        return [{"event": "registro_recibo", "status": "disabled", "claimed": 0, "sent": 0}]

    resultados: list[Dict[str, Any]] = []
    for target in targets:
        resultados.extend(_run_registro_recibos_for_professor(channel, dry_run, target))
    return resultados


def run_event(event: str, prof: Dict[str, Any], channel: str, dry_run: bool, target_date: Optional[str] = None) -> Dict[str, Any]:
    spec = EVENTS[event]
    pid = int(prof["id"])
    result = {"professor_id": pid, "event": event, "tipo": spec.tipo, "status": "init"}
    preferences_allowed = can_notify(pid, spec.categoria)
    result["preferences_allowed"] = preferences_allowed
    if not preferences_allowed and not dry_run:
        result["status"] = "blocked_by_preferences"
        return result
    content, raw = build_content(event, prof, target_date=target_date)
    result["raw_totals"] = {k: raw.get(k) for k in ("total_aulas", "total_alunos", "pior_atraso_dias") if isinstance(raw, dict) and k in raw}
    if not content:
        result["status"] = "empty_skip"
        return result
    result["content_preview"] = content
    if dry_run:
        result["status"] = "dry_run_ready"
        return result
    title = "Briefing matinal" if event == "briefing" else "Pendência de registro"
    claim = claim_notification(pid, spec, channel, content, title)
    result["claim"] = claim
    if not claim.get("claimed"):
        result["status"] = "already_claimed_or_sent"
        return result
    notification_id = claim.get("notificacao_id")
    try:
        deliver(pid, channel, content)
        mark_sent(notification_id)
        result["status"] = "sent"
    except Exception as exc:
        try:
            mark_failed(notification_id, str(exc))
        finally:
            result["status"] = "failed"
            result["error"] = str(exc)[:500]
    return result


# ─────────────────────────────────────────────────────────────────────────────
# Devolutiva pronta — o único evento que NÃO tem hora marcada.
#
# briefing e pendência disparam por relógio (is_due(agora, "08:00", janela)).
# A devolutiva fica pronta quando o professor confirma o registro, a qualquer
# hora do dia. Por isso ela é uma varredura de fila e passa longe do is_due.
#
# A trava contra oferecer duas vezes é dupla, de propósito:
#   1. fabio_claim_notificacao_por_referencia (018) — índice único parcial na
#      referência devolutiva:<id>. Dois workers no mesmo ciclo: só um reivindica.
#   2. fabio_devolutiva_oferecida (023) — carimba oferecida_em movendo
#      gerada -> oferecida, e devolve ok=false se alguém chegou antes.
# O timer roda de 5 em 5 minutos; sem isso o professor levaria a mesma
# mensagem a cada ciclo, pra sempre.


def devolutivas_a_oferecer(limite: int = 50) -> list[Dict[str, Any]]:
    data = rpc("fabio_devolutivas_a_oferecer", {"p_limite": int(limite)})
    return data if isinstance(data, list) else []


def format_oferta_devolutiva(prof: Dict[str, Any], devolutivas: list[Dict[str, Any]]) -> str:
    """Monta o aviso. NÃO carrega o texto da devolutiva.

    A RPC nem devolve texto_normal — o professor lê e edita no app, onde ele
    vê o que vai sair antes de mandar. Despejar o texto aqui faria a versão do
    WhatsApp virar a versão real, sem passagem pela tela de revisão.
    """
    nome = first_name(prof)
    quantas = len(devolutivas)
    plural = "as devolutivas" if quantas > 1 else "a devolutiva"
    aulas = f"*{quantas} aulas*" if quantas > 1 else "*1 aula*"

    linhas = [f"Oi, {nome}! 🎵", "", f"Escrevi {plural} de {aulas} de hoje:", ""]
    for d in devolutivas:
        aluno = (d.get("aluno_nome") or "Aluno").strip()
        para = (d.get("destinatario_nome") or "").strip()
        if para:
            linhas.append(f"👤 *{aluno}* → para {para}")
        else:
            linhas.append(f"👤 *{aluno}*")
    linhas += [
        "",
        "Abre o app em *Devolutivas* pra ler, ajustar o que quiser e compartilhar.",
        "",
        "Eu escrevi, mas quem manda é você. 😉",
    ]
    return "\n".join(linhas)


DIAS_AGUARDANDO = int(os.getenv("FABIO_DEVOLUTIVA_DIAS_AGUARDANDO", "7"))
DIAS_ENTREGA_INCERTA = int(os.getenv("FABIO_DEVOLUTIVA_DIAS_ENTREGA_INCERTA", "3"))


def manutencao_devolutivas() -> Dict[str, int]:
    """Fecha os dois becos antes de varrer a fila.

    As RPCs da 025 existem; se ninguém as chamar, os dois estados voltam a ser
    becos sem saída — que é exatamente o defeito que a 025 veio consertar. Já
    aconteceu três vezes neste projeto (gancho da 020, ceifar_travadas da
    020e, timer da oferta): função pronta, chamador nenhum, silêncio total.
    """
    resumo = {"expiradas": 0, "incertas": 0}
    try:
        resumo["expiradas"] = int(rpc("fabio_devolutiva_expirar_aguardando",
                                      {"p_dias": DIAS_AGUARDANDO}) or 0)
    except Exception as exc:
        log("devolutiva_expirar_falhou", error=str(exc)[:300])
    try:
        resumo["incertas"] = int(rpc("fabio_devolutiva_marcar_entrega_incerta",
                                     {"p_dias": DIAS_ENTREGA_INCERTA}) or 0)
    except Exception as exc:
        log("devolutiva_entrega_incerta_falhou", error=str(exc)[:300])
    if resumo["expiradas"] or resumo["incertas"]:
        log("devolutiva_manutencao", **resumo)
    return resumo


def run_devolutivas(channel: str, dry_run: bool, professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    spec_tipo, spec_categoria = "devolutiva_pronta", "informativa"
    resultados: list[Dict[str, Any]] = []

    if not dry_run:
        manutencao_devolutivas()

    grupos = devolutivas_a_oferecer()
    if professor_id is not None:
        grupos = [g for g in grupos if int(g.get("professor_id") or 0) == int(professor_id)]
    if not grupos:
        return resultados

    por_id = {int(p["id"]): p for p in active_professors()}

    for grupo in grupos:
        pid = int(grupo.get("professor_id") or 0)
        devolutivas = grupo.get("devolutivas") or []
        resultado: Dict[str, Any] = {
            "professor_id": pid, "event": "devolutiva", "tipo": spec_tipo,
            "quantas": len(devolutivas), "status": "init",
        }
        prof = por_id.get(pid)
        if not prof:
            resultado["status"] = "professor_inativo_skip"
            resultados.append(resultado)
            continue
        if channel == "whatsapp" and not bridge.canonical_phone(prof.get("telefone_whatsapp") or ""):
            resultado["status"] = "missing_phone_skip"
            resultados.append(resultado)
            continue
        if not can_notify(pid, spec_categoria) and not dry_run:
            resultado["status"] = "blocked_by_preferences"
            resultados.append(resultado)
            continue

        corpo = format_oferta_devolutiva(prof, devolutivas)
        if dry_run:
            resultado["status"] = "dry_run_ready"
            resultado["content_preview"] = corpo
            resultados.append(resultado)
            continue

        # A referência é a PRIMEIRA devolutiva do lote. Um aviso cobre várias,
        # mas cada uma é carimbada individualmente logo abaixo — quem entrar na
        # fila depois deste envio vira o lote do próximo ciclo.
        referencia_id = str(devolutivas[0]["id"])
        claim = rpc("fabio_claim_notificacao_por_referencia", {
            "p_professor_id": pid,
            "p_tipo": spec_tipo,
            "p_categoria": spec_categoria,
            "p_canal": channel,
            "p_corpo": corpo,
            "p_referencia_tipo": "devolutiva",
            "p_referencia_id": referencia_id,
            "p_titulo": "Devolutiva pronta",
            "p_lease_minutos": 10,
        }) or {}
        if not claim.get("claimed"):
            resultado["status"] = "already_claimed_or_sent"
            resultados.append(resultado)
            continue

        notificacao_id = claim.get("notificacao_id")
        lease_token = claim.get("lease_token")
        try:
            deliver(pid, channel, corpo)
            if not mark_sent(notificacao_id, lease_token):
                # A mensagem JÁ foi entregue. Não dá pra desfazer, mas o
                # registro tem que dizer isso alto — senão a casa acha que
                # nada saiu.
                log("notificacao_enviada_mas_nao_fechada",
                    notificacao_id=str(notificacao_id), professor_id=pid)
                resultado["aviso"] = "entregue_mas_nao_fechada"
        except Exception as exc:
            try:
                mark_failed(notificacao_id, str(exc), lease_token)
            finally:
                resultado["status"] = "failed"
                resultado["error"] = str(exc)[:500]
            resultados.append(resultado)
            continue

        # Enviou: carimba cada devolutiva do lote. Se o carimbo falhar, a
        # devolutiva volta na próxima varredura — o claim por referência é que
        # impede o professor de receber o aviso repetido.
        carimbadas = 0
        for d in devolutivas:
            try:
                if (rpc("fabio_devolutiva_oferecida", {
                    "p_id": str(d["id"]),
                    "p_notificacao_id": notificacao_id,
                }) or {}).get("ok"):
                    carimbadas += 1
            except Exception as exc:
                log("devolutiva_carimbo_falhou", devolutiva_id=str(d.get("id")), error=str(exc)[:300])
        resultado["status"] = "sent"
        resultado["carimbadas"] = carimbadas
        resultados.append(resultado)

    return resultados


# ─────────────────────────────────────────────────────────────────────────────
# Aula sem aluno — o professor gravou e o registro não tinha em quem entrar.
#
# O normalizador recusa CERTO: sem roster não dá pra fatiar por aluno sem
# inventar gente. O defeito era o silêncio depois disso — a linha ia pra
# erro_terminal e o professor nunca soube que o trabalho dele sumiu. Medido em
# 15/08: 1 áudio em 30 dias (prof 35, G_Seg_17/CG), sobre 92 aulas âncora sem
# nenhum aluno no roster. Pouco áudio, mas 100% de perda silenciosa.
#
# Duas metades, e a segunda é o que torna a primeira honesta:
#   1. avisar — com o motivo certo: não é o professor, é a turma vazia lá;
#   2. CUMPRIR a promessa do aviso — `fn_fila_audio_retomar_por_roster` religa
#      o áudio quando a secretaria lança os alunos. Roda ANTES da varredura,
#      pelo mesmo motivo de `manutencao_devolutivas`: função pronta sem
#      chamador é o erro que este arquivo já viu três vezes.


def retomar_sem_roster() -> int:
    try:
        return int(rpc("fn_fila_audio_retomar_por_roster", {"p_limite": 20}) or 0)
    except Exception as exc:
        log("sem_roster_retomada_falhou", error=str(exc)[:300])
        return 0


SEM_ROSTER_DIAS = int(os.getenv("FABIO_SEM_ROSTER_DIAS", "7"))
SEM_ROSTER_GRACE_MIN = int(os.getenv("FABIO_SEM_ROSTER_GRACE_MIN", "30"))


def format_aviso_sem_roster(prof: Dict[str, Any], item: Dict[str, Any]) -> str:
    curso = (item.get("curso_nome") or "aula").strip()
    turma = (item.get("turma_nome") or "").strip()
    titulo = f"{curso} — {turma}" if turma else curso

    quando = str(item.get("inicio_brt") or "")
    # A RPC devolve timestamp sem fuso, já em BRT. Formato curto: o professor
    # precisa reconhecer QUAL aula, não ler um ISO.
    try:
        momento = datetime.fromisoformat(quando.replace(" ", "T")[:19])
        quando_texto = momento.strftime("%d/%m às %Hh%M").replace("h00", "h")
    except Exception:  # noqa: BLE001
        quando_texto = quando or "há alguns dias"

    return "\n".join([
        f"Oi, {first_name(prof)}! 🎵",
        "",
        f"Recebi seu áudio de *{titulo}*, de *{quando_texto}*, mas não consegui "
        "gravar o registro: no sistema essa aula está *sem nenhum aluno*.",
        "",
        "Não é você. Sem aluno na turma eu não tenho em quem lançar o conteúdo — "
        "e eu não invento aluno.",
        "",
        "*Seu áudio está guardado.* Assim que a secretaria lançar os alunos "
        "dessa turma, eu processo sozinho e te aviso.",
        "",
        "Se achar que é engano, fala com a secretaria da unidade. 😉",
    ])


def run_sem_roster(channel: str, dry_run: bool, professor_id: Optional[int] = None) -> list[Dict[str, Any]]:
    spec_tipo, spec_categoria = "registro_sem_roster", "informativa"
    resultados: list[Dict[str, Any]] = []

    if not dry_run:
        religados = retomar_sem_roster()
        if religados:
            log("sem_roster_religados", quantos=religados)
            resultados.append({"event": "sem_roster", "status": "religados", "quantos": religados})

    try:
        pendentes = rpc("fabio_fila_sem_roster_a_avisar", {
            "p_limite": 20,
            "p_grace_minutos": SEM_ROSTER_GRACE_MIN,
            "p_dias": SEM_ROSTER_DIAS,
        }) or []
    except Exception as exc:
        return resultados + [{"event": "sem_roster", "status": "error", "error": str(exc)[:500]}]

    if professor_id is not None:
        pendentes = [p for p in pendentes if int(p.get("professor_id") or 0) == int(professor_id)]
    if not pendentes:
        return resultados

    por_id = {int(p["id"]): p for p in active_professors()}

    for item in pendentes:
        pid = int(item.get("professor_id") or 0)
        resultado: Dict[str, Any] = {
            "professor_id": pid, "event": "sem_roster", "tipo": spec_tipo,
            "fila_id": str(item.get("fila_id")), "status": "init",
        }
        prof = por_id.get(pid)
        if not prof:
            resultado["status"] = "professor_inativo_skip"
            resultados.append(resultado)
            continue
        if channel == "whatsapp" and not bridge.canonical_phone(prof.get("telefone_whatsapp") or ""):
            resultado["status"] = "missing_phone_skip"
            resultados.append(resultado)
            continue
        if not can_notify(pid, spec_categoria) and not dry_run:
            resultado["status"] = "blocked_by_preferences"
            resultados.append(resultado)
            continue

        corpo = format_aviso_sem_roster(prof, item)
        if dry_run:
            resultado["status"] = "dry_run_ready"
            resultado["content_preview"] = corpo
            resultados.append(resultado)
            continue

        claim = rpc("fabio_claim_notificacao_por_referencia", {
            "p_professor_id": pid,
            "p_tipo": spec_tipo,
            "p_categoria": spec_categoria,
            "p_canal": channel,
            "p_corpo": corpo,
            # A referência é a LINHA DA FILA, não a aula: é ela que a retomada
            # procura depois pra saber onde a promessa foi feita.
            "p_referencia_tipo": "fila_audio_sem_roster",
            "p_referencia_id": str(item["fila_id"]),
            "p_titulo": "Aula sem aluno no sistema",
            "p_lease_minutos": 10,
        }) or {}
        if not claim.get("claimed"):
            resultado["status"] = "already_claimed_or_sent"
            resultados.append(resultado)
            continue

        notificacao_id = claim.get("notificacao_id")
        lease_token = claim.get("lease_token")
        try:
            deliver(pid, channel, corpo)
            if not mark_sent(notificacao_id, lease_token):
                log("notificacao_enviada_mas_nao_fechada",
                    notificacao_id=str(notificacao_id), professor_id=pid)
                resultado["aviso"] = "entregue_mas_nao_fechada"
            resultado["status"] = "sent"
        except Exception as exc:
            try:
                mark_failed(notificacao_id, str(exc), lease_token)
            finally:
                resultado["status"] = "failed"
                resultado["error"] = str(exc)[:500]
        resultados.append(resultado)

    return resultados


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", choices=["briefing", "pendencia", "devolutiva", "registro_recibo", "registro-recibo", "sem_roster", "sem-roster", "escalonamento", "feedback", "all"], default="all")
    parser.add_argument("--professor-id", type=int)
    parser.add_argument("--channel", choices=["whatsapp", "app"], default=DEFAULT_CHANNEL)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true", help="ignore time window")
    parser.add_argument("--window-minutes", type=int, default=DEFAULT_WINDOW_MINUTES)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--date", help=(
        "BRT date YYYY-MM-DD. Feeds briefing's p_data, but ALSO reaches "
        "--event feedback as p_dia (run_feedback -> fn_feedback_cobranca_do_dia "
        "-> fn_reservar_cobranca_feedback[_coordenacao]), which sets "
        "dia_referencia — the feedback dedupe key. Debugging with "
        "'--event feedback --date YYYY-MM-DD' WITHOUT --dry-run reserves and "
        "sends a REAL WhatsApp message dated for that day. Defaults to today."))
    args = parser.parse_args()
    if args.event == "registro-recibo":
        args.event = "registro_recibo"
    if args.event == "sem-roster":
        args.event = "sem_roster"

    now = datetime.now(BRT)
    target_date = args.date or now.date().isoformat()
    selected = ["briefing", "pendencia", "devolutiva"] if args.event == "all" else [args.event]

    results = []

    if "registro_recibo" in selected:
        try:
            recibo_results = run_registro_recibos(args.channel, args.dry_run, args.professor_id)
        except Exception as exc:
            recibo_results = [{"event": "registro_recibo", "status": "error", "error": str(exc)[:500]}]
        for r in recibo_results:
            log("event_result", **r)
        results.extend(recibo_results)
        if args.event == "registro_recibo":
            payload = {"ok": True, "results": results}
            print(json.dumps(payload, ensure_ascii=False) if args.json else payload)
            return 0

    # Aula sem aluno: varredura de fila, sem hora marcada — como a devolutiva.
    # Fica FORA do "all" de propósito: tem timer próprio (fabio-sem-roster), e
    # entrar no "all" faria a rodada do briefing das 8h cobrar a secretaria
    # junto, misturando duas conversas.
    if "sem_roster" in selected:
        try:
            sem_roster_results = run_sem_roster(args.channel, args.dry_run, args.professor_id)
        except Exception as exc:
            sem_roster_results = [{"event": "sem_roster", "status": "error", "error": str(exc)[:500]}]
        for r in sem_roster_results:
            log("event_result", **r)
        results.extend(sem_roster_results)
        if args.event == "sem_roster":
            payload = {"ok": True, "results": results}
            print(json.dumps(payload, ensure_ascii=False) if args.json else payload)
            return 0

    # A devolutiva sai da lógica de horário: varre a fila sempre que rodar.
    if "devolutiva" in selected:
        try:
            devolutiva_results = run_devolutivas(args.channel, args.dry_run, args.professor_id)
        except Exception as exc:
            devolutiva_results = [{"event": "devolutiva", "status": "error", "error": str(exc)[:500]}]
        for r in devolutiva_results:
            log("event_result", **r)
        results.extend(devolutiva_results)

    por_relogio = [e for e in selected if e in EVENTS]
    due_events = []
    for event in por_relogio:
        spec = EVENTS[event]
        if args.force or is_due(now, spec.target_time, args.window_minutes):
            due_events.append(event)
    if not due_events and not results:
        payload = {"ok": True, "status": "nothing_due", "now_brt": now.isoformat(), "events_checked": selected}
        print(json.dumps(payload, ensure_ascii=False) if args.json else payload)
        return 0

    # O escalonamento NAO e por professor: e uma mensagem so, pro grupo da
    # coordenacao, agregando todo mundo que passou do prazo. Por isso sai do
    # laco de professores — se ficasse dentro, o grupo levaria uma mensagem
    # por professor.
    if "escalonamento" in due_events:
        due_events = [e for e in due_events if e != "escalonamento"]
        enviadas = 0
        try:
            linhas = pendencias_escalonadas(args.professor_id)
            mensagens = montar_escalonamento(linhas)
            professores = len({r.get("professor_id") for r in linhas})
            if not mensagens:
                results.append({"event": "escalonamento", "status": "sem_pendencia_escalonada"})
            elif args.dry_run:
                results.append({"event": "escalonamento", "status": "dry_run_ready",
                                "professores": professores,
                                "mensagens": len(mensagens),
                                "content_preview": "\n\n>>> PRÓXIMA MENSAGEM >>>\n\n".join(mensagens)})
            else:
                for i, corpo in enumerate(mensagens):
                    # O grupo recebe indice e unidades EM ORDEM. Enviar em
                    # rajada deixa a ordem por conta do WhatsApp, e indice que
                    # chega depois do corpo nao serve de indice.
                    if i:
                        _time.sleep(1.2)
                    enviar_grupo(corpo)
                    enviadas += 1
                results.append({"event": "escalonamento", "status": "sent",
                                "professores": professores,
                                "mensagens": enviadas})
        except Exception as exc:
            # `enviadas` conta o que JA foi pro grupo: falhar na 3ª de 4 nao é
            # o mesmo que não ter enviado nada, e o log tem que saber a
            # diferença antes de alguém decidir reenviar.
            results.append({"event": "escalonamento", "status": "error",
                            "enviadas": enviadas, "error": str(exc)[:500]})
        log("event_result", **results[-1])

    if "feedback" in due_events:
        due_events = [e for e in due_events if e != "feedback"]
        try:
            feedback_results = run_feedback(args.channel, args.dry_run,
                                            args.professor_id, args.date)
        except Exception as exc:
            feedback_results = [{"event": "feedback", "status": "error",
                                 "error": str(exc)[:500]}]
        for r in feedback_results:
            log("event_result", **r)
        results.extend(feedback_results)

    rows = active_professors(args.professor_id) if due_events else []
    for prof in rows:
        # WhatsApp delivery needs a phone. App delivery can work without phone.
        if args.channel == "whatsapp" and not bridge.canonical_phone(prof.get("telefone_whatsapp") or ""):
            results.append({"professor_id": prof.get("id"), "status": "missing_phone_skip"})
            continue
        for event in due_events:
            try:
                res = run_event(event, prof, args.channel, args.dry_run, target_date=target_date)
            except Exception as exc:
                res = {"professor_id": prof.get("id"), "event": event, "status": "error", "error": str(exc)[:500]}
            results.append(res)
            log("event_result", **res)

    summary = {}
    for r in results:
        summary[r.get("status", "unknown")] = summary.get(r.get("status", "unknown"), 0) + 1
    payload = {"ok": True, "dry_run": args.dry_run, "now_brt": now.isoformat(), "target_date": target_date, "due_events": due_events, "summary": summary, "results": results}
    print(json.dumps(payload, ensure_ascii=False, indent=2) if args.json else payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
