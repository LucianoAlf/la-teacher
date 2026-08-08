// professor-liberar-acesso — o admin dá acesso a um professor que já existe.
//
// NÃO É "CADASTRAR PESSOA". Os 44 professores já estão no sistema, com aula,
// aluno e agenda. Criar gente nova (como faz o LA Organizer, que parte do zero)
// duplicaria quem já existe e quebraria o vínculo com a agenda. Aqui só se
// forjam os dois elos que faltam: o usuário no Auth e a linha em `usuarios`.
//
// A ORDEM IMPORTA, E A VOLTA TAMBÉM
// Cria no Auth → amarra no banco → convida. Se a amarração falhar, o usuário do
// Auth é APAGADO antes de retornar: usuário órfão no Auth é o tipo de sujeira
// que ninguém vê e que impede a segunda tentativa (o e-mail já existe).
//
// O CONVITE COBRE iPHONE E ANDROID
// O LA Organizer só ensina o caminho do Chrome. Metade da escola usa iPhone, e
// no iPhone o botão é outro, em outro lugar, com outro nome — quem recebe a
// instrução errada conclui que o app não funciona no aparelho dele.

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

const APP_URL = 'https://la-teacher.vercel.app';

function convite(primeiroNome: string): string {
  return (
    `Oi, ${primeiroNome}! Aqui é o *Fábio* 🎧\n\n` +
    `Seu acesso ao *LA Teacher* está liberado — é o app onde você vê sua agenda, ` +
    `registra suas aulas *falando* (sem digitar) e acompanha seus alunos.\n\n` +
    `*1. Abre o link:*\n` +
    `${APP_URL}\n\n` +
    `*2. Entra com este mesmo WhatsApp.* Eu te mando um código aqui na hora.\n\n` +
    `*3. Instala na tela do celular* (fica com cara de app):\n\n` +
    `📱 *Android:* toca nos 3 pontinhos (⋮) do Chrome → _Adicionar à tela inicial_\n\n` +
    `🍎 *iPhone:* precisa ser no *Safari*. Toca no quadradinho com a seta pra cima ` +
    `(embaixo, no meio) → _Adicionar à Tela de Início_\n\n` +
    `Qualquer dúvida é só me chamar aqui. 😉`
  );
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

    // 1. Quem está chamando? Identidade pelo JWT, perfil pelo banco.
    const meRes = await fetch(`${SB_URL}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: ANON },
    });
    if (!meRes.ok) return json({ ok: false, erro: 'nao_autenticado' }, 401);
    const me = await meRes.json();

    const perfRes = await fetch(
      `${SB_URL}/rest/v1/usuarios?auth_user_id=eq.${me.id}&select=perfil,ativo&limit=1`,
      { headers: H },
    );
    const perfis = perfRes.ok ? await perfRes.json() : [];
    if (!perfis[0]?.ativo || perfis[0]?.perfil !== 'admin') {
      return json({ ok: false, erro: 'apenas_admin' }, 403);
    }

    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ ok: false, erro: 'json_invalido' }, 400); }

    const professorId = Number(body.professor_id);
    if (!Number.isInteger(professorId)) return json({ ok: false, erro: 'professor_id_invalido' }, 400);

    // 2. Já liberado? Pergunta antes de criar nada no Auth — criar e depois
    //    descobrir que não precisava deixaria um usuário órfão pra trás.
    const jaRes = await fetch(
      `${SB_URL}/rest/v1/professores?id=eq.${professorId}&select=id,nome,nome_preferido,telefone_whatsapp,usuario_id,ativo&limit=1`,
      { headers: H },
    );
    const profs = jaRes.ok ? await jaRes.json() : [];
    const prof = profs[0];
    if (!prof) return json({ ok: false, erro: 'professor_inexistente' }, 404);
    if (!prof.ativo) return json({ ok: false, erro: 'professor_inativo' }, 409);
    if (!prof.telefone_whatsapp) return json({ ok: false, erro: 'professor_sem_whatsapp' }, 409);

    const telefone: string = String(prof.telefone_whatsapp).replace(/\D/g, '');
    const primeiroNome: string =
      (prof.nome_preferido ?? '').trim() || String(prof.nome).trim().split(' ')[0];

    let usuarioId: number | null = prof.usuario_id ?? null;
    let jaEstava = usuarioId !== null;

    if (!jaEstava) {
      // 3. Usuário no Auth. E-mail interno e estável — o professor nunca digita
      //    isso, entra pelo WhatsApp.
      const email = `${telefone}@la.internal`;
      const novoRes = await fetch(`${SB_URL}/auth/v1/admin/users`, {
        method: 'POST',
        headers: H,
        body: JSON.stringify({
          email, email_confirm: true, user_metadata: { nome: prof.nome, professor_id: professorId },
        }),
      });
      const novo = await novoRes.json();
      if (!novoRes.ok || !novo?.id) {
        console.error('[professor-liberar-acesso] createUser falhou:', novoRes.status, JSON.stringify(novo).slice(0, 300));
        return json({ ok: false, erro: 'auth_falhou' }, 502);
      }

      // 4. Amarra. Se falhar, DESFAZ o usuário do Auth.
      const ligaRes = await fetch(`${SB_URL}/rest/v1/rpc/fn_liberar_acesso_professor`, {
        method: 'POST', headers: H,
        body: JSON.stringify({ p_professor_id: professorId, p_auth_user_id: novo.id, p_email: email }),
      });
      if (!ligaRes.ok) {
        const txt = await ligaRes.text();
        console.error('[professor-liberar-acesso] amarração falhou:', ligaRes.status, txt.slice(0, 300));
        const desfez = await fetch(`${SB_URL}/auth/v1/admin/users/${novo.id}`, { method: 'DELETE', headers: H });
        if (!desfez.ok) {
          // Grita: sem isto o e-mail fica ocupado e a segunda tentativa falha
          // com "já existe", sem que ninguém entenda por quê.
          console.error('[professor-liberar-acesso] ÓRFÃO no Auth:', novo.id);
        }
        return json({ ok: false, erro: 'nao_consegui_amarrar' }, 500);
      }
      const liga = await ligaRes.json();
      usuarioId = liga?.usuario_id ?? null;
      jaEstava = liga?.ja_liberado === true;
    }

    // 5. Convite. Vai mesmo quando já estava liberado — reenviar convite é o
    //    caso de uso mais comum depois de "perdi a mensagem".
    const waRes = await fetch(`${WA_URL}/send/text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', token: WA_TOKEN },
      body: JSON.stringify({ number: telefone, text: convite(primeiroNome), readchat: true }),
    });
    if (!waRes.ok) {
      console.error('[professor-liberar-acesso] uazapi falhou:', waRes.status, (await waRes.text()).slice(0, 200));
    }

    return json({
      ok: true,
      professor_id: professorId,
      usuario_id: usuarioId,
      ja_estava_liberado: jaEstava,
      // O admin precisa saber se a mensagem saiu — "liberado" sem convite é
      // acesso que a pessoa não sabe que tem.
      convite_enviado: waRes.ok,
    });

  } catch (e) {
    console.error('[professor-liberar-acesso] erro nao tratado:', e);
    return json({ ok: false, erro: 'indisponivel' }, 500);
  }
});
