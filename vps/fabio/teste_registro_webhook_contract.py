import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent


class RegistroWebhookContractTest(unittest.TestCase):
    def test_prompt_usa_audio_id_da_fila_e_nao_registro_id(self):
        config = json.loads(
            (ROOT / "hermes-webhook-registro-aula.json").read_text(encoding="utf-8")
        )
        prompt = str(config["prompt"])
        prompt_lower = prompt.lower()
        self.assertIn("`audio_id` = `audio_id` do payload bruto", prompt)
        self.assertIn("nunca use `registro_id` como `audio_id`", prompt_lower)
        self.assertIn("`fabio_transcrever_audio_fila`", prompt)
        self.assertIn("origem, aula_id e professor_id", prompt_lower)
        self.assertIn("derivados da fila", prompt_lower)
        self.assertNotIn("`fabio_transcrever_audio_url`", prompt)
        self.assertNotIn('`origem` = "app"', prompt_lower)
        self.assertNotIn("`audio_id` = `registro_id`", prompt)
        self.assertEqual(config["skills"], ["registro-aula-audio-la-music"])
        self.assertEqual(config["deliver"], "log")


if __name__ == "__main__":
    unittest.main(verbosity=2)
