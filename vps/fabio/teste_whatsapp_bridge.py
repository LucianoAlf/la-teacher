#!/usr/bin/env python3
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("FABIO_CHAT_BRIDGE_LOG", str(Path(os.getenv("TEMP", ".")) / "fabio-whatsapp-bridge-test.log"))
os.environ.setdefault("FABIO_WHATSAPP_REGISTRO_MODE", "off")

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fabio_chat_bridge as bridge  # noqa: E402


def professor_row(*, professor_id=25, kind="text", text="bater a chamada da aula de hoje"):
    return {
        "id": "chat-1",
        "identidade_tipo": "professor",
        "professor_id": professor_id,
        "role": "professor",
        "kind": kind,
        "content": text if kind == "text" else None,
        "media_extracted_text": text if kind == "audio" else None,
        "media_url": "https://media/audio" if kind == "audio" else None,
        "media_mime": "audio/ogg" if kind == "audio" else None,
        "channel": "whatsapp",
        "wa_message_id": "wa-1",
        "criado_em": "2026-08-11T12:00:00+00:00",
    }


class BridgeIntegrationTest(unittest.TestCase):
    def tearDown(self):
        bridge.WHATSAPP_REGISTRO_MODE = "off"
        bridge.WHATSAPP_REGISTRO_PILOT_IDS = set()

    def test_invalid_mode_is_closed_to_off(self):
        self.assertEqual(bridge.normalizar_whatsapp_registro_mode("unexpected"), "off")
        self.assertEqual(bridge.normalizar_whatsapp_registro_mode(None), "off")

    def test_off_preserves_current_hermes_behavior(self):
        row = professor_row()
        calls = []
        with patch.object(bridge, "claim_next_message", return_value=row), \
             patch.object(bridge, "collect_message_batch", return_value=[row]), \
             patch.object(bridge, "merge_message_batch", return_value=row), \
             patch.object(bridge, "generate_answer", side_effect=lambda value: (calls.append(value) or ("resposta Hermes", "test"))), \
             patch.object(bridge, "insert_fabio_response_for_row"), \
             patch.object(bridge, "send_whatsapp_text"), \
             patch.object(bridge, "mark_done"):
            result = bridge.process_one()
        self.assertTrue(result)
        self.assertEqual(len(calls), 1)

    def test_shadow_classifies_without_action_backend_and_keeps_hermes(self):
        row = professor_row(kind="audio", text="trabalhei respiração e repertório")
        bridge.WHATSAPP_REGISTRO_MODE = "shadow"
        calls = []
        with patch.object(bridge, "claim_next_message", return_value=row), \
             patch.object(bridge, "collect_message_batch", return_value=[row]), \
             patch.object(bridge, "merge_message_batch", return_value=row), \
             patch.object(bridge, "tratar_mensagem_professor", side_effect=AssertionError("shadow nao abre acao")), \
             patch.object(bridge, "generate_answer", side_effect=lambda value: (calls.append(value) or ("resposta Hermes", "test"))), \
             patch.object(bridge, "insert_fabio_response_for_row"), \
             patch.object(bridge, "send_whatsapp_text"), \
             patch.object(bridge, "mark_done"), \
             patch.object(bridge, "log") as log_mock:
            result = bridge.process_one()
        self.assertTrue(result)
        self.assertEqual(len(calls), 1)
        self.assertTrue(any(call.args[0] == "whatsapp_registro_shadow" for call in log_mock.call_args_list))

    def test_pilot_only_intercepts_allowlisted_professor(self):
        bridge.WHATSAPP_REGISTRO_MODE = "pilot"
        bridge.WHATSAPP_REGISTRO_PILOT_IDS = {25}
        self.assertEqual(bridge.whatsapp_registro_mode(professor_row(professor_id=25)), "pilot")
        self.assertEqual(bridge.whatsapp_registro_mode(professor_row(professor_id=26)), "off")
        self.assertEqual(bridge.whatsapp_registro_mode(dict(professor_row(), channel="app")), "off")

    def test_capacity_text_matches_effective_mode(self):
        row = professor_row()
        bridge.WHATSAPP_REGISTRO_MODE = "off"
        self.assertIn("ainda nao consegue gravar", bridge.capacidade_professor(row).lower())
        bridge.WHATSAPP_REGISTRO_MODE = "on"
        self.assertIn("fluxo guardado", bridge.capacidade_professor(row).lower())

    def test_on_intercepts_after_batching_before_generate_answer(self):
        row = professor_row()
        bridge.WHATSAPP_REGISTRO_MODE = "on"
        order = []
        action_result = {"handled": True, "reply": "Chamada confirmada?", "code": "call_preview", "action_id": "acao-1"}
        with patch.object(bridge, "claim_next_message", return_value=row), \
             patch.object(bridge, "collect_message_batch", side_effect=lambda value: (order.append("batch") or [value])), \
             patch.object(bridge, "merge_message_batch", side_effect=lambda value: (order.append("merge") or row)), \
             patch.object(bridge, "tratar_mensagem_professor", side_effect=lambda context, backend: (order.append("action") or action_result)), \
             patch.object(bridge, "generate_answer", side_effect=AssertionError("Hermes nao deve rodar")), \
             patch.object(bridge, "insert_fabio_response_for_row"), \
             patch.object(bridge, "send_whatsapp_text"), \
             patch.object(bridge, "mark_done"):
            result = bridge.process_one()
        self.assertTrue(result)
        self.assertEqual(order, ["batch", "merge", "action"])

    def test_action_reply_does_not_append_devolutiva_text(self):
        row = professor_row()
        bridge.WHATSAPP_REGISTRO_MODE = "on"
        sent = []
        action_result = {"handled": True, "reply": "Pronto: chamada registrada.", "code": "confirmed_call", "action_id": "acao-1"}
        with patch.object(bridge, "tratar_mensagem_professor", return_value=action_result), \
             patch.object(bridge, "insert_fabio_response_for_row", side_effect=lambda value, text, channel: sent.append(text)), \
             patch.object(bridge, "send_whatsapp_text"), \
             patch.object(bridge, "log"):
            self.assertTrue(bridge.try_handle_whatsapp_action(row))
        self.assertEqual(sent, ["Pronto: chamada registrada."])
        self.assertNotIn("devolutiva", sent[0].lower())

    def test_multi_message_batch_bypasses_new_action_path(self):
        first = professor_row(kind="audio", text="trabalhei ritmo")
        second = dict(professor_row(kind="audio", text="trabalhei repertório"), id="chat-2", wa_message_id="wa-2")
        with patch.object(bridge, "tratar_mensagem_professor", side_effect=AssertionError("lote nao abre uma acao")), \
             patch.object(bridge, "generate_answer", return_value=("resposta Hermes", "test")), \
             patch.object(bridge, "insert_fabio_response_for_row"), \
             patch.object(bridge, "send_whatsapp_text"), \
             patch.object(bridge, "mark_done"):
            bridge.WHATSAPP_REGISTRO_MODE = "on"
            with patch.object(bridge, "claim_next_message", return_value=first), \
                 patch.object(bridge, "collect_message_batch", return_value=[first, second]):
                self.assertTrue(bridge.process_one())

    def test_media_ingress_persists_inbox_before_ack_and_does_not_transcribe(self):
        body = {"id": "wa-audio-1", "chatid": "5511999999999@s.whatsapp.net", "messageType": "audio"}
        events = []
        identity = {"tipo": "professor", "professor_id": 25}
        with patch.object(bridge, "resolve_identity_by_phone", return_value=identity), \
             patch.object(bridge, "insert_identity_message", side_effect=lambda *args, **kwargs: (events.append("insert") or {"duplicate": False})), \
             patch.object(bridge, "uazapi_transcrever_audio", side_effect=AssertionError("transcricao antes do ack")):
            result = bridge.ingest_media_message(body, "5511999999999", "wa-audio-1", "audio")
        self.assertEqual(result["status"], "media")
        self.assertEqual(events, ["insert"])

    def test_audio_hydration_happens_only_after_claim_and_patches_same_row(self):
        row = professor_row(kind="audio", text="")
        with patch.object(bridge, "uazapi_transcrever_audio", return_value={"texto": "trabalhei ritmo", "url": "https://media/1", "mime": "audio/ogg"}), \
             patch.object(bridge, "sb_patch") as patch_mock:
            response = type("Response", (), {"status_code": 200, "text": "", "json": lambda self: [dict(row, media_extracted_text="trabalhei ritmo")]})()
            patch_mock.return_value = response
            hydrated = bridge.hydrate_audio_row(row)
        self.assertEqual(hydrated["media_extracted_text"], "trabalhei ritmo")
        self.assertEqual(patch_mock.call_args.args[0], "/rest/v1/fabio_chat_mensagens")
        self.assertEqual(patch_mock.call_args.args[2]["media_extracted_text"], "trabalhei ritmo")

    def test_remove_audio_uses_storage_bulk_delete_contract(self):
        backend = bridge.FabioBridgeBackend("fabio-audios")
        response = type("Response", (), {"status_code": 200, "text": ""})()
        with patch.object(bridge, "SUPABASE_KEY", "test-key"), \
             patch.object(bridge.requests, "delete", return_value=response) as delete_mock:
            backend.remove_audio("whatsapp/25/e2e.ogg")
        delete_mock.assert_called_once()
        self.assertTrue(delete_mock.call_args.args[0].endswith("/storage/v1/object/fabio-audios"))
        self.assertEqual(delete_mock.call_args.kwargs["json"], {"prefixes": ["whatsapp/25/e2e.ogg"]})

    def test_preview_outbox_replay_does_not_send_twice(self):
        backend = bridge.FabioBridgeBackend("fabio-audios")
        existing = [{
            "id": "chat-preview-1",
            "role": "fabio",
            "professor_id": 25,
            "channel": "whatsapp",
            "content": "preview canonico",
            "fabio_done_at": "2026-08-12T00:00:00+00:00",
            "wa_message_id": "fabio-preview:acao-1",
        }]
        with patch.object(bridge, "sb_get", return_value=existing), \
             patch.object(bridge, "send_whatsapp_text") as send_mock:
            result = backend.send_preview("acao-1", 25, "preview canonico")
        self.assertTrue(result["ok"])
        self.assertTrue(result["ja_enviado"])
        send_mock.assert_not_called()

    def test_preview_outbox_uncertain_delivery_never_resends(self):
        backend = bridge.FabioBridgeBackend("fabio-audios")
        existing = [{
            "id": "chat-preview-uncertain",
            "role": "fabio",
            "professor_id": 25,
            "channel": "whatsapp",
            "content": "preview canonico",
            "fabio_done_at": None,
            "wa_message_id": "fabio-preview:acao-uncertain",
        }]
        with patch.object(bridge, "sb_get", return_value=existing), \
             patch.object(bridge, "send_whatsapp_text") as send_mock:
            with self.assertRaisesRegex(RuntimeError, "preview_entrega_incerta"):
                backend.send_preview("acao-uncertain", 25, "preview canonico")
        send_mock.assert_not_called()

    def test_preview_outbox_persists_sends_and_marks_done(self):
        backend = bridge.FabioBridgeBackend("fabio-audios")
        inserted = [{
            "id": "chat-preview-2",
            "role": "fabio",
            "professor_id": 25,
            "channel": "whatsapp",
            "content": "preview canonico",
            "wa_message_id": "fabio-preview:acao-2",
            "fabio_done_at": None,
        }]
        post_response = type("Response", (), {
            "status_code": 201,
            "text": "",
            "json": lambda self: inserted,
        })()
        patch_response = type("Response", (), {"status_code": 200, "text": ""})()
        with patch.object(bridge, "sb_get", return_value=[]), \
             patch.object(bridge, "sb_post", return_value=post_response) as post_mock, \
             patch.object(bridge, "send_whatsapp_text", return_value="wa-out-2") as send_mock, \
             patch.object(bridge, "sb_patch", return_value=patch_response) as patch_mock:
            result = backend.send_preview("acao-2", 25, "preview canonico")
        self.assertTrue(result["ok"])
        self.assertFalse(result["ja_enviado"])
        self.assertEqual(post_mock.call_args.args[1]["wa_message_id"], "fabio-preview:acao-2")
        send_mock.assert_called_once_with(25, "preview canonico")
        self.assertEqual(patch_mock.call_args.args[1], {"id": "eq.chat-preview-2"})
        self.assertIn("fabio_done_at", patch_mock.call_args.args[2])

    def test_preview_outbox_concurrent_insert_loser_never_sends(self):
        backend = bridge.FabioBridgeBackend("fabio-audios")
        concurrent = [{
            "id": "chat-preview-race",
            "role": "fabio",
            "professor_id": 25,
            "channel": "whatsapp",
            "content": "preview canonico",
            "fabio_done_at": "2026-08-12T10:35:00+00:00",
            "wa_message_id": "fabio-preview:acao-race",
        }]
        conflict = type("Response", (), {
            "status_code": 409,
            "text": "conflict",
        })()
        with patch.object(bridge, "sb_get", side_effect=[[], concurrent]), \
             patch.object(bridge, "sb_post", return_value=conflict), \
             patch.object(bridge, "send_whatsapp_text") as send_mock:
            result = backend.send_preview("acao-race", 25, "preview canonico")
        self.assertTrue(result["ja_enviado"])
        send_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
