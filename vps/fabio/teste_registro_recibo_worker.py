#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fabio_notification_worker as worker  # noqa: E402


def registro_fixture():
    return {
        "ok": True,
        "registro_id": "reg-1",
        "aula": {
            "data": "2026-08-11",
            "hora": "15:00",
            "curso": "Piano T",
            "turma": "Turma de 1",
        },
        "tronco": {
            "campos": {"conteudo": "Leitura de partitura e escalas"},
            "texto_consolidado": "Leitura de partitura e escalas",
        },
        "fatias": [
            {
                "aluno_id": 7,
                "aluno_nome": "Lucas",
                "status": "gravado_emusys",
                "campos": {"presenca": "presente"},
                "texto_consolidado": "Trabalhou leitura de partitura.",
                "devolutiva": {"texto_normal": "Lucas avançou na leitura."},
            },
            {
                "aluno_id": 8,
                "aluno_nome": "Sofia",
                "status": "confirmado",
                "campos": {"presenca": "ausente"},
                "texto_consolidado": "",
            },
            {
                "aluno_id": 9,
                "aluno_nome": "Nathalia",
                "status": "gravado_emusys",
                "campos": {"presenca": "presente"},
                "texto_consolidado": "Trabalhou escalas maiores.",
                "devolutiva": {"texto_normal": "Nathalia manteve bom foco."},
            },
        ],
    }


class ReceiptBackend:
    def __init__(self, *, fail_delivery=False, empty_claim=False, fail_conclude=False):
        self.fail_delivery = fail_delivery
        self.empty_claim = empty_claim
        self.fail_conclude = fail_conclude
        self.calls = []
        self.sent = []

    def rpc(self, name, payload):
        self.calls.append((name, payload))
        if name == "fabio_claim_registro_recibo":
            if self.empty_claim:
                return {"ok": True, "lease_token": "lease-1", "itens": []}
            return {
                "ok": True,
                "lease_token": "lease-1",
                "itens": [{
                    "notificacao_id": "notif-1",
                    "professor_id": 25,
                    "registro_id": "reg-1",
                    "titulo": "Registro confirmado",
                }],
            }
        if name == "fabio_registro_recibo_dados":
            registro = registro_fixture()
            registro["devolutivas"] = [
                {"registro_fatia_id": 7, "texto_normal": "Lucas avançou na leitura."},
                {"registro_fatia_id": 9, "texto_normal": "Nathalia manteve bom foco."},
            ]
            registro["fatias"][0].pop("devolutiva", None)
            registro["fatias"][2].pop("devolutiva", None)
            return registro
        if name == "fabio_concluir_registro_recibo":
            if self.fail_conclude:
                raise RuntimeError("timeout no fechamento")
            return {"ok": True, "notificacao_id": "notif-1", "envio_recibo": "wa-receipt-1"}
        if name == "fabio_falhar_registro_recibo":
            return {"ok": True, "codigo": "falha_registrada"}
        raise AssertionError(f"RPC inesperada: {name}")

    def deliver(self, professor_id, channel, content):
        if self.fail_delivery:
            raise RuntimeError("uazapi indisponivel")
        self.sent.append((professor_id, channel, content))
        return "wa-receipt-1"


class RegistroReciboWorkerTest(unittest.TestCase):
    def setUp(self):
        self.old_mode = worker.REGISTRO_RECIBO_MODE
        self.old_pilot_ids = worker.REGISTRO_RECIBO_PILOT_IDS
        worker.REGISTRO_RECIBO_MODE = "on"
        worker.REGISTRO_RECIBO_PILOT_IDS = set()

    def tearDown(self):
        worker.REGISTRO_RECIBO_MODE = self.old_mode
        worker.REGISTRO_RECIBO_PILOT_IDS = self.old_pilot_ids

    def test_off_mode_never_claims_or_sends(self):
        worker.REGISTRO_RECIBO_MODE = "off"
        backend = ReceiptBackend()
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False, professor_id=25)

        self.assertEqual(result, [{"event": "registro_recibo", "status": "disabled", "claimed": 0, "sent": 0}])
        self.assertEqual(backend.calls, [])
        self.assertEqual(backend.sent, [])

    def test_pilot_without_explicit_argument_claims_only_allowlisted_professors(self):
        worker.REGISTRO_RECIBO_MODE = "pilot"
        worker.REGISTRO_RECIBO_PILOT_IDS = {25, 26}
        backend = ReceiptBackend(empty_claim=True)
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False)

        self.assertEqual(result, [])
        claims = [payload for name, payload in backend.calls if name == "fabio_claim_registro_recibo"]
        self.assertEqual([payload["p_professor_id"] for payload in claims], [25, 26])
        self.assertEqual(backend.sent, [])

    def test_receipt_has_class_students_presence_content_and_draft_feedback(self):
        text = worker.format_registro_recibo(registro_fixture(), "Registro confirmado")

        self.assertIn("Piano T", text)
        self.assertIn("15:00", text)
        self.assertIn("Lucas", text)
        self.assertIn("Sofia", text)
        self.assertIn("Nathalia", text)
        self.assertRegex(text, r"Presen[cç]a")
        self.assertRegex(text, r"Falta")
        self.assertIn("Rascunho de devolutiva", text)
        self.assertIn("Lucas avançou", text)
        self.assertIn("Nathalia manteve", text)
        self.assertNotIn("telefone", text.lower())
        self.assertNotIn("token", text.lower())
        self.assertNotIn("família", text.lower())

    def test_worker_claims_sends_once_and_concludes_with_receipt(self):
        backend = ReceiptBackend()
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False, professor_id=25)

        self.assertEqual(result[0]["status"], "sent")
        self.assertEqual(len(backend.sent), 1)
        claim = next(payload for name, payload in backend.calls if name == "fabio_claim_registro_recibo")
        self.assertEqual(claim["p_professor_id"], 25)
        conclude = next(payload for name, payload in backend.calls if name == "fabio_concluir_registro_recibo")
        self.assertEqual(conclude["p_notificacao_id"], "notif-1")
        self.assertEqual(conclude["p_lease_token"], "lease-1")
        self.assertEqual(conclude["p_envio_recibo"], "wa-receipt-1")
        self.assertIn("Lucas", conclude["p_corpo"])

    def test_transport_failure_marks_receipt_failed_without_concluding(self):
        backend = ReceiptBackend(fail_delivery=True)
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False, professor_id=25)

        self.assertEqual(result[0]["status"], "failed")
        self.assertTrue(any(name == "fabio_falhar_registro_recibo" for name, _ in backend.calls))
        self.assertFalse(any(name == "fabio_concluir_registro_recibo" for name, _ in backend.calls))

    def test_close_failure_never_retries_the_whatsapp_send(self):
        backend = ReceiptBackend(fail_conclude=True)
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False, professor_id=25)

        self.assertEqual(result[0]["status"], "delivered_unclosed")
        self.assertEqual(len(backend.sent), 1)
        self.assertEqual(len([name for name, _ in backend.calls if name == "fabio_concluir_registro_recibo"]), 2)
        self.assertFalse(any(name == "fabio_falhar_registro_recibo" for name, _ in backend.calls))

    def test_empty_claim_replay_does_not_send_again(self):
        backend = ReceiptBackend(empty_claim=True)
        with patch.object(worker, "rpc", side_effect=backend.rpc), \
             patch.object(worker, "deliver", side_effect=backend.deliver):
            result = worker.run_registro_recibos("whatsapp", False, professor_id=25)

        self.assertEqual(result, [])
        self.assertEqual(backend.sent, [])

    def test_reconciler_has_no_receipt_sender(self):
        source = (Path(__file__).with_name("fabio_whatsapp_reconciler.py")).read_text(encoding="utf-8")
        self.assertNotIn("fabio_claim_registro_recibo", source)
        self.assertNotIn("send_whatsapp_text", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
