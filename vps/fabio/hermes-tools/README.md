# Espelho de ferramentas customizadas do Hermes

> **Cópia de auditoria, não fonte de deploy.** Estas ferramentas rodam sob
> `~/.hermes/hermes-agent/tools/` na VPS. O runtime permanece VPS-owned; antes
> de qualquer cópia em qualquer direção, compare o SHA-256 e o diff.

| Ferramenta | Runtime ativo | SHA-256 de paridade inicial |
|---|---|---|
| `fabio_registro_aula_tool.py` | `~/.hermes/hermes-agent/tools/fabio_registro_aula_tool.py` | `c76a3600df7a368c2d9b9a6766e7559dfdaddb035e2c98e79cb167b35efa5e8a` |

A ferramenta acima estava sem rastreamento no checkout Git do Hermes na VPS em
11/08/2026. Este espelho cria uma trilha auditável para a customização sem
alterar o arquivo vivo nem a configuração do gateway.

Para trazer uma atualização, faça primeiro uma cópia da VPS para um arquivo
temporário, confira hash e diff contra este espelho e só então aplique uma
alteração revisada no repositório. Não use este diretório como comando de deploy.
