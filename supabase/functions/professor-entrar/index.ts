// professor-entrar — o professor entra com o WhatsApp dele e um código.
//
// SEM SENHA, DE PROPÓSITO. O professor já conversa com o Fábio naquele número
// todos os dias; o código chega na mesma conversa. Senha é a primeira coisa que
// 44 pessoas esquecem numa segunda-feira de manhã, e "esqueci minha senha" por
// e-mail não ajuda quem nem sabe qual e-mail a escola cadastrou.
//
// Molde: `send-magic-link` do LA Organizer, que já roda com gente de verdade.
//
// O QUE ESTA FUNÇÃO **NÃO** DECIDE
// Quem pode receber código, e quantos, é o banco quem diz
// (`fn_pedir_codigo_de_acesso`, migration 056). Aqui só tem encanamento:
// perguntar, gerar o OTP, entregar, registrar. Regra que morasse neste arquivo
// não teria como ser testada com mutante.
//
// A RESPOSTA DE RECUSA É SEMPRE A MESMA
// Número desconhecido, professor sem acesso liberado e professor inativo
// devolvem `nao_encontrado`, igualzinho. Distinguir seria entregar a lista de
// quem trabalha na escola pra quem testar número por número.

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
    const SB_URL   = Deno.env.get('SUPABASE_URL')!;
    const SB_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    // Instância do FÁBIO, não a do TOM: a mensagem tem que chegar na conversa
    // que o professor já tem aberta. Código vindo de número estranho parece
    // golpe — e em 2026 o professor está certo de desconfiar.
    const WA_URL   = Deno.env.get('FABIO_UAZAPI_URL') || 'https://lamusic.uazapi.com';
    const WA_TOKEN = Deno.env.get('FABIO_UAZAPI_TOKEN') || '';
    const H = { Authorization: `Bearer ${SB_KEY}`, apikey: SB_KEY, 'Content-Type': 'application/json' };

    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ ok: false, motivo: 'json_invalido' }, 400); }

    const telefone = String(body.telefone ?? '').trim();
    if (!telefone) return json({ ok: false, motivo: 'telefone_invalido' }, 400);

    // 1. O banco decide
    const permRes = await fetch(`${SB_URL}/rest/v1/rpc/fn_pedir_codigo_de_acesso`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify({
        p_telefone:   telefone,
        p_ip_hint:    req.headers.get('x-forwarded-for') ?? '',
        p_user_agent: req.headers.get('user-agent') ?? '',
      }),
    });
    if (!permRes.ok) {
      console.error('[professor-entrar] rpc falhou:', permRes.status, (await permRes.text()).slice(0, 300));
      return json({ ok: false, motivo: 'indisponivel' }, 502);
    }
    const perm = await permRes.json();
    if (!perm?.ok) {
      // 200 de propósito: não é erro do cliente, é resposta. E o status HTTP não
      // pode virar mais um jeito de distinguir "não existe" de "não liberado".
      return json({ ok: false, motivo: perm?.motivo ?? 'nao_encontrado', espere_min: perm?.espere_min });
    }

    const professorId: number = perm.professor_id;
    const destino: string     = perm.telefone;       // o do cadastro
    const primeiroNome: string = perm.primeiro_nome ?? '';
    let email: string          = perm.email ?? '';

    // 2. Sem e-mail cadastrado, um interno e estável. O professor nunca digita
    //    isso: é só a chave que o Supabase Auth exige pra pendurar o OTP.
    if (!email) {
      email = `${destino}@la.internal`;
      await fetch(`${SB_URL}/auth/v1/admin/users`, {
        method: 'POST',
        headers: H,
        body: JSON.stringify({ email, email_confirm: true }),
      });
      // Amarra no usuário do professor pra próxima vez achar direto.
      await fetch(`${SB_URL}/rest/v1/rpc/fn_amarrar_email_do_professor`, {
        method: 'POST', headers: H,
        body: JSON.stringify({ p_professor_id: professorId, p_email: email }),
      });
    }

    // 3. Gera o código
    const glRes = await fetch(`${SB_URL}/auth/v1/admin/generate_link`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify({ type: 'magiclink', email }),
    });
    if (!glRes.ok) {
      console.error('[professor-entrar] generate_link falhou:', glRes.status, (await glRes.text()).slice(0, 300));
      return json({ ok: false, motivo: 'indisponivel' }, 500);
    }
    const gl = await glRes.json();
    const otp: string = gl.email_otp ?? gl.properties?.email_otp;
    if (!otp) {
      console.error('[professor-entrar] email_otp ausente; chaves:', Object.keys(gl).join(','));
      return json({ ok: false, motivo: 'indisponivel' }, 500);
    }

    // 4. Entrega
    const texto =
      `Seu código de acesso ao *LA Teacher* é: *${otp}*\n\n` +
      `Vale por 1 hora. Se não foi você que pediu, é só ignorar.`;
    const waRes = await fetch(`${WA_URL}/send/text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', token: WA_TOKEN },
      body: JSON.stringify({ number: destino, text: texto, readchat: false }),
    });

    // 5. Registra o que aconteceu — inclusive quando não deu
    await fetch(`${SB_URL}/rest/v1/rpc/fn_registrar_codigo_enviado`, {
      method: 'POST', headers: H,
      body: JSON.stringify({
        p_professor_id: professorId,
        p_telefone:     destino,
        p_email:        email,
        p_enviou:       waRes.ok,
        p_ip_hint:      req.headers.get('x-forwarded-for') ?? '',
        p_user_agent:   req.headers.get('user-agent') ?? '',
      }),
    });

    if (!waRes.ok) {
      console.error('[professor-entrar] uazapi falhou:', waRes.status, (await waRes.text()).slice(0, 200));
      return json({ ok: false, motivo: 'nao_consegui_enviar' }, 502);
    }

    return json({
      ok: true,
      email,
      primeiro_nome: primeiroNome,
      telefone_mascarado: destino.slice(0, 4) + '·····' + destino.slice(-2),
    });

  } catch (e) {
    console.error('[professor-entrar] erro nao tratado:', e);
    return json({ ok: false, motivo: 'indisponivel' }, 500);
  }
});
