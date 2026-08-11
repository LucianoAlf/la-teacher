#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_actions import tratar_mensagem_professor  # noqa: E402


class FakeBackend:
    def __init__(self, action=None, candidates=None):
        self.action = action
        self.candidates = candidates or []
        self.calls = []
        self.uploads = []
        self.removals = []
        self.action_id = "acao-1"

    def rpc(self, name, payload):
        self.calls.append((name, payload))
        if name == "fabio_acao_ativa":
            return self.action
        if name == "fabio_aulas_candidatas":
            return {"ok": True, "codigo": "candidatas_prontas", "candidatas": self.candidates}
        if name == "fabio_iniciar_acao":
            self.action = {
                "id": self.action_id,
                "professor_id": payload["p_professor_id"],
                "wa_message_id": payload["p_wa_message_id"],
                "tipo": payload["p_tipo"],
                "estado": "aberta",
                "storage_path": payload.get("p_storage_path"),
                "payload": payload.get("p_payload") or {},
            }
            return self.action
        if name == "fabio_enfileirar_audio":
            return {"ok": True, "audio_id": "audio-1", "status": "pendente"}
        if name == "fabio_registro_completo":
            return {"ok": True, "registro_id": payload["p_registro_id"], "aula": {"data": "2026-08-11", "hora": "14:00"}, "tronco": {"texto_consolidado": "respiração"}, "fatias": [{"aluno_id": 7, "texto_consolidado": "apoio"}]}
        if name == "fabio_confirmar_registro":
            return {"ok": True, "registro_id": payload["p_registro_id"], "gravadas": 1, "ausentes_pulados": 0}
        if name == "fabio_atualizar_fatia":
            return {"ok": True, "registro_id": payload["p_id"]}
        if name == "fabio_atualizar_devolutiva_rascunho":
            return {"ok": True, "devolutiva_id": payload["p_devolutiva_id"], "texto_normal": payload["p_texto_normal"]}
        if name == "fabio_responder_presenca":
            return {"ok": True, "registro_alvo_id": payload["p_registro_alvo_id"], "presenca": payload["p_presenca"]}
        if name == "fabio_registrar_presencas_aula":
            return {"ok": True, "aula_id": payload["p_aula_emusys_id"], "inseridos": 2, "total_roster": 2}
        if name in {"fabio_status_acao", "fabio_status_audio_fila"}:
            return {"ok": True, "status": "aguardando_confirmacao"}
        if name == "fabio_acao_json":
            return self.action
        if name == "fabio_aplicar_evento_acao":
            return {"ok": True, "evento": payload["p_evento"], "acao_id": payload["p_acao_id"]}
        raise AssertionError(f"RPC inesperada: {name}")

    def download_audio(self, media_url, max_bytes):
        self.calls.append(("download_audio", {"media_url": media_url, "max_bytes": max_bytes}))
        return b"audio-bytes", "ogg", "audio/ogg"

    def upload_audio(self, storage_path, content, mime):
        self.uploads.append((storage_path, content, mime))

    def remove_audio(self, storage_path):
        self.removals.append(storage_path)


def professor_context(**overrides):
    value = {
        "professor_id": 25,
        "channel": "whatsapp",
        "kind": "text",
        "wa_message_id": "wa-1",
        "text": "",
    }
    value.update(overrides)
    return value


class WhatsappActionsTest(unittest.TestCase):
    def test_audio_conversation_forwards_without_upload_or_rpc(self):
        backend = FakeBackend()
        result = tratar_mensagem_professor(professor_context(kind="audio", text="Como foi seu dia?", media_url="https://media/1"), backend)
        self.assertEqual(result, {"handled": False, "reply": None, "forward_to_hermes": True, "action_id": None, "code": "conversation"})
        self.assertFalse(backend.uploads)
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_iniciar_acao"])

    def test_ambiguous_audio_is_staged_and_asks_before_pool_lookup(self):
        backend = FakeBackend(candidates=[{"aula_id": 101}])
        result = tratar_mensagem_professor(professor_context(kind="audio", text="A Sofia faltou e a aula foi boa", media_url="https://media/1"), backend)
        self.assertTrue(result["handled"])
        self.assertFalse(result["forward_to_hermes"])
        self.assertEqual(result["code"], "confirm_audio_intent")
        self.assertEqual(len(backend.uploads), 1)
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_aulas_candidatas"])
        self.assertEqual(backend.action["tipo"], "confirmar_intencao_audio")

    def test_registration_audio_uses_candidates_then_enqueues_once(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(professor_context(kind="audio", text="Na aula de piano de hoje às 14h trabalhei respiração", media_url="https://media/1"), backend)
        self.assertTrue(result["handled"])
        self.assertEqual(result["code"], "audio_enqueued")
        self.assertEqual(len(backend.uploads), 1)
        self.assertEqual(len([x for x in backend.calls if x[0] == "fabio_enfileirar_audio"]), 1)
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        self.assertTrue(enqueue["p_storage_path"].startswith("whatsapp/25/wa-1."))

    def test_selected_audio_uses_distinct_event_keys_for_each_transition(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(
            professor_context(
                kind="audio",
                text="Na aula de piano de hoje as 14h trabalhei respiracao",
                media_url="https://media/1",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        events = [
            payload for name, payload in backend.calls
            if name == "fabio_aplicar_evento_acao"
        ]
        self.assertEqual(
            [payload["p_evento"] for payload in events],
            ["shortlist_definida", "aula_escolhida", "audio_enfileirado"],
        )
        self.assertEqual(
            len({payload["p_wa_message_id"] for payload in events}),
            len(events),
        )

    def test_discriminant_reply_recalculates_pool_before_selecting(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-11", "hora": "19:00", "curso": "Piano"},
            {"aula_id": 102, "data": "2026-08-11", "hora": "16:00", "curso": "Piano"},
            {"aula_id": 103, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"},
            {"aula_id": 104, "data": "2026-08-11", "hora": "12:00", "curso": "Piano"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="refine-1",
                text="Foi a aula de hoje as 19h",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        pool = next(payload for name, payload in backend.calls if name == "fabio_aulas_candidatas")
        self.assertEqual(pool["p_fluxo"], "registro")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)

    def test_two_candidates_wait_for_human_choice_and_do_not_enqueue(self):
        backend = FakeBackend(candidates=[
            {"aula_id": 101, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"},
            {"aula_id": 102, "data": "2026-08-11", "hora": "16:00", "curso": "Piano"},
        ])
        result = tratar_mensagem_professor(professor_context(kind="audio", text="Foi a aula de hoje", media_url="https://media/1"), backend)
        self.assertEqual(result["code"], "choose_audio_class")
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_enfileirar_audio"])
        shortlist = next(payload for name, payload in backend.calls if name == "fabio_aplicar_evento_acao" and payload["p_evento"] == "shortlist_definida")
        self.assertEqual(shortlist["p_dados"]["candidatas"], [101, 102])

    def test_mixed_text_asks_intention_without_call_pool(self):
        backend = FakeBackend(candidates=[{"aula_id": 101}])
        result = tratar_mensagem_professor(professor_context(text="A Sofia faltou e trabalhamos respiração"), backend)
        self.assertEqual(result["code"], "confirm_call_intent")
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_aulas_candidatas"])

    def test_clear_call_uses_independent_call_pool(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(professor_context(text="Só a Sofia faltou, todo mundo veio"), backend)
        self.assertEqual(result["code"], "call_preview")
        pool = next(payload for name, payload in backend.calls if name == "fabio_aulas_candidatas")
        self.assertEqual(pool["p_fluxo"], "chamada")

    def test_existing_action_does_not_capture_parallel_conversation(self):
        action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "old", "tipo": "confirmar_registro", "estado": "aberta", "registro_id": "reg-1", "payload": {}}
        backend = FakeBackend(action=action)
        result = tratar_mensagem_professor(professor_context(wa_message_id="wa-2", text="Qual é minha agenda amanhã?"), backend)
        self.assertFalse(result["handled"])
        self.assertTrue(result["forward_to_hermes"])
        self.assertFalse([call for call in backend.calls if call[0] in {"fabio_confirmar_registro", "fabio_aplicar_evento_acao"}])

    def test_existing_action_cancellation_and_deferral_are_explicit(self):
        for text, expected in (("cancela isso", "cancelled"), ("depois eu vejo", "deferred")):
            action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "old", "tipo": "confirmar_registro", "estado": "aberta", "registro_id": "reg-1", "payload": {}}
            backend = FakeBackend(action=action)
            result = tratar_mensagem_professor(professor_context(wa_message_id="wa-2", text=text), backend)
            self.assertEqual(result["code"], expected)
            event = next(payload for name, payload in backend.calls if name == "fabio_aplicar_evento_acao")
            self.assertEqual(event["p_evento"], "cancelado" if expected == "cancelled" else "adiado")

    def test_correction_uses_guarded_rpc_then_readback(self):
        action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "old", "tipo": "confirmar_registro", "estado": "aberta", "registro_id": "reg-1", "payload": {"rascunho": {"id": "fat-1", "aluno_id": 7, "status": "aguardando_confirmacao"}, "roster": [{"aluno_id": 7, "nome": "Sofia"}]}}
        backend = FakeBackend(action=action)
        result = tratar_mensagem_professor(professor_context(text="não, a Sofia veio"), backend)
        self.assertEqual(result["code"], "correction_applied")
        names = [name for name, _ in backend.calls]
        self.assertIn("fabio_responder_presenca", names)
        self.assertIn("fabio_registro_completo", names)
        self.assertNotIn("update_table", names)

    def test_confirm_receipt_only_after_positive_commit_and_readback(self):
        action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "old", "tipo": "confirmar_registro", "estado": "aberta", "registro_id": "reg-1", "payload": {}}
        backend = FakeBackend(action=action)
        result = tratar_mensagem_professor(professor_context(text="sim"), backend)
        self.assertEqual(result["code"], "confirmed")
        names = [name for name, _ in backend.calls]
        self.assertLess(names.index("fabio_confirmar_registro"), names.index("fabio_registro_completo"))
        self.assertIn("gravadas", result["receipt"])
        self.assertNotIn("fabio_devolutivas", names)

    def test_replay_same_message_does_not_upload_or_start_again(self):
        action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "wa-1", "tipo": "processando_audio", "estado": "processando", "storage_path": "whatsapp/25/wa-1.ogg", "payload": {}}
        backend = FakeBackend(action=action)
        result = tratar_mensagem_professor(professor_context(kind="audio", media_url="https://media/again", text="Na aula trabalhei ritmo"), backend)
        self.assertEqual(result["code"], "replay")
        self.assertFalse(backend.uploads)
        self.assertFalse([call for call in backend.calls if call[0] in {"fabio_iniciar_acao", "fabio_enfileirar_audio"}])

    def test_devolutiva_revision_uses_only_audited_rpc(self):
        backend = FakeBackend()
        result = tratar_mensagem_professor(
            professor_context(
                text="melhora a devolutiva do Lucas",
                devolutiva_id="dev-1",
                devolutiva_texto_apoio_casa="Praticar a leitura por dez minutos.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "devolutiva_draft_updated")
        names = [name for name, _ in backend.calls]
        self.assertIn("fabio_atualizar_devolutiva_rascunho", names)
        self.assertNotIn("update_table", names)
        payload = next(payload for name, payload in backend.calls if name == "fabio_atualizar_devolutiva_rascunho")
        self.assertEqual(payload["p_devolutiva_id"], "dev-1")
        self.assertEqual(payload["p_canal"], "whatsapp")

    def test_devolutiva_revision_without_homework_text_asks_instead_of_calling_rpc(self):
        backend = FakeBackend()
        result = tratar_mensagem_professor(
            professor_context(text="melhora a devolutiva do Lucas", devolutiva_id="dev-1"),
            backend,
        )
        self.assertEqual(result["code"], "devolutiva_revision_question")
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_atualizar_devolutiva_rascunho"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
