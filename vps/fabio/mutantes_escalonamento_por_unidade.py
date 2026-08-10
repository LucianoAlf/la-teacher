"""Mutantes do teste do escalonamento por unidade — verde tem que ser falsificável.

O `teste_escalonamento_por_unidade.py` roda contra uma fixture, sem banco e sem
rede. Teste assim passa fácil demais: se ele não morrer quando o defeito volta,
ele só decora o commit.

Cada mutante aqui reintroduz UM defeito plausível — a maioria deles é uma
decisão que eu quase tomei do outro jeito — roda o teste, e espera vermelho.

Rodar: python mutantes_escalonamento_por_unidade.py
"""
import os
import shutil
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
ALVO = os.path.join(AQUI, "fabio_notification_worker.py")
BACKUP = os.path.join(AQUI, "_fabio_notification_worker.original.py")
TESTE = os.path.join(AQUI, "teste_escalonamento_por_unidade.py")

MUTANTES = [
    {
        "nome": "V1 — a unidade vira a primeira da lista, não a dominante",
        "pega": "4b (Lohana tem 5 aulas em CG e cairia na Barra)",
        "de": "    if contagem:\n"
              "        # Empate resolvido pelo nome da unidade: mesma entrada, mesma saida.\n"
              "        return sorted(contagem.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]",
        "para": "    if False:\n"
                "        return sorted(contagem.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]",
    },
    {
        "nome": "V2 — o professor multi-unidade entra em TODAS (a contagem dobrada)",
        "pega": "3a e 4a — 11 professores somariam 13",
        "de": "        grupos.setdefault(_unidade_de_cobranca(r), []).append(r)",
        "para": "        for _u in (r.get('unidades') or [_unidade_de_cobranca(r)]):\n"
                "            grupos.setdefault(_u, []).append(r)",
    },
    {
        "nome": "V3 — o índice conta por conta própria, não pelo agrupamento",
        "pega": "3b — índice e mensagem discordariam (o defeito da 080)",
        "de": '                 " · ".join(f"{u} {len(linhas)}" for u, linhas in grupos.items()),',
        "para": '                 " · ".join(f"{u} {sum(1 for r in rows if u in (r.get(chr(117)+chr(110)+chr(105)+chr(100)+chr(97)+chr(100)+chr(101)+chr(115)) or []))}" for u, linhas in grupos.items()),',
    },
    {
        "nome": "V4 — o racionamento vira CORTE (quem sobra é descartado)",
        "pega": "6c/6d/6g — a lista curta passaria por completa",
        "de": "    resto = [] if limite <= 0 else ordenados[limite:]",
        "para": "    resto = []",
    },
    {
        "nome": "V5 — a fila perde a capa",
        "pega": "1a/1b — 4 mensagens virariam 3",
        "de": "    if len(grupos) > 1:\n        indice = format_escalonamento_indice(rows)",
        "para": "    if False:\n        indice = format_escalonamento_indice(rows)",
    },
    {
        "nome": "V6 — capa também com uma unidade só",
        "pega": "9b — duas mensagens onde bastava uma",
        "de": "    if len(grupos) > 1:\n        indice = format_escalonamento_indice(rows)",
        "para": "    if len(grupos) >= 1:\n        indice = format_escalonamento_indice(rows)",
    },
    {
        "nome": "V7 — a ordem passa a ser por dias de atraso, não por aula parada",
        "pega": "6e/6f — quem tem 14 aulas abriria na frente de quem tem 19",
        "de": "    return (-int(row.get(\"total_aulas\") or 0),\n"
              "            -int(row.get(\"pior_atraso\") or 0),",
        "para": "    return (-int(row.get(\"pior_atraso\") or 0),\n"
                "            -int(row.get(\"total_aulas\") or 0),",
    },
    {
        "nome": "V8 — o '+N aulas' some depois da divisão",
        "pega": "5 — o corte da RPC (p_max_aulas=12) viraria mentira",
        "de": "    if total > len(aulas):\n"
              "        out.append(\"\")\n"
              "        out.append(f\"_+{total - len(aulas)} aulas atrasadas deste professor_\")",
        "para": "    if False:\n"
                "        out.append(\"\")\n"
                "        out.append(f\"_+{total - len(aulas)} aulas atrasadas deste professor_\")",
    },
    {
        "nome": "V9 — o bloco perde a hora em negrito (formato A quebrado)",
        "pega": "7a — a âncora visual de quem lê no celular",
        "de": '            out.append(f"*{hora}* · {curso}" if hora else f"· {curso}")',
        "para": '            out.append(f"{hora} · {curso}" if hora else f"· {curso}")',
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
