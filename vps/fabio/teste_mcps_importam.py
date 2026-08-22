#!/usr/bin/env python3
"""Teste da trava de import dos MCPs (fabio_auditoria.mcps_declarados).

POR QUE ELE EXISTE. Em 21/08 o update do Hermes quebrou o gateway com um
ImportError; em 22/08 o MESMO update quebrou o `fabio_presence_mcp.py` — a
dependência `mcp` foi para 2.0.0, que REMOVEU `mcp.server.fastmcp` e renomeou
`FastMCP` -> `MCPServer`. Dois estragos, a mesma causa: **o update troca uma
dependência da venv e um script NOSSO para de importar**.

O que existia só via o PROCESSO ("não aparece no `ps`"), e isso chega tarde e
mal: o processo velho continua vivo em memória com o código antigo, então
enquanto ninguém reinicia o alarme fica MUDO — e quando toca, não diz por quê.
A trava aqui mede o que o `ps` não vê: se o script AINDA IMPORTA no
interpretador que o gateway usa pra subir ele.

Os casos negativos são os que seguram a régua honesta: sem eles,
`mcps_declarados` vira "devolve tudo" e passaria a checar o `postgres-mcp`
(binário de terceiro, não é nosso) e MCPs desligados de propósito.

Rodar:  python3 teste_mcps_importam.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_auditoria import mcps_declarados  # noqa: E402

falhas: list[str] = []
total = 0


def checar(nome: str, esperado, obtido) -> None:
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


# O config REAL do Fábio (recortado): um MCP nosso em python e um binário de
# terceiro. A forma vem de ~/.hermes/config.yaml.
CONFIG_REAL = {
    "mcp_servers": {
        "lareport": {
            "command": "/home/fabio/.local/bin/postgres-mcp",
            "args": ["--access-mode=unrestricted"],
            "env": {"DATABASE_URI": "postgresql://..."},
            "enabled": True,
        },
        "fabio_presence_governance": {
            "command": "/home/fabio/.hermes/hermes-agent/venv/bin/python",
            "args": ["/home/fabio/fabio-chat-bridge/fabio_presence_mcp.py"],
            "env": {"HERMES_HOME": "/home/fabio/.hermes", "FABIO_HOME": "/home/fabio"},
            "enabled": True,
        },
    }
}

achados = mcps_declarados(CONFIG_REAL)

# 1. pega o MCP nosso (script python)
checar("1. acha exatamente 1 MCP nosso no config real", 1, len(achados))
checar("1b. e é o da presença", "fabio_presence_governance",
       achados[0]["nome"] if achados else None)
checar("1c. com o script certo", "/home/fabio/fabio-chat-bridge/fabio_presence_mcp.py",
       achados[0]["script"] if achados else None)
checar("1d. e o interpretador da VENV (é ele que o update troca)",
       "/home/fabio/.hermes/hermes-agent/venv/bin/python",
       achados[0]["interpretador"] if achados else None)

# 2. NEGATIVO: binário de terceiro não é nosso — checar import dele não faz
#    sentido e só geraria alarme falso.
checar("2. ignora o postgres-mcp (binário, não script python)", [],
       [m for m in achados if "postgres" in m["interpretador"]])
# 2b. O caso que DISTINGUE a guarda do interpretador (sem ele, o teste 2 acima
# passa por outro motivo: o postgres-mcp já cai fora por não ter `.py` nos
# args — mutante provou). Wrapper `.sh` que chama um `.py` é forma REAL nesta
# casa: os MCPs da Mila são assim (`lareport-readonly-mcp.sh`). Rodar
# `wrapper.sh -c "import ..."` não importa nada e viraria alarme FALSO.
checar("2b. ignora wrapper .sh mesmo com .py nos args", [], mcps_declarados({"mcp_servers": {
    "x": {"command": "/home/mila/.openclaw/workspace/scripts/lareport-readonly-mcp.sh",
          "args": ["/a/b.py"]}}}))

# 3. NEGATIVO: desligado de propósito não vira alarme.
checar("3. ignora enabled: false", [], mcps_declarados({"mcp_servers": {
    "x": {"command": "/venv/bin/python", "args": ["/a/b.py"], "enabled": False}}}))

# 4. `enabled` ausente = ligado (é o default do Hermes); tratar como desligado
#    esconderia um MCP real.
checar("4. enabled ausente conta como ligado", 1, len(mcps_declarados({"mcp_servers": {
    "x": {"command": "/venv/bin/python", "args": ["/a/b.py"]}}})))

# 5. o env declarado viaja junto: o gateway sobe o MCP COM ele, então o teste
#    tem que subir igual — senão mede um cenário que não existe.
checar("5. leva o env declarado", {"HERMES_HOME": "/home/fabio/.hermes", "FABIO_HOME": "/home/fabio"},
       achados[0]["env"] if achados else None)

# 6. formas degeneradas não podem explodir a auditoria inteira.
checar("6. sem mcp_servers, lista vazia", [], mcps_declarados({}))
checar("6b. mcp_servers nulo, lista vazia", [], mcps_declarados({"mcp_servers": None}))
checar("6c. spec que não é dict é ignorado", [], mcps_declarados({"mcp_servers": {"x": "nada"}}))
checar("6d. python sem nenhum .py nos args é ignorado", [], mcps_declarados({"mcp_servers": {
    "x": {"command": "/venv/bin/python", "args": ["-m", "alguma_coisa"]}}}))

# 7. python3 (não só "python") também conta — a VPS tem os dois nomes.
checar("7. aceita python3 como interpretador", 1, len(mcps_declarados({"mcp_servers": {
    "x": {"command": "/usr/bin/python3", "args": ["/a/b.py"]}}})))


print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  ✗ {f}")
    sys.exit(1)
print("tudo verde ✅")
