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
    // A dica que o professor lê minutos antes de entrar na sala. Nullable de
    // propósito: conversa que só falou de preço e horário não vira conduta, e
    // vazio honesto continua sendo resposta.
    como_conduzir: { type: "string", nullable: true },
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

function prompt(
  transcricao: string,
  observacoes: string | null,
  curso: string | null,
  nomeAluno: string | null,
): string {
  return `Você lê a conversa de agendamento de uma aula experimental na LA Music
e prepara o professor que vai dar essa aula.

O professor conduz a aula em cinco momentos: recebe o aluno e o responsável pelo
primeiro nome, faz um aquecimento, cria conexão com o aluno, encerra elogiando, e
dá uma devolutiva ao responsável. Sua saída alimenta esses momentos.

REGRAS QUE NÃO SE NEGOCIAM

1. NUNCA escreva valor de mensalidade, forma de pagamento, desconto, negociação
   ou qualquer menção a dinheiro em nenhum campo.

   atencao_conversao="alta" é ALERTA, e alerta que toca sempre ninguém escuta.
   Perguntar preço é o que TODA família faz, inclusive quem matricula na hora —
   isso é "normal". "alta" pede hesitação ou objeção DECLARADA: falar que não
   sabe se consegue manter, comparar com outra escola, pedir desconto, dizer que
   vai pensar por causa do custo, sumir depois de saber o valor.
   Na dúvida entre "alta" e "normal", escolha "normal".
   O campo porque explica em UMA frase, sem cifra e sem condição de pagamento.
2. NUNCA repasse recado operacional interno da escola (ex.: "ajustar data de
   nascimento", "lançamento fictício para concluir cadastro").
3. Motivo de saúde entra APENAS como alerta tipo "saude_agenda" descrevendo o
   efeito na agenda (ex.: "pediu remarcar por motivo de saúde"). Nunca nomeie
   doença nem diagnóstico da criança.
4. apoio_declarado é escrito em linguagem de CONDUÇÃO, não de rótulo. Certo:
   "responde melhor a instrução curta, uma de cada vez; os pais relataram
   suporte nível 1". Errado: "autista nível 1".
5. NÃO calcule nem escreva idade em NENHUM campo — nem em historia, nem nos
   ganchos, nem nos alertas. So data_nascimento, no formato AAAA-MM-DD, e só
   se a família tiver informado.

   Idade em texto congela: "bebê de 11 meses" continua dizendo 11 meses no ano
   que vem, e na metodologia da casa a faixa etária muda o que se faz na aula —
   um bebê muda de faixa aos 12 meses. A data acompanha, o texto mente.
   Errado: "Bebê de 11 meses que fica na creche". Certo: "Fica na creche das 10h
   às 17h" (a idade sai da data, depois).
   A unica excecao e junto_com, onde a idade do IRMÃO ajuda o professor a
   entender a sequência de aulas.
6. O que não foi dito fica null ou "nao_informado". Não invente, não deduza
   personalidade, não preencha por simpatia. Vazio honesto é resposta.

O QUE PROCURAR
- recepcao: primeiro nome do responsável e do aluno, como serão chamados.
- quem_e_esse_aluno: se já tocou antes, a história em uma frase, e de quem
  partiu a vontade (do aluno, dos pais, de terceiro).
- ganchos_de_conexao: 1 a 3 coisas CONCRETAS para o professor puxar na aula —
  o que a criança gosta de ouvir ou cantar, o que já tentou, o que a encanta.
- como_conduzir: UMA sugestão de condução, no máximo 2 frases, escrita para o
  professor ler minutos antes de entrar na sala. Parta do que a conversa
  REVELOU sobre esse aluno e diga o que FAZER com isso. Não repita o gancho —
  use ele.
  Errado: "Ela gosta de pop internacional." (isso é gancho, tem campo próprio)
  Certo: "Comece deixando ela escolher a música: a mãe contou que ela trava
  quando tem gente olhando."
  NUNCA cite preço, mensalidade, matrícula, decisão de compra nem o interesse
  comercial da família. Este campo vai para quem vai DAR a aula, e a aula dele
  não é venda. Se a conversa só tratou de valor e horário, devolva null — uma
  dica inventada é pior que nenhuma, porque o professor confia nela.
- para_a_devolutiva: o que a família espera ouvir no fim.
- alertas: mudanças de agenda, cancelamentos, restrição de horário.

ESTA EXTRAÇÃO É SOBRE UM ALUNO SÓ: ${nomeAluno ?? "(nome não informado)"}

Uma mesma conversa pode agendar aula para mais de um filho — irmãos entram na
mesma conversa e cada um tem a sua aula. Extraia APENAS o que é desse aluno.
Se a conversa citar outros, não misture: recepcao.aluno recebe só o nome
acima, e data_nascimento só a data dele. Os irmãos entram em junto_com
("irmão Pedro, 9 anos, na aula seguinte"), nunca o responsável — o responsável
tem campo próprio.

Curso da experimental: ${curso ?? "não informado"}

Observação que a recepção digitou (pode estar vazia ou desatualizada):
${observacoes ?? "(vazia)"}

Conversa completa:
${transcricao}`;
}

async function extrair(transcricao: string, observacoes: string | null, curso: string | null, nomeAluno: string | null) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt(transcricao, observacoes, curso, nomeAluno) }] }],
      generationConfig: {
        temperature: 0.2,
        // O thinking dos modelos 3.x sai do MESMO orçamento da resposta. Com
        // maxOutputTokens 1200 a primeira rodada real gastou 1153 em pensamento
        // e sobraram 32 para o JSON: finishReason=MAX_TOKENS e a saída cortada
        // no meio de uma string. Não é resposta malformada, é resposta abortada.
        //
        // `thinkingConfig: {thinkingBudget: 0}` seria o corte limpo, mas este
        // modelo devolve 400 "invalid argument" — não dá para desligar. Então o
        // caminho é orçamento que caiba nos dois: ~1200 de pensamento medidos na
        // rodada real, mais folga para o JSON de uma conversa de 56 mensagens.
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
        responseSchema: SCHEMA_SAIDA,
      },
    }),
  });
  if (!r.ok) throw new Error(`gemini HTTP ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const j = await r.json();
  const cand = j?.candidates?.[0];
  const partes: any[] = cand?.content?.parts ?? [];
  const texto = partes.map((p) => (typeof p?.text === "string" ? p.text : "")).join("").trim();
  if (!texto) throw new Error(`gemini devolveu vazio (finishReason=${cand?.finishReason})`);
  try {
    return JSON.parse(texto);
  } catch (e) {
    // "Unterminated string" quer dizer resposta CORTADA, não malformada. A causa
    // provável nos modelos 3.x é o thinking consumir o orçamento de saída antes
    // de o JSON terminar. Sem finishReason e sem contagem de tokens no erro, a
    // gente fica adivinhando — então o erro carrega as duas coisas.
    const u = j?.usageMetadata ?? {};
    throw new Error(
      `gemini JSON invalido (${String((e as Error).message).slice(0, 60)}) ` +
      `finishReason=${cand?.finishReason} ` +
      `tokens=prompt:${u.promptTokenCount}/saida:${u.candidatesTokenCount}/pensamento:${u.thoughtsTokenCount ?? 0} ` +
      `fim_do_texto=${JSON.stringify(texto.slice(-80))}`,
    );
  }
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

      const bruto = await extrair(transcrever(conv.mensagens), alvo.observacoes, alvo.curso, alvo.nome_aluno);
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
  // `aluno_nome` é NOT NULL sem default nesta tabela — o insert sem ela falha, e
  // como o retorno não era checado, a rodada inteira ficava sem rastro em
  // silêncio. Que é exatamente o defeito que este log existe para evitar.
  // O log é por RODADA, não por aluno, então o rótulo diz isso.
  const { error: erroLog } = await sb.from("automacao_log").insert({
    evento: "contexto_experimental",
    acao: DRY_RUN ? "extraido_sombra" : "extraido",
    aluno_nome: `(rodada: ${(alvos ?? []).length} experimentais)`,
    detalhes: { processados: (alvos ?? []).length, gravados, pulados, erros, itens: detalhes },
    workflow_id: "extrair-contexto-experimental",
    execution_id: new Date().toISOString(),
  });
  if (erroLog) {
    console.error("[extrator] FALHA AO GRAVAR O RASTRO:", erroLog.message);
  }

  return new Response(
    JSON.stringify({ dry_run: DRY_RUN, processados: (alvos ?? []).length, gravados, pulados, erros, detalhes }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
