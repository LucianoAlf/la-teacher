"""Mutantes do override de destinatario da experimental (Task 6, Passo 1).

O `teste_experimental_lembrete.py` (casos 15-19) roda contra fixtures e
mocks, sem banco e sem rede. Verde nao-falsificado e decoracao -- cada
trava aqui precisa de um mutante que morre, em especial os dois que a
spec do rollout marcou por nome:

  - um mutante que REMOVE o override (o envio vazaria pro professor de
    verdade mesmo com `FABIO_EXPERIMENTAL_DEST_OVERRIDE` setada);
  - um mutante que REMOVE o aviso de teste do corpo (quem le a mensagem no
    numero de override acha que e cobranca real).

DIFERENTE do padrao antigo desta pasta (mutantes_escalonamento_experimental.py
etc, que mutam o arquivo do repo IN PLACE com backup/restore): este
checkout e COMPARTILHADO com outra sessao, e uma arena que reescreve
`fabio_notification_worker.py` no lugar ja travou uma vez hoje e deixou o
arquivo mutado no disco por minutos, no meio do trabalho de outra sessao.
Aqui a copia dos `.py` necessarios (worker + bridge + o teste) vai pra um
diretorio TEMPORARIO antes de mutar -- o arquivo do repo nunca e tocado,
nem por um instante.

Rodar: python3 mutantes_override_experimental.py
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
# fabio_chat_bridge.py importa este fechamento inteiro na carga do modulo
# (fabio_whatsapp_actions -> fabio_whatsapp_intents; fabio_consulta_fallback;
# fabio_promessa; fabio_registro_normalization_contract). Sem copiar os
# cinco, o import de bridge quebra com ModuleNotFoundError antes mesmo de
# qualquer mutante rodar -- conferido rodando a copia isolada na mao.
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
        "nome": "M1 -- o override e removido (manda pro professor de verdade mesmo ligado)",
        "pega": "caso 16 -- com FABIO_EXPERIMENTAL_DEST_OVERRIDE setada, o envio TEM"
                " que ir pro numero configurado, nunca pro professor real via deliver()",
        "de": "                if override[\"destino\"]:\n"
              "                    enviar_uazapi_direto(override[\"destino\"], override[\"corpo\"])",
        "para": "                if False:\n"
                "                    enviar_uazapi_direto(override[\"destino\"], override[\"corpo\"])",
    },
    {
        "nome": "M2 -- o aviso de teste some do corpo enviado",
        "pega": "caso 17 -- sem o carimbo, quem le a mensagem no numero de override"
                " acha que e cobranca real (nao sabe que era pro professor X)",
        "de": "    aviso = (\n"
              "        \"⚠️ TESTE DE ROLLOUT (Task 6) — NÃO é cobrança real. \"\n"
              "        f\"Destinatário verdadeiro seria {prof.get('nome') or 'professor desconhecido'} \"\n"
              "        f\"(professor_id {pid}). Mensagem que ele receberia:\\n\\n\"\n"
              "    )\n"
              "    return {\"destino\": destino, \"corpo\": aviso + corpo}",
        "para": "    return {\"destino\": destino, \"corpo\": corpo}",
    },
    {
        "nome": "M3 -- o log do override e removido (silencioso)",
        "pega": "caso 18 -- sem o log, a auditoria do banco nao tem como saber que"
                " o envio foi desviado; ela leria so 'notificacao enviada' e diria"
                " que o PROFESSOR foi avisado quando na verdade foi o destino de teste",
        "de": "                    enviar_uazapi_direto(override[\"destino\"], override[\"corpo\"])\n"
              "                    # Sem este log, a auditoria do banco (fabio_notificacoes)\n"
              "                    # ia dizer que o PROFESSOR foi avisado quando quem\n"
              "                    # recebeu foi o destino do override — a mesma mentira\n"
              "                    # de \"corrigi sozinho\" que abriu esta entrega inteira.\n"
              "                    log(\"experimental_override_ativo\",\n"
              "                        professor_id=pid, vinculo_id=vinculo,\n"
              "                        destino_override=override[\"destino\"],\n"
              "                        destino_original=(\n"
              "                            bridge.canonical_phone(prof.get(\"telefone_whatsapp\") or \"\")\n"
              "                            or f\"professor_id:{pid}\"))",
        "para": "                    enviar_uazapi_direto(override[\"destino\"], override[\"corpo\"])",
    },
    {
        "nome": "M4 -- o log perde o destino ORIGINAL (so diz que houve override)",
        "pega": "caso 18 -- sem o destino original no log, a auditoria nao"
                " distingue 'professor real' de 'destino de teste' -- so sabe"
                " que 'rolou um override', nao pra onde o professor iria",
        "de": "                        destino_original=(\n"
              "                            bridge.canonical_phone(prof.get(\"telefone_whatsapp\") or \"\")\n"
              "                            or f\"professor_id:{pid}\"))",
        "para": "                        destino_original=True)",
    },
    {
        "nome": "M5 -- run_event() nunca desvia (C2: as 2 recobrancas ficam de fora)",
        "pega": "caso 22 -- com a secao experimental no corpo e o override"
                " ligado, run_event() (recobranca noite/manha) TEM que desviar"
                " pro destino configurado tambem, nao so o lembrete imediato",
        "de": "        if contem_secao_experimental(content):\n"
              "            override = resolve_experimental_override(pid, prof, content)\n"
              "        else:\n"
              "            override = {\"destino\": None, \"corpo\": content}",
        "para": "        override = {\"destino\": None, \"corpo\": content}",
    },
    {
        "nome": "M6 -- run_event() desvia SEMPRE, mesmo sem secao experimental"
                " (o override vira mudo geral em vez de trilha experimental)",
        "pega": "caso 20 -- cobranca de aluno PURA (sem secao experimental)"
                " tem que continuar indo pro proprio numero do professor"
                " mesmo com o override ligado",
        "de": "        if contem_secao_experimental(content):\n"
              "            override = resolve_experimental_override(pid, prof, content)\n"
              "        else:\n"
              "            override = {\"destino\": None, \"corpo\": content}",
        "para": "        override = resolve_experimental_override(pid, prof, content)",
    },
]


def _preparar_workdir() -> str:
    workdir = tempfile.mkdtemp(prefix="mutantes_override_experimental_")
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
        # Restaura o alvo copiado (defensivo -- ninguem le mais este workdir
        # depois disto) e apaga o diretorio temporario inteiro. O arquivo do
        # REPO nunca foi tocado: so a copia em `workdir` foi mutada.
        open(alvo_path, "w", encoding="utf-8").write(fonte_original)
        shutil.rmtree(workdir, ignore_errors=True)
    extra = f"  —  {podres} ANCORA(S) PODRE(S)" if podres else ""
    print(f"\n{mortos}/{len(MUTANTES)} mutantes mortos{extra}")
    return 0 if mortos == len(MUTANTES) and not podres else 1


if __name__ == "__main__":
    raise SystemExit(main())
