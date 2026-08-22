"""Mutantes do teste do escalonamento da experimental — verde tem que ser falsificável.

O `teste_escalonamento_experimental.py` roda contra fixtures e mocks, sem
banco e sem rede. Teste assim passa fácil demais: se ele não morrer quando
o defeito volta, ele só decora o commit — foi exatamente isso que a
revisão de 22/08/2026 mediu: rodou 7 mutantes além dos que a primeira
versão desta arena tinha (fio de ligação em main(), segmento de
dias_em_atraso, hora do "quando" truncada) e TRÊS sobreviveram, porque não
existia teste nem mutante pra eles ainda.

Cada mutante aqui reintroduz UM defeito plausível — vários são decisões que
a revisão pegou entrando (ou saindo) por engano da versão anterior deste
arquivo. Roda o teste, espera vermelho.

Rodar: python mutantes_escalonamento_experimental.py
"""
import os
import shutil
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
ALVO = os.path.join(AQUI, "fabio_notification_worker.py")
BACKUP = os.path.join(AQUI, "_fabio_notification_worker.original.py")
TESTE = os.path.join(AQUI, "teste_escalonamento_experimental.py")

MUTANTES = [
    {
        "nome": "M1 — sem unidade (brief)",
        "pega": "caso 2 (cita a unidade)",
        "de": "f\"• *{l.get('nome_aluno') or 'lead'}* — {l.get('unidade_nome') or '?'}, \"",
        "para": "f\"• *{l.get('nome_aluno') or 'lead'}* — \"",
    },
    {
        "nome": "M2 — sem professor (brief)",
        "pega": "caso 4 (cita o professor)",
        "de": "f\"{l.get('quando') or '?'} · prof. {l.get('professor_nome') or '?'} \"",
        "para": "f\"{l.get('quando') or '?'} \"",
    },
    {
        "nome": "M3 — lista vazia vira bloco (brief)",
        "pega": "caso 6 (lista vazia devolve None) e 11a (fila do aluno para de ficar intocada)",
        "de": "    if not linhas:\n"
              "        return None\n"
              "    limite = ESCALONAMENTO_EXPERIMENTAL_TETO if teto is None else teto",
        "para": "    if linhas is None:\n"
                "        return None\n"
                "    limite = ESCALONAMENTO_EXPERIMENTAL_TETO if teto is None else teto",
    },
    {
        "nome": "M4 — Ruling 18 regride: quem passa do teto some de vez",
        "pega": "9c/9d/9e/10b — ninguém pode sumir, nem bem acima do teto",
        "de": "    resto = [] if limite <= 0 else linhas[limite:]",
        "para": "    resto = []",
    },
    {
        "nome": "M5 — isolamento da falha da RPC perde o log",
        "pega": "12c/12e — a falha deixa de chegar ao journal",
        "de": "    except Exception as exc:\n"
              "        log(\"escalonamento_experimental_falhou\", error=str(exc)[:300])\n"
              "        return []",
        "para": "    except Exception:\n"
                "        return []",
    },
    {
        "nome": "M6 — intocabilidade da fila do aluno perde a guarda",
        "pega": "11a — sem experimental, a fila do aluno deixa de sair intacta",
        "de": "    bloco_exp = format_escalonamento_experimental(linhas_exp)\n"
              "    if not bloco_exp:\n"
              "        return list(mensagens_aluno)\n"
              "    return list(mensagens_aluno) + [bloco_exp]",
        "para": "    bloco_exp = format_escalonamento_experimental(linhas_exp)\n"
                "    return list(mensagens_aluno) + [bloco_exp]",
    },
    {
        "nome": "M7 (I1) — o fio de ligação em main() é apagado",
        "pega": "caso 20 — guarda por inspect.getsource(main): a rodada anterior deixava"
                " isto passar 22/22 verde",
        "de": "        resultado = rodar_escalonamento(args.professor_id, args.dry_run)\n"
              "        results.append(resultado)\n"
              "        log(\"event_result\", **resultado)",
        "para": "        results.append({\"event\": \"escalonamento\", \"status\": \"sem_pendencia_escalonada\"})",
    },
    {
        "nome": "M8 (I2) — o segmento 'há X dia(s)' some inteiro",
        "pega": "7a — ninguém sabe há quanto tempo o lead está sem devolutiva",
        "de": "            f\"· há {_dias_em_atraso_txt(l)} dia(s)\"\n"
              "        )",
        "para": "            f\"\"\n"
                "        )",
    },
    {
        "nome": "M9 (minor) — a hora do 'quando' é truncada pra só a data",
        "pega": "3b — a coordenação perde a hora pra achar a aula na agenda",
        "de": "f\"{l.get('quando') or '?'} · prof. {l.get('professor_nome') or '?'} \"",
        "para": "f\"{(l.get('quando') or '?')[:5]} · prof. {l.get('professor_nome') or '?'} \"",
    },
    {
        "nome": "M10 (I2) — a defesa contra chave ausente é revertida",
        "pega": "7b/7c — chave ausente volta a renderizar a string 'None'",
        "de": "    dias = l.get(\"dias_em_atraso\")\n"
              "    return str(dias) if dias is not None else \"?\"",
        "para": "    return str(l.get(\"dias_em_atraso\"))",
    },
    {
        "nome": "M11 (I5) — o recorte por professor_id deixa de proteger a experimental",
        "pega": "15a/15c — --professor-id vazaria a experimental da escola inteira",
        "de": "        if professor_id is not None:\n"
              "            log(\"escalonamento_experimental_pulado\",\n"
              "                motivo=\"professor_id setado -- recorte de teste, nao coordenacao\")\n"
              "        else:\n"
              "            linhas_exp = linhas_experimental_escalonadas()",
        "para": "        linhas_exp = linhas_experimental_escalonadas()",
    },
    {
        "nome": "M12 (I4) — o bloco da experimental perde o evento próprio",
        "pega": "14d — journal volta a gravar escalonamento_enviado pros dois",
        "de": "            evento = \"escalonamento\" if i < n_aluno else \"escalonamento_experimental\"\n"
              "            enviar_grupo(corpo, evento=evento)",
        "para": "            enviar_grupo(corpo)",
    },
    {
        "nome": "M13 (I4) — a falha parcial deixa de avisar que a experimental se perdeu",
        "pega": "18c — enviadas=N sem dizer que a coordenação ficou sem a lista",
        "de": "        resultado = {\"event\": \"escalonamento\", \"status\": \"error\",\n"
              "                     \"enviadas\": enviadas, \"error\": str(exc)[:500]}\n"
              "        if linhas_exp and not experimental_enviado:\n"
              "            resultado[\"experimental_perdida\"] = True\n"
              "        return resultado",
        "para": "        return {\"event\": \"escalonamento\", \"status\": \"error\",\n"
                "                \"enviadas\": enviadas, \"error\": str(exc)[:500]}",
    },
    {
        "nome": "M14 (minor) — o desempacotamento volta pra fora do try",
        "pega": "12d — resposta de shape inesperado (não-dict) vaza um AttributeError cru",
        "de": "    try:\n"
              "        data = rpc(\"fn_experimental_escalonadas\", {})\n"
              "        return (data or {}).get(\"linhas\") or []\n"
              "    except Exception as exc:\n"
              "        log(\"escalonamento_experimental_falhou\", error=str(exc)[:300])\n"
              "        return []",
        "para": "    try:\n"
                "        data = rpc(\"fn_experimental_escalonadas\", {})\n"
                "    except Exception as exc:\n"
                "        log(\"escalonamento_experimental_falhou\", error=str(exc)[:300])\n"
                "        return []\n"
                "    return (data or {}).get(\"linhas\") or []",
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
