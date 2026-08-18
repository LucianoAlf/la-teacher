#!/usr/bin/env python3
"""Fronteira da passada A (rede de segurança da consulta letiva).

Contrato do Alf em 18/08/2026 — os itens 9 e 10 dele são testes OBRIGATÓRIOS e
estão em `FronteiraDaIdentidadeTest` e `SchemaFechadoTest`.

O que este arquivo protege, em uma frase: o modelo pode dizer O QUE consultar;
nunca DE QUEM. `professor_id` nasce da linha, no bridge, e não existe campo
para ele em lugar nenhum deste caminho.
"""
import json
import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_consulta_fallback import (  # noqa: E402
    CAMPOS_PERMITIDOS,
    deve_tentar_fallback,
    montar_prompt_pedido,
    validar_pedido,
)

HOJE = date(2026, 8, 18)
UNIDADES = ["Campo Grande", "Recreio", "Barra"]


def pedido(**campos):
    return json.dumps(campos, ensure_ascii=False)


class FronteiraDaIdentidadeTest(unittest.TestCase):
    """Item 9 do contrato: induzir `professor_id` tem que MORRER.

    Não é hipótese. Medido em 18/08/2026: com o prompt cheio (12.024 chars) a
    passada A inventou o campo `aulas_ministradas` e devolveu `professor_id` na
    resposta. Com o prompt curto (424 chars) saiu o schema exato, 4/4.
    O prompt curto é a primeira trava; esta validação é a segunda, e é a que
    não depende de o modelo se comportar.
    """

    def test_professor_id_no_retorno_rejeita_o_payload_inteiro(self):
        bruto = pedido(consulta="aulas_periodo", inicio="2026-08-11",
                       fim="2026-08-15", unidade=None, professor_id=36)
        self.assertIsNone(validar_pedido(bruto, HOJE, UNIDADES))

    def test_rejeita_mesmo_quando_o_resto_esta_perfeito(self):
        # A tentação é "limpa o campo e segue" — isso faria funcionar e
        # ESCONDERIA que o modelo saiu do schema. Rejeitar deixa rastro.
        bom = pedido(consulta="aulas_periodo", inicio="2026-08-11",
                     fim="2026-08-15", unidade=None)
        self.assertIsNotNone(validar_pedido(bom, HOJE, UNIDADES))
        ruim = json.loads(bom)
        ruim["professor_id"] = 36
        self.assertIsNone(validar_pedido(json.dumps(ruim), HOJE, UNIDADES))

    def test_qualquer_chave_com_professor_morre(self):
        for chave in ("professor_id", "professor", "id_professor", "professorId"):
            with self.subTest(chave=chave):
                self.assertIsNone(validar_pedido(
                    pedido(**{"consulta": "aulas_periodo", "inicio": "2026-08-11",
                              "fim": "2026-08-15", chave: 36}), HOJE, UNIDADES))

    def test_o_prompt_nao_menciona_professor_id(self):
        # Se a palavra não está no prompt, o modelo não é convidado a inventá-la.
        p = montar_prompt_pedido("quantas aulas eu dei semana passada?", HOJE)
        self.assertNotIn("professor", p.lower())

    def test_o_prompt_e_curto(self):
        # 424 chars foi o que saiu 4/4 exato na medição; 12.024 derivou.
        p = montar_prompt_pedido("quantas aulas eu dei semana passada?", HOJE)
        self.assertLess(len(p), 900, f"prompt com {len(p)} chars — a deriva mora aqui")

    def test_texto_do_professor_nao_injeta_instrucao_no_schema(self):
        # O texto entra no prompt; ele não pode virar comando. A trava real é a
        # validação: mesmo que o modelo obedeça ao professor, o campo morre.
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="2026-08-11",
                   fim="2026-08-15", professor_id=99), HOJE, UNIDADES))


class SchemaFechadoTest(unittest.TestCase):
    """Item 10 do contrato: campo extra rejeita."""

    def test_aceita_exatamente_os_campos_do_contrato(self):
        self.assertEqual(CAMPOS_PERMITIDOS, {"consulta", "inicio", "fim", "unidade"})

    def test_campo_inventado_rejeita(self):
        # `aulas_ministradas` foi o campo que o modelo inventou de verdade.
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="2026-08-11", fim="2026-08-15",
                   aulas_ministradas=36), HOJE, UNIDADES))

    def test_unidade_ausente_e_permitido(self):
        r = validar_pedido(pedido(consulta="aulas_periodo", inicio="2026-08-11",
                                  fim="2026-08-15"), HOJE, UNIDADES)
        self.assertIsNotNone(r)
        self.assertIsNone(r["unidade"])

    def test_json_dentro_de_cerca_de_markdown_ainda_vale(self):
        bruto = '```json\n{"consulta":"aulas_periodo","inicio":"2026-08-11","fim":"2026-08-15"}\n```'
        r = validar_pedido(bruto, HOJE, UNIDADES)
        self.assertIsNotNone(r)
        self.assertEqual(r["metrica"], "aulas")

    def test_resposta_que_nao_e_json_rejeita(self):
        self.assertIsNone(validar_pedido("Você deu 36 aulas nesse período!", HOJE, UNIDADES))

    def test_lista_no_lugar_do_objeto_rejeita(self):
        self.assertIsNone(validar_pedido('[{"consulta":"aulas_periodo"}]', HOJE, UNIDADES))


class ValoresTest(unittest.TestCase):
    def test_aulas_e_presencas_viram_metrica(self):
        r = validar_pedido(pedido(consulta="aulas_periodo", inicio="2026-08-11",
                                  fim="2026-08-15"), HOJE, UNIDADES)
        self.assertEqual(r["metrica"], "aulas")
        r = validar_pedido(pedido(consulta="presencas_periodo", inicio="2026-08-11",
                                  fim="2026-08-15"), HOJE, UNIDADES)
        self.assertEqual(r["metrica"], "presencas")

    def test_nenhuma_nao_e_falha_e_nao_injeta(self):
        # A dizendo "não era consulta" é resposta válida — e não vira bloco.
        self.assertIsNone(validar_pedido(pedido(consulta="nenhuma"), HOJE, UNIDADES))

    def test_nenhuma_manda_MESMO_com_periodo_valido_junto(self):
        # O mutante 7 mostrou que o teste acima passava por falta de datas, nao
        # por respeitar o "nenhuma". Aqui o modelo preenche periodo E diz que
        # nao e consulta — a palavra dele tem que valer.
        self.assertIsNone(validar_pedido(
            pedido(consulta="nenhuma", inicio="2026-08-11", fim="2026-08-15"),
            HOJE, UNIDADES))

    def test_consulta_desconhecida_rejeita(self):
        self.assertIsNone(validar_pedido(
            pedido(consulta="faturas_periodo", inicio="2026-08-11", fim="2026-08-15"),
            HOJE, UNIDADES))

    def test_periodo_invertido_rejeita(self):
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="2026-08-15", fim="2026-08-11"),
            HOJE, UNIDADES))

    def test_janela_longa_demais_rejeita(self):
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="2026-01-01", fim="2026-08-15"),
            HOJE, UNIDADES))

    def test_data_alucinada_longe_de_hoje_rejeita(self):
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="1999-08-11", fim="1999-08-15"),
            HOJE, UNIDADES))

    def test_data_que_nao_existe_rejeita(self):
        self.assertIsNone(validar_pedido(
            pedido(consulta="aulas_periodo", inicio="2026-02-30", fim="2026-03-01"),
            HOJE, UNIDADES))

    def test_periodo_faltando_rejeita(self):
        self.assertIsNone(validar_pedido(pedido(consulta="aulas_periodo"), HOJE, UNIDADES))

    def test_unidade_real_passa(self):
        r = validar_pedido(pedido(consulta="aulas_periodo", inicio="2026-08-11",
                                  fim="2026-08-15", unidade="campo grande"), HOJE, UNIDADES)
        self.assertEqual(r["unidade"], "Campo Grande")

    def test_unidade_inventada_nao_chega_na_rpc(self):
        # Texto livre do modelo nunca vira filtro: vira None, e a consulta sai
        # sem recorte de unidade em vez de sair com recorte errado.
        r = validar_pedido(pedido(consulta="aulas_periodo", inicio="2026-08-11",
                                  fim="2026-08-15", unidade="Unidade Central"), HOJE, UNIDADES)
        self.assertIsNotNone(r)
        self.assertIsNone(r["unidade"])


class GateTest(unittest.TestCase):
    """Item 3: A só roda quando o determinístico volta vazio ou ambíguo.

    O gate é largo de propósito (quem decide de verdade é a validação), mas
    NÃO pode abrir para registro de aula: medido no corpus de 60 dias, as
    mensagens que só um gate largo pegaria são majoritariamente registro
    ("quero registrar a aula de piano T, turma P_QUI_19, do dia 6 de agosto").
    Rodar A ali é custo puro no pior momento.
    """

    def test_pergunta_letiva_sem_periodo_abre(self):
        self.assertTrue(deve_tentar_fallback("me diz o total que eu trabalhei"))

    def test_forma_que_o_regex_de_hoje_nao_ve_abre(self):
        self.assertTrue(deve_tentar_fallback("fábio, quanto que eu trabalhei na semana retrasada?"))

    def test_registro_de_aula_nao_abre(self):
        self.assertFalse(deve_tentar_fallback(
            "quero registrar a aula de piano t, turma p_qui_19, do dia 6 de agosto, às 19h."))

    def test_registro_em_outra_forma_nao_abre(self):
        self.assertFalse(deve_tentar_fallback("vamos registrar a aula do bernardo de hoje"))

    def test_conversa_solta_nao_abre(self):
        self.assertFalse(deve_tentar_fallback("bom dia! tudo certo por aí?"))

    def test_pedido_pedagogico_nao_abre(self):
        self.assertFalse(deve_tentar_fallback(
            "me ajuda na aula da luiza com digitação e asa branca, plano de 3 passos"))

    def test_texto_vazio_nao_abre(self):
        self.assertFalse(deve_tentar_fallback(""))
        self.assertFalse(deve_tentar_fallback("   "))


if __name__ == "__main__":
    unittest.main(verbosity=1)
