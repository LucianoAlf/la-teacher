#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_reconciler import cleanup_once, reconcile_once  # noqa: E402


class FakeBackend:
    def __init__(self, *, process_items=None, audio=None, readback=None,
                 reconcile_result=None, cleanup_items=None, proof=None,
                 cleanup_result=None):
        self.process_items = list(process_items or [])
        self.audio = audio or {}
        self.readback = readback or {}
        self.reconcile_result = reconcile_result or {"ok": True, "codigo": "reconciliacao_concluida"}
        self.cleanup_items = list(cleanup_items or [])
        self.proof = proof or {"ok": True, "codigo": "limpeza_provada", "pode_remover": True}
        self.cleanup_result = cleanup_result or {"ok": True, "codigo": "limpeza_concluida"}
        self.calls = []
        self.removals = []

    def rpc(self, name, payload):
        self.calls.append((name, payload))
        if name == "fabio_claim_acoes_processando":
            return {"ok": True, "itens": self.process_items}
        if name == "fabio_status_audio_fila":
            return self.audio
        if name == "fabio_registro_completo":
            return self.readback
        if name == "fabio_concluir_reconciliacao":
            return self.reconcile_result
        if name == "fabio_claim_acoes_limpeza":
            return {"ok": True, "itens": self.cleanup_items}
        if name == "fabio_provar_limpeza":
            return self.proof
        if name == "fabio_concluir_limpeza":
            return self.cleanup_result
        raise AssertionError(f"RPC inesperada: {name}")

    def remove_audio(self, storage_path):
        self.calls.append(("remove_audio", {"storage_path": storage_path}))
        self.removals.append(storage_path)

    def send_preview(self, action_id, professor_id, content):
        self.calls.append(("send_preview", {
            "action_id": action_id,
            "professor_id": professor_id,
            "content": content,
        }))
        return {"ok": True, "wa_message_id": f"preview:{action_id}"}


def action(*, attempts=0, action_id="acao-1"):
    return {
        "id": action_id,
        "professor_id": 25,
        "audio_id": "audio-1",
        "tipo": "processando_audio",
        "estado": "processando",
        "payload": {"reconciliador": {"tentativas": attempts}},
    }


def process_item(item=None, token="lease-1"):
    return {"acao": item or action(), "lease_token": token}


class WhatsappReconcilerTest(unittest.TestCase):
    def test_promotes_only_authoritative_draft_after_audio_poll(self):
        backend = FakeBackend(
            process_items=[process_item()],
            audio={"ok": True, "status": "normalizado", "registro_id": "reg-1"},
            readback={
                "ok": True,
                "aula": {"curso": "Piano T", "turma": "P_Qui_19", "data_aula": "2026-08-06", "hora": "19:00:00"},
                "tronco": {
                    "id": "reg-1",
                    "status": "aguardando_confirmacao",
                    "campos": {"objetivo": "Coordenar as duas maos", "atividades": "Jingle Bells", "repertorio": "Jingle Bells", "dever_casa": None, "obs_gerais": None},
                },
                "fatias": [{"aluno_id": 7, "aluno_nome": "Pedro", "presenca": None, "campos": {"progresso": "Tocou com as duas maos", "observacao": None, "proximo_passo": None}}],
                "incertezas": [],
            },
        )

        result = reconcile_once(backend, limit=7)

        self.assertEqual(result["promovidas"], 1)
        conclusion = next(payload for name, payload in backend.calls if name == "fabio_concluir_reconciliacao")
        self.assertEqual(conclusion["p_evento"], "rascunho_pronto")
        self.assertEqual(conclusion["p_dados"]["registro_id"], "reg-1")
        self.assertEqual(conclusion["p_lease_token"], "lease-1")
        self.assertEqual(backend.calls[0][1]["p_limite"], 7)
        names = [name for name, _ in backend.calls]
        self.assertLess(names.index("send_preview"), names.index("fabio_concluir_reconciliacao"))
        preview = next(payload for name, payload in backend.calls if name == "send_preview")
        self.assertIn("Preview do registro", preview["content"])
        self.assertIn("Objetivo: Coordenar as duas maos", preview["content"])
        self.assertIn("Dever de casa: —", preview["content"])
        self.assertIn("Pedro", preview["content"])
        self.assertIn("Presente (padrão ao confirmar)", preview["content"])

    def test_draft_not_ready_is_temporary_then_terminal_at_bound(self):
        item = process_item(action(attempts=0))
        backend = FakeBackend(
            process_items=[item],
            audio={"ok": True, "status": "normalizado", "registro_id": "reg-1"},
            readback={"ok": True, "tronco": {"id": "reg-1", "status": "rascunho"}},
        )
        first = reconcile_once(backend)
        first_conclusion = next(payload for name, payload in backend.calls if name == "fabio_concluir_reconciliacao")
        self.assertEqual(first["retentativas"], 1)
        self.assertEqual(first_conclusion["p_evento"], "falha_temporaria")
        self.assertEqual(first_conclusion["p_dados"]["tentativas"], 1)

        terminal_backend = FakeBackend(
            process_items=[process_item(action(attempts=2))],
            audio={"ok": True, "status": "normalizado", "registro_id": "reg-1"},
            readback={"ok": True, "tronco": {"id": "reg-1", "status": "rascunho"}},
        )
        second = reconcile_once(terminal_backend)
        second_conclusion = next(payload for name, payload in terminal_backend.calls if name == "fabio_concluir_reconciliacao")
        self.assertEqual(second["terminais"], 1)
        self.assertEqual(second_conclusion["p_evento"], "falha_terminal")
        self.assertEqual(second_conclusion["p_dados"]["tentativas"], 3)

    def test_queue_error_is_terminal_without_readback(self):
        backend = FakeBackend(
            process_items=[process_item()],
            audio={"ok": True, "status": "erro", "tem_erro": True},
        )

        result = reconcile_once(backend)

        self.assertEqual(result["terminais"], 1)
        self.assertFalse([name for name, _ in backend.calls if name == "fabio_registro_completo"])
        conclusion = next(payload for name, payload in backend.calls if name == "fabio_concluir_reconciliacao")
        self.assertEqual(conclusion["p_evento"], "falha_terminal")

    def test_stale_lease_is_reported_without_local_retry(self):
        backend = FakeBackend(
            process_items=[process_item()],
            audio={"ok": True, "status": "normalizado", "registro_id": "reg-1"},
            readback={"ok": True, "tronco": {"id": "reg-1", "status": "aguardando_confirmacao"}, "fatias": [{"aluno_nome": "Aluno", "campos": {}}]},
            reconcile_result={"ok": False, "codigo": "lease_invalido"},
        )

        result = reconcile_once(backend)

        self.assertEqual(result["stale"], 1)
        self.assertEqual(len([name for name, _ in backend.calls if name == "fabio_concluir_reconciliacao"]), 1)

    def test_cleanup_never_removes_before_negative_proof_is_cleared(self):
        backend = FakeBackend(
            cleanup_items=[{"acao_id": "acao-1", "storage_path": "whatsapp/25/a.ogg", "lease_token": "lease-c"}],
            proof={"ok": True, "codigo": "limpeza_reprovada", "pode_remover": False, "motivo": "registro_confirmado_referencia_storage"},
        )

        result = cleanup_once(backend)

        self.assertEqual(result["bloqueadas"], 1)
        self.assertFalse(backend.removals)
        self.assertFalse([name for name, _ in backend.calls if name == "fabio_concluir_limpeza"])

    def test_cleanup_proves_then_removes_then_completes(self):
        backend = FakeBackend(
            cleanup_items=[{"acao_id": "acao-1", "storage_path": "whatsapp/25/a.ogg", "lease_token": "lease-c"}],
        )

        result = cleanup_once(backend)

        self.assertEqual(result["limpas"], 1)
        self.assertEqual(backend.removals, ["whatsapp/25/a.ogg"])
        names = [name for name, _ in backend.calls]
        self.assertLess(names.index("fabio_provar_limpeza"), names.index("remove_audio"))
        self.assertLess(names.index("remove_audio"), names.index("fabio_concluir_limpeza"))

    def test_new_cycle_has_no_process_local_lease_state(self):
        backend = FakeBackend(
            process_items=[process_item()],
            audio={"ok": True, "status": "normalizado", "registro_id": "reg-1"},
            readback={"ok": True, "tronco": {"id": "reg-1", "status": "aguardando_confirmacao"}, "fatias": [{"aluno_nome": "Aluno", "campos": {}}]},
        )

        first = reconcile_once(backend)
        second = reconcile_once(backend)

        self.assertEqual(first["promovidas"], 1)
        self.assertEqual(second["promovidas"], 1)
        self.assertEqual(len([name for name, _ in backend.calls if name == "fabio_claim_acoes_processando"]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
