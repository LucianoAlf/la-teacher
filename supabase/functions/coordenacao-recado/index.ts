// coordenacao-recado — a coordenação cobra um professor pelo WhatsApp do Fábio.
//
// POR QUE É SÍNCRONO, E NÃO "ENFILEIRA"
// A fila do Fábio (`fabio_notificacoes`) não tem estado de entrada: o `status`
// aceita 'processando', 'enviada', 'falhou' e 'pulada_*' — não existe
// 'pendente'. A linha NASCE no claim do worker. Não há caixa onde depositar um
// recado para alguém levar depois.
//
// E é melhor assim: quem clicou está olhando a tela. Ela merece saber se
// CHEGOU, não que "foi enfileirado" — que é uma promessa sobre o futuro.
//
// RESERVA → ENVIA → CONCLUI
// A ordem existe pra que a colisão seja descoberta ANTES do WhatsApp sair.
// Enviar primeiro e gravar depois deixaria a dedupe inútil: ninguém desentrega
// mensagem. Se o envio falhar, a linha vira 'falhou' com o erro — e não some,
// pra que a segunda tentativa saiba que houve uma primeira.
//
// A COBRANÇA IGNORA SILÊNCIO E DOMINGO, DE PROPÓSITO
// `fn_fabio_pode_notificar` trata categoria 'governanca' com bypass estrutural:
// só férias (`pausa_ate`) barra. Isso é decisão da casa, não descuido — e é por
// isso que aqui não existe estado "fora de horário".

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const auth = req.headers.get('Authorization');
    if (!auth) return json({ ok: false, erro: 'nao_autenticado' }, 401);

    const SB_URL   = Deno.env.get('SUPABASE_URL')!;
    const SB_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const ANON     = Deno.env.get('SUPABASE_ANON_KEY')!;
    const WA_URL   = Deno.env.get('FABIO_UAZAPI_URL') || 'https://lamusic.uazapi.com';
    const WA_TOKEN = Deno.env.get('FABIO_UAZAPI_TOKEN') || '';
    const H = { Authorization: `Bearer ${SB_KEY}`, apikey: SB_KEY, 'Content-Type': 'application/json' };

    // 1. Identidade pelo JWT. A permissão quem confere é o BANCO, duas vezes:
    //    aqui (pra devolver 403 sem escrever nada) e dentro da RPC (que é quem
    //    de fato assina o `solicitado_por`). Perfil guardado no cliente seria
    //    sugestão; a RPC não aceita sugestão.
    const meRes = await fetch(`${SB_URL}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: ANON },
    });
    if (!meRes.ok) return json({ ok: false, erro: 'nao_autenticado' }, 401);
    const me = await meRes.json();

    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ ok: false, erro: 'json_invalido' }, 400); }

    const professorId = Number(body.professor_id);
    if (!Number.isInteger(professorId)) return json({ ok: false, erro: 'professor_id_invalido' }, 400);

    const corpo = String(body.corpo ?? '').trim();
    if (corpo.length < 3) return json({ ok: false, erro: 'recado_vazio' }, 400);

    // 2. Reserva. A RPC confere o autor contra `la_teacher_coordenacao` e
    //    devolve o motivo quando não dá pra mandar — 'ja_cobrado_hoje' inclusive,
    //    que NÃO é erro: é o Fábio já ter cobrado hoje.
    const resRes = await fetch(`${SB_URL}/rest/v1/rpc/fn_reservar_recado_coordenacao`, {
      method: 'POST', headers: H,
      body: JSON.stringify({
        p_professor_id: professorId, p_corpo: corpo, p_solicitado_por: me.id,
      }),
    });

    if (!resRes.ok) {
      const txt = await resRes.text();
      if (txt.includes('apenas_admin')) return json({ ok: false, erro: 'apenas_admin' }, 403);
      if (txt.includes('professor_inexistente')) return json({ ok: false, erro: 'professor_inexistente' }, 404);
      if (txt.includes('professor_inativo')) return json({ ok: false, erro: 'professor_inativo' }, 409);
      if (txt.includes('recado_vazio')) return json({ ok: false, erro: 'recado_vazio' }, 400);
      console.error('[coordenacao-recado] reserva falhou:', resRes.status, txt.slice(0, 300));
      return json({ ok: false, erro: 'nao_consegui_reservar' }, 500);
    }

    const reserva = await resRes.json();
    if (reserva?.reservado !== true) {
      return json({ ok: true, enviado: false, motivo: reserva?.motivo ?? 'desconhecido' });
    }

    // 3. Envia. A partir daqui existe uma linha em 'processando' com o meu
    //    lease — ela PRECISA ser fechada nos dois desfechos, senão fica presa
    //    até o lease vencer e o professor não recebe nem cobrança nem retry.
    let recibo: string | null = null;
    let envioOk = false;
    let erroEnvio = '';

    try {
      const waRes = await fetch(`${WA_URL}/send/text`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', token: WA_TOKEN },
        body: JSON.stringify({ number: reserva.telefone, text: corpo, readchat: true }),
      });
      const waTxt = await waRes.text();
      envioOk = waRes.ok;
      if (waRes.ok) {
        try {
          const wa = JSON.parse(waTxt);
          recibo = String(wa?.id ?? wa?.messageid ?? wa?.key?.id ?? '') || null;
        } catch { recibo = null; }
      } else {
        erroEnvio = `uazapi ${waRes.status}: ${waTxt.slice(0, 300)}`;
        console.error('[coordenacao-recado]', erroEnvio);
      }
    } catch (e) {
      erroEnvio = `uazapi inalcancavel: ${String(e).slice(0, 300)}`;
      console.error('[coordenacao-recado]', erroEnvio);
    }

    // 4. Fecha. O lease prova que quem conclui é quem reservou.
    const fimRes = await fetch(`${SB_URL}/rest/v1/rpc/fn_concluir_recado_coordenacao`, {
      method: 'POST', headers: H,
      body: JSON.stringify({
        p_notificacao_id: reserva.notificacao_id,
        p_lease_token: reserva.lease_token,
        p_ok: envioOk,
        p_recibo: recibo,
        p_erro: erroEnvio || null,
      }),
    });
    if (!fimRes.ok) {
      // Grita alto: a mensagem pode ter saído e o banco não sabe. É o único
      // estado aqui em que o registro e a realidade divergem.
      console.error('[coordenacao-recado] LINHA PRESA em processando:',
        reserva.notificacao_id, fimRes.status, (await fimRes.text()).slice(0, 200));
    }

    return json({
      ok: true,
      enviado: envioOk,
      motivo: envioOk ? null : 'falha_no_envio',
      notificacao_id: reserva.notificacao_id,
    }, envioOk ? 200 : 502);

  } catch (e) {
    console.error('[coordenacao-recado] erro nao tratado:', e);
    return json({ ok: false, erro: 'indisponivel' }, 500);
  }
});
