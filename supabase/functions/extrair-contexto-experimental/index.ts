// Edge Function: extrair-contexto-experimental
//
// Lê a conversa da Mila no Chatwoot, trata com Gemini e grava o contexto
// pedagógico em lead_experimentais.contexto_ia.
//
// EXTRATOR_DRY_RUN=true (default) => extrai e LOGA, mas não grava.
//
// ⚠️ A paginação até o começo da conversa NÃO é detalhe. A API do Chatwoot
// devolve as ~20 mensagens mais recentes, e a qualificação da Mila está sempre
// nas PRIMEIRAS. Quem ler só a última página captura "pode ser quarta?" e perde
// idade, nível, gosto musical e motivação — que é o produto inteiro.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CHATWOOT_URL = Deno.env.get("CHATWOOT_URL") ?? "https://crmchat.agenticflowio.com.br";
const CHATWOOT_ACCOUNT = Deno.env.get("CHATWOOT_ACCOUNT_ID") ?? "5";
const CHATWOOT_TOKEN = Deno.env.get("CHATWOOT_TOKEN") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = "gemini-3.6-flash";
const DRY_RUN = (Deno.env.get("EXTRATOR_DRY_RUN") ?? "true") === "true";

// O Cloudflare na frente do Chatwoot devolve 1010 para User-Agent de script.
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function chatwoot(path: string): Promise<any> {
  const r = await fetch(`${CHATWOOT_URL}/api/v1/accounts/${CHATWOOT_ACCOUNT}${path}`, {
    headers: { api_access_token: CHATWOOT_TOKEN, "User-Agent": UA },
  });
  if (!r.ok) throw new Error(`chatwoot ${path} -> HTTP ${r.status}`);
  return await r.json();
}

/** Só os dígitos finais: o Chatwoot guarda +5521..., o lead guarda 5521... */
function digitos(tel: string): string {
  return (tel || "").replace(/\D/g, "").slice(-8);
}

async function conversaInteira(telefone: string) {
  const busca = await chatwoot(`/contacts/search?q=${encodeURIComponent(digitos(telefone))}`);
  const contato = (busca?.payload ?? [])[0];
  if (!contato) return null;

  const convs = await chatwoot(`/contacts/${contato.id}/conversations`);
  const conversa = (convs?.payload ?? [])[0];
  if (!conversa) return null;

  const tudo: any[] = [];
  let antes: number | null = null;
  for (let i = 0; i < 15; i++) {
    const q = antes ? `?before=${antes}` : "";
    const pagina = await chatwoot(`/conversations/${conversa.id}/messages${q}`);
    const arr: any[] = pagina?.payload ?? [];
    if (!arr.length) break;
    const vistos = new Set(tudo.map((m) => m.id));
    const novos = arr.filter((m) => !vistos.has(m.id));
    if (!novos.length) break;
    tudo.unshift(...novos);
    antes = Math.min(...arr.map((m) => m.id));
  }
  return { contato, conversa, mensagens: tudo };
}

function transcrever(mensagens: any[]): string {
  const linhas: string[] = [];
  for (const m of mensagens) {
    if (m.message_type === 2) continue; // atividade do sistema
    const texto = String(m.content ?? "").replace(/\s+/g, " ").trim();
    if (!texto) continue;
    const bot = String(m.sender?.type ?? "").toLowerCase().includes("bot");
    const quem = m.message_type === 0 ? "FAMILIA" : (bot ? "MILA" : "ESCOLA");
    linhas.push(`${quem}: ${texto.slice(0, 500)}`);
  }
  return linhas.join("\n").slice(0, 24000);
}

const SCHEMA_SAIDA = {
  type: "object",
  properties: {
    recepcao: {
      type: "object",
      properties: {
        responsavel: { type: "string", nullable: true },
        aluno: { type: "string", nullable: true },
        data_nascimento: { type: "string", nullable: true },
        junto_com: { type: "string", nullable: true },
      },
    },
    quem_e_esse_aluno: {
      type: "object",
      properties: {
        nivel_declarado: { type: "string", enum: ["iniciante", "ja_tocava", "nao_informado"] },
        historia: { type: "string", nullable: true },
        de_quem_partiu: { type: "string", enum: ["do aluno", "dos pais", "de terceiro", "nao_informado"] },
      },
    },
    ganchos_de_conexao: { type: "array", items: { type: "string" } },
    para_a_devolutiva: {
      type: "object",
      properties: {
        o_que_a_familia_espera: { type: "string", nullable: true },
        atencao_conversao: { type: "string", enum: ["alta", "normal", "nao_informado"] },
        porque: { type: "string", nullable: true },
      },
    },
    apoio_declarado: { type: "string", nullable: true },
    alertas: {
      type: "array",
      items: {
        type: "object",
        properties: {
          tipo: { type: "string", enum: ["agenda", "saude_agenda", "acessibilidade"] },
          texto: { type: "string" },
        },
        required: ["tipo", "texto"],
      },
    },
  },
  required: ["recepcao", "quem_e_esse_aluno", "ganchos_de_conexao", "para_a_devolutiva", "alertas"],
};

function prompt(transcricao: string, observacoes: string | null, curso: string | null): string {
  return `Você lê a conversa de agendamento de uma aula experimental na LA Music
e prepara o professor que vai dar essa aula.

O professor conduz a aula em cinco momentos: recebe o aluno e o responsável pelo
primeiro nome, faz um aquecimento, cria conexão com o aluno, encerra elogiando, e
dá uma devolutiva ao responsável. Sua saída alimenta esses momentos.

REGRAS QUE NÃO SE NEGOCIAM

1. NUNCA escreva valor de mensalidade, forma de pagamento, desconto, negociação
   ou qualquer menção a dinheiro. Se a família falou de preço, isso só pode
   aparecer como atencao_conversao="alta" com o porquê em UMA frase sem cifra.
2. NUNCA repasse recado operacional interno da escola (ex.: "ajustar data de
   nascimento", "lançamento fictício para concluir cadastro").
3. Motivo de saúde entra APENAS como alerta tipo "saude_agenda" descrevendo o
   efeito na agenda (ex.: "pediu remarcar por motivo de saúde"). Nunca nomeie
   doença nem diagnóstico da criança.
4. apoio_declarado é escrito em linguagem de CONDUÇÃO, não de rótulo. Certo:
   "responde melhor a instrução curta, uma de cada vez; os pais relataram
   suporte nível 1". Errado: "autista nível 1".
5. NÃO calcule nem escreva idade. Devolva data_nascimento no formato AAAA-MM-DD
   quando a família tiver informado. A idade é calculada depois, porque o texto
   envelhece e a data não.
6. O que não foi dito fica null ou "nao_informado". Não invente, não deduza
   personalidade, não preencha por simpatia. Vazio honesto é resposta.

O QUE PROCURAR
- recepcao: primeiro nome do responsável e do aluno, como serão chamados.
- quem_e_esse_aluno: se já tocou antes, a história em uma frase, e de quem
  partiu a vontade (do aluno, dos pais, de terceiro).
- ganchos_de_conexao: 1 a 3 coisas CONCRETAS para o professor puxar na aula —
  o que a criança gosta de ouvir ou cantar, o que já tentou, o que a encanta.
- para_a_devolutiva: o que a família espera ouvir no fim.
- alertas: mudanças de agenda, cancelamentos, restrição de horário.

Curso da experimental: ${curso ?? "não informado"}

Observação que a recepção digitou (pode estar vazia ou desatualizada):
${observacoes ?? "(vazia)"}

Conversa completa:
${transcricao}`;
}

async function extrair(transcricao: string, observacoes: string | null, curso: string | null) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt(transcricao, observacoes, curso) }] }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 1200,
        responseMimeType: "application/json",
        responseSchema: SCHEMA_SAIDA,
      },
    }),
  });
  if (!r.ok) throw new Error(`gemini HTTP ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const j = await r.json();
  const partes: any[] = j?.candidates?.[0]?.content?.parts ?? [];
  const texto = partes.map((p) => (typeof p?.text === "string" ? p.text : "")).join("").trim();
  if (!texto) throw new Error("gemini devolveu vazio");
  return JSON.parse(texto);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const sb = createClient(SUPABASE_URL, SERVICE_KEY);
  let dias = 7, limite = 50;
  try {
    const body = await req.json();
    if (typeof body?.dias === "number") dias = body.dias;
    if (typeof body?.limite === "number") limite = body.limite;
  } catch (_e) { /* body vazio é válido */ }

  const { data: alvos, error } = await sb.rpc("fn_experimentais_a_extrair",
    { p_dias: dias, p_limite: limite });
  if (error) {
    return new Response(JSON.stringify({ erro: error.message }), {
      status: 500, headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let gravados = 0, pulados = 0, erros = 0;
  const detalhes: any[] = [];

  for (const alvo of alvos ?? []) {
    try {
      const conv = await conversaInteira(alvo.telefone);
      if (!conv || !conv.mensagens.length) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sem_conversa" });
        continue;
      }
      const ultimaId = Math.max(...conv.mensagens.map((m: any) => m.id));
      if (alvo.extraido_ate_id && Number(alvo.extraido_ate_id) >= ultimaId) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sem_mensagem_nova" });
        continue;
      }

      const bruto = await extrair(transcrever(conv.mensagens), alvo.observacoes, alvo.curso);
      const contexto = {
        ...bruto,
        procedencia: {
          fonte: "conversa Mila + recepcao",
          contato_id: conv.contato.id,
          conversa_id: conv.conversa.id,
          ultima_mensagem_id: String(ultimaId),
          mensagens_lidas: conv.mensagens.length,
          modelo: GEMINI_MODEL,
          extraido_em: new Date().toISOString(),
        },
      };

      if (DRY_RUN) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sombra", contexto });
      } else {
        const { data: ok } = await sb.rpc("fabio_gravar_contexto_experimental", {
          p_lead_experimental_id: alvo.lead_experimental_id,
          p_contexto: contexto,
        });
        if (ok) { gravados++; detalhes.push({ id: alvo.lead_experimental_id, acao: "gravado" }); }
        else { pulados++; detalhes.push({ id: alvo.lead_experimental_id, acao: "recusado_pela_guarda" }); }
      }
    } catch (e: any) {
      erros++;
      detalhes.push({ id: alvo.lead_experimental_id, acao: "erro", erro: String(e?.message ?? e).slice(0, 300) });
    }
  }

  // Falha silenciosa com HTTP 200 já custou caro duas vezes neste projeto
  // (o Fábio surdo a áudio e a notificar-anamnese com o canal morto desde
  // 11/07). Toda rodada deixa rastro.
  await sb.from("automacao_log").insert({
    evento: "contexto_experimental",
    acao: DRY_RUN ? "extraido_sombra" : "extraido",
    detalhes: { processados: (alvos ?? []).length, gravados, pulados, erros, itens: detalhes },
    workflow_id: "extrair-contexto-experimental",
    execution_id: new Date().toISOString(),
  });

  return new Response(
    JSON.stringify({ dry_run: DRY_RUN, processados: (alvos ?? []).length, gravados, pulados, erros, detalhes }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
