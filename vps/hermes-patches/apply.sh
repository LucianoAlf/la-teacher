#!/usr/bin/env bash
#
# apply.sh — reaplica o patch do ImportError re-entrante do Hermes
# (agent/conversation_compression.py) DEPOIS de um update do Hermes.
#
# Por que existe: o updater do Hermes faz `git stash --include-untracked ->
# reset --hard origin/main -> stash pop`. Quando a versao nova toca o mesmo
# arquivo, o `pop` conflita e o patch local se perde (visto na Lia, 21/08/2026).
# Este script NAO depende do stash: reaplica a partir do .patch versionado neste
# repo. Idempotente e barulhento no erro.
#
# Uso (UMA VEZ POR AGENTE, logo apos cada update do Hermes):
#   ./apply.sh                    # usa $HOME/.hermes do usuario atual (fabio/mila/lia/...)
#   ./apply.sh /home/mila/.hermes # ou aponte o HERMES_HOME explicitamente
#
# Saidas:
#   0 = ja estava corrigido, ou aplicou e verificou com sucesso
#   2 = ambiente errado (arquivo/patch nao encontrado)
#   3 = FALHA ALTA: o patch nao aplica (a versao nova mudou o arquivo) -> o bug
#       pode ter voltado; NAO confie no registro por audio ate revisar a mao
#   4 = aplicou mas a verificacao falhou (AST/marcador)
set -euo pipefail

HERMES_HOME="${1:-$HOME/.hermes}"
AGENT_DIR="$HERMES_HOME/hermes-agent"
TARGET="$AGENT_DIR/agent/conversation_compression.py"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCRIPT_DIR/conversation_compression-lazy-import.patch"
BUG_LINE='^from agent\.auxiliary_client import AuxiliaryExplicitCancellation'
FIX_MARK='Import lazy (runtime)'

say(){ printf '%s\n' "$*"; }
loud(){
  say "════════════════════════════════════════════════════════════════"
  for l in "$@"; do say "$l"; done
  say "════════════════════════════════════════════════════════════════"
}

# De proposito NAO reinicia nada. O modo de subir o gateway varia por agente e um
# restart cego e PERIGOSO: o Fabio ja rodou o gateway FORA do systemd (com processos
# manuais), e um `systemctl start` num service desatualizado, com processo manual
# vivo, DUPLICA o bot -> erro 409 (mesmo mecanismo que derrubou a Sol em 21/08/2026).
# Quem reinicia e quem sabe como ESTE agente sobe.
avisar_restart(){
  loud "⚠ PATCH no disco — mas o gateway ainda roda o codigo ANTIGO em memoria ate reiniciar." \
       "  Reinicie o gateway DESTE agente do jeito que ele sobe AQUI." \
       "  NAO rode 'systemctl start' as cegas: se o gateway roda manual, voce duplica" \
       "  o processo e derruba o bot (erro 409)."
}

[ -f "$TARGET" ] || { loud "🔴 alvo nao existe: $TARGET" "HERMES_HOME certo? ($HERMES_HOME)"; exit 2; }
[ -f "$PATCH"  ] || { loud "🔴 patch nao encontrado: $PATCH"; exit 2; }

# 1) limpar bytecode velho: o reset --hard pode deixar .pyc dessincronizado do .py
#    (familia da issue upstream #88274, que e sobre .pyc stale — referencia lateral).
find "$AGENT_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
say "• __pycache__ limpo em $AGENT_DIR"

# 2) ja corrigido? (nosso patch OU upstream = sem o import de topo buguado)
if ! grep -qE "$BUG_LINE" "$TARGET"; then
  if grep -q "$FIX_MARK" "$TARGET"; then
    say "✅ Ja corrigido (patch nosso presente). Nada a aplicar."
  else
    loud "✅ Import de topo ausente e SEM nosso marcador — provavelmente corrigido UPSTREAM." \
         "   Se upstream corrigiu de verdade, aposente este patch (ver README)."
  fi
  exit 0
fi

# 3) aplicar (dry-run primeiro; se nao aplicar limpo, GRITA e sai 3)
if ! patch -p1 -d "$AGENT_DIR" --dry-run < "$PATCH" >/dev/null 2>&1; then
  loud "🔴 FALHA ALTA: o patch NAO aplica limpo em:" \
       "   $TARGET" \
       "   A versao nova do Hermes provavelmente mudou conversation_compression.py." \
       "   O ImportError na compressao PODE ESTAR DE VOLTA -> o registro por AUDIO" \
       "   pode quebrar EM SILENCIO. NAO confie no audio ate revisar o patch a mao." \
       "   Ver: vps/hermes-patches/README.md"
  exit 3
fi
patch -p1 -d "$AGENT_DIR" < "$PATCH"
say "• patch aplicado"

# 4) verificar
python3 -c "import ast; ast.parse(open('$TARGET', encoding='utf-8').read())" \
  || { loud "🔴 AST quebrado apos aplicar o patch em $TARGET"; exit 4; }
grep -q "$FIX_MARK" "$TARGET" || { loud "🔴 marcador do fix ausente apos aplicar"; exit 4; }
if grep -qE "$BUG_LINE" "$TARGET"; then loud "🔴 import de topo AINDA presente apos aplicar"; exit 4; fi
say "✅ patch aplicado e verificado ($TARGET)"

avisar_restart
