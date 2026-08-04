#!/usr/bin/env python3
"""Conversa com o Fábio em OFF — mesmo caminho da mensagem real, sem WhatsApp.

POR QUE ISSO EXISTE
Em 04/08/2026 eu consertei o bloco `cadastro` do prontuário, provei que o dado
certo chegava no prompt, e reportei como resolvido. O Alf mandou testar
conversando: eu tinha validado o que ENTRA, não o que SAI. A resposta do Fábio
é o produto — o contexto é só insumo.

Regra que ficou: mexeu no Fábio, pergunta pra ele antes de dizer que está
pronto. Se a resposta não serve pro professor, não está pronto.

COMO USA
    ssh ... 'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && \
      python3 falar_com_fabio.py "quem é a aluna Fernanda?"'

    --professor-id N   (padrão 25, Matheus — o único do piloto com login)
    --admin            fala como Alf em vez de professor
    --sem-historico    ignora a conversa recente; use pra saber se ele acerta
                       sozinho ou se está lendo a resposta do briefing anterior

O QUE ELE FAZ E NÃO FAZ
Chama generate_answer(), que é exatamente o que a fila chama: mesmo
build_prompt, mesmo prefetch, mesmo histórico real, mesmo modelo. NÃO chama
_send_row_whatsapp — nada sai pro telefone de ninguém. Também não grava a
pergunta na fabio_chat_mensagens, então o teste não polui o histórico do
professor nem vira contexto da próxima resposta de verdade.
"""
import argparse
import sys
import time

import fabio_chat_bridge as B


def main() -> int:
    p = argparse.ArgumentParser(description="Pergunta ao Fábio sem enviar WhatsApp.")
    p.add_argument("pergunta", help="o que o professor perguntaria")
    p.add_argument("--professor-id", type=int, default=25)
    p.add_argument("--usuario-id", type=int, default=None, help="obrigatório com --admin")
    p.add_argument("--admin", action="store_true", help="fala como Alf (identidade admin)")
    p.add_argument("--sem-historico", action="store_true")
    p.add_argument("--mostrar-prompt", action="store_true", help="imprime o prompt inteiro")
    args = p.parse_args()

    if args.admin and not args.usuario_id:
        print("erro: --admin exige --usuario-id", file=sys.stderr)
        return 2

    row = {
        "identidade_tipo": "admin" if args.admin else "professor",
        "professor_id": args.professor_id,
        "usuario_id": args.usuario_id,
        "channel": "whatsapp",
        "content": args.pergunta,
    }

    if args.sem_historico:
        B.recent_history_for_row = lambda r, limit=10: []

    # O prefetch é o insumo; imprimir junto mostra se uma resposta ruim veio de
    # dado que faltou ou de dado que chegou e ele não usou. São consertos
    # diferentes e é fácil confundir os dois.
    if not args.admin:
        try:
            ctx = B.pedagogical_prefetch(args.professor_id, args.pergunta,
                                         B.recent_history_for_row(row, 12))
            cad = (ctx or {}).get("cadastro") or {}
            if ctx:
                print(f"[prefetch] intent={ctx.get('intent')} "
                      f"aluno={(ctx.get('resolved') or {}).get('aluno_nome')} "
                      f"cadastro={'sim' if cad else 'nao'}"
                      + (f" novo={cad.get('e_aluno_novo')} dias={cad.get('dias_desde_matricula')}"
                         if cad else ""))
            else:
                print("[prefetch] nao acionado")
        except Exception as e:
            print(f"[prefetch] erro: {e}")

    if args.mostrar_prompt:
        print("\n--- PROMPT ---")
        print(B.build_prompt(row))
        print("--- FIM DO PROMPT ---")

    print(f"\n> professor: {args.pergunta}\n")
    t0 = time.time()
    try:
        resposta, origem = B.generate_answer(row)
    except Exception as e:
        print(f"ERRO ao gerar resposta: {e}", file=sys.stderr)
        return 1
    print(f"> Fábio ({origem}, {time.time() - t0:.1f}s):\n")
    print(resposta)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
