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
    registry_module = types.ModuleType("tools.registry")
    registry_module.registry = type("Registry", (), {"register": staticmethod(lambda **_kwargs: None)})()
    tools_module = types.ModuleType("tools")
    tools_module.registry = registry_module
    sys.modules["tools"] = tools_module
    sys.modules["tools.registry"] = registry_module
    caminho = Path(__file__).resolve().parent / "hermes-tools" / "fabio_registro_aula_tool.py"
    spec = importlib.util.spec_from_file_location("fabio_registro_aula_tool_test", caminho)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class RegistroNormalizationConsumerTest(unittest.TestCase):
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
        with patch.object(tool, "_buscar_roster_aula", side_effect=tool.requests.Timeout("tempo")), \
             patch.object(tool.requests, "post") as post_mock, \
             patch.object(tool, "fabio_atualizar_status_audio") as status_mock:
            result = json.loads(tool.fabio_criar_registro_aula(self._legacy_payload()))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "roster_indisponivel")
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

    def test_tool_rejeita_fatias_vazias_sem_chamar_rpc(self):
        tool = _carregar_tool_real()
        roster = [{"aluno_id": 7, "aluno_nome": "Lucas", "aula_id": 101}]
        payload = self._legacy_payload()
        payload["fatias"] = []
        with patch.object(tool, "_headers", return_value={}), \
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
