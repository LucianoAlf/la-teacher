#!/usr/bin/env bash
#
# hermes-patch-guard.sh — RODA COMO ROOT (via cron).
#
# Varre TODOS os agentes Hermes do host (/home/*/.hermes/...), checa se o patch do
# ImportError re-entrante (conversation_compression.py) está aplicado, e reporta o
# estado por agente em public.hermes_patch_status. O edge `monitor-saude-fabio`
# (cron a cada 10min) lê essa tabela e alerta no WhatsApp do Luciano se algum
# agente está SEM patch, ou se ESTE guard parou de rodar (status velho).
#
# Por que ROOT: o usuário de um agente (ex: fabio) NÃO lê o ~/.hermes dos outros
# (mila, lia, sol...). Só root cobre os 7 de uma vez — esse é o buraco que o
# apply.sh (por-usuário) não fecha sozinho.
#
# Precisa das credenciais do Supabase no ambiente:
#   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
# (exporte no cron root, ou faça `source` de um arquivo seguro só-do-root).
#
# Cron root sugerido (a cada 15min):
#   */15 * * * * SUPABASE_URL=https://ouqwbbermlzqqvtqwlul.supabase.co \
#     SUPABASE_SERVICE_ROLE_KEY=*** /opt/hermes-patches/hermes-patch-guard.sh >> /var/log/hermes-patch-guard.log 2>&1
set -uo pipefail

: "${SUPABASE_URL:?defina SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?defina SUPABASE_SERVICE_ROLE_KEY}"

PATCH_NOME="conversation_compression-lazy-import"
BUG_LINE='^from agent\.auxiliary_client import AuxiliaryExplicitCancellation'

reportar(){ # $1=agente  $2=patched(true/false)  $3=detalhe
  curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/hermes_patch_status_reportar" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"p_agente\":\"$1\",\"p_patch\":\"$PATCH_NOME\",\"p_patched\":$2,\"p_detalhe\":\"$3\"}" \
    -o /dev/null
}

found=0
for f in /home/*/.hermes/hermes-agent/agent/conversation_compression.py; do
  [ -f "$f" ] || continue
  found=1
  agente="$(printf '%s' "$f" | sed -E 's#^/home/([^/]+)/.*#\1#')"
  if grep -qE "$BUG_LINE" "$f"; then
    reportar "$agente" false "import de topo presente (patch AUSENTE)"
    echo "[$agente] SEM patch — $f"
  else
    reportar "$agente" true "sem import de topo (patch nosso ou upstream)"
    echo "[$agente] patch OK — $f"
  fi
done

[ "$found" = 1 ] || echo "AVISO: nenhum conversation_compression.py em /home/*/.hermes/hermes-agent/agent/"
