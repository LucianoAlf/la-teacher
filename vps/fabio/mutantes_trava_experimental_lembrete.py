"""Mutantes da trava de duplicata do lembrete da experimental (C1, revisão 22/08/2026).

A spec diz "mutante vivo = trava sem teste". O CÓDIGO já estava certo (dois
ticks seguidos dão 'enviada' depois 'ja_avisado', com uma entrega só) — o que
faltava era o teste que DISTINGUE isso de um código sem a guarda. Os casos
25-27 de `teste_experimental_lembrete.py` (e o ajuste em `FakeBackend.rpc`
pra simular a cerca real da 018 em `fabio_marcar_notificacao_enviada`) foram
escritos pra matar os dois mutantes abaixo, que sobreviviam 58/58 antes deles:

  - M1: apaga a guarda `if not claim.get("claimed"): ... continue` — sem ela,
    dois ticks do timer (5 em 5 minutos, janela de 20) mandam a MESMA
    cobrança duas vezes, pra sempre, sem erro nenhum no journal.
  - M2: troca `mark_sent(notificacao_id, lease_token)` por
    `mark_sent(notificacao_id)` — pior que "preso em processando": o claim
    POR REFERÊNCIA sempre escreve lease_token, chamar sem ele não casa com
    nenhum lado da cerca 018 (zero linhas), e a `fabio_claim_notificacao_
    por_referencia` re-reivindica a linha com lease vencido (10min contra
    janela de 20) — SEGUNDA entrega no próximo tick.

MESMO padrão seguro de `mutantes_override_experimental.py` (não
`mutantes_escalonamento_experimental.py`): este checkout é COMPARTILHADO com
outra sessão, então a arena copia os `.py` necessários pra um diretório
TEMPORÁRIO antes de mutar — o arquivo do repo nunca é tocado, nem por um
instante.

Rodar: python3 mutantes_trava_experimental_lembrete.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
ALVO_NOME = "fabio_notification_worker.py"
TESTE_NOME = "teste_experimental_lembrete.py"
# Mesmo fechamento de dependências de mutantes_override_experimental.py:
# fabio_chat_bridge.py importa estes 5 módulos locais na carga.
DEPENDENCIAS = [
    "fabio_chat_bridge.py",
    "fabio_whatsapp_actions.py",
    "fabio_whatsapp_intents.py",
    "fabio_consulta_fallback.py",
    "fabio_promessa.py",
    "fabio_registro_normalization_contract.py",
]

MUTANTES = [
    {
        "nome": "M1 -- apaga a guarda 'ja_avisado' (dois ticks = duas entregas)",
        "pega": "caso 25 -- rodar o worker duas vezes no MESMO FakeBackend tem"
                " que dar ['enviada','ja_avisado'] com exatamente UMA entrega;"
                " sem a guarda, o segundo tick reenvia a mesma cobranca",
        "de": "            if not claim.get(\"claimed\"):\n"
              "                resultado[\"status\"] = \"ja_avisado\"\n"
              "                resultados.append(resultado)\n"
              "                continue",
        "para": "            pass",
    },
    {
        "nome": "M2 -- mark_sent perde o lease_token (nao casa com a cerca 018)",
        "pega": "caso 26/27 -- sem o lease_token no corpo, a cerca real (018)"
                " devolve False (zero linhas); o FakeBackend simula isso e o"
                " status TEM que virar 'entregue_mas_nao_fechada', nunca 'enviada'",
        "de": "                if not mark_sent(notificacao_id, lease_token):",
        "para": "                if not mark_sent(notificacao_id):",
    },
]


def _preparar_workdir() -> str:
    workdir = tempfile.mkdtemp(prefix="mutantes_trava_experimental_lembrete_")
    for nome in [ALVO_NOME, TESTE_NOME] + DEPENDENCIAS:
        shutil.copyfile(os.path.join(AQUI, nome), os.path.join(workdir, nome))
    return workdir


def _rodar_teste(workdir: str) -> bool:
    r = subprocess.run([sys.executable, TESTE_NOME], cwd=workdir,
                        capture_output=True, text=True)
    return r.returncode == 0


def main() -> int:
    workdir = _preparar_workdir()
    alvo_path = os.path.join(workdir, ALVO_NOME)
    fonte_original = open(alvo_path, encoding="utf-8").read()
    mortos = 0
    podres = 0
    try:
        if not _rodar_teste(workdir):
            print("ABORTADO: o teste ja falha SEM mutante nenhum.")
            return 1
        for m in MUTANTES:
            n = fonte_original.count(m["de"])
            if n != 1:
                print(f"STALE  {m['nome']} — ancora aparece {n}x, esperava 1")
                podres += 1
                continue
            open(alvo_path, "w", encoding="utf-8").write(fonte_original.replace(m["de"], m["para"]))
            if _rodar_teste(workdir):
                print(f"FALHA  SOBREVIVEU: {m['nome']}  ({m['pega']})")
            else:
                mortos += 1
                print(f"OK     morto: {m['nome']}  ({m['pega']})")
    finally:
        # Restaura o alvo copiado (defensivo) e apaga o diretorio temporario
        # inteiro. O arquivo do REPO nunca foi tocado: so a copia em
        # `workdir` foi mutada.
        open(alvo_path, "w", encoding="utf-8").write(fonte_original)
        shutil.rmtree(workdir, ignore_errors=True)
    extra = f"  —  {podres} ANCORA(S) PODRE(S)" if podres else ""
    print(f"\n{mortos}/{len(MUTANTES)} mutantes mortos{extra}")
    return 0 if mortos == len(MUTANTES) and not podres else 1


if __name__ == "__main__":
    raise SystemExit(main())
