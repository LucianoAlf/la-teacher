#!/usr/bin/env python3
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_intents import (  # noqa: E402
    classificar_intencao_audio,
    classificar_intencao_texto,
    interpretar_resposta_pendente,
    reduzir_shortlist,
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
