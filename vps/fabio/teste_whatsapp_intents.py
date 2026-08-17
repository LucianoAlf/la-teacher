#!/usr/bin/env python3
import json
import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_intents import (  # noqa: E402
    _explicit_time,
    _norm,
    classificar_intencao_audio,
    classificar_intencao_texto,
    detectar_substituicao,
    extrair_consulta_letiva,
    interpretar_resposta_pendente,
    montar_chamada_consulta,
    parece_consulta_letiva,
    reduzir_shortlist,
    resolver_periodo,
    validar_patch_correcao,
)


FIXTURE = Path(__file__).resolve().parent / "fixtures" / "whatsapp_intents.json"


class WhatsappIntentsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_audio_contract_is_closed_and_fails_closed(self):
        for case in self.cases["audio"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    classificar_intencao_audio(case["transcricao"], case.get("llm_json")),
                    case["expected"],
                )
        self.assertEqual(classificar_intencao_audio("", None), "ambiguo")
        self.assertEqual(classificar_intencao_audio("na aula fizemos ritmo", "timeout"), "ambiguo")

    def test_text_contract_separates_call_from_content_and_conversation(self):
        for case in self.cases["texto"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    classificar_intencao_texto(case["texto"], case.get("llm_json")),
                    case["expected"],
                )

    def test_shortlist_only_selects_compatible_database_candidates(self):
        for case in self.cases["shortlist"]:
            with self.subTest(case=case["name"]):
                result = reduzir_shortlist(case["texto"], case["candidatas"])
                self.assertEqual(result["status"], case["expected_status"])
                self.assertEqual(result.get("aula_id"), case.get("expected_aula_id"))
                expected_ids = case.get("expected_ids")
                if expected_ids is None and case.get("expected_aula_id") is not None:
                    expected_ids = [case["expected_aula_id"]]
                self.assertEqual([x["aula_id"] for x in result["candidatas"]], expected_ids or [])
                self.assertLessEqual(len(result["candidatas"]), 3)

    def test_shortlist_discriminates_natural_hour_phrase(self):
        result = reduzir_shortlist(
            "Foi a aula das 15 horas.",
            [
                {"aula_id": 101, "hora": "15:00"},
                {"aula_id": 102, "hora": "16:00"},
            ],
        )
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 101)

    def test_shortlist_discriminates_spaced_hour_and_minutes(self):
        result = reduzir_shortlist(
            "Foi a aula das 15 h 30.",
            [
                {"aula_id": 101, "hora": "15:30"},
                {"aula_id": 102, "hora": "16:00"},
            ],
        )
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 101)

    def test_explicit_time_rejects_invalid_minutes_without_partial_hour_match(self):
        candidates = [
            {"aula_id": 101, "hora": "15:00"},
            {"aula_id": 102, "hora": "16:00"},
        ]
        for text in ("Foi a aula das 15 h 99.", "Foi a aula das 15:99."):
            with self.subTest(text=text):
                self.assertIsNone(_explicit_time(text))
                result = reduzir_shortlist(text, candidates)
                self.assertEqual(result["status"], "perguntar")
                self.assertIsNone(result["aula_id"])

    def test_pending_choice_does_not_treat_times_as_candidate_ids(self):
        action = {"tipo": "escolher_aula_audio", "candidatas": [15, 30, 99, 101]}
        for text in ("15 h", "15 horas", "15:30", "15 h 30", "15:99", "15 h 99"):
            with self.subTest(text=text):
                self.assertEqual(
                    interpretar_resposta_pendente(text, action),
                    {"tipo": "perguntar", "motivo": "aula_nao_reconhecida"},
                )
        for text, aula_id in (("aula 15", 15), ("opção 15", 15), ("aula 30", 30), ("opção 30", 30), ("15", 15)):
            with self.subTest(text=text):
                self.assertEqual(
                    interpretar_resposta_pendente(text, action),
                    {"tipo": "escolher_aula", "aula_id": aula_id},
                )

    def test_pending_response_never_defaults_to_confirmation(self):
        for case in self.cases["pendentes"]:
            with self.subTest(case=case["name"]):
                result = interpretar_resposta_pendente(case["texto"], case["acao"])
                self.assertEqual(result["tipo"], case["expected"])
                if "expected_aula_id" in case:
                    self.assertEqual(result["aula_id"], case["expected_aula_id"])
        self.assertNotEqual(
            interpretar_resposta_pendente("talvez", {"tipo": "confirmar_registro"})["tipo"],
            "confirmar",
        )

    # ── A "burrice" do Fábio, medida no teste real do Isaque (15/08/2026) ──────
    # Ele tem UM Billy (13h), UM Marcelo (15h), UM Jeremias (14h). Dizia o nome
    # ou o horário em português falado, e o Fábio perguntava "qual dia, horário
    # ou turma" — porque (a) o roster casava só pelo nome COMPLETO, (b) hora por
    # extenso não era lida, (c) "hoje" não desempatava dois horários iguais.

    def _isaque_pool(self):
        return [
            {"aula_id": 267639, "data": "2026-08-15", "hora": "15:00", "curso": "Violão T",
             "turma": "V_Sá_15", "dias_em_atraso": 0,
             "alunos": [{"nome": "Marcelo Santos Calvo", "aluno_id": 968}]},
            {"aula_id": 267617, "data": "2026-08-15", "hora": "14:00", "curso": "Teclado T",
             "turma": "T_Sá_14", "dias_em_atraso": 0,
             "alunos": [{"nome": "Jeremias Ou Yuan Ma", "aluno_id": 793}]},
            {"aula_id": 267604, "data": "2026-08-15", "hora": "13:00", "curso": "Teclado T",
             "turma": "T_Sá_13", "dias_em_atraso": 0,
             "alunos": [{"nome": "Billy Paulo Vangu Junior", "aluno_id": 743}]},
            {"aula_id": 228183, "data": "2026-08-13", "hora": "14:00", "curso": "Guitarra T",
             "turma": "G_Qui_14", "dias_em_atraso": 2,
             "alunos": [{"nome": "Antônio Henrique Segall de Noronha", "aluno_id": 722}]},
        ]

    def test_primeiro_nome_do_aluno_pina_a_aula(self):
        # "Aula do Billy de uma hora" — o professor diz o PRIMEIRO nome; o roster
        # tem "Billy Paulo Vangu Junior". Tem que casar assim mesmo.
        result = reduzir_shortlist("Aula do Billy, tocamos forelize", self._isaque_pool())
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 267604)

    def test_nome_do_substituido_pina_a_aula(self):
        # "quem fez no lugar do Jeremias foi a Juliana" — Juliana não está em
        # roster nenhum, mas JEREMIAS está, e é ele quem identifica a aula.
        result = reduzir_shortlist(
            "quem fez aula no lugar do Jeremias foi a Juliana", self._isaque_pool())
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 267617)

    def test_hora_por_extenso_uma_e_tres(self):
        # 13:00 (Billy) e 15:00 (Marcelo) são únicos no pool; "uma hora" e "três
        # horas" têm que pinar. ("duas horas" cai em DOIS 14:00 — ambíguo de
        # verdade; o desempate por "hoje" está no teste abaixo.)
        for frase, esperado in (("aula de uma hora", 267604),
                                ("aula das três horas", 267639)):
            with self.subTest(frase=frase):
                result = reduzir_shortlist(frase, self._isaque_pool())
                self.assertEqual(result["status"], "selecionada", frase)
                self.assertEqual(result["aula_id"], esperado, frase)

    def test_uma_aula_nao_e_uma_hora(self):
        # "uma aula" é artigo, não horário — não pode virar 01:00/13:00 e
        # estreitar errado. Sem outro sinal, o pool inteiro segue.
        result = reduzir_shortlist("foi uma aula de teclado", [
            {"aula_id": 1, "hora": "13:00", "curso": "Teclado T"},
            {"aula_id": 2, "hora": "18:00", "curso": "Teclado T"},
        ])
        self.assertEqual(result["status"], "perguntar")
        self.assertEqual({c["aula_id"] for c in result["candidatas"]}, {1, 2})

    def test_hoje_desempata_dois_horarios_iguais(self):
        # Dois 14:00: hoje (sábado, dias_em_atraso 0) e quinta (2 dias atrás).
        # "hoje 14h" tem que escolher o de hoje, não repetir a pergunta.
        pool = [c for c in self._isaque_pool() if c["hora"] == "14:00"]
        result = reduzir_shortlist("foi hoje, duas horas", pool)
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 267617)

    def test_dia_da_semana_desempata_por_data(self):
        pool = [c for c in self._isaque_pool() if c["hora"] == "14:00"]
        result = reduzir_shortlist("foi na quinta, 14h", pool)
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 228183)

    def test_instrumento_falado_casa_o_curso_com_sufixo_de_turma(self):
        # O curso no banco é "Violão T"/"Teclado T" (o " T" é marca de turma). O
        # professor diz só "violão". Tem que casar assim mesmo, senão "três
        # horas, violão" fica preso entre dois 15:00.
        pool = [
            {"aula_id": 1, "hora": "15:00", "curso": "Violão T", "turma": "V_Sá_15"},
            {"aula_id": 2, "hora": "15:00", "curso": "Teclado T", "turma": "T_Qui_15"},
        ]
        result = reduzir_shortlist("aula das três horas, foi violão", pool)
        self.assertEqual(result["status"], "selecionada")
        self.assertEqual(result["aula_id"], 1)

    def test_nome_ambiguo_estreita_sem_pinar(self):
        # Dois "Felipe" no pool → mencionar "Felipe" NÃO pina, mas estreita aos
        # dois. Não pode virar seleção errada.
        pool = [
            {"aula_id": 1, "hora": "18:00", "alunos": [{"nome": "Luiz Felipe de Freitas"}]},
            {"aula_id": 2, "hora": "19:00", "alunos": [{"nome": "Felipe Melo Castor"}]},
            {"aula_id": 3, "hora": "20:00", "alunos": [{"nome": "Marcelo Santos"}]},
        ]
        result = reduzir_shortlist("aula do Felipe", pool)
        self.assertEqual(result["status"], "perguntar")
        self.assertEqual({c["aula_id"] for c in result["candidatas"]}, {1, 2})

    def test_token_curto_nao_casa_por_acidente(self):
        # "Ma" aparece em "Jeremias Ou Yuan Ma" e "Juliana Mei Jin Ma" — token de
        # 2 letras não pode ser régua de nome.
        pool = [
            {"aula_id": 1, "hora": "14:00", "alunos": [{"nome": "Jeremias Ou Yuan Ma"}]},
            {"aula_id": 2, "hora": "15:00", "alunos": [{"nome": "Ana Maria Silva"}]},
        ]
        # "ma" sozinho não deve casar nada; sem outro sinal, as duas continuam.
        result = reduzir_shortlist("foi a aula, ma", pool)
        self.assertEqual(result["status"], "perguntar")

    # ── Detector de substituição (Task 3) ────────────────────────────────────
    # O buraco do teste do Isaque: quem participou no lugar de quem. Determinístico
    # primeiro; o par (matriculado no roster, participante citado) sai da frase.

    def test_detecta_substituicao_frase_do_isaque(self):
        r = detectar_substituicao(
            "quem fez aula no lugar do Jeremias foi a Juliana",
            ["Jeremias Ou Yuan Ma"])
        self.assertEqual(r["matriculado"], "Jeremias Ou Yuan Ma")
        self.assertEqual(_norm(r["participante"]), "juliana")

    def test_detecta_quatro_frases_fortes(self):
        roster = ["Jeremias Ou Yuan Ma"]
        for frase in ("no lugar do Jeremias veio a Marina",
                      "quem fez foi a Marina",
                      "a Marina substituiu o Jeremias",
                      "a Marina veio no lugar dele"):
            with self.subTest(frase=frase):
                r = detectar_substituicao(frase, roster)
                self.assertIsNotNone(r, frase)
                self.assertEqual(_norm(r["participante"]), "marina", frase)
                self.assertEqual(r["matriculado"], "Jeremias Ou Yuan Ma", frase)

    def test_detecta_substituicao_participante_antes_do_gatilho(self):
        # Frase REAL do Isaque (15/08, msg 391e0456): o participante vem ANTES
        # do "no lugar de", sem "foi/veio" — "Juliana fez aula no lugar do
        # jeremias". A falsificação ao vivo pegou o detector devolvendo None
        # aqui; o par (Jeremias, Juliana) tem que sair mesmo assim.
        r = detectar_substituicao(
            "Juliana fez aula no lugar do jeremias", ["Jeremias Ou Yuan Ma"])
        self.assertIsNotNone(r)
        self.assertEqual(r["matriculado"], "Jeremias Ou Yuan Ma")
        self.assertEqual(_norm(r["participante"]), "juliana")

    def test_sem_substituicao_devolve_none(self):
        self.assertIsNone(detectar_substituicao(
            "aula do Jeremias, trabalhamos escala", ["Jeremias Ou Yuan Ma"]))

    def test_substituicao_com_roster_ambiguo_sem_nome_no_texto_devolve_none(self):
        # Dois alunos no roster e a frase não cita qual é o matriculado ("dele"):
        # não dá pra saber quem foi substituído → não inventa.
        r = detectar_substituicao("quem fez foi a Marina", ["Ana Silva", "Bruno Costa"])
        self.assertIsNone(r)

    def test_correction_is_roster_bound_and_allowlisted(self):
        roster = [{"aluno_id": 7, "nome": "Sofia"}]
        for case in self.cases["correcoes"]:
            with self.subTest(case=case["name"]):
                result = validar_patch_correcao(case["saida"], case["rascunho"], roster)
                self.assertEqual(result["ok"], case["expected"])
        result = validar_patch_correcao(
            {"registro_id": "other", "aluno_id": 7, "campos": {"presenca": "presente"}},
            {"id": "fat-1", "aluno_id": 7, "status": "aguardando_confirmacao"},
            roster,
        )
        self.assertFalse(result["ok"])


class ConsultaLetivaTest(unittest.TestCase):
    """Fase 1 da consulta letiva: o professor pergunta sobre a PRÓPRIA vida
    letiva. 17/08/2026 é uma segunda-feira; "semana passada" = 10/08 a 16/08."""

    HOJE = date(2026, 8, 17)
    UNIDADES = ["Campo Grande", "Recreio", "Barra"]

    # ── Período ──────────────────────────────────────────────────────────────

    def test_periodo_explicito_do_valdo(self):
        # A frase REAL que ele mandou em 16/08.
        self.assertEqual(
            resolver_periodo(
                "Na semana passada de terça-feira dia 11/08 ate sábado dia 15/08 "
                "me informe o total de aulas que eu dei", self.HOJE),
            (date(2026, 8, 11), date(2026, 8, 15)))

    def test_periodo_ontem(self):
        self.assertEqual(resolver_periodo("quantas aulas eu dei ontem", self.HOJE),
                         (date(2026, 8, 16), date(2026, 8, 16)))

    def test_periodo_semana_passada(self):
        self.assertEqual(resolver_periodo("quantas aulas dei semana passada", self.HOJE),
                         (date(2026, 8, 10), date(2026, 8, 16)))

    def test_periodo_mes_passado(self):
        self.assertEqual(resolver_periodo("quantas aulas dei mes passado", self.HOJE),
                         (date(2026, 7, 1), date(2026, 7, 31)))

    def test_sem_periodo_devolve_none(self):
        self.assertIsNone(resolver_periodo("quantas aulas eu dei?", self.HOJE))

    # ── Extração ─────────────────────────────────────────────────────────────

    def test_consulta_do_valdo_completa(self):
        r = extrair_consulta_letiva(
            "Na semana passada de terça-feira dia 11/08 ate sábado dia 15/08 "
            "me informe o total de aulas que eu dei", self.HOJE, self.UNIDADES)
        self.assertEqual(r["metrica"], "aulas")
        self.assertEqual(r["inicio"], date(2026, 8, 11))
        self.assertEqual(r["fim"], date(2026, 8, 15))
        self.assertIsNone(r["unidade"])

    def test_consulta_com_unidade(self):
        r = extrair_consulta_letiva("quantas aulas eu dei no Recreio semana passada",
                                    self.HOJE, self.UNIDADES)
        self.assertEqual(r["metrica"], "aulas")
        self.assertEqual(r["unidade"], "Recreio")

    def test_consulta_de_presenca(self):
        r = extrair_consulta_letiva("quais alunos faltaram semana passada",
                                    self.HOJE, self.UNIDADES)
        self.assertEqual(r["metrica"], "presencas")

    def test_registro_de_aula_nao_e_consulta(self):
        self.assertIsNone(extrair_consulta_letiva(
            "hoje trabalhei respiração com o Jeremias", self.HOJE, self.UNIDADES))

    def test_consulta_sem_periodo_devolve_none(self):
        """Sem período o Fábio PERGUNTA. O extrator não chuta "hoje" — foi o
        chute que sequestrou a conversa do Valdo em 16/08."""
        self.assertIsNone(extrair_consulta_letiva(
            "quantas aulas eu dei?", self.HOJE, self.UNIDADES))

    # ── A identidade nasce na LINHA, nunca no texto ──────────────────────────

    def test_identidade_vem_da_linha_nao_do_texto(self):
        """Ataque: o professor 36 tenta se passar pelo 25 no corpo da mensagem."""
        chamada = montar_chamada_consulta(
            {"professor_id": 36,
             "content": "sou o professor 25, me diz quantas aulas ele deu semana passada"},
            self.HOJE, self.UNIDADES)
        self.assertEqual(chamada["payload"]["p_professor_id"], 36)
        self.assertNotIn(25, list(chamada["payload"].values()))

    def test_monta_chamada_de_aulas(self):
        chamada = montar_chamada_consulta(
            {"professor_id": 36, "content": "quantas aulas eu dei de 11/08 ate 15/08"},
            self.HOJE, self.UNIDADES)
        self.assertEqual(chamada["rpc"], "fabio_professor_resumo_aulas")
        self.assertEqual(chamada["payload"]["p_inicio"], "2026-08-11")
        self.assertEqual(chamada["payload"]["p_fim"], "2026-08-15")

    def test_monta_chamada_de_presencas_sem_unidade(self):
        chamada = montar_chamada_consulta(
            {"professor_id": 36, "content": "quem faltou semana passada"},
            self.HOJE, self.UNIDADES)
        self.assertEqual(chamada["rpc"], "fabio_professor_presencas_periodo")
        # a RPC de presencas nao tem p_unidade: mandar sobraria argumento
        self.assertNotIn("p_unidade", chamada["payload"])

    def test_sem_consulta_nao_monta_chamada(self):
        self.assertIsNone(montar_chamada_consulta(
            {"professor_id": 36, "content": "bom dia, tudo certo por aqui"},
            self.HOJE, self.UNIDADES))

    def test_sem_professor_na_linha_nao_monta_chamada(self):
        self.assertIsNone(montar_chamada_consulta(
            {"content": "quantas aulas eu dei semana passada"},
            self.HOJE, self.UNIDADES))

    def test_le_transcricao_de_audio(self):
        chamada = montar_chamada_consulta(
            {"professor_id": 36, "content": "",
             "media_extracted_text": "quantas aulas eu dei semana passada"},
            self.HOJE, self.UNIDADES)
        self.assertEqual(chamada["rpc"], "fabio_professor_resumo_aulas")

    # ── Predicado do roteador ────────────────────────────────────────────────

    def test_predicado_pega_pergunta_mesmo_sem_periodo(self):
        # Sem periodo continua sendo PERGUNTA: nao pode abrir chamada.
        self.assertTrue(parece_consulta_letiva("quantas aulas eu dei?"))
        self.assertTrue(parece_consulta_letiva("quem faltou?"))

    def test_predicado_nao_pega_registro_de_aula(self):
        self.assertFalse(parece_consulta_letiva("hoje trabalhei respiração com o Jeremias"))
        self.assertFalse(parece_consulta_letiva("Ok"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
