#!/usr/bin/env python3
"""Contrato puro para normalização de registros antes da persistência."""

import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_registro_normalization_contract import (  # noqa: E402
    NormalizationContractError,
    sanear_readback_para_preview,
    validar_e_sanear_normalizacao,
)


class RegistroNormalizationContractTest(unittest.TestCase):
    def _payload(self, comum=None, fatias=None, **overrides):
        payload = {
            "aula_id": 101,
            "professor_id": 25,
            "comum": comum or {
                "objetivo": None,
                "atividades": None,
                "repertorio": None,
                "dever_casa": None,
                "observacoes": None,
            },
            "fatias": fatias if fatias is not None else [{
                "aluno_id": 7,
                "campos": {
                    "progresso": None,
                    "repertorio": None,
                    "proximo_passo": None,
                    "observacoes": None,
                },
            }],
        }
        payload.update(overrides)
        return payload

    def _normalizar(self, payload, roster_ids={7, 8}):
        return validar_e_sanear_normalizacao(
            payload,
            aula_id=101,
            professor_id=25,
            roster_ids=roster_ids,
        )

    def test_comum_nao_reaparece_no_lucas(self):
        resultado = self._normalizar(self._payload(
            comum={
                "objetivo": None,
                "atividades": "Leitura de partitura.",
                "repertorio": "Prelude em Do e Minueto em Sol",
                "dever_casa": None,
                "observacoes": None,
            },
            fatias=[{
                "aluno_id": 7,
                "campos": {
                    "progresso": None,
                    "repertorio": "Prelude em Do e Minueto em Sol",
                    "proximo_passo": None,
                    "observacoes": None,
                },
            }],
        ))
        self.assertEqual(resultado["comum"]["repertorio"], "Prelude em Do e Minueto em Sol")
        self.assertIsNone(resultado["fatias"][0]["campos"]["repertorio"])

    def test_repertorio_comum_remove_prefixo_nominal_da_fatia(self):
        resultado = self._normalizar(self._payload(
            comum={
                "objetivo": None,
                "atividades": None,
                "repertorio": "Prelude em Do e Minueto em Sol, de Bach",
                "dever_casa": None,
                "observacoes": None,
            },
            fatias=[{
                "aluno_id": 7,
                "campos": {
                    "progresso": None,
                    "repertorio": "Lucas: Prelude em Do e Minueto em Sol, de Bach",
                    "proximo_passo": None,
                    "observacoes": None,
                },
            }],
        ))
        self.assertIsNone(resultado["fatias"][0]["campos"]["repertorio"])

    def test_progresso_nomeado_fica_somente_na_fatia_correspondente(self):
        resultado = self._normalizar(self._payload(
            fatias=[
                {"aluno_id": 7, "campos": {"progresso": "Lucas leu o quarto sistema com segurança.", "repertorio": None, "proximo_passo": None, "observacoes": None}},
                {"aluno_id": 8, "campos": {"progresso": None, "repertorio": None, "proximo_passo": None, "observacoes": None}},
            ],
        ))
        por_aluno = {fatia["aluno_id"]: fatia for fatia in resultado["fatias"]}
        self.assertEqual(por_aluno[7]["campos"]["progresso"], "Lucas leu o quarto sistema com segurança.")
        self.assertIsNone(por_aluno[8]["campos"]["progresso"])

    def test_roster_completa_fatia_vazia_para_aluno_sem_complemento(self):
        resultado = self._normalizar(self._payload(
            comum={
                "objetivo": None,
                "atividades": "Leitura de partitura.",
                "repertorio": None,
                "dever_casa": None,
                "observacoes": None,
            },
            fatias=[{
                "aluno_id": 7,
                "campos": {
                    "progresso": "Lucas leu o quarto sistema com seguran\u00e7a.",
                    "repertorio": None,
                    "proximo_passo": None,
                    "observacoes": None,
                },
            }],
        ))
        por_aluno = {fatia["aluno_id"]: fatia for fatia in resultado["fatias"]}
        self.assertEqual(set(por_aluno), {7, 8})
        self.assertIsNone(por_aluno[8]["presenca"])
        self.assertEqual(por_aluno[8]["campos"], {
            "progresso": None,
            "repertorio": None,
            "proximo_passo": None,
            "observacoes": None,
        })

    def test_objetivo_equivalente_a_atividade_vira_nulo(self):
        resultado = self._normalizar(self._payload(comum={
            "objetivo": "Trabalhar leitura de partitura",
            "atividades": "Leitura de partitura trabalhar",
            "repertorio": None,
            "dever_casa": None,
            "observacoes": None,
        }))
        self.assertIsNone(resultado["comum"]["objetivo"])

    def test_quadro_quarto_sistema_incerto_nao_vira_observacao_factual(self):
        resultado = self._normalizar(self._payload(comum={
            "objetivo": None,
            "atividades": "Leitura de partitura.",
            "repertorio": None,
            "dever_casa": None,
            "observacoes": "Conseguiu ler o quadro/quarto sistema.",
        }))
        self.assertIsNone(resultado["comum"]["observacoes"])
        self.assertEqual(resultado["incertezas"], [{"campo": "comum.observacoes", "motivo": "termo_ambiguo"}])

    def test_quadro_sistema_em_observacao_e_incerto_sem_apagar_progresso_nominal(self):
        resultado = self._normalizar(self._payload(
            comum={
                "objetivo": None,
                "atividades": "Leitura de partitura.",
                "repertorio": None,
                "dever_casa": None,
                "observacoes": "Conseguiu ler o quadro sistema.",
            },
            fatias=[{
                "aluno_id": 7,
                "campos": {
                    "progresso": "Lucas leu o quarto sistema com segurança.",
                    "repertorio": None,
                    "proximo_passo": None,
                    "observacoes": None,
                },
            }],
        ))
        self.assertIsNone(resultado["comum"]["observacoes"])
        self.assertEqual(resultado["incertezas"], [{"campo": "comum.observacoes", "motivo": "termo_ambiguo"}])
        self.assertEqual(resultado["fatias"][0]["campos"]["progresso"], "Lucas leu o quarto sistema com segurança.")

    def test_fatias_vazias_falham_fechado(self):
        with self.assertRaises(NormalizationContractError):
            self._normalizar(self._payload(fatias=[]))

    def test_aluno_fora_do_roster_e_rejeitado(self):
        with self.assertRaises(NormalizationContractError):
            self._normalizar(self._payload(fatias=[{
                "aluno_id": 99,
                "campos": {"progresso": "Não pode entrar.", "repertorio": None, "proximo_passo": None, "observacoes": None},
            }]))

    def test_chave_desconhecida_e_ids_divergentes_falham_fechado(self):
        with self.assertRaises(NormalizationContractError):
            self._normalizar(self._payload(chave_nao_permitida=True))
        with self.assertRaises(NormalizationContractError):
            self._normalizar(self._payload(aula_id=999))
        with self.assertRaises(NormalizationContractError):
            self._normalizar(self._payload(professor_id=999))


class _FakeResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code
        self.content = b"{}"
        self.text = json.dumps(payload)

    def json(self):
        return self._payload


def _carregar_tool_real():
    registrations = []
    registry_module = types.ModuleType("tools.registry")
    registry_module.registry = type(
        "Registry",
        (),
        {"register": staticmethod(lambda **kwargs: registrations.append(kwargs))},
    )()
    tools_module = types.ModuleType("tools")
    tools_module.registry = registry_module
    sys.modules["tools"] = tools_module
    sys.modules["tools.registry"] = registry_module
    caminho = Path(__file__).resolve().parent / "hermes-tools" / "fabio_registro_aula_tool.py"
    spec = importlib.util.spec_from_file_location("fabio_registro_aula_tool_test", caminho)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    module._captured_registrations = registrations
    return module


class RegistroNormalizationConsumerTest(unittest.TestCase):
    @staticmethod
    def _audio_queue(*, origem="app", aula_id=101, professor_id=25):
        return {
            "id": "audio-1",
            "aula_id": aula_id,
            "professor_id": professor_id,
            "origem": origem,
        }

    def _legacy_payload(self, *, aluno_id=7):
        return {
            "audio_id": "audio-1",
            "aula_id": 101,
            "professor_id": 25,
            "origem": "app",
            "molde": "C",
            "tronco": {"campos": {
                "objetivo": "Leitura de partitura trabalhar",
                "atividades": "Trabalhar leitura de partitura",
                "repertorio": "Prelude em Do e Minueto em Sol",
                "dever_casa": None,
                "obs_gerais": "Conseguiu ler o quadro/quarto sistema.",
            }},
            "fatias": [{"aluno_id": aluno_id, "presenca": "presente", "campos": {
                "progresso": "Lucas leu o quarto sistema com segurança.",
                "repertorio": "Prelude em Do e Minueto em Sol",
                "proximo_passo": None,
                "observacao": None,
            }}],
        }

    def test_tool_rejeita_contrato_invalido_sem_chamar_rpc(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 1})), \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])), \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio", return_value="{}"):
            result = json.loads(tool.fabio_criar_registro_aula(self._legacy_payload(aluno_id=99)))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "normalizacao_invalida")
        post_mock.assert_not_called()

    def test_tool_resolve_contrato_runtime_antes_do_fallback_local(self):
        tool = _carregar_tool_real()
        contract_file = Path(__file__).resolve().parent / "fabio_registro_normalization_contract.py"
        missing_file = contract_file.parent / "nao-existe" / contract_file.name

        self.assertEqual(
            tool._contract_path(runtime_root=contract_file.parent, local_file=missing_file),
            contract_file.resolve(),
        )
        self.assertEqual(
            tool._contract_path(runtime_root=missing_file.parent, local_file=contract_file),
            contract_file.resolve(),
        )
        self.assertEqual(Path(tool._CONTRACT_MODULE.__file__).resolve(), contract_file.resolve())

    def test_tool_timeout_no_roster_falha_sem_post_ou_status_audio(self):
        tool = _carregar_tool_real()
        with patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", side_effect=tool.requests.Timeout("tempo")), \
             patch.object(tool.requests, "post") as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio") as status_mock:
            result = json.loads(tool.fabio_criar_registro_aula(self._legacy_payload()))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "fila_ou_roster_indisponivel")
        post_mock.assert_not_called()
        status_mock.assert_not_called()

    def test_tool_sem_audio_id_rejeita_sem_consultar_fila_ou_postar(self):
        tool = _carregar_tool_real()
        payload = self._legacy_payload()
        payload.pop("audio_id")
        with patch.object(tool, "_buscar_roster_aula") as roster_mock, \
             patch.object(tool.requests, "get") as get_mock, \
             patch.object(tool.requests, "post") as post_mock:
            result = json.loads(tool.fabio_criar_registro_aula(payload))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "audio_id_obrigatorio")
        roster_mock.assert_not_called()
        get_mock.assert_not_called()
        post_mock.assert_not_called()

    def test_schema_exige_audio_id_da_fila_no_topo(self):
        tool = _carregar_tool_real()
        registration = next(
            item
            for item in tool._captured_registrations
            if item.get("name") == "fabio_criar_registro_aula"
        )
        parameters = registration["schema"]["parameters"]
        self.assertIn("audio_id", parameters["required"])
        description = parameters["properties"]["audio_id"]["description"].lower()
        self.assertIn("fila", description)
        self.assertIn("nunca use registro_id", description)

    def test_transcricao_resolve_storage_pelo_audio_id_sem_url_do_modelo(self):
        tool = _carregar_tool_real()
        queue = _FakeResponse([{
            "id": "audio-1",
            "storage_path": "whatsapp/25/audio-1.webm",
            "aula_id": 101,
            "professor_id": 25,
        }])
        signed = _FakeResponse({
            "signedURL": "/object/sign/fabio-audios/whatsapp/25/audio-1.webm?token=seguro",
        })
        with patch.object(tool, "_headers", return_value={"Authorization": "Bearer seguro"}), \
             patch.object(tool.requests, "get", return_value=queue) as get_mock, \
             patch.object(tool.requests, "post", return_value=signed) as post_mock, \
             patch.object(tool, "_transcription_hints", return_value={
                 "initial_prompt": "Aula de teclado. Repertorio possivel: Astro Bot, Meu Lanchinho.",
                 "hotwords": "Astro Bot, Meu Lanchinho",
                 "titles_count": 2,
             }) as hints_mock, \
             patch.object(tool, "fabio_transcrever_audio_url", return_value='{"ok": true}') as transcribe_mock:
            result = json.loads(tool.fabio_transcrever_audio_fila("audio-1", "pt"))

        self.assertTrue(result["ok"])
        self.assertIn("/rest/v1/fabio_fila_audios", get_mock.call_args.args[0])
        self.assertEqual(get_mock.call_args.kwargs["params"]["id"], "eq.audio-1")
        self.assertIn("aula_id", get_mock.call_args.kwargs["params"]["select"])
        self.assertIn("professor_id", get_mock.call_args.kwargs["params"]["select"])
        self.assertIn("/storage/v1/object/sign/fabio-audios/", post_mock.call_args.args[0])
        self.assertEqual(post_mock.call_args.kwargs["json"], {"expiresIn": 600})
        hints_mock.assert_called_once_with(101, 25)
        called_url = transcribe_mock.call_args.args[0]
        self.assertIn("/storage/v1/object/sign/fabio-audios/", called_url)
        self.assertNotIn("audio_url", called_url)
        self.assertEqual(transcribe_mock.call_args.kwargs["hotwords"], "Astro Bot, Meu Lanchinho")
        self.assertIn("Astro Bot", transcribe_mock.call_args.kwargs["initial_prompt"])

        registration = next(
            item
            for item in tool._captured_registrations
            if item.get("name") == "fabio_transcrever_audio_fila"
        )
        self.assertEqual(
            registration["schema"]["parameters"]["required"],
            ["audio_id"],
        )

    def test_vocabulario_da_transcricao_usa_repertorio_real_da_mesma_turma(self):
        tool = _carregar_tool_real()
        contexto = [{
            "aula_local_id": 101,
            "professor_id": 25,
            "professor_nome": "Isaac Professor",
            "aluno_id": 7,
            "aluno_nome": "Arthur Darzi Ferreira",
            "curso_nome": "Teclado",
            "turma_nome": "T_Ter_11",
        }]
        historico = _FakeResponse([
            {
                "data_aula": "2026-08-11",
                "turma_nome": "T_Ter_11",
                "anotacoes": (
                    "Repertorio: Astro Bot, meu lanchinho\n"
                    "Conteudo: Digitacao, passagem do polegar\n"
                    "Objetivo: Aprender parte 3 da musica"
                ),
            },
            {
                "data_aula": "2026-08-04",
                "turma_nome": "T_Ter_11",
                "anotacoes": "Repertorio: Astro Bot, Show da Luna",
            },
        ])
        with patch.object(tool, "_context_rows", return_value=(contexto, None)), \
             patch.object(tool, "_headers", return_value={}), \
             patch.object(tool.requests, "get", return_value=historico) as get_mock:
            hints = tool._transcription_hints(101, 25)

        self.assertIn("Astro Bot", hints["initial_prompt"])
        self.assertIn("meu lanchinho", hints["initial_prompt"])
        self.assertNotIn("Show da Luna", hints["initial_prompt"])
        self.assertIn("Arthur Darzi Ferreira", hints["initial_prompt"])
        self.assertEqual(hints["titles_count"], 2)
        self.assertIn("/rest/v1/aulas_emusys", get_mock.call_args.args[0])
        self.assertEqual(get_mock.call_args.kwargs["params"]["turma_nome"], "eq.T_Ter_11")

    def test_vocabulario_da_transcricao_limita_e_saneia_texto_historico(self):
        tool = _carregar_tool_real()
        contexto = [{
            "aula_local_id": 101,
            "professor_id": 25,
            "professor_nome": "Professor\nInjetado",
            "aluno_id": 7,
            "aluno_nome": "Arthur\tDarzi",
            "curso_nome": "Teclado",
            "turma_nome": "T_Ter_11",
        }]
        historico = _FakeResponse([{
            "data_aula": "2026-08-11",
            "turma_nome": "T_Ter_11",
            "anotacoes": "Repertorio: Astro Bot, <script>alert(1)</script>, " + ("X" * 200),
        }])
        with patch.object(tool, "_context_rows", return_value=(contexto, None)), \
             patch.object(tool, "_headers", return_value={}), \
             patch.object(tool.requests, "get", return_value=historico):
            hints = tool._transcription_hints(101, 25)

        self.assertNotIn("<", hints["initial_prompt"])
        self.assertNotIn("\n", hints["initial_prompt"])
        self.assertLessEqual(len(hints["initial_prompt"]), tool._MAX_INITIAL_PROMPT_CHARS)
        self.assertLessEqual(len(hints["hotwords"]), tool._MAX_HOTWORDS_CHARS)

    def test_modelo_padrao_prioriza_qualidade_pedagogica(self):
        tool = _carregar_tool_real()
        self.assertEqual(tool._DEFAULT_WHISPER_MODEL, "large-v3-turbo")

    def test_correcao_contextual_recupera_titulo_sem_inventar_frase_distante(self):
        tool = _carregar_tool_real()
        corrected = tool._apply_contextual_title_corrections(
            "Aprendendo uma musica no lanchinho e tocando Astro Bot ate a metade.",
            ["Astro Bot", "Meu Lanchinho"],
        )
        untouched = tool._apply_contextual_title_corrections(
            "Fizemos um exercicio no banquinho.",
            ["Meu Lanchinho"],
        )

        self.assertIn("Meu Lanchinho", corrected)
        self.assertNotIn("no lanchinho", corrected)
        self.assertEqual(untouched, "Fizemos um exercicio no banquinho.")

    def test_erro_semantico_usa_porta_terminal_tipificada(self):
        tool = _carregar_tool_real()
        response = _FakeResponse({
            "audio_id": "audio-1",
            "status": "erro_terminal",
            "erro_tipo": "semantico_terminal",
        })
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool.requests, "post", return_value=response) as post_mock:
            result = json.loads(tool.fabio_marcar_audio_erro_terminal(
                "audio-1",
                "sem_conteudo_pedagogico",
                "Audio sem fala de aula.",
            ))

        self.assertTrue(result["ok"])
        self.assertIn("/rest/v1/rpc/fabio_marcar_audio_erro_terminal", post_mock.call_args.args[0])
        self.assertEqual(post_mock.call_args.kwargs["json"]["p_codigo"], "sem_conteudo_pedagogico")

    def test_codigo_terminal_fora_da_lista_nao_chama_rpc(self):
        tool = _carregar_tool_real()
        with patch.object(tool.requests, "post") as post_mock:
            result = json.loads(tool.fabio_marcar_audio_erro_terminal(
                "audio-1",
                "codigo_inventado",
                None,
            ))

        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "codigo_terminal_invalido")
        post_mock.assert_not_called()

    def test_schema_expoe_porta_terminal_sem_permitir_sql_livre(self):
        tool = _carregar_tool_real()
        registration = next(
            item
            for item in tool._captured_registrations
            if item.get("name") == "fabio_marcar_audio_erro_terminal"
        )
        codigo = registration["schema"]["parameters"]["properties"]["codigo"]
        self.assertEqual(
            codigo["enum"],
            ["sem_conteudo_pedagogico", "transcricao_incompativel"],
        )

    def test_tool_rejeita_fatias_vazias_sem_chamar_rpc(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        payload = self._legacy_payload()
        payload["fatias"] = []
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 1})) as roster_mock, \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])), \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio", return_value="{}"):
            result = json.loads(tool.fabio_criar_registro_aula(payload))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "normalizacao_invalida")
        roster_mock.assert_not_called()
        post_mock.assert_not_called()

    def test_tool_rejeita_roster_parcial_sem_chamar_rpc_ou_status_audio(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 2, "qtd_roster": 1})), \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])) as get_mock, \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio") as status_mock:
            result = json.loads(tool.fabio_criar_registro_aula(self._legacy_payload()))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "normalizacao_invalida")
        get_mock.assert_not_called()
        post_mock.assert_not_called()
        status_mock.assert_not_called()

    def test_tool_adapta_legado_para_payload_canonico_antes_da_rpc(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 1})), \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])), \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio", return_value="{}"):
            result = json.loads(tool.fabio_criar_registro_aula(self._legacy_payload()))
        self.assertTrue(result["ok"])
        persisted = post_mock.call_args.kwargs["json"]["p_payload"]
        self.assertIsNone(persisted["tronco"]["campos"]["objetivo"])
        self.assertIsNone(persisted["tronco"]["campos"]["observacoes"])
        self.assertIsNone(persisted["fatias"][0]["campos"]["repertorio"])
        self.assertNotIn("texto_consolidado", persisted["tronco"])
        self.assertTrue(result["aguardando_confirmacao"])
        self.assertEqual(result["incertezas"], [{"campo": "comum.observacoes", "motivo": "termo_ambiguo"}])

    def test_tool_projeta_saida_completa_da_skill_e_remove_transcricao_incerta(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        payload = self._legacy_payload()
        payload.update({
            "modo": "novo",
            "checkpoint_sugerido": None,
            "avisos": ["O nome da musica foi transcrito como ingobels; confirmar o titulo."],
            "qualidade": {"faltando": {"7": ["proximo_passo"]}},
        })
        payload["tronco"]["campos"].update({
            "materiais": None,
            "marco_ref": None,
            "eixos": ["CoordenacaoMotora"],
        })
        payload["tronco"]["campos"]["atividades"] = (
            "Execucao com as duas maos da musica mencionada como ingobels, "
            "improvisacao com a mao direita."
        )
        payload["fatias"][0]["campos"]["progresso"] = (
            "Tocou com as duas maos a musica mencionada como ingobels e improvisou."
        )
        payload["fatias"][0]["campos"]["repertorio"] = (
            "Musica mencionada na transcricao como ingobels (nome a confirmar)."
        )

        with patch.object(tool, "_headers", return_value={}), \
             patch.object(tool, "_buscar_audio_fila", return_value=self._audio_queue()), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 1})), \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])), \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio", return_value="{}"):
            result = json.loads(tool.fabio_criar_registro_aula(payload))

        self.assertTrue(result["ok"])
        persisted = post_mock.call_args.kwargs["json"]["p_payload"]
        self.assertEqual(
            set(persisted["tronco"]["campos"]),
            {"objetivo", "atividades", "repertorio", "dever_casa", "observacoes"},
        )
        self.assertNotIn("mencionada", persisted["tronco"]["campos"]["atividades"].lower())
        self.assertNotIn("mencionada", persisted["fatias"][0]["campos"]["progresso"].lower())
        self.assertIsNone(persisted["fatias"][0]["campos"]["repertorio"])
        self.assertTrue(result["aguardando_confirmacao"])
        self.assertTrue(
            any(item["motivo"] == "transcricao_incerta" for item in result["incertezas"])
        )

    def test_tool_deriva_origem_e_identidade_da_fila_e_nao_do_modelo(self):
        tool = _carregar_tool_real()
        payload = self._legacy_payload()
        payload.update({"aula_id": 999, "professor_id": 999, "origem": "app"})
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        with patch.object(tool, "_headers", return_value={}), \
             patch.object(
                 tool,
                 "_buscar_audio_fila",
                 return_value=self._audio_queue(origem="whatsapp"),
             ), \
             patch.object(tool, "_buscar_roster_aula", return_value=(roster, {"ok": True, "qtd_contexto": 1})) as roster_mock, \
             patch.object(tool.requests, "get", return_value=_FakeResponse([])), \
             patch.object(tool.requests, "post", return_value=_FakeResponse({"status": "criado"})) as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio", return_value="{}"):
            result = json.loads(tool.fabio_criar_registro_aula(payload))

        self.assertTrue(result["ok"])
        roster_mock.assert_called_once_with(101, 25)
        persisted = post_mock.call_args.kwargs["json"]["p_payload"]
        self.assertEqual(persisted["aula_id"], 101)
        self.assertEqual(persisted["professor_id"], 25)
        self.assertEqual(persisted["origem"], "whatsapp")

    def test_bridge_sanea_readback_antes_do_preview_das_actions(self):
        import fabio_chat_bridge as bridge

        raw = {
            "aula": {"data_aula": "2026-08-11", "hora": "14:00"},
            "tronco": {
                "id": "registro-1",
                "aula_id": 101,
                "professor_id": 25,
                "status": "aguardando_confirmacao",
                "campos": {
                    "objetivo": "Trabalhar leitura de partitura",
                    "atividades": "Leitura de partitura trabalhar",
                    "repertorio": "Prelude em Do e Minueto em Sol",
                    "dever_casa": None,
                    "obs_gerais": "Conseguiu ler o quadro/quarto sistema.",
                },
                "texto_consolidado": "texto legado que nao pode voltar ao preview",
            },
            "fatias": [{
                "id": "fatia-1",
                "aluno_id": 7,
                "aluno_nome": "Lucas",
                "presenca": "presente",
                "campos": {
                    "progresso": "Lucas leu o quarto sistema com segurança.",
                    "repertorio": "Prelude em Do e Minueto em Sol",
                    "proximo_passo": None,
                    "observacao": None,
                },
                "texto_consolidado": "texto legado duplicado",
            }],
        }
        roster = [{"aula_local_id": 101, "professor_id": 25, "aluno_id": 7}]
        with patch.object(bridge, "sb_post", return_value=_FakeResponse(raw)), \
             patch.object(bridge, "sb_get", return_value=roster) as get_mock:
            readback = bridge.FabioBridgeBackend().rpc(
                "fabio_registro_completo",
                {"p_professor_id": 25, "p_registro_id": "registro-1"},
            )
        self.assertIn("ok", readback)
        self.assertTrue(readback["ok"])
        self.assertEqual(readback["tronco"]["status"], "aguardando_confirmacao")
        self.assertIsNone(readback["tronco"]["campos"]["objetivo"])
        self.assertIsNone(readback["tronco"]["campos"]["obs_gerais"])
        self.assertIsNone(readback["fatias"][0]["campos"]["repertorio"])
        self.assertIsNone(readback["tronco"]["texto_consolidado"])
        self.assertIsNone(readback["fatias"][0]["texto_consolidado"])
        get_mock.assert_called_once_with(
            "/rest/v1/vw_fabio_aulas_contexto",
            {
                "select": "aula_local_id,professor_id,aluno_id",
                "aula_local_id": "eq.101",
                "professor_id": "eq.25",
            },
        )

    def test_bridge_sanea_readback_pos_confirmacao_sem_expor_metadados_do_motor(self):
        raw = {
            "aula": {"data_aula": "2026-08-06", "hora": "19:00:00", "turma": "P_Qui_19", "curso": "Piano T", "tipo": "turma"},
            "tronco": {
                "id": "reg-1", "aula_id": 202499, "professor_id": 10, "status": "gravado_emusys",
                "campos": {
                    "objetivo": "Coordenar as duas maos", "atividades": "Jingle Bells",
                    "repertorio": "Jingle Bells", "dever_casa": None, "observacoes": None,
                    "presenca_emitida": True, "presenca_aplicado": True,
                    "presenca_emitida_em": "2026-08-12T00:37:52Z", "presenca_erro": None,
                },
            },
            "fatias": [{
                "id": "fat-1", "aula_id": 202500, "professor_id": 10, "aluno_id": 1629,
                "aluno_nome": "Pedro", "status": "gravado_emusys", "presenca": "presente",
                "campos": {
                    "presenca": "presente", "progresso": "Tocou com as duas maos",
                    "observacao": None, "proximo_passo": None, "aula_alvo_resolvida": 202500,
                },
            }],
        }
        result = sanear_readback_para_preview(raw, professor_id=10, roster_ids={1629})
        self.assertTrue(result["ok"])
        self.assertEqual(result["tronco"]["status"], "gravado_emusys")
        self.assertEqual(result["fatias"][0]["presenca"], "presente")
        serialized = json.dumps(result, ensure_ascii=False)
        self.assertNotIn("presenca_emitida", serialized)
        self.assertNotIn("aula_alvo_resolvida", serialized)

    def test_bridge_recusa_fatia_fora_do_roster_real(self):
        import fabio_chat_bridge as bridge

        raw = {
            "tronco": {"id": "registro-1", "aula_id": 101, "professor_id": 25, "campos": {
                "objetivo": None, "atividades": "Leitura", "repertorio": None,
                "dever_casa": None, "obs_gerais": None,
            }},
            "fatias": [{"id": "fatia-99", "aluno_id": 99, "aluno_nome": "Estranho", "presenca": "presente", "campos": {
                "progresso": "Texto", "repertorio": None, "proximo_passo": None, "observacao": None,
            }}],
        }
        roster = [{"aula_local_id": 101, "professor_id": 25, "aluno_id": 7}]
        with patch.object(bridge, "sb_post", return_value=_FakeResponse(raw)), \
             patch.object(bridge, "sb_get", return_value=roster):
            readback = bridge.FabioBridgeBackend().rpc(
                "fabio_registro_completo",
                {"p_professor_id": 25, "p_registro_id": "registro-1"},
            )
        self.assertFalse(readback["ok"])
        self.assertIsNone(readback["tronco"])
        self.assertEqual(readback["fatias"], [])

    def test_bridge_falha_fechado_quando_consulta_roster_falha(self):
        import fabio_chat_bridge as bridge

        raw = {
            "tronco": {"id": "registro-1", "aula_id": 101, "professor_id": 25, "campos": {
                "objetivo": None, "atividades": "Leitura", "repertorio": None,
                "dever_casa": None, "obs_gerais": None,
            }},
            "fatias": [{"id": "fatia-7", "aluno_id": 7, "aluno_nome": "Lucas", "presenca": "presente", "campos": {
                "progresso": "Texto", "repertorio": None, "proximo_passo": None, "observacao": None,
            }}],
        }
        with patch.object(bridge, "sb_post", return_value=_FakeResponse(raw)), \
             patch.object(bridge, "sb_get", side_effect=OSError("indisponivel")):
            readback = bridge.FabioBridgeBackend().rpc(
                "fabio_registro_completo",
                {"p_professor_id": 25, "p_registro_id": "registro-1"},
            )
        self.assertFalse(readback["ok"])
        self.assertIsNone(readback["tronco"])
        self.assertEqual(readback["fatias"], [])

    def test_bridge_recusa_readback_invalido_sem_preview_cru(self):
        import fabio_chat_bridge as bridge

        raw = {"tronco": {"aula_id": 101, "professor_id": 25}, "fatias": []}
        with patch.object(bridge, "sb_post", return_value=_FakeResponse(raw)), \
             patch.object(bridge, "sb_get") as get_mock:
            readback = bridge.FabioBridgeBackend().rpc(
                "fabio_registro_completo",
                {"p_professor_id": 25, "p_registro_id": "registro-1"},
            )
        self.assertEqual(readback["ok"], False)
        self.assertEqual(readback["erro"], "normalizacao_readback_invalida")
        self.assertIsNone(readback["tronco"])
        self.assertEqual(readback["fatias"], [])
        get_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
