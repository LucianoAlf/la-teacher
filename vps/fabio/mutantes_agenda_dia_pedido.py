"""Mutantes do teste da agenda por dia — o verde tem que ser falsificavel.

O `teste_agenda_dia_pedido.py` roda contra um bridge falso (fixture de agenda,
`today_brt` congelado). Um teste assim passa facil demais: se ele nao morrer
quando o defeito volta, ele so decora o commit.

Cada mutante aqui reintroduz UM defeito real no `fabio_chat_bridge.py`, roda o
teste, e espera vermelho. V1 e literalmente o bug de 09/08/2026 ("amanha"
respondido com a agenda de hoje). V5 a V8 guardam o vizinho cego — o bloco de
outro dia que o caminho do Hermes passou a receber.

Rodar: python mutantes_agenda_dia_pedido.py
"""
import os
import shutil
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
ALVO = os.path.join(AQUI, "fabio_chat_bridge.py")
BACKUP = os.path.join(AQUI, "_fabio_chat_bridge.original.py")
TESTE = os.path.join(AQUI, "teste_agenda_dia_pedido.py")

MUTANTES = [
    {
        "nome": "V1 — o dia volta a ser sempre hoje (o bug de 09/08)",
        "pega": "1x/2x: 'amanha' respondido com a agenda de hoje",
        "de": '    ctx = professor_context(professor_id, dia["iso"])\n'
              '    if not isinstance(ctx, dict) or not ctx.get("ok"):',
        "para": '    ctx = professor_context(professor_id)\n'
                '    if not isinstance(ctx, dict) or not ctx.get("ok"):',
    },
    {
        "nome": "V2 — nao saber o dia volta a virar hoje",
        "pega": "os passos de periodo/ambiguidade ('da semana', dois dias)",
        "de": "    if _PERIODO_RE.search(norm):\n        return None",
        "para": "    if False:\n        return None",
    },
    {
        "nome": "V3 — a trava do dia divergente cai",
        "pega": "passo 6: RPC teimoso devolvendo hoje",
        "de": '    servido = (ctx.get("hoje") or {}).get("data")\n'
              '    if servido and servido != dia["iso"]:',
        "para": '    servido = (ctx.get("hoje") or {}).get("data")\n'
                '    if False:',
    },
    {
        "nome": "V4 — 'quantos alunos eu tenho' volta a virar contagem de hoje",
        "pega": "passo 5c: pergunta de carteira respondida com agenda",
        "de": '    if asks_count and not asks_schedule and not dia["explicito"]:\n        return None',
        "para": '    if False:\n        return None',
    },
    {
        "nome": "V5 — o vizinho cego volta: o Hermes so recebe hoje",
        "pega": "passos 7a/7b/7c (bloco do dia citado)",
        "de": '    if not dia or not dia.get("explicito") or dia["iso"] == today_brt():\n        return None',
        "para": "    return None\n    if False:\n        return None",
    },
    {
        "nome": "V6 — o bloco do dia citado busca hoje mesmo assim",
        "pega": "passo 7b (traria as aulas erradas)",
        "de": '        ctx = professor_context(professor_id, dia["iso"])\n'
              '    except Exception as e:',
        "para": "        ctx = professor_context(professor_id)\n"
                "    except Exception as e:",
    },
    {
        "nome": "V7 — dia vazio deixa de ser resposta e vira ausencia de bloco",
        "pega": "passo 7c/7c2 (vazio e 'nao tem aula', nao 'nao sei')",
        "de": '    return {\n        "data": dia["iso"],',
        "para": '    if not (bloco.get("aulas") or []):\n        return None\n'
                '    return {\n        "data": dia["iso"],',
    },
    {
        "nome": "V8 — o bloco entra sempre, inclusive sem dia citado",
        "pega": "passos 7d/7e (ruido no prompt de toda conversa)",
        "de": '    if not dia or not dia.get("explicito") or dia["iso"] == today_brt():',
        "para": "    if not dia:",
    },
]


def rodar_teste() -> bool:
    r = subprocess.run([sys.executable, TESTE], cwd=AQUI,
                       capture_output=True, text=True)
    return r.returncode == 0


def main() -> int:
    fonte = open(ALVO, encoding="utf-8").read()
    shutil.copyfile(ALVO, BACKUP)
    mortos = 0
    podres = 0
    try:
        if not rodar_teste():
            print("ABORTADO: o teste ja falha SEM mutante nenhum.")
            return 1
        for m in MUTANTES:
            n = fonte.count(m["de"])
            if n != 1:
                print(f"STALE  {m['nome']} — ancora aparece {n}x, esperava 1")
                podres += 1
                continue
            open(ALVO, "w", encoding="utf-8").write(fonte.replace(m["de"], m["para"]))
            if rodar_teste():
                print(f"FALHA  SOBREVIVEU: {m['nome']}  ({m['pega']})")
            else:
                mortos += 1
                print(f"OK     morto: {m['nome']}  ({m['pega']})")
    finally:
        shutil.copyfile(BACKUP, ALVO)
        os.remove(BACKUP)
    extra = f"  —  {podres} ANCORA(S) PODRE(S)" if podres else ""
    print(f"\n{mortos}/{len(MUTANTES)} mutantes mortos{extra}")
    return 0 if mortos == len(MUTANTES) else 1


if __name__ == "__main__":
    raise SystemExit(main())
