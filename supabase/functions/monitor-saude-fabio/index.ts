// monitor-saude-fabio
// Chamado pelo pg_cron a cada 10 minutos.
// Duas travas de saúde do Fábio, que caem no MESMO WhatsApp de alerta (Luciano):
//   (1) Áudio empacado: gravação presa em 'transcrevendo'/'transcrito' há >30min
//       = turno do gateway do Hermes não terminou (ex: ImportError na compressão).
//   (2) Patch do Hermes: lê hermes_patch_status (escrito pelo guard root que varre
//       todos os agentes) — alerta se algum agente está SEM patch, ou se o próprio
//       guard parou de rodar (status velho = a trava morreu).
// Ver vps/hermes-patches/README.md.
// @ts-nocheck

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Número que recebe o alerta (Luciano) — mesmo do monitor-saude-webhook.
const NUMERO_ALERTA = '5521966583325';

// Se o guard root não reporta há mais que isto, considera que a trava morreu.
const GUARD_STALE_HORAS = 2;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok');

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const problemas: string[] = [];

  // (1) Áudio empacado no gateway
  {
    const trintaMin = new Date(Date.now() - 30 * 60_000).toISOString();
    const umDia = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { data, error } = await supabase
      .from('fabio_fila_audios')
      .select('id, aula_id, criado_em')
      .in('status', ['transcrevendo', 'transcrito'])
      .lt('atualizado_em', trintaMin)
      .gt('criado_em', umDia);
    if (error) {
      problemas.push(`*Áudio (Fábio)*: falha ao checar a fila — ${error.message}`);
    } else if (data && data.length > 0) {
      problemas.push(
        `*Áudio do Fábio empacando*: ${data.length} gravação(ões) presa(s) em ` +
        `'transcrevendo/transcrito' há >30min. Provável: gateway do Hermes crashando ` +
        `(ImportError na compressão). Rodar vps/hermes-patches/apply.sh e reiniciar o gateway.`
      );
    }
  }

  // (2) Patch do Hermes por agente + staleness do próprio guard
  {
    const { data, error } = await supabase
      .from('hermes_patch_status')
      .select('agente, patched, detalhe, checado_em');
    if (error) {
      problemas.push(`*Patch Hermes*: falha ao ler hermes_patch_status — ${error.message}`);
    } else if (!data || data.length === 0) {
      // Tabela vazia = o guard root ainda não foi implantado. Esperado nesse
      // intervalo; NÃO alerta (senão vira spam pré-deploy). A cobertura
      // cross-agente só existe depois que o guard root roda — flag manual.
      console.log('[monitor-saude-fabio] hermes_patch_status vazio (guard root ainda não implantado)');
    } else {
      const semPatch = data.filter((r) => r.patched === false);
      if (semPatch.length > 0) {
        const nomes = semPatch.map((r) => r.agente).join(', ');
        problemas.push(
          `*Patch Hermes AUSENTE* em: ${nomes}. O ImportError da compressão pode ativar ` +
          `no próximo restart desse(s) agente(s). Rodar vps/hermes-patches/apply.sh como o usuário de cada um.`
        );
      }
      const maisNovo = Math.max(...data.map((r) => new Date(r.checado_em).getTime()));
      const horas = (Date.now() - maisNovo) / 3600_000;
      if (horas > GUARD_STALE_HORAS) {
        problemas.push(
          `*Guard do patch parou*: último check há ~${horas.toFixed(1)}h ` +
          `(esperado a cada poucos minutos). A trava estática pode estar morta — ver cron root.`
        );
      }
    }
  }

  // Alerta (mesmo mecanismo do monitor-saude-webhook: caixa admin -> UAZAPI)
  if (problemas.length > 0) {
    const mensagem =
      `🚨 *Alerta de saúde — Fábio / Hermes*\n\n` +
      problemas.join('\n\n') +
      `\n\n_(monitor-saude-fabio, a cada 10min)_`;

    const { data: caixas } = await supabase
      .from('whatsapp_caixas')
      .select('id, numero, uazapi_url, uazapi_token')
      .eq('funcao', 'administrativo')
      .eq('ativo', true)
      .limit(1)
      .single();

    if (caixas?.uazapi_url && caixas?.uazapi_token) {
      await fetch(`${caixas.uazapi_url}/send/text`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', token: caixas.uazapi_token },
        body: JSON.stringify({ phone: NUMERO_ALERTA, message: mensagem }),
      });
      console.log(`[monitor-saude-fabio] Alerta enviado para ${NUMERO_ALERTA}`);
    } else {
      console.error('[monitor-saude-fabio] Sem credenciais UAZAPI para alertar');
    }
  }

  return new Response(
    JSON.stringify({ ok: problemas.length === 0, problemas }),
    { headers: { 'Content-Type': 'application/json' } }
  );
});
