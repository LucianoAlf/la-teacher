#!/usr/bin/env python3
"""Closed, side-effect-free contracts for the WhatsApp action bridge.

This module deliberately does not call Hermes, Supabase or UAZAPI.  It can
rank evidence, but it never turns a guess into a database write authority.
"""
from __future__ import annotations

import json
import re
import unicodedata
from datetime import date, timedelta
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


# ── Substituição (Task 3 do plano) ───────────────────────────────────────────
# "Juliana no lugar do Jeremias" — quem PARTICIPOU no lugar de quem. O casador
# já pina a AULA (pelo Jeremias, que está no roster); aqui a gente isola o par
# (matriculado esperado, participante que veio). Determinístico primeiro: só as
# frases fortes; o resto devolve None e (fase seguinte) cai pro LLM. Nunca
# inventa — sem par claro, None.

_SUBST_SINAIS = re.compile(
    r"\bno lugar d[eoa]\b|\bquem fez foi\b|\bsubstitui|\bveio no lugar\b"
)
# Palavras que aparecem perto dos gatilhos mas não são nome de gente.
_PARTICIPANTE_STOP = {
    "aula", "hoje", "ontem", "tarde", "manha", "noite", "lugar", "dele", "dela",
    "aluno", "aluna", "ele", "ela", "essa", "esse", "uma",
}
# Cada padrão captura o nome do PARTICIPANTE numa posição diferente da fala.
_PARTICIPANTE_PADROES = (
    re.compile(r"\bfoi\s+(?:a\s+|o\s+)?([a-z]{3,})\b"),        # "...foi a Juliana"
    re.compile(r"\bveio\s+(?:a\s+|o\s+)?([a-z]{3,})\b"),       # "...veio a Marina"
    re.compile(r"\b([a-z]{3,})\s+substitui"),                  # "Marina substituiu..."
    re.compile(r"\b([a-z]{3,})\s+veio no lugar\b"),            # "Marina veio no lugar dele"
    # Participante ANTES do gatilho, sem "foi/veio" — "Juliana fez aula no lugar
    # do Jeremias" (frase real do Isaque). Último da lista de propósito: quando
    # há "...foi a X", o padrão de cima já resolveu e "quem fez" nunca é lido
    # como nome (o `quem` cai fora antes de chegar aqui).
    re.compile(r"\b([a-z]{3,})\s+fez\b"),                      # "Juliana fez aula..."
)


def _tokens_de_nome(nome: str) -> set[str]:
    return {t for t in _norm(nome).split() if len(t) >= 3 and t not in _SOBRENOMES_COMUNS}


def detectar_substituicao(texto: str, roster_nomes: list[str]) -> dict[str, Any] | None:
    """Isola o par (matriculado, participante) numa fala de substituição.

    `matriculado` é devolvido como o NOME do roster (string original); o
    `participante` é o token citado (normalizado). Devolve None quando não há
    sinal forte OU quando o matriculado não é determinável sem chute (roster com
    mais de um aluno e nenhum citado na fala).
    """
    hay = _norm(texto)
    if not _SUBST_SINAIS.search(hay):
        return None

    matriculado = None
    matr_tokens: set[str] = set()
    for nome in roster_nomes or []:
        toks = _tokens_de_nome(nome)
        if any(re.search(rf"\b{re.escape(t)}\b", hay) for t in toks):
            matriculado, matr_tokens = nome, toks
            break
    if matriculado is None:
        # Ninguém do roster foi citado ("dele"/"dela"). Só resolve sozinho se a
        # aula tem UM aluno; com dois, quem foi substituído é chute — devolve None.
        vivos = [n for n in (roster_nomes or []) if _norm(n)]
        if len(vivos) == 1:
            matriculado = vivos[0]
            matr_tokens = _tokens_de_nome(matriculado)
        else:
            return None

    for padrao in _PARTICIPANTE_PADROES:
        for m in padrao.finditer(hay):
            tok = m.group(1)
            if tok in matr_tokens or tok in _PARTICIPANTE_STOP:
                continue
            return {"matriculado": matriculado, "participante": tok}
    return None


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


# ── Consulta letiva (Fase 1) ────────────────────────────────────────────────
# O professor pergunta sobre a PRÓPRIA vida letiva: "quantas aulas eu dei de
# 11/08 a 15/08?", "quantas no Recreio?", "quem faltou?". Nasceu do pedido do
# prof. Valdo em 16/08, que o Fábio não soube responder.
#
# O extrator é DETERMINÍSTICO de propósito: é ele a trava. Quando não consegue
# isolar o período, devolve None e o Fábio PERGUNTA — foi justamente o chute
# (intenção "ambigua" virando chamada) que sequestrou a conversa do Valdo e
# terminou em "não gravei nada".

_CONSULTA_AULAS = re.compile(
    r"\bquantas?\s+aulas?\b|\btotal\s+de\s+aulas?\b|\baulas?\s+que\s+eu\s+dei\b|\bministrei\b"
)
_CONSULTA_PRESENCA = re.compile(
    r"\bquais?\s+alunos?\b.*\bfalt|\bquem\s+faltou\b|\bfaltaram\b|\bfaltas?\b|\bpresen[çc]as?\b"
)
_DATA_EXPLICITA = re.compile(r"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b")

# O professor FALA a data, e o Whisper escreve o que ele falou: "dia 11 do 8",
# nunca "11/08". Medido na transcrição real do Valdo em 17/08/2026 — os dois
# áudios dele morriam aqui, com `parece_consulta_letiva` dizendo True e o
# período saindo None. A forma digitada era a única que eu tinha testado,
# porque é como EU escrevo.
_DATA_FALADA = re.compile(r"\b(\d{1,2})\s+d[eo]\s+(\d{1,2})\b")

_MESES = {
    "janeiro": 1, "fevereiro": 2, "marco": 3, "março": 3, "abril": 4,
    "maio": 5, "junho": 6, "julho": 7, "agosto": 8, "setembro": 9,
    "outubro": 10, "novembro": 11, "dezembro": 12,
}
_DATA_MES_EXTENSO = re.compile(
    rf"\b(\d{{1,2}})\s+de\s+({'|'.join(_MESES)})\b")

# O MÊS É DITO UMA VEZ, NO FIM — é assim que brasileiro fala intervalo.
#
# Medido em produção em 18/08/2026: "quantas aulas eu dei de 11 a 15 de agosto?"
# resolvia para 15/08–15/08, e o Fábio devolvia a conta de UM dia para uma
# pergunta de cinco. As regras acima exigem o mês colado em CADA dia, então o
# `11` ficava órfão, sobrava uma data só, e uma data só vira inicio == fim.
# Valia igual para "entre 11 e 15 de agosto" e "do dia 11 ao dia 15 de agosto",
# e também para faltas.
#
# `(?<![\d/-])` impede que o primeiro número seja pedaço de uma data digitada:
# sem ele, "de 11/08 a 15/08" leria o "08" como dia inicial e o período viraria
# 08/08–15/08 — quebraria a forma que já funcionava para consertar a que não.
#
# `as` fica DE FORA da lista de conectores de propósito: "das 8 as 10 da manhã"
# é horário, não intervalo de dias. Sem período reconhecido o contrato é
# PERGUNTAR, que é melhor do que inventar mês para um horário.
_INTERVALO_MES_UMA_VEZ = re.compile(
    rf"(?<![\d/-])\b(\d{{1,2}})\s+(?:a|ate|ao|e)\s+(?:o\s+)?(?:dia\s+)?"
    rf"(\d{{1,2}})\s+d[eo]\s+({'|'.join(_MESES)}|\d{{1,2}})\b")

# Mesma família: "de 11 a 15/08" — o mês só aparece grudado no fim do intervalo.
_INTERVALO_ATE_DATA_DIGITADA = re.compile(
    r"(?<![\d/-])\b(\d{1,2})\s+(?:a|ate|ao|e)\s+(?:o\s+)?(?:dia\s+)?"
    r"(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b")


_MES_DE_DATA_ANTERIOR = re.compile(r"\d{1,2}\s+d[eo]\s+$")


def _e_mes_de_data_anterior(hay: str, inicio: int) -> bool:
    """O número que abre o intervalo é, na verdade, o MÊS da data anterior?

    Pego por um teste que já existia, ao consertar o intervalo de mês dito uma
    vez: em "de 11 de 8 ate 15 de 8" o padrão casava a partir do `8` de
    "11 de 8" e o período virava 08/08–15/08. O `(?<![\\d/-])` do padrão não
    alcança isso porque aqui o número vem depois de um ESPAÇO, não de barra —
    e o `re` do Python não aceita lookbehind de largura variável.
    """
    return bool(_MES_DE_DATA_ANTERIOR.search(hay[:inicio]))


def _data_de(dia: str, mes: str, ano: str | None, hoje: date) -> date | None:
    try:
        a = int(ano) if ano else hoje.year
        if a < 100:
            a += 2000
        return date(a, int(mes), int(dia))
    except ValueError:
        return None  # "32/13" não é data; não inventa


def resolver_periodo(texto: str, hoje: date) -> tuple[date, date] | None:
    """Isola o período pedido na fala. Devolve None quando não há período.

    None NÃO é falha: é o gatilho para o Fábio perguntar em vez de assumir
    "hoje". Ver `atalho-chuta-default-em-vez-de-se-calar`.
    """
    hay = _norm(texto)

    # 1) datas explícitas, nas TRÊS formas que aparecem de verdade:
    #    digitada ("de 11/08 até 15/08"), falada ("do dia 11 do 8 até o dia 15
    #    do 8" — o Valdo, por áudio) e mês por extenso ("11 de agosto"), mais o
    #    intervalo em que o mês aparece UMA vez ("de 11 a 15 de agosto").
    #    Data impossível ("32 do 13") continua devolvendo None em vez de virar
    #    data torta: `_data_de` recusa, e sem período o contrato é PERGUNTAR.
    brutas = list(_DATA_EXPLICITA.findall(hay))
    brutas += [(dia, mes, None) for dia, mes in _DATA_FALADA.findall(hay)]
    brutas += [(dia, str(_MESES[mes]), None)
               for dia, mes in _DATA_MES_EXTENSO.findall(hay)]
    # As duas pontas do intervalo herdam o MESMO mês, dito uma vez só.
    for m in _INTERVALO_MES_UMA_VEZ.finditer(hay):
        if _e_mes_de_data_anterior(hay, m.start()):
            continue
        d1, d2, mes = m.groups()
        numero = str(_MESES[mes]) if mes in _MESES else mes
        brutas += [(d1, numero, None), (d2, numero, None)]
    for m in _INTERVALO_ATE_DATA_DIGITADA.finditer(hay):
        if _e_mes_de_data_anterior(hay, m.start()):
            continue
        d1, d2, mes, ano = m.groups()
        brutas += [(d1, mes, ano or None), (d2, mes, ano or None)]
    achadas = [d for d in (_data_de(dia, mes, ano, hoje)
                           for dia, mes, ano in brutas)
               if d is not None]
    if len(achadas) >= 2:
        achadas.sort()
        return achadas[0], achadas[-1]
    if len(achadas) == 1:
        return achadas[0], achadas[0]

    # 2) formas relativas
    if re.search(r"\bontem\b", hay):
        d = hoje - timedelta(days=1)
        return d, d
    if re.search(r"\bhoje\b", hay):
        return hoje, hoje
    if re.search(r"\bsemana passada\b", hay):
        inicio = hoje - timedelta(days=hoje.weekday() + 7)   # segunda anterior
        return inicio, inicio + timedelta(days=6)
    if re.search(r"\b(essa|esta) semana\b", hay):
        return hoje - timedelta(days=hoje.weekday()), hoje
    if re.search(r"\bm[eê]s passado\b", hay):
        fim = hoje.replace(day=1) - timedelta(days=1)
        return fim.replace(day=1), fim
    if re.search(r"\b(esse|este) m[eê]s\b", hay):
        return hoje.replace(day=1), hoje
    return None


def parece_consulta_letiva(texto: str) -> bool:
    """A fala é uma PERGUNTA sobre a vida letiva (não um lançamento de aula)?

    Puro e sem dependência de data/unidade porque quem chama é o roteador em
    `fabio_whatsapp_actions`, que não conhece nenhum dos dois. Serve só para
    impedir que uma pergunta abra ação de chamada; período e unidade são
    resolvidos depois, no bridge.
    """
    hay = _norm(texto)
    return bool(_CONSULTA_AULAS.search(hay) or _CONSULTA_PRESENCA.search(hay))


def extrair_consulta_letiva(texto: str, hoje: date, unidades: list[str]) -> dict[str, Any] | None:
    """Parâmetros da consulta, ou None quando não é consulta / falta período."""
    hay = _norm(texto)
    if _CONSULTA_AULAS.search(hay):
        metrica = "aulas"
    elif _CONSULTA_PRESENCA.search(hay):
        metrica = "presencas"
    else:
        return None

    periodo = resolver_periodo(texto, hoje)
    if periodo is None:
        return None

    unidade = None
    for nome in unidades or []:
        alvo = _norm(nome)
        if alvo and re.search(rf"\b{re.escape(alvo)}\b", hay):
            unidade = nome
            break

    return {"metrica": metrica, "inicio": periodo[0], "fim": periodo[1], "unidade": unidade}


def consulta_vence_atalho(texto: str, hoje: date, unidades: list[str]) -> bool:
    """True quando o atalho determinístico do bridge tem que se calar.

    O atalho (`try_fast_response`) responde de `professor_context(prof, dia)`:
    UM dia, da AGENDA, sem filtro de unidade. Ele roda ANTES do `build_prompt`,
    que é onde mora o bloco da consulta — então quando ele casa com uma pergunta
    que o formato dele não sabe representar, ele responde primeiro, com o número
    de outra pergunta, e a consulta canônica nem chega a rodar.

    Medido em 17/08/2026, na pergunta que o Valdo mandou: "quantas aulas eu dei
    de 11/08 a 15/08?" pegava a PRIMEIRA data do intervalo e devolvia as 5 aulas
    do dia 11 — a resposta certa era 36. Nenhum log de consulta_letiva saía.

    Três formas de a pergunta não caber no atalho:
      - período de mais de um dia  → ele só sabe um;
      - filtro de unidade          → ele devolveria o dia inteiro como se fosse
                                     só daquela unidade;
      - pergunta de presença       → o contador dele conta aluno NA AGENDA, que
                                     é o oposto de "quem faltou".

    Pergunta de um dia só, sem unidade, sobre aula: continua no atalho — é o que
    ele sabe fazer, e rápido.
    """
    consulta = extrair_consulta_letiva(texto, hoje, unidades)
    if consulta is None:
        return False
    return (consulta["metrica"] == "presencas"
            or consulta["unidade"] is not None
            or consulta["inicio"] != consulta["fim"])


def montar_chamada_consulta(row: dict[str, Any], hoje: date,
                            unidades: list[str]) -> dict[str, Any] | None:
    """Traduz a mensagem em (rpc, payload) pronto pro bridge disparar.

    A IDENTIDADE NASCE AQUI, e nasce da LINHA: `row["professor_id"]`. O texto do
    professor nunca decide de quem é o dado — se ele escrever "sou o professor
    25", o payload continua saindo com o id da linha dele. Esta função é pura de
    propósito: é o que torna esse ataque testável sem subir o bridge.
    """
    professor_id = row.get("professor_id")
    if not professor_id:
        return None
    texto = str(row.get("content") or row.get("media_extracted_text") or "")
    pedido = extrair_consulta_letiva(texto, hoje, unidades)
    if not pedido:
        return None

    return chamada_do_pedido(professor_id, pedido)


def chamada_do_pedido(professor_id: Any, pedido: dict[str, Any]) -> dict[str, Any]:
    """(rpc, payload) a partir de um pedido já validado — a ÚNICA porta da RPC.

    Existe para que a passada A (`fabio_consulta_fallback`) dispare exatamente a
    mesma consulta do caminho determinístico, em vez de repetir o nome da RPC e
    o formato do payload num segundo lugar. Duas cópias da mesma régua é como
    uma delas envelhece sem ninguém ver.

    `p_professor_id` vem SEMPRE do argumento — que o bridge tira da linha. Nem
    o texto do professor nem o modelo têm como influenciar este campo.
    """
    payload: dict[str, Any] = {
        "p_professor_id": int(professor_id),
        "p_inicio": pedido["inicio"].isoformat(),
        "p_fim": pedido["fim"].isoformat(),
    }
    if pedido["metrica"] == "aulas":
        payload["p_unidade"] = pedido["unidade"]
        return {"rpc": "fabio_professor_resumo_aulas", "payload": payload, "pedido": pedido}
    return {"rpc": "fabio_professor_presencas_periodo", "payload": payload, "pedido": pedido}


def tem_sinal_de_aula(texto: str) -> bool:
    """A fala carrega ALGUM sinal de aula (presença ou conteúdo)?

    Discriminador do roteador, e de propósito não é lista de palavrinhas de
    confirmação ("ok", "sim", "blz"...): a régua é se a mensagem fala de aula.
    Um "Ok" solto não fala; "A Sofia faltou e trabalhamos respiração" fala.

    Existe porque em 16/08 o "Ok" do prof. Valdo — resposta a uma pergunta de
    CONSULTA — abriu uma ação de chamada do nada e a conversa terminou em "Não
    gravei nada". Ambíguo COM sinal continua legítimo para perguntar: ali há
    conteúdo real, e o caminho determinístico é o único que consegue gravá-lo.
    """
    hay = _norm(texto)
    if not hay:
        return False
    return _has_phrase(hay, _PRESENCE_WORDS) or _has_phrase(hay, _CONTENT_WORDS)
