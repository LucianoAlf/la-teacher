#!/usr/bin/env python3
"""Teste do casador de carimbo da auditoria (fabio_auditoria.carimba_escrita).

POR QUE ELE EXISTE. A checagem "o Fábio disse que gravou e não gravou" só vale
o WhatsApp que ela custa se acertar. A primeira versão era uma lista de frases
e acertava METADE das 113 respostas reais do Fábio no banco:

  · "Ficaram *4 aulas sem presença marcada*"      -> disparava. É RELATO de
    estado, não promessa. O Fábio está dizendo o contrário do que o alarme leu.
  · "ainda não consigo gravar o registro"          -> disparava. É a resposta
    HONESTA que entrou hoje. O alarme puniria exatamente o conserto.
  · "Posso deixar esse registro salvo?"            -> disparava. É pergunta.

Alarme que grita errado o Alf aprende a ignorar em dois dias, e aí o alarme
certo morre junto. Por isso os casos NEGATIVOS aqui são mais importantes que os
positivos: sem eles, "melhorar o casador" vira `return True`.

Todas as frases abaixo são REAIS, tiradas de `fabio_chat_mensagens`, exceto as
quatro marcadas como (sintética) — que cobrem carimbos que ele ainda não deu
mas o prompt já proíbe.

Rodar:  python3 teste_auditoria_carimbo.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_auditoria import carimba_escrita  # noqa: E402


# ── tem que DISPARAR: o Fábio afirma ter escrito ───────────────────────────
DEVE_PEGAR = [
    "Pronto, Daiana. Deixei o registro da Beatriz organizado e salvo.",
    "Pronto, Daiana. Deixei o registro da Júlia Vilardo e da Clara organizado e "
    "salvo com o nome corrigido.",
    "Perfeito, Daiana. Confirmado: o Eduardo compareceu à aula de 06/08.",
    "Entendi, Daiana. Vou considerar a ausência do Anderson Cheren nesta aula.",
    "Pronto, irmão. Registrei a aula do Braz no dia 16 às 18h certinho.",
    "Pronto, irmão. Registrei a aula experimental do dia 16 às 17h certinho.",
    # (sintética) — carimbos que o prompt novo proíbe e que ele ainda não deu
    "Marquei a presença do João na aula de ontem.",
    "Deixo a presença encaminhada para validação.",
    "Prontinho, atualizei no sistema.",
    "A observação já está salva.",
    # (sintética) o carimbo divide a MENSAGEM com uma negação que fala de outra
    # coisa. Sem quebrar em frases, o "não" da primeira inocenta a segunda e o
    # carimbo passa batido — é o mutante M2.
    "Daiana, hoje não tem aula na sua agenda. Registrei a aula de ontem.",
]

# ── NÃO pode disparar ──────────────────────────────────────────────────────
DEVE_IGNORAR = [
    # relato de estado: ele está dizendo que FALTA presença, não que marcou
    "Sim, Matheus. Ficaram *4 aulas sem presença marcada*:\n\n• 16:00 — Giovana\n"
    "• 17:00 — Júlia e Natália",
    "Tenho certeza do que aparece no sistema, Matheus:\n\n• *4 aulas sem presença "
    "marcada*: 16h, 17h, 18h e 19h.",
    # a resposta honesta que entrou em 10/08 — o alarme não pode punir o conserto
    "Daiana, por aqui no WhatsApp eu ainda não consigo gravar o registro. No app "
    "do LA Teacher, vá em Agenda, abra essa aula e use o microfone no registro.",
    "Daiana, por aqui no WhatsApp eu ainda não consigo marcar a presença.",
    "Daiana, como já passou da janela de 7 dias, o app bloqueia mesmo. Nesse "
    "caso, fala com a coordenação para verificarem a liberação.",
    # perguntas. As duas primeiras são reais e, na verdade, já caem pelo tempo
    # verbal ("deixar"/"deixe" não é "deixei") — foi o mutante M3 sobrevivendo
    # que mostrou isso. As duas de baixo são as que a peneira de pergunta
    # realmente segura: sem ela, "presença marcada" casa e o alarme dispara numa
    # frase em que o Fábio está PEDINDO permissão, não avisando que fez.
    "Quer que eu deixe esse texto como registro da aula dela?",
    "Posso deixar esse registro salvo?",
    "Posso deixar a presença marcada?",
    "Quer que a observação fique registrada junto?",
    # leitura de histórico
    "A última aula dela foi em 05/08 e ficou sem registro. O último conteúdo "
    "registrado que encontrei foi em 08/07: percepção melódica.",
    # "corrigindo" não é "corrigi"
    "Tô aqui, Matheus. 👋 Inclusive, corrigindo a rota pra te ajudar melhor: na "
    "Luiza em Canto, a última aula foi diferente.",
    # organizar texto não é gravar texto
    "Boa, Daiana. Organizei assim:\n\nJúlia e Clara — quarta, 16h\n\nTrabalharam "
    "postação e projeção vocal.",
    "Fechado, Daiana. Quando quiser, me manda os pontos do jeito que lembrar que "
    "eu organizo contigo.",
    "Imagina, Daiana! Quando quiser, me chama por aqui.",
]


def main() -> int:
    falhas = []
    for f in DEVE_PEGAR:
        if not carimba_escrita(f):
            falhas.append(("DEIXOU PASSAR (carimbo não detectado)", f))
    for f in DEVE_IGNORAR:
        if carimba_escrita(f):
            falhas.append(("FALSO ALARME (não é carimbo)", f))

    total = len(DEVE_PEGAR) + len(DEVE_IGNORAR)
    for motivo, frase in falhas:
        print(f"✗ {motivo}\n    {frase[:110]!r}\n")
    if falhas:
        print(f"{len(falhas)} de {total} casos falharam "
              f"({len(DEVE_PEGAR)} positivos, {len(DEVE_IGNORAR)} negativos)")
        return 1
    print(f"✓ {total} casos OK — {len(DEVE_PEGAR)} carimbos pegos, "
          f"{len(DEVE_IGNORAR)} frases inocentes ignoradas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
