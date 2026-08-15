#!/usr/bin/env python3
"""Closed, side-effect-free contracts for the WhatsApp action bridge.

This module deliberately does not call Hermes, Supabase or UAZAPI.  It can
rank evidence, but it never turns a guess into a database write authority.
"""
from __future__ import annotations

import json
import re
import unicodedata
from datetime import date
from typing import Any, Literal

AudioIntent = Literal["registro", "conversa", "ambiguo"]
TextIntent = Literal["chamada", "conversa", "ambiguo"]

_AUDIO_INTENTS = {"registro", "conversa", "ambiguo"}
_TEXT_INTENTS = {"chamada", "conversa", "ambiguo"}
_AFFIRMATIVE = {
    "sim", "s", "pode", "confirmo", "confirmado", "confirma", "manda",
    "vamos", "ok", "okay", "certo", "isso", "isso mesmo", "pode gravar",
}
_CANCEL_WORDS = ("cancela", "cancelar", "cancele", "deixa pra la", "deixa isso", "esquece")
_DEFER_WORDS = ("depois", "mais tarde", "outra hora", "amanha", "amanhã")
_PRESENCE_WORDS = (
    "presenca", "presença", "chamada", "presente", "presentes", "veio", "vieram",
    "faltou", "faltaram", "ausente", "ausentes", "nao veio", "não veio",
)
_CONTENT_WORDS = (
    "trabalhei", "trabalhamos", "fizemos", "atividade", "exercicio", "exercício",
    "conteudo", "conteúdo", "objetivo", "repertorio", "repertório", "tecnica",
    "técnica", "respiracao", "respiração", "registro", "aula de", "estudamos",
)
_CONVERSATION_WORDS = (
    "oi", "ola", "olá", "como", "como foi", "agenda", "quem e", "quem é", "obrigado",
    "valeu", "me ajuda", "pode me ajudar", "qual", "quando", "onde",
)
_TEXTUAL_FIELDS = {
    "objetivo", "materiais", "repertorio", "marco_ref", "anotacao_pedagogica",
    "devolutiva_familia", "proximos_passos", "leitura_de_conversao",
}
_ALLOWED_FIELDS = _TEXTUAL_FIELDS | {"presenca"}
_EXPLICIT_TIME_RE = re.compile(
    r"\b([01]?\d|2[0-3])(?:\s*(?:h|horas?)|:)(?:\s*([0-5]\d))?(?!\s*\d)\b"
)
_TIME_MARKED_NUMBER_RE = re.compile(
    r"\b([01]?\d|2[0-3])(?:\s*(?:h|horas?)|:)(?:\s*(\d+))?\b"
)
# Sem dígito nenhum, de propósito: quem lê isto é `_explicit_time`, e a ordem
# importa — "e meia" antes das formas curtas.
_APELIDOS_DE_HORARIO = (
    (re.compile(r"\bmeio[-\s]?dia\s+e\s+meia\b"), "12:30"),
    (re.compile(r"\bmeia[-\s]?noite\s+e\s+meia\b"), "00:30"),
    (re.compile(r"\bmeio[-\s]?dia\b"), "12:00"),
    (re.compile(r"\bmeia[-\s]?noite\b"), "00:00"),
)

# Hora POR EXTENSO — o professor fala "uma hora", "duas horas", não "13h". O
# Isaque disse exatamente assim no teste de 15/08 e o casador ficou surdo,
# perguntando "qual horário" pra uma aula que ele já tinha nomeado.
#
# Só conta quando o número vem seguido de "hora(s)": "uma hora" é horário,
# "uma aula" é artigo. Sem essa âncora, "uma aula de hoje" viraria 01:00.
_NUMEROS_POR_EXTENSO = {
    "uma": 1, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
    "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12,
}
_HORA_POR_EXTENSO_RE = re.compile(
    r"\b(" + "|".join(_NUMEROS_POR_EXTENSO) + r")\s+horas?\b"
)

# Dia da semana desempata dois horários iguais em dias diferentes (dois 14:00,
# um sábado, um quinta). Normalizado sem acento; o índice bate com date.weekday()
# (segunda=0 … domingo=6).
_DIAS_DA_SEMANA = {
    "segunda": 0, "segunda-feira": 0, "terca": 1, "terca-feira": 1,
    "quarta": 2, "quarta-feira": 2, "quinta": 3, "quinta-feira": 3,
    "sexta": 4, "sexta-feira": 4, "sabado": 5, "domingo": 6,
}
# Tokens que aparecem em nome de gente mas não identificam ninguém — não podem
# virar régua. "de/da/do" já caem pelo tamanho; sobrenomes comuns ficam de fora
# porque colidiriam entre alunos diferentes.
_SOBRENOMES_COMUNS = {
    "junior", "filho", "neto", "silva", "santos", "souza", "sousa", "oliveira",
    "pereira", "lima", "costa", "ferreira", "rodrigues", "almeida", "nascimento",
}


def _norm(value: Any) -> str:
    raw = str(value or "").lower()
    raw = "".join(c for c in unicodedata.normalize("NFKD", raw) if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", raw).strip()


def _has_phrase(hay: str, phrases: tuple[str, ...]) -> bool:
    return any(
        re.search(rf"\b{re.escape(phrase)}\b", hay) if " " not in phrase else phrase in hay
        for phrase in phrases
    )


def _parse_llm_label(llm_json: str | None, allowed: set[str]) -> str | None:
    if llm_json is None:
        return None
    if not isinstance(llm_json, str) or not llm_json.strip() or llm_json.strip().lower() in {"timeout", "none", "null"}:
        return None
    try:
        value = json.loads(llm_json)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict):
        return None
    label = value.get("intencao", value.get("intent"))
    return label if isinstance(label, str) and label in allowed else None


def _audio_heuristic(text: str) -> AudioIntent:
    hay = _norm(text)
    if not hay:
        return "ambiguo"
    has_presence = _has_phrase(hay, _PRESENCE_WORDS)
    has_content = _has_phrase(hay, _CONTENT_WORDS)
    if has_presence and has_content:
        return "ambiguo"
    if has_presence:
        return "ambiguo"
    if has_content:
        return "registro"
    if _has_phrase(hay, _CONVERSATION_WORDS):
        return "conversa"
    return "ambiguo"


def classificar_intencao_audio(transcricao: str, llm_json: str | None = None) -> AudioIntent:
    """Return a closed audio intent; malformed model output fails closed."""
    heuristic = _audio_heuristic(transcricao)
    if llm_json is None:
        return heuristic
    label = _parse_llm_label(llm_json, _AUDIO_INTENTS)
    if label is None or heuristic == "ambiguo" or label != heuristic:
        return "ambiguo"
    return label  # type: ignore[return-value]


def _text_heuristic(text: str) -> TextIntent:
    hay = _norm(text)
    if not hay:
        return "ambiguo"
    has_presence = _has_phrase(hay, _PRESENCE_WORDS)
    has_content = _has_phrase(hay, _CONTENT_WORDS)
    if has_presence and has_content:
        return "ambiguo"
    if has_presence:
        uncertain = any(word in hay for word in ("acho", "talvez", "parece", "nao sei", "não sei"))
        return "ambiguo" if uncertain else "chamada"
    if _has_phrase(hay, _CONVERSATION_WORDS):
        return "conversa"
    if has_content:
        return "conversa"
    return "ambiguo"


def classificar_intencao_texto(texto: str, llm_json: str | None = None) -> TextIntent:
    """Classify a text call trigger without ever consulting a candidate pool."""
    heuristic = _text_heuristic(texto)
    if llm_json is None:
        return heuristic
    label = _parse_llm_label(llm_json, _TEXT_INTENTS)
    if label is None or heuristic == "ambiguo" or label != heuristic:
        return "ambiguo"
    return label  # type: ignore[return-value]


def _horas_pedidas(text: str) -> set[str]:
    """Todas as horas "HH:MM" que o texto pode estar pedindo.

    Devolve CONJUNTO porque a fala é ambígua de propósito: "uma hora" pode ser
    01:00 ou 13:00, e quem desempata é a agenda — só existe aula às 13:00. O
    casador aceita a candidata cuja hora está no conjunto; nenhuma escola de
    música tem aula à 01:00, então na prática o dígito da tarde vence sozinho.
    """
    hay = _norm(text)
    horas: set[str] = set()
    # Apelido: "meio-dia", "meia-noite", "e meia". A ordem importa e o primeiro
    # match ENCERRA o grupo: "meio-dia e meia" casa com a regra longa (12:30) E
    # com a curta (12:00); sem o break, as duas entrariam e "meia" viraria
    # ambíguo entre 12:00 e 12:30.
    for regex, valor in _APELIDOS_DE_HORARIO:
        if regex.search(hay):
            horas.add(valor)
            break
    # Por extenso: "uma hora" → {01:00, 13:00}. Ancorado em "hora(s)" pra não
    # ler o artigo de "uma aula".
    for match in _HORA_POR_EXTENSO_RE.finditer(hay):
        n = _NUMEROS_POR_EXTENSO[match.group(1)]
        horas.add(f"{n:02d}:00")
        horas.add(f"{(n + 12) % 24:02d}:00")
    # Dígito: explícito, sem +12 (quem escreve "13h" já foi exato).
    match = _EXPLICIT_TIME_RE.search(hay)
    if match:
        horas.add(f"{int(match.group(1)):02d}:{int(match.group(2) or 0):02d}")
    return horas


def _explicit_time(text: str) -> str | None:
    """Uma hora canônica (compat: o dígito, ou o apelido). Prefere a tarde.

    Mantido porque testes e outras portas ainda chamam por um valor único. O
    casador de verdade usa `_horas_pedidas` (conjunto), que é o superconjunto.
    """
    hay = _norm(text)
    for regex, valor in _APELIDOS_DE_HORARIO:
        if regex.search(hay):
            return valor
    match = _EXPLICIT_TIME_RE.search(hay)
    if match:
        return f"{int(match.group(1)):02d}:{int(match.group(2) or 0):02d}"
    # Por extenso, quando não há dígito: escolhe a tarde (13-24), que é quando
    # a escola funciona — mas só como valor de exibição; o casamento é por set.
    ext = _HORA_POR_EXTENSO_RE.search(hay)
    if ext:
        n = _NUMEROS_POR_EXTENSO[ext.group(1)]
        return f"{(n + 12) % 24:02d}:00"
    return None


def texto_tem_horario(texto: str) -> bool:
    """O texto cita um horário? Inclui apelido e extenso, não só dígito.

    Fonte ÚNICA desse vocabulário. `_looks_like_class_refinement`, em
    `fabio_whatsapp_actions`, tinha uma régua PRÓPRIA que só lia dígito: o
    `2b716aa` ensinou "meio-dia" ao casador e a porteira lá continuou surda,
    então a resposta que o casador entenderia era barrada antes de chegar
    nele. Duas réguas pra mesma pergunta é como o defeito volta pela metade.
    """
    return bool(_horas_pedidas(texto))


def _nome_tokens(candidate: dict[str, Any]) -> set[str]:
    """Tokens de nome de aluno que IDENTIFICAM (primeiro nome, do meio, raros).

    O roster guarda o nome COMPLETO ("Billy Paulo Vangu Junior"), mas o
    professor diz "Billy". Casar pela string inteira (como era até 15/08) nunca
    pegava o primeiro nome. Aqui cada palavra ≥3 letras vira um token, menos os
    sobrenomes comuns — que colidiriam entre alunos diferentes.
    """
    tokens: set[str] = set()
    alunos = candidate.get("alunos") or candidate.get("alunos_sem_presenca_forte") or []
    if not isinstance(alunos, list):
        return tokens
    for aluno in alunos:
        nome = _norm(aluno.get("nome") if isinstance(aluno, dict) else aluno)
        for token in nome.split():
            if len(token) >= 3 and token not in _SOBRENOMES_COMUNS:
                tokens.add(token)
    return tokens


def _curso_tokens(candidate: dict[str, Any]) -> set[str]:
    """Instrumento falado, sem a marca de turma. "Violão T" → {violao}.

    O " T"/"T" final é sufixo de turma, não parte do nome do instrumento — cai
    pelo tamanho (1 letra). Sobra o token que o professor realmente diz.
    """
    curso = _norm(candidate.get("curso"))
    return {token for token in curso.split() if len(token) >= 3}


def _dias_pedidos(text: str) -> set[int]:
    hay = _norm(text)
    return {idx for termo, idx in _DIAS_DA_SEMANA.items()
            if re.search(rf"\b{re.escape(termo)}\b", hay)}


def _compatible(text: str, candidate: dict[str, Any], all_candidates: list[dict[str, Any]]) -> bool:
    hay = _norm(text)
    # Turma é código estruturado ("T_Sá_14") — o professor não fala isso, então
    # casa pela string cheia. Curso é instrumento falado: o banco guarda
    # "Violão T" (o " T" marca turma) e o professor diz só "violão". Casar pela
    # string inteira deixaria "três horas, violão" preso entre dois 15:00.
    known = {_norm(c.get("turma")) for c in all_candidates if len(_norm(c.get("turma"))) >= 3}
    mentioned = {value for value in known if re.search(rf"\b{re.escape(value)}\b", hay)}
    if mentioned and _norm(candidate.get("turma")) not in mentioned:
        return False

    curso_para_aulas: dict[str, set[int]] = {}
    for item in all_candidates:
        for token in _curso_tokens(item):
            curso_para_aulas.setdefault(token, set()).add(int(item["aula_id"]))
    cursos_mencionados = {tok for tok in curso_para_aulas if re.search(rf"\b{re.escape(tok)}\b", hay)}
    if cursos_mencionados:
        aulas_do_curso: set[int] = set().union(*(curso_para_aulas[t] for t in cursos_mencionados))
        if int(candidate["aula_id"]) not in aulas_do_curso:
            return False

    # Nome de aluno POR TOKEN. "Billy" pina a aula cujo roster tem esse token;
    # o substituto ("no lugar do Jeremias") também identifica, porque Jeremias
    # está no roster mesmo tendo faltado.
    token_para_aulas: dict[str, set[int]] = {}
    for item in all_candidates:
        for token in _nome_tokens(item):
            token_para_aulas.setdefault(token, set()).add(int(item["aula_id"]))
    mencionados = {tok for tok in token_para_aulas if re.search(rf"\b{re.escape(tok)}\b", hay)}
    if mencionados:
        aulas_do_nome: set[int] = set().union(*(token_para_aulas[t] for t in mencionados))
        if int(candidate["aula_id"]) not in aulas_do_nome:
            return False

    # Horário: conjunto (dígito, apelido ou extenso). A candidata precisa bater
    # com pelo menos uma das horas pedidas.
    horas = _horas_pedidas(text)
    if horas and _norm(candidate.get("hora")) and _norm(candidate.get("hora")) not in horas:
        return False

    # Dia da semana / "hoje" desempata horários iguais em dias diferentes.
    dias = _dias_pedidos(text)
    if dias:
        data_str = _norm(candidate.get("data"))
        try:
            weekday = date.fromisoformat(data_str).weekday()
        except (TypeError, ValueError):
            weekday = None
        if weekday is not None and weekday not in dias:
            return False
    if re.search(r"\bhoje\b", hay) and candidate.get("dias_em_atraso") is not None:
        # "hoje" só é régua quando a candidata carrega a distância em dias (o
        # pool fresco traz; a shortlist guardada pode não trazer). Sem o campo,
        # "hoje" é inerte — melhor não filtrar do que filtrar errado.
        if int(candidate.get("dias_em_atraso") or 0) != 0:
            return False
    return True


def _question_for(candidates: list[dict[str, Any]], discriminante: bool = False) -> str:
    if discriminante:
        return "Qual dia, horário ou turma foi essa aula?"
    labels = []
    for item in candidates:
        label = " ".join(str(x) for x in (item.get("data"), item.get("hora"), item.get("curso"), item.get("turma")) if x)
        labels.append(label or f"aula {item['aula_id']}")
    return "Qual delas foi: " + " ou ".join(labels) + "?"


def reduzir_shortlist(texto: str, candidatas: list[dict[str, Any]]) -> dict[str, Any]:
    """Filter/rank supplied DB rows; never invent or return an external ID."""
    unique: list[dict[str, Any]] = []
    seen: set[int] = set()
    for item in candidatas or []:
        if not isinstance(item, dict):
            continue
        try:
            aula_id = int(item["aula_id"])
        except (KeyError, TypeError, ValueError):
            continue
        if aula_id <= 0 or aula_id in seen:
            continue
        seen.add(aula_id)
        unique.append(dict(item, aula_id=aula_id))
    compatible = [item for item in unique if _compatible(texto, item, unique)]
    if not compatible:
        return {"status": "nenhuma", "aula_id": None, "candidatas": [], "pergunta": None}
    if len(compatible) > 3:
        # `candidatas` vai CHEIA de propósito. "Discriminante" quer dizer "são
        # aulas demais pra listar num menu", não "não sei quais são" — e quem
        # recebe isto guarda a lista na ação. Devolvendo `[]` aqui (como era até
        # 15/08/2026) a ação nascia sem candidata nenhuma, e o interpretador de
        # resposta desse tipo de ação só sabe casar contra essa lista: nenhuma
        # resposta do professor podia ser aceita, nunca. Foi o laço em que o
        # Isaque ficou preso, respondendo três vezes e ouvindo a mesma frase.
        # ⚠️ `fabio_shortlist_valida` exige `cardinality between 1 and 3`, e o
        # teto é DELIBERADO: shortlist é tamanho de MENU. Guardar as 10 fez a
        # RPC real devolver `shortlist_invalida` num ensaio contra produção,
        # depois de o teste de unidade passar verde (o dublê aceitava qualquer
        # tamanho; agora ele também recusa >3).
        #
        # `truncada` existe porque guardar 3 de 10 é PIOR que não guardar: a
        # lista vira a única régua contra a qual a resposta do professor é
        # casada (`_refine_pending_class` filtra o pool por ela), e as outras 7
        # aulas passam a ser resposta impossível. Sem shortlist guardada, a
        # resposta é casada contra o pool inteiro — que é o que a pergunta
        # aberta ("qual dia, horário ou turma?") pede. Quem decide guardar é o
        # chamador; aqui só se diz a verdade sobre o que coube.
        return {"status": "discriminante", "aula_id": None, "candidatas": compatible[:3],
                "truncada": len(compatible) > 3, "pergunta": _question_for(compatible, True)}
    if len(compatible) == 1:
        return {"status": "selecionada", "aula_id": compatible[0]["aula_id"], "candidatas": compatible, "pergunta": None}
    return {"status": "perguntar", "aula_id": None, "candidatas": compatible[:3], "pergunta": _question_for(compatible[:3])}


def interpretar_resposta_pendente(texto: str, acao: dict[str, Any]) -> dict[str, Any]:
    normalized = _norm(texto)
    hay = re.sub(r"[^a-z0-9áéíóúãõç ]", " ", normalized)
    hay = re.sub(r"\s+", " ", hay).strip()
    tipo = str((acao or {}).get("tipo") or "")
    if not hay:
        return {"tipo": "perguntar", "motivo": "resposta_vazia"}
    if any(word in hay for word in _CANCEL_WORDS):
        return {"tipo": "cancelar"}
    if any(hay.startswith(prefix) for prefix in ("qual ", "como ", "o que ", "quando ", "onde ")):
        return {"tipo": "conversa"}
    if any(hay == word or hay.startswith(word + " ") for word in _DEFER_WORDS):
        return {"tipo": "adiar"}
    candidates = [int(x) for x in (acao or {}).get("candidatas", []) if str(x).isdigit()]
    if tipo.startswith("escolher_aula"):
        time_marked_numbers = {
            int(number)
            for match in _TIME_MARKED_NUMBER_RE.finditer(normalized)
            for number in match.groups()
            if number is not None
        }
        for candidate in candidates:
            if re.search(rf"\b(?:aula|opcao)\s+{candidate}\b", hay):
                return {"tipo": "escolher_aula", "aula_id": candidate}
        ordinals = {"primeira": 0, "1": 0, "segunda": 1, "2": 1, "terceira": 2, "3": 2}
        match = next(
            (
                index for word, index in ordinals.items()
                if re.search(rf"\b{word}\b", hay)
                and not (word.isdigit() and int(word) in time_marked_numbers)
            ),
            None,
        )
        if match is not None and match < len(candidates):
            return {"tipo": "escolher_aula", "aula_id": candidates[match]}
        for candidate in candidates:
            if candidate not in time_marked_numbers and re.search(rf"\b{candidate}\b", hay):
                return {"tipo": "escolher_aula", "aula_id": candidate}
        return {"tipo": "perguntar", "motivo": "aula_nao_reconhecida"}
    if tipo in {"confirmar_registro", "confirmar_chamada"} and (
        hay.startswith("nao ") or hay.startswith("não ") or " veio" in hay or " faltou" in hay
    ) and any(word in hay for word in ("veio", "vieram", "faltou", "faltaram", "troca", "corrige", "correcao", "correção")):
        return {"tipo": "correcao", "texto": texto.strip()}
    if hay in _AFFIRMATIVE or any(hay.startswith(word + " ") for word in _AFFIRMATIVE):
        return {"tipo": "confirmar_intencao" if tipo.startswith("confirmar_intencao") else "confirmar"}
    if hay.startswith("nao ") or hay.startswith("não ") or hay in {"nao", "não"}:
        return {"tipo": "negar"}
    return {"tipo": "conversa"}


def validar_patch_correcao(saida: dict[str, Any], rascunho: dict[str, Any], roster: list[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(saida, dict) or not isinstance(rascunho, dict):
        return {"ok": False, "motivo": "formato_invalido"}
    if rascunho.get("status") not in {"rascunho", "aguardando_confirmacao"}:
        return {"ok": False, "motivo": "rascunho_fechado"}
    if str(saida.get("registro_id")) != str(rascunho.get("id")):
        return {"ok": False, "motivo": "registro_divergente"}
    aluno_id = saida.get("aluno_id", rascunho.get("aluno_id"))
    if rascunho.get("aluno_id") is not None and aluno_id != rascunho.get("aluno_id"):
        return {"ok": False, "motivo": "aluno_divergente"}
    if aluno_id is not None and not any(isinstance(row, dict) and row.get("aluno_id") == aluno_id for row in roster or []):
        return {"ok": False, "motivo": "aluno_fora_roster"}
    fields = saida.get("campos")
    if not isinstance(fields, dict) or not fields or any(key not in _ALLOWED_FIELDS for key in fields):
        return {"ok": False, "motivo": "campo_nao_permitido"}
    for key, value in fields.items():
        if key == "presenca":
            if value not in {"presente", "ausente"}:
                return {"ok": False, "motivo": "presenca_invalida"}
        elif not isinstance(value, str) or not value.strip() or len(value) > 4000:
            return {"ok": False, "motivo": "valor_invalido"}
    return {"ok": True, "registro_id": rascunho["id"], "aluno_id": aluno_id, "campos": dict(fields)}
