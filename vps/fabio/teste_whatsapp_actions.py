#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_whatsapp_actions import tratar_mensagem_professor  # noqa: E402
from fabio_whatsapp_intents import reduzir_shortlist  # noqa: E402


class FakeBackend:
    def __init__(self, action=None, candidates=None, readback_status="aguardando_confirmacao",
                 participacao=None, participacao_explode=False):
        self.action = action
        self.candidates = candidates or []
        self.calls = []
        self.uploads = []
        self.removals = []
        self.action_id = "acao-1"
        self.readback_status = readback_status
        # Ocorrência de substituição em SHADOW. Resposta controlável por teste;
        # `participacao_explode` simula o banco fora do ar pra provar que a
        # falha na camada shadow NUNCA derruba o registro normal (freio do Alf).
        self.participacao_response = participacao or {
            "ok": True, "ocorrencia_id": "oc-1", "estado": "candidata",
            "precisa_confirmar": True, "ja_existia": False,
        }
        self.participacao_explode = participacao_explode
        # A fila de espera do áudio (migration 20260815110000). O dublê guarda
        # linha de verdade, com as MESMAS travas de produção — FIFO, um destino
        # só e consumo atômico. Dublê mais permissivo que o banco é verde que
        # não vale (já custou o teto de 3 da shortlist, acima).
        self.parqueados = []
        self._sequencia_parqueado = 0

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
        if name == "fabio_participacao_registrar_candidata":
            if self.participacao_explode:
                raise RuntimeError("banco fora do ar (simulado)")
            return self.participacao_response
        if name == "fabio_registro_completo":
            return {
                "ok": True,
                "registro_id": payload["p_registro_id"],
                "aula": {"data": "2026-08-11", "hora": "14:00"},
                "tronco": {"id": payload["p_registro_id"], "status": self.readback_status},
                "fatias": [{"aluno_id": 7, "texto_consolidado": "apoio"}],
            }
        if name == "fabio_registro_completo_legacy":
            return {"ok": True, "registro_id": payload["p_registro_id"], "aula": {"data": "2026-08-11", "hora": "14:00"}, "tronco": {"texto_consolidado": "respiração"}, "fatias": [{"aluno_id": 7, "texto_consolidado": "apoio"}]}
        if name == "fabio_parquear_audio":
            if any(p["wa_message_id"] == payload["p_wa_message_id"]
                   and p["professor_id"] == payload["p_professor_id"]
                   for p in self.parqueados):
                return {"ok": True, "ja_existia": True}
            self._sequencia_parqueado += 1
            self.parqueados.append({
                "id": f"parq-{self._sequencia_parqueado}",
                "ordem": self._sequencia_parqueado,
                "professor_id": payload["p_professor_id"],
                "wa_message_id": payload["p_wa_message_id"],
                "storage_path": payload["p_storage_path"],
                "transcricao": payload.get("p_transcricao") or "",
                "duracao_segundos": payload.get("p_duracao_segundos") or 0,
                "consumido": False,
                "descartado": False,
            })
            return {"ok": True, "ja_existia": False, "id": self.parqueados[-1]["id"]}
        if name == "fabio_audio_parqueado_proximo":
            espera = [p for p in self.parqueados
                      if p["professor_id"] == payload["p_professor_id"]
                      and not p["consumido"] and not p["descartado"]]
            if not espera:
                return {}
            return dict(sorted(espera, key=lambda p: p["ordem"])[0])
        if name in {"fabio_audio_parqueado_consumir", "fabio_audio_parqueado_descartar"}:
            alvo = next((p for p in self.parqueados if p["id"] == payload["p_id"]), None)
            if not alvo or alvo["consumido"] or alvo["descartado"]:
                return {"ok": False}
            if name == "fabio_audio_parqueado_consumir":
                alvo["consumido"] = True
            else:
                alvo["descartado"] = True
                alvo["motivo"] = payload.get("p_motivo")
            return {"ok": True}
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
        if name == "fabio_confirmar_chamada_acao":
            # Confirmar FECHA a ação em produção. O dublê precisa fechar também:
            # é justamente a ação fechando que abre a vez do áudio parqueado.
            self.action = None
            return {"ok": True, "codigo": "chamada_confirmada", "escrita": {"aula_id": 101, "inseridos": 2, "total_roster": 2}}
        if name in {"fabio_status_acao", "fabio_status_audio_fila"}:
            return {"ok": True, "status": "aguardando_confirmacao"}
        if name == "fabio_acao_json":
            return self.action
        if name == "fabio_aplicar_evento_acao":
            # Em produção o evento `shortlist_definida` é o que ESCREVE
            # `candidatas` na linha da ação (medido em 15/08: as ações com
            # esse evento têm candidatas, a do Isaque — que só teve
            # `pergunta_refinada` — tem lista vazia). O dublê precisa fazer o
            # mesmo, senão nenhum teste consegue enxergar a diferença.
            if payload["p_evento"] == "shortlist_definida" and isinstance(self.action, dict):
                candidatas = list((payload.get("p_dados") or {}).get("candidatas") or [])
                # `fabio_shortlist_valida` exige `cardinality between 1 and 3`.
                # O dublê tem que recusar igual: sem isto o teste ficou verde
                # com uma shortlist de 10 que a RPC real devolveu
                # `shortlist_invalida` — dublê mais permissivo que produção é
                # verde que não vale.
                if not 1 <= len(candidatas) <= 3:
                    return {"ok": False, "codigo": "shortlist_invalida"}
                self.action["candidatas"] = candidatas
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
    # ── A consulta letiva vence TUDO — inclusive audio e acao pendente ────────
    # Medido em 17/08/2026, na fala REAL do Valdo (por AUDIO): "lista o total de
    # aulas que eu ministrei de terca 11/08 a sabado 15/08". Ele tinha uma
    # `escolher_aula_chamada` aberta desde a noite de 16/08 (a ferida do "Ok"),
    # entao cada audio dele virava "ainda nao sei de qual aula voce esta
    # falando" e a consulta nunca era alcancada. Dois buracos ao mesmo tempo:
    #   (A) o caminho de AUDIO nunca checava parece_consulta_letiva;
    #   (B) uma acao pendente curto-circuitava antes de qualquer checagem.
    # Meus testes ao vivo nao pegaram porque falar_com_fabio.py manda TEXTO e
    # nunca com acao aberta.
    CONSULTA_VALDO = ("Fala, Fabio, bom dia. Me faz um favor? Lista pra mim o "
                      "numero total de aulas que eu ministrei na semana passada, "
                      "de terca 11/08 a sabado 15/08?")

    def test_audio_consulta_letiva_forwards_without_opening_action(self):
        # Buraco (A): audio de consulta, SEM acao pendente. Nao pode abrir
        # confirmar_intencao_audio -- e pergunta, nao lancamento.
        backend = FakeBackend()
        result = tratar_mensagem_professor(
            professor_context(kind="audio", text=self.CONSULTA_VALDO, media_url="https://media/1"),
            backend,
        )
        self.assertEqual(result["code"], "conversation")
        self.assertFalse(result["handled"])
        self.assertTrue(result["forward_to_hermes"])
        self.assertFalse(backend.uploads)
        self.assertFalse([c for c in backend.calls if c[0] == "fabio_iniciar_acao"])

    def test_audio_consulta_letiva_breaks_out_of_pending_call_action(self):
        # Buraco (B): a MESMA consulta, agora com a chamada pendente aberta do
        # Valdo. Tem que sair da acao (forward), nao virar "qual aula?".
        action = {
            "id": "acao-1", "professor_id": 36, "wa_message_id": "chamada-original",
            "tipo": "escolher_aula_chamada", "estado": "aberta", "candidatas": [],
            "payload": {"transcricao": "bater chamada", "intencao": "ambiguo"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "14:00", "curso": "Guitarra T"},
        ])
        result = tratar_mensagem_professor(
            professor_context(kind="audio", professor_id=36, wa_message_id="consulta-nova",
                              text=self.CONSULTA_VALDO, media_url="https://media/1"),
            backend,
        )
        self.assertEqual(result["code"], "conversation")
        self.assertFalse(result["handled"])
        self.assertTrue(result["forward_to_hermes"])
        # Nao pode ter caido no dead-end da chamada.
        self.assertNotIn(result["code"], {"choose_call_class", "refine_class", "no_candidate"})

    def test_pending_call_still_accepts_a_real_class_refinement(self):
        # A trava e ESTREITA: uma resposta de verdade a "qual aula?" continua
        # refinando. Nao e pra consulta engolir o fluxo legitimo de chamada.
        action = {
            "id": "acao-1", "professor_id": 36, "wa_message_id": "chamada-original",
            "tipo": "escolher_aula_chamada", "estado": "aberta", "candidatas": [],
            "payload": {"transcricao": "bater chamada", "intencao": "ambiguo"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "14:00", "curso": "Guitarra T"},
        ])
        result = tratar_mensagem_professor(
            professor_context(professor_id=36, wa_message_id="refine-1",
                              text="foi a aula de sabado as 14h"),
            backend,
        )
        self.assertNotEqual(result["code"], "conversation")

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

    def test_uazapi_message_id_never_leaks_unsafe_chars_into_storage_path(self):
        """O id real do UAZAPI e `<telefone>:<hash>` — com dois-pontos.

        Bug de producao (15/08/2026, prof. Valdo): o id entrava cru no nome do
        objeto. Upload 200 e assinatura 200, mas o GET da URL assinada voltava
        400 InvalidSignature — provado com dois objetos identicos, um com ':' e
        outro sem. O audio morria e o professor ficava no silencio.

        Os testes antigos passavam porque a fixture usava `wa-1`, um id limpo
        que o UAZAPI nunca produz.
        """
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11", "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(
            professor_context(
                kind="audio",
                text="Na aula de piano de hoje às 14h trabalhei respiração",
                media_url="https://media/1",
                wa_message_id="5521998250178:A5B8AC2B450B8544E2DDBC41AA3EC59D",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        path = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")["p_storage_path"]

        self.assertNotIn(":", path, f"dois-pontos quebra a URL assinada (400 InvalidSignature): {path}")
        # Regra ampla: so o alfabeto seguro sobrevive no nome do objeto.
        nome = path.rsplit("/", 1)[-1]
        self.assertRegex(nome, r"^[A-Za-z0-9._-]+$", f"nome de objeto com caractere inseguro: {nome}")
        # O caminho continua roteado pelo professor e o id segue distinguivel.
        self.assertTrue(path.startswith("whatsapp/25/"), path)
        self.assertIn("A5B8AC2B450B8544E2DDBC41AA3EC59D", path)

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

    def test_pending_audio_choice_accepts_natural_reply_only_within_shortlist(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15", "alunos": [{"nome": "Beatriz Ohana"}]},
            {"aula_id": 102, "data": "2026-08-06", "hora": "20:00", "curso": "Canto T", "turma": "C_Qui_20", "alunos": [{"nome": "Outra Aluna"}]},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15", "alunos": [{"nome": "Beatriz Ohana"}]},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural",
                kind="audio",
                text="Estou falando da Beatriz Ohana, das 15 horas, da Unidade Barra.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        self.assertNotEqual(enqueue["p_aula_id"], 103)

    def test_pending_audio_choice_ambiguous_natural_reply_does_not_mutate_shortlist(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
            {"aula_id": 102, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural-ambigua",
                kind="audio",
                text="Foi a aula das 15 horas.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "choose_audio_class")
        names = [name for name, _ in backend.calls]
        self.assertNotIn("fabio_aplicar_evento_acao", names)
        self.assertNotIn("fabio_enfileirar_audio", names)

    def test_pending_audio_choice_natural_hour_selects_without_shortlist_event(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
            {"aula_id": 102, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural-horario",
                kind="audio",
                text="Foi a aula das 15 horas.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        events = [
            payload["p_evento"] for name, payload in backend.calls
            if name == "fabio_aplicar_evento_acao"
        ]
        self.assertEqual(events, ["aula_escolhida", "audio_enfileirado"])

    def test_pending_audio_choice_spaced_hour_selects_within_shortlist(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
            {"aula_id": 102, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural-horario-espacado",
                kind="audio",
                text="Foi a aula das 15 h.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        self.assertNotEqual(enqueue["p_aula_id"], 103)

    def test_pending_audio_choice_time_does_not_select_matching_id(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [15, 101],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 15, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural-horario-id-15",
                kind="audio",
                text="Foi a aula das 15 h.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        self.assertNotEqual(enqueue["p_aula_id"], 15)
        self.assertNotEqual(enqueue["p_aula_id"], 103)

    def test_pending_audio_choice_time_minutes_refine_instead_of_selecting_id(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [30, 101],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        candidates = [
            {"aula_id": 30, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:30", "curso": "Canto T", "turma": "C_Qua_1530"},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:30", "curso": "Canto T", "turma": "C_Qua_1530"},
        ]
        for text in ("Foi a aula das 15 h 30.", "Foi a aula das 15:30."):
            with self.subTest(text=text):
                backend = FakeBackend(action=dict(action), candidates=candidates)
                result = tratar_mensagem_professor(
                    professor_context(
                        wa_message_id=f"selecao-natural-horario-minuto-{text}",
                        kind="audio",
                        text=text,
                    ),
                    backend,
                )
                self.assertEqual(result["code"], "audio_enqueued")
                self.assertIn("fabio_aulas_candidatas", [name for name, _ in backend.calls])
                enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
                self.assertEqual(enqueue["p_aula_id"], 101)
                self.assertNotEqual(enqueue["p_aula_id"], 30)
                self.assertNotEqual(enqueue["p_aula_id"], 103)

    def test_pending_audio_choice_invalid_time_minutes_do_not_enqueue_candidate_id(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [99, 101],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        candidates = [
            {"aula_id": 99, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
        ]
        for text in ("Foi a aula das 15 h 99.", "Foi a aula das 15:99."):
            with self.subTest(text=text):
                backend = FakeBackend(action=dict(action), candidates=candidates)
                result = tratar_mensagem_professor(
                    professor_context(
                        wa_message_id=f"selecao-natural-horario-invalido-{text}",
                        kind="audio",
                        text=text,
                    ),
                    backend,
                )
                # Era `pending_question` até 15/08/2026. O que essa asserção
                # guardava de verdade — 15:99 não virar a aula 99, não
                # enfileirar, não emitir evento — continua abaixo, intacto. O
                # que mudou é a FALA: numa ação de escolher aula, o fallback
                # agora repete a pergunta da aula em vez de oferecer
                # "confirmar/corrigir/cancelar", que é o menu de outro estado.
                self.assertEqual(result["code"], "choose_audio_class")
                self.assertNotIn("confirmar, corrigir, cancelar", result.get("reply", ""))
                names = [name for name, _ in backend.calls]
                self.assertNotIn("fabio_aplicar_evento_acao", names)
                self.assertNotIn("fabio_enfileirar_audio", names)

    def test_pending_audio_choice_known_student_name_selects_within_shortlist(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "alunos": [{"nome": "Beatriz Ohana"}]},
            {"aula_id": 102, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "alunos": [{"nome": "Outra Aluna"}]},
            {"aula_id": 103, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "alunos": [{"nome": "Beatriz Ohana"}]},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-natural-aluna",
                kind="audio",
                text="Foi a Beatriz Ohana.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 101)
        self.assertNotEqual(enqueue["p_aula_id"], 103)

    def test_pending_audio_choice_explicit_id_overrides_conflicting_natural_time(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=[
            {"aula_id": 101, "data": "2026-08-12", "hora": "15:00", "curso": "Canto T", "turma": "C_Qua_15"},
            {"aula_id": 102, "data": "2026-08-12", "hora": "16:00", "curso": "Canto T", "turma": "C_Qua_16"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                wa_message_id="selecao-explicita-conflitante",
                kind="audio",
                text="A aula 102, às 15 horas.",
            ),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 102)

    def test_mixed_text_asks_intention_without_call_pool(self):
        """Ambíguo COM sinal de aula continua perguntando — aqui há conteúdo real
        ("faltou" + "trabalhamos respiração") e o caminho determinístico é o
        único que consegue gravar isso. O que mudou (16/08) foi o ambíguo SEM
        sinal nenhum: ver AmbiguoSemSinalNaoAbreAcaoTest."""
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
        self.assertLess(names.index("fabio_registro_completo"), names.index("fabio_confirmar_registro"))
        self.assertEqual(names.count("fabio_registro_completo"), 2)
        self.assertIn("gravadas", result["receipt"])
        self.assertNotIn("fabio_devolutivas", names)

    def test_confirm_replay_recovers_post_commit_without_writing_twice(self):
        action = {"id": "acao-1", "professor_id": 25, "wa_message_id": "old", "tipo": "confirmar_registro", "estado": "aberta", "registro_id": "reg-1", "payload": {}}
        backend = FakeBackend(action=action, readback_status="gravado_emusys")
        result = tratar_mensagem_professor(professor_context(text="sim"), backend)
        self.assertEqual(result["code"], "confirmed")
        names = [name for name, _ in backend.calls]
        self.assertNotIn("fabio_confirmar_registro", names)
        event = next(payload for name, payload in backend.calls if name == "fabio_aplicar_evento_acao")
        self.assertEqual(event["p_evento"], "confirmado")
        self.assertTrue(result["receipt"]["recuperado_pos_commit"])

    def test_confirm_call_uses_atomic_action_confirmation_not_a_parallel_writer(self):
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "old",
            "tipo": "confirmar_chamada",
            "estado": "aberta",
            "aula_id": 101,
            "payload": {"alunos_ausentes": [7]},
        }
        backend = FakeBackend(action=action)

        result = tratar_mensagem_professor(professor_context(text="sim"), backend)

        self.assertEqual(result["code"], "confirmed_call")
        names = [name for name, _ in backend.calls]
        self.assertIn("fabio_confirmar_chamada_acao", names)
        self.assertNotIn("fabio_registrar_presencas_aula", names)
        self.assertNotIn("fabio_aplicar_evento_acao", names)

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


class PerguntaDiscriminanteTest(unittest.TestCase):
    """O laço que prendeu o Isaque em 15/08/2026.

    Ele mandou dois áudios dizendo a aula ("sábado, meio-dia"). O redutor achou
    mais de 3 aulas compatíveis, escolheu perguntar de forma discriminante
    ("Qual dia, horário ou turma foi essa aula?") — e **jogou a lista fora**.
    A ação nasceu com `candidatas = []`, e o interpretador de resposta desse
    tipo de ação só sabe casar contra essa lista. Lista vazia = nenhuma resposta
    dele podia ser aceita, nunca. Três respostas, três vezes a mesma frase.
    """

    @staticmethod
    def _quatro_aulas():
        return [
            {"aula_id": 201, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T", "turma": "T_Sa_12"},
            {"aula_id": 202, "data": "2026-08-15", "hora": "13:00", "curso": "Teclado T", "turma": "T_Sa_13"},
            {"aula_id": 203, "data": "2026-08-15", "hora": "14:00", "curso": "Teclado T", "turma": "T_Sa_14"},
            {"aula_id": 204, "data": "2026-08-13", "hora": "15:00", "curso": "Teclado T", "turma": "T_Qui_15"},
        ]

    def test_pergunta_discriminante_com_lista_truncada_nao_guarda_meia_verdade(self):
        # Quatro compatíveis, teto de 3: guardar 3 faria a 4ª virar resposta
        # impossível — o mesmo laço, só que mais difícil de ver. Sem shortlist
        # guardada, a resposta casa contra o pool inteiro (provado no teste
        # seguinte, que responde "13h" e acerta a 202).
        backend = FakeBackend(candidates=self._quatro_aulas())
        result = tratar_mensagem_professor(
            professor_context(kind="audio", text="trabalhei repertorio", media_url="https://media/1"),
            backend,
        )
        self.assertEqual(result["code"], "refine_class")
        eventos = [
            payload for name, payload in backend.calls
            if name == "fabio_aplicar_evento_acao" and payload["p_evento"] == "shortlist_definida"
        ]
        self.assertFalse(eventos, "guardou uma shortlist truncada")
        # A pergunta foi feita, e o evento que a registra continua saindo: é
        # ele que prova, no banco, que o professor foi perguntado.
        self.assertIn("pergunta_refinada", [
            payload["p_evento"] for name, payload in backend.calls
            if name == "fabio_aplicar_evento_acao"
        ])

    def test_professor_responde_a_pergunta_discriminante_e_a_aula_e_escolhida(self):
        backend = FakeBackend(candidates=self._quatro_aulas())
        tratar_mensagem_professor(
            professor_context(kind="audio", text="trabalhei repertorio", media_url="https://media/1"),
            backend,
        )
        backend.calls.clear()
        # "as 12 horas", e não "meio-dia": o casador entende HORÁRIO, não
        # apelido de horário — e o Isaque disse justamente "meio-dia" no áudio.
        # Isso é um buraco SEPARADO, anotado na RETOMADA; aqui o que se prova é
        # que a resposta agora tem contra o que casar, que era o defeito.
        result = tratar_mensagem_professor(
            professor_context(wa_message_id="resposta-1", text="foi a das 12 horas"),
            backend,
        )
        self.assertEqual(result["code"], "audio_enqueued")
        enqueue = next(payload for name, payload in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enqueue["p_aula_id"], 201)

    def test_resposta_nao_reconhecida_reoferece_a_pergunta_da_aula_e_nao_o_menu_de_confirmacao(self):
        """O agravante: a pergunta era "qual aula?" e o fallback respondia
        "confirmar, corrigir, cancelar ou deixar para depois" — menu de OUTRO
        estado. Foi isso que ensinou o Isaque a responder "Grave" e "Confirma
        os 2", que esse estado não tem como aceitar."""
        action = {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [201, 202, 203, 204],
            "payload": {"transcricao": "trabalhei repertorio"},
        }
        backend = FakeBackend(action=action, candidates=self._quatro_aulas())
        result = tratar_mensagem_professor(
            professor_context(wa_message_id="grave-1", text="Grave"),
            backend,
        )
        self.assertNotIn("confirmar, corrigir, cancelar", result.get("reply", ""))
        self.assertIn("aula", result.get("reply", "").lower())
        self.assertFalse([call for call in backend.calls if call[0] == "fabio_enfileirar_audio"])


class AudioComAcaoAbertaTest(unittest.TestCase):
    """O segundo áudio não pode sumir.

    Até 15/08/2026: havendo ação aberta, a mensagem ia direto pra
    `_handle_existing_action` seja qual for o `kind`, e o `_stage_audio` nunca
    era alcançado — os bytes não subiam pro Storage. O Isaque mandou dois
    áudios seguidos e o da aula das 13h morreu assim: sobrou a transcrição,
    sumiu o áudio.

    Guardar é incondicional; ROTEAR é que depende de estado. Enquanto a fila de
    áudios pendentes não existe, o mínimo é não destruir.
    """

    def _acao_aberta(self):
        return {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhei repertorio"},
        }

    def test_audio_que_chega_com_acao_aberta_sobe_pro_storage(self):
        backend = FakeBackend(action=self._acao_aberta(), candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T"},
            {"aula_id": 102, "data": "2026-08-15", "hora": "13:00", "curso": "Teclado T"},
        ])
        tratar_mensagem_professor(
            professor_context(
                kind="audio",
                wa_message_id="segundo-audio",
                text="aula de uma hora, tocamos Fur Elise e vimos o pedal",
                media_url="https://media/2",
            ),
            backend,
        )
        self.assertEqual(len(backend.uploads), 1, "o segundo áudio não foi guardado")
        # O caminho vem do wa_message_id: e isso que torna o audio recuperavel
        # depois sem coluna nova nenhuma (`fabio_chat_mensagens` ja guarda o id).
        self.assertTrue(backend.uploads[0][0].startswith("whatsapp/25/segundo-audio."))

    def test_o_professor_e_avisado_de_que_o_audio_ficou_guardado(self):
        backend = FakeBackend(action=self._acao_aberta(), candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T"},
            {"aula_id": 102, "data": "2026-08-15", "hora": "13:00", "curso": "Teclado T"},
        ])
        result = tratar_mensagem_professor(
            professor_context(
                kind="audio", wa_message_id="segundo-audio",
                text="aula de uma hora, tocamos Fur Elise", media_url="https://media/2",
            ),
            backend,
        )
        self.assertIn("guardei", (result.get("reply") or "").lower())

    def test_texto_com_acao_aberta_continua_sem_upload(self):
        backend = FakeBackend(action=self._acao_aberta(), candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T"},
        ])
        tratar_mensagem_professor(
            professor_context(wa_message_id="resposta", text="foi a das 12 horas"),
            backend,
        )
        self.assertFalse(backend.uploads)


class ShortlistTruncadaTest(unittest.TestCase):
    """Guardar 3 de 10 é pior que não guardar.

    A shortlist guardada é a régua contra a qual `_refine_pending_class` filtra
    o pool. Com 10 aulas compatíveis, guardar 3 transforma as outras 7 em
    resposta impossível — o professor responde certo e ouve "não consegui
    identificar", que é o laço do Isaque com outro nome.

    O teto de 3 do banco (`fabio_shortlist_valida`) continua intocado: ele é
    tamanho de MENU, e a pergunta discriminante não tem menu.
    """

    def _dez_aulas(self):
        return [
            {"aula_id": 100 + i, "data": "2026-08-15", "hora": f"{8 + i}:00", "curso": "Violão T"}
            for i in range(10)
        ]

    def test_com_dez_compativeis_a_shortlist_nao_e_guardada_pela_metade(self):
        backend = FakeBackend(candidates=self._dez_aulas())
        resultado = tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="audio-1",
                              text="dei aula hoje, trabalhamos repertório",
                              media_url="https://media/1"),
            backend,
        )
        self.assertEqual(resultado.get("code"), "refine_class")
        eventos = [p["p_evento"] for name, p in backend.calls if name == "fabio_aplicar_evento_acao"]
        self.assertNotIn("shortlist_definida", eventos,
                         "guardou uma shortlist truncada — as outras 7 aulas viraram resposta impossível")
        self.assertIn("pergunta_refinada", eventos)

    def test_com_tres_compativeis_a_shortlist_continua_sendo_guardada(self):
        backend = FakeBackend(candidates=self._dez_aulas()[:3])
        tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="audio-1",
                              text="dei aula hoje, trabalhamos repertório",
                              media_url="https://media/1"),
            backend,
        )
        shortlist = next(p for name, p in backend.calls
                         if name == "fabio_aplicar_evento_acao" and p["p_evento"] == "shortlist_definida")
        self.assertEqual(len(shortlist["p_dados"]["candidatas"]), 3)

    def test_sem_shortlist_guardada_a_resposta_casa_contra_o_pool_inteiro(self):
        # A aula certa é a 8ª — fora de qualquer corte em 3.
        acao_sem_shortlist = {
            "id": "acao-1", "professor_id": 25, "wa_message_id": "audio-1",
            "tipo": "escolher_aula_audio", "estado": "aberta",
            "storage_path": "whatsapp/25/audio-1.ogg",
            "payload": {"transcricao": "trabalhamos repertório"},
        }
        backend = FakeBackend(action=acao_sem_shortlist, candidates=self._dez_aulas())
        tratar_mensagem_professor(
            professor_context(wa_message_id="resposta", text="foi a das 15 horas"),
            backend,
        )
        enfileirado = next(p for name, p in backend.calls if name == "fabio_enfileirar_audio")
        self.assertEqual(enfileirado["p_aula_id"], 107, "a 8ª aula ficou inalcançável")


class PorteiraDoHorarioTest(unittest.TestCase):
    """A porteira e o casador têm que falar a mesma língua.

    O `2b716aa` ensinou "meio-dia" ao casador, mas `_looks_like_class_refinement`
    tinha régua própria, só de dígito: a resposta que o casador entenderia era
    barrada ANTES de chegar nele. Era a "outra porteira" anotada na RETOMADA
    como não rastreada.
    """

    def _acao_com_shortlist(self):
        return {
            "id": "acao-1", "professor_id": 25, "wa_message_id": "audio-1",
            "tipo": "escolher_aula_audio", "estado": "aberta",
            "storage_path": "whatsapp/25/audio-1.ogg",
            "candidatas": [101, 102],
            "payload": {"transcricao": "trabalhamos repertório"},
        }

    def test_meio_dia_atravessa_a_porteira_e_seleciona_a_aula(self):
        backend = FakeBackend(action=self._acao_com_shortlist(), candidates=[
            {"aula_id": 101, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T"},
            {"aula_id": 102, "data": "2026-08-15", "hora": "16:00", "curso": "Teclado T"},
        ])
        tratar_mensagem_professor(
            professor_context(wa_message_id="resposta", text="foi a de sábado, meio-dia"),
            backend,
        )
        enfileirados = [p for name, p in backend.calls if name == "fabio_enfileirar_audio"]
        self.assertTrue(enfileirados, '"meio-dia" foi barrado na porteira e a aula nem chegou ao casador')
        self.assertEqual(enfileirados[0]["p_aula_id"], 101)


class FilaDeEsperaDoAudioTest(unittest.TestCase):
    """O áudio guardado tem que ENTRAR quando a vez dele chega.

    O `5867be0` parou de destruir o segundo áudio, mas a resposta prometia
    "assim que a gente fechar o anterior, ele entra" sem ninguém pra cumprir.
    Estes testes cobram a promessa: parquear na chegada, drenar no fechamento,
    e nunca deixar linha presa na fila sem destino.
    """

    def _acao_de_chamada(self):
        # Mesma forma do `test_confirm_call_uses_atomic_action_confirmation`:
        # é esta que o "sim" fecha de verdade.
        return {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "chamada-original",
            "tipo": "confirmar_chamada",
            "estado": "aberta",
            "aula_id": 101,
            "payload": {"alunos_ausentes": [7]},
        }

    def _candidatas(self):
        return [
            {"aula_id": 101, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T"},
            {"aula_id": 102, "data": "2026-08-15", "hora": "13:00", "curso": "Teclado T"},
        ]

    def test_audio_com_acao_aberta_entra_na_fila_de_espera(self):
        backend = FakeBackend(action=self._acao_de_chamada(), candidates=self._candidatas())
        tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="segundo-audio",
                              text="aula das 13h", media_url="https://media/2"),
            backend,
        )
        parqueado = next(p for name, p in backend.calls if name == "fabio_parquear_audio")
        self.assertEqual(parqueado["p_wa_message_id"], "segundo-audio")
        self.assertTrue(str(parqueado["p_storage_path"]).startswith("whatsapp/25/segundo-audio."))
        # A transcrição vai junto: é ela que o casador usa pra escolher a aula
        # quando a vez chegar. Sem isso, o áudio volta mudo.
        self.assertEqual(parqueado["p_transcricao"], "aula das 13h")

    def test_a_fila_nao_drena_enquanto_a_acao_continua_aberta(self):
        backend = FakeBackend(action=self._acao_de_chamada(), candidates=self._candidatas())
        tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="segundo-audio",
                              text="aula das 13h", media_url="https://media/2"),
            backend,
        )
        self.assertEqual(len(backend.parqueados), 1)
        self.assertFalse(backend.parqueados[0]["consumido"],
                         "o áudio foi drenado com a ação ainda aberta")

    def test_ao_fechar_a_acao_o_audio_guardado_entra_sozinho(self):
        backend = FakeBackend(action=self._acao_de_chamada(), candidates=self._candidatas())
        tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="segundo-audio",
                              text="aula das 13 horas", media_url="https://media/2"),
            backend,
        )
        # O professor confirma a chamada: a ação fecha e a vez passa pro áudio.
        resultado = tratar_mensagem_professor(
            professor_context(wa_message_id="confirma", text="sim"),
            backend,
        )
        self.assertTrue(backend.parqueados[0]["consumido"],
                        "a ação fechou e o áudio guardado continuou parado")
        # O áudio guardado não é re-baixado nem re-subido: os bytes já estão no
        # Storage desde a chegada. Subir de novo seria pagar duas vezes e mudar
        # o caminho que a ação já conhece.
        self.assertEqual(len(backend.uploads), 1)
        enfileirado = next(p for name, p in backend.calls if name == "fabio_enfileirar_audio")
        self.assertTrue(str(enfileirado["p_storage_path"]).startswith("whatsapp/25/segundo-audio."))
        self.assertEqual(enfileirado["p_aula_id"], 102, "entrou na aula errada")
        self.assertIn("áudio recebido", (resultado.get("reply") or "").lower())

    def test_audio_sem_candidata_sai_da_fila_com_motivo(self):
        backend = FakeBackend(action=self._acao_de_chamada(), candidates=self._candidatas())
        tratar_mensagem_professor(
            professor_context(kind="audio", wa_message_id="segundo-audio",
                              text="aula das 13 horas", media_url="https://media/2"),
            backend,
        )
        # Quando a vez dele chegar não haverá aula elegível nenhuma.
        backend.candidates = []
        tratar_mensagem_professor(
            professor_context(wa_message_id="confirma", text="sim"),
            backend,
        )
        self.assertTrue(backend.parqueados[0]["descartado"],
                        "o áudio sem candidata ficou preso na fila pra sempre")
        self.assertFalse(backend.parqueados[0]["consumido"])
        self.assertTrue(backend.parqueados[0].get("motivo"))


class ApelidoDeHorarioTest(unittest.TestCase):
    """"meio-dia" é horário, não enfeite.

    O Isaque disse exatamente isso no áudio de 15/08 ("a aula de sábado,
    meio-dia") e o casador não entendeu, porque só lia dígito. Professor fala
    como gente fala.
    """

    def _acao(self):
        return {
            "id": "acao-1",
            "professor_id": 25,
            "wa_message_id": "audio-original",
            "tipo": "escolher_aula_audio",
            "estado": "aberta",
            "storage_path": "whatsapp/25/audio-original.ogg",
            "candidatas": [301, 302],
            "payload": {"transcricao": "trabalhei repertorio"},
        }

    def _aulas(self):
        return [
            {"aula_id": 301, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T", "turma": "T_Sa_12"},
            {"aula_id": 302, "data": "2026-08-15", "hora": "15:00", "curso": "Teclado T", "turma": "T_Sa_15"},
        ]

    def test_meio_dia_seleciona_a_aula_das_doze(self):
        for texto in ("foi a de meio-dia", "foi a de meio dia", "a aula de sábado, meio-dia"):
            with self.subTest(texto=texto):
                escolha = reduzir_shortlist(texto, self._aulas())
                self.assertEqual(escolha["status"], "selecionada")
                self.assertEqual(escolha["aula_id"], 301)

    def test_meia_noite_nao_vira_meio_dia(self):
        aulas = [
            {"aula_id": 401, "data": "2026-08-15", "hora": "00:00", "curso": "Teclado T", "turma": "T_Sa_00"},
            {"aula_id": 402, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T", "turma": "T_Sa_12"},
        ]
        escolha = reduzir_shortlist("foi a de meia-noite", aulas)
        self.assertEqual(escolha["aula_id"], 401)

    def test_meio_dia_e_meia_nao_e_lido_como_meio_dia(self):
        aulas = [
            {"aula_id": 501, "data": "2026-08-15", "hora": "12:00", "curso": "Teclado T", "turma": "A"},
            {"aula_id": 502, "data": "2026-08-15", "hora": "12:30", "curso": "Teclado T", "turma": "B"},
        ]
        escolha = reduzir_shortlist("foi a de meio-dia e meia", aulas)
        self.assertEqual(escolha["aula_id"], 502)


class SubstituicaoShadowTest(unittest.TestCase):
    """Wiring em SHADOW: quando a transcrição diz que alguém participou no lugar
    de um aluno do roster, registrar a candidata via RPC — sem tocar o registro
    normal, sem efeito operacional, e sem nunca derrubar o fluxo do Fábio."""

    ROSTER = [
        {"aluno_id": 793, "nome": "Jeremias Alves"},
        {"aluno_id": 794, "nome": "Beatriz Ohana"},
    ]
    FALA = ("Na aula de piano de hoje as 14h trabalhei respiracao; "
            "no lugar do Jeremias foi a Juliana")

    def _candidate(self, alunos=None):
        return {"aula_id": 101, "data": "2026-08-11", "hora": "14:00",
                "curso": "Piano", "alunos": alunos if alunos is not None else list(self.ROSTER)}

    def _run(self, text, alunos=None, **kw):
        backend = FakeBackend(candidates=[self._candidate(alunos)], **kw)
        result = tratar_mensagem_professor(
            professor_context(kind="audio", text=text, media_url="https://media/1"), backend)
        return backend, result

    def _participacao(self, backend):
        return [p for n, p in backend.calls if n == "fabio_participacao_registrar_candidata"]

    def test_substituicao_detectada_registra_candidata_em_shadow(self):
        backend, result = self._run(self.FALA)
        self.assertEqual(result["code"], "audio_enqueued")
        chamadas = self._participacao(backend)
        self.assertEqual(len(chamadas), 1)
        p = chamadas[0]
        self.assertEqual(p["p_aula_id"], 101)
        self.assertEqual(p["p_professor_id"], 25)
        self.assertEqual(p["p_aluno_matriculado_id"], 793)          # Jeremias, do roster
        self.assertIsNone(p["p_participante_real_id"])              # citado, ainda não resolvido
        self.assertEqual(p["p_participante_nome"].lower(), "juliana")
        self.assertEqual(p["p_confianca"], "baixa")
        self.assertEqual(p["p_metodo_extracao"], "deterministico")
        self.assertEqual(p["p_origem_message_id"], "wa-1")
        self.assertIn("juliana", (p["p_origem_transcricao"] or "").lower())

    def test_registro_normal_intacto_com_substituicao(self):
        backend, result = self._run(self.FALA)
        enfileiradas = [p for n, p in backend.calls if n == "fabio_enfileirar_audio"]
        self.assertEqual(len(enfileiradas), 1)
        self.assertEqual(enfileiradas[0]["p_aula_id"], 101)
        self.assertEqual(result["code"], "audio_enqueued")
        self.assertEqual(len(backend.uploads), 1)

    def test_substituicao_pergunta_confirmacao_curta(self):
        _, result = self._run(self.FALA)   # precisa_confirmar=True (default do dublê)
        self.assertIn("Juliana", result["reply"])
        self.assertIn("Jeremias", result["reply"])

    def test_sem_substituicao_nao_chama_participacao(self):
        backend, result = self._run("Na aula de piano de hoje as 14h trabalhei respiracao e escalas")
        self.assertEqual(result["code"], "audio_enqueued")
        self.assertFalse(self._participacao(backend))

    def test_falha_na_substituicao_nunca_derruba_registro(self):
        backend, result = self._run(self.FALA, participacao_explode=True)
        self.assertEqual(result["code"], "audio_enqueued")
        self.assertEqual(len([p for n, p in backend.calls if n == "fabio_enfileirar_audio"]), 1)
        self.assertTrue(result["reply"])

    def test_matriculado_sem_aluno_id_no_roster_nao_registra(self):
        backend, result = self._run(self.FALA, alunos=[{"aluno_id": None, "nome": "Jeremias Alves"}])
        self.assertEqual(result["code"], "audio_enqueued")
        self.assertFalse(self._participacao(backend))


class AmbiguoSemSinalNaoAbreAcaoTest(unittest.TestCase):
    """A ferida do Valdo (16/08). Ele perguntou quantas aulas tinha dado; o Fábio
    respondeu que não tinha a agenda; ele disse "Ok" — e esse "Ok" CRIOU uma ação
    de chamada do nada (medido em `fabio_acoes_pendentes`:
    `{"intencao":"ambiguo","transcricao":"Ok"}`), terminando em "Não gravei nada."

    Não havia ação pendente antes. Uma fala SEM nenhum sinal de aula não pode
    abrir fluxo de registro/chamada."""

    def _backend(self):
        return FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11",
                                        "hora": "14:00", "curso": "Piano"}])

    def _nao_abriu(self, backend, result):
        self.assertFalse(result["handled"])
        self.assertTrue(result["forward_to_hermes"])
        self.assertFalse([p for n, p in backend.calls if n == "fabio_iniciar_acao"],
                         "nao pode abrir acao")
        self.assertFalse([c for c in backend.calls if c[0] == "fabio_aulas_candidatas"],
                         "nao pode nem consultar o pool")

    def test_ok_solto_nao_abre_acao(self):
        backend = self._backend()
        self._nao_abriu(backend, tratar_mensagem_professor(professor_context(text="Ok"), backend))

    def test_sim_solto_nao_abre_acao(self):
        backend = self._backend()
        self._nao_abriu(backend, tratar_mensagem_professor(professor_context(text="Sim"), backend))

    def test_pergunta_do_valdo_nao_abre_acao(self):
        """A pergunta que começou tudo: consulta é pergunta, não lançamento."""
        backend = self._backend()
        self._nao_abriu(backend, tratar_mensagem_professor(professor_context(
            text="Na semana passada de terça-feira dia 11/08 ate sábado dia 15/08 "
                 "me informe o total de aulas que eu dei"), backend))

    def test_pergunta_de_falta_nao_abre_acao(self):
        backend = self._backend()
        self._nao_abriu(backend, tratar_mensagem_professor(
            professor_context(text="quais alunos faltaram semana passada"), backend))

    def test_pergunta_por_unidade_nao_abre_acao(self):
        backend = self._backend()
        self._nao_abriu(backend, tratar_mensagem_professor(
            professor_context(text="quantas aulas eu dei no Recreio semana passada"), backend))

    def test_audio_ambiguo_segue_perguntando(self):
        """Áudio NÃO muda: ali existe conteúdo gravado que justifica pinar a aula."""
        backend = self._backend()
        result = tratar_mensagem_professor(
            professor_context(kind="audio", text="A Sofia faltou e trabalhamos respiração",
                              media_url="https://media/1"), backend)
        self.assertEqual(result["code"], "confirm_audio_intent")


if __name__ == "__main__":
    unittest.main(verbosity=2)
