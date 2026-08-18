#!/usr/bin/env python3
"""O detector de promessa medido contra a fala REAL do Fábio.

Todas as frases de `REAIS_*` foram copiadas de `fabio_chat_mensagens`
(role='fabio', últimos 60 dias, consultado em 18/08/2026). Nenhuma foi
inventada por mim — detector treinado em fixture que eu escrevo passa verde e
falha em produção, que foi exatamente o que aconteceu com o detector de
substituição em 15/08.

As inocentes importam tanto quanto as culpadas: 5 das 8 frases que "parecem
promessa" no corpus são VERDADE, porque existe fila de áudio atrás delas. Um
detector que mata essas cinco cala o Fábio no lugar errado.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fabio_promessa import CONSULTA_DEPOIS, FLUXO_SEM_FILA, classificar_promessa  # noqa: E402


# ── promessas de verdade: nao existe caminho que entregue isso depois ─────────
REAIS_PROMESSAS = [
    # prof 36, 10/08 12:42 — carteira, capacidade que ele NAO tem
    "Claro, Valdo. Vou conferir a divisão certinha entre Recreio e Campo Grande "
    "para te passar os números corretos.",
    # prof 36, 16/08 21:30 — e ele TINHA a ferramenta
    "Se quiser, eu olho esse período certinho e te trago o total.",
    # prof 36, 17/08 13:30 — a conversa que virou o bug do parser
    "Perfeito, Valdo. Vou conferir de terça, 11/08, até sábado, 15/08, e te "
    "passo o total certinho.",
]

# ── falam do futuro e sao HONESTAS: existe fila/worker por tras ───────────────
REAIS_INOCENTES_COM_FLUXO = [
    "Áudio recebido. Vou processar a aula e te mostro o resumo antes de gravar. "
    "(guardei esse áudio aqui — assim que a gente fechar o anterior, ele entra.)",
    "Ainda não sei de qual aula você está falando. Me diz o dia e o horário "
    '(ex.: "sábado, meio-dia") ou o nome do aluno. (guardei esse áudio aqui — '
    "assim que a gente fechar o anterior, ele entra.)",
    "Parece que o da Valentina ainda está em processamento, Matheus — ainda não "
    "ficou confirmado nem gravado. Não precisa reenviar por enquanto; assim que "
    "sair o preview, eu te aviso.",
    "Perfeito, Matheus. O relatório da musicalização ficou encaminhado para o "
    "app. Assim que a confirmação aparecer aqui, ele estará disponível por lá.",
    "Ainda não gravei. Você quer confirmar, corrigir, cancelar ou deixar para "
    "depois? (guardei esse áudio aqui — assim que a gente fechar o anterior, "
    "ele entra.)",
]

# ── nao falam de compromisso nenhum ───────────────────────────────────────────
REAIS_INOCENTES_SEM_FUTURO = [
    "E aí, Matheus! Vi que teu dia fechou com *6 aulas* e *9 atendimentos*. "
    "Como foram as aulas hoje?",
    # o falso positivo classico: "pode deixar" que nao e "pode deixar comigo"
    "Acho uma ótima, irmão. Karaokê pode deixar a Fernanda mais à vontade logo "
    "de cara e ainda cria uma interação natural com a Julia e a Natália.",
    "De 11 a 15 de agosto, você deu 36 aulas: 25 em Campo Grande e 11 no Recreio.",
    "De que dia a que dia, Valdo? Foi hoje ou algum período específico?",
]


class PromessaDeConsultaTest(unittest.TestCase):
    """Consulta nao tem fila: promessa de trazer numero depois e SEMPRE falsa."""

    def test_as_tres_promessas_reais_do_corpus_sao_pegas(self):
        for frase in REAIS_PROMESSAS:
            with self.subTest(frase=frase[:50]):
                achado = classificar_promessa(frase, ha_fluxo_pendente=False)
                self.assertIsNotNone(achado, "promessa real passou batido")
                self.assertEqual(achado["tipo"], CONSULTA_DEPOIS)

    def test_promessa_de_consulta_e_falsa_ATE_com_fila_viva(self):
        # A fila entrega áudio, nunca número. Ter áudio processando não torna
        # verdadeira a promessa de "te passo o total".
        for frase in REAIS_PROMESSAS:
            with self.subTest(frase=frase[:50]):
                self.assertIsNotNone(classificar_promessa(frase, ha_fluxo_pendente=True))


class InocentesTest(unittest.TestCase):
    """A metade que costuma faltar: nao calar o Fabio onde ele fala verdade."""

    def test_frases_com_fila_viva_atras_passam(self):
        for frase in REAIS_INOCENTES_COM_FLUXO:
            with self.subTest(frase=frase[:50]):
                self.assertIsNone(classificar_promessa(frase, ha_fluxo_pendente=True))

    def test_frases_sem_compromisso_passam_sempre(self):
        for frase in REAIS_INOCENTES_SEM_FUTURO:
            with self.subTest(frase=frase[:50]):
                self.assertIsNone(classificar_promessa(frase, ha_fluxo_pendente=False))
                self.assertIsNone(classificar_promessa(frase, ha_fluxo_pendente=True))

    def test_pode_deixar_a_fernanda_nao_e_pode_deixar_comigo(self):
        # Falso positivo que o corpus entregou de bandeja.
        frase = REAIS_INOCENTES_SEM_FUTURO[1]
        self.assertIsNone(classificar_promessa(frase, ha_fluxo_pendente=False))


# ⚠️ ESTA e a unica frase INVENTADA do arquivo, e esta marcada de proposito.
# O mutante 4 mostrou que a exclusao de "pode deixar" nao era sustentada por
# teste nenhum: a frase real da Fernanda passa porque nao tem objeto de
# consulta, nao por causa da exclusao. Faltava o caso em que as duas coisas
# aparecem juntas — sugestao pedagogica que por acaso cita um numero.
INVENTADA_SUGESTAO_COM_NUMERO = (
    "Karaokê pode deixar a turma mais à vontade logo de cara — são 6 alunos "
    "no total, dá pra revezar bem."
)


class ExclusaoDoPodeDeixarTest(unittest.TestCase):
    def test_sugestao_pedagogica_que_cita_numero_nao_e_promessa(self):
        self.assertIsNone(
            classificar_promessa(INVENTADA_SUGESTAO_COM_NUMERO, ha_fluxo_pendente=False))


class FluxoSemFilaTest(unittest.TestCase):
    """A MESMA frase muda de veredito conforme exista fila ou nao."""

    def test_promessa_de_audio_sem_fila_e_pega(self):
        frase = REAIS_INOCENTES_COM_FLUXO[0]
        achado = classificar_promessa(frase, ha_fluxo_pendente=False)
        self.assertIsNotNone(achado)
        self.assertEqual(achado["tipo"], FLUXO_SEM_FILA)

    def test_e_a_mesma_frase_passa_quando_a_fila_existe(self):
        frase = REAIS_INOCENTES_COM_FLUXO[0]
        self.assertIsNone(classificar_promessa(frase, ha_fluxo_pendente=True))


class BordasTest(unittest.TestCase):
    def test_vazio_e_none(self):
        self.assertIsNone(classificar_promessa("", False))
        self.assertIsNone(classificar_promessa(None, False))

    def test_o_gatilho_vem_junto_pro_log(self):
        # "eu olho esse periodo certinho e te trago o total": o gatilho e o
        # PRIMEIRO compromisso da frase, nao o ultimo. Minha expectativa estava
        # errada aqui, nao o detector.
        achado = classificar_promessa(REAIS_PROMESSAS[1], ha_fluxo_pendente=False)
        self.assertEqual(achado["gatilho"], "eu olho")
        achado = classificar_promessa(REAIS_PROMESSAS[0], ha_fluxo_pendente=False)
        self.assertEqual(achado["gatilho"], "vou conferir")


if __name__ == "__main__":
    unittest.main(verbosity=1)
