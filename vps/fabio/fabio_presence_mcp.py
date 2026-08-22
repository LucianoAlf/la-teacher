#!/usr/bin/env python3
"""MCP read-only tools for Fabio presence governance."""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict

try:
    from mcp.server.fastmcp import FastMCP  # mcp 1.x
except ModuleNotFoundError:  # mcp 2.x: FastMCP virou MCPServer
    from mcp.server import MCPServer as FastMCP

BRIDGE_DIR = Path(__file__).resolve().parent
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

import fabio_presence_governance as gov  # noqa: E402

mcp = FastMCP(
    "fabio-presence-governance",
    instructions=(
        "Ferramentas read-only para governança de presença do Fábio. "
        "Não escrevem no banco e não enviam WhatsApp. Use preview-first."
    ),
)


@mcp.tool(
    name="fabio_buscar_presencas_pendentes_professor",
    description=(
        "Consulta read-only a RPC public.fabio_presencas_pendentes_professor(p_professor_id int). "
        "Retorna jsonb com dentro_janela (dias <= 3, detalhado por aula/alunos) e "
        "escalar_coordenacao (dias > 3, resumo por aula). Não escreve nada."
    ),
)
def fabio_buscar_presencas_pendentes_professor(professor_id: int) -> Dict[str, Any]:
    gov._init_env()
    return gov.fabio_buscar_presencas_pendentes_professor(int(professor_id))


@mcp.tool(
    name="fabio_preview_governanca_presenca_professor",
    description=(
        "Gera preview-first, sem envio, da DM do professor e do resumo de escala da coordenação "
        "para um professor específico. Usa presença pendente + registro pendente read-only."
    ),
)
def fabio_preview_governanca_presenca_professor(professor_id: int) -> Dict[str, Any]:
    gov._init_env()
    preview = gov.gerar_preview([int(professor_id)], limit=1)
    return preview


if __name__ == "__main__":
    mcp.run("stdio")
