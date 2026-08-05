// supabase/functions/notificar-anamnese/index.ts
// Edge Function: prepara resumo + briefing pedagogico (Gemini) e enfileira para Sol/Hermes.
// Body esperado: { anamnese_id: number, dry_run?: boolean }
//
// ─────────────────────────────────────────────────────────────────────────────
// A FRONTEIRA DO DADO DE SAUDE (05/08/2026)
//
// O professor precisa saber COMO APOIAR. Nao precisa saber o NOME do
// diagnostico, nem a condicao medica literal. Essa foi a decisao do Alf
// ("letra B"): conteudo pedagogico + uma linha traduzida sobre necessidade de
// apoio, nunca o rotulo.
//
// O vazamento tinha DUAS fontes, e so uma era obvia:
//
//   1. DETERMINISTICA — `buildEstrutura` imprimia `⚠️ *Diagnostico:* <lista>`
//      literal, antes do briefing. Sempre que houvesse diagnostico, vazava.
//
//   2. PROBABILISTICA — o rotulo e o `cuidado_medico` iam para a IA, e o prompt
//      pedia "foque em adaptacao, nao em rotulos". Medido nas mensagens ja
//      geradas: 1 de 3 briefings repetiu o rotulo do diagnostico e 1 de 4
//      repetiu a condicao medica literal ("Tratamento psiquiatrico de..."),
//      COM a regra escrita no prompt.
//
// Por isso a defesa aqui nao e uma instrucao melhor: e uma VARREDURA
// DETERMINISTICA na saida (`briefingVazou`). O prompt pede a traducao; o codigo
// e quem garante. Se vazar mesmo assim, o briefing e descartado inteiro — o
// professor recebe menos, nunca a mais. Fail closed.
//
// Nada disso foi entregue a ninguem ainda: as 3 mensagens com diagnostico cru
// que existiam estavam todas com status `erro` (o canal WAHA estava morto). O
// canal foi religado em 04/08 pelo Alfredo, e e por isso que isto virou urgente.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
const PUBLIC_BASE_URL = "https://anamnese-la-music.vercel.app";
const QUEUE_TABLE = "fila_anamnese_sol_hermes";
// Normaliza telefone BR para o formato do WhatsApp (DDI 55 + DDD + numero).
// Retorna null se o numero for invalido (ex.: cadastro truncado) — nesse caso NAO envia.
function normalizePhone(raw) {
  const digits = (raw || "").replace(/\D/g, "");
  if (!digits) return null;
  const withDdi = digits.startsWith("55") ? digits : `55${digits}`;
  // 55 + DDD(2) + numero(8 ou 9) => 12 ou 13 digitos
  if (withDdi.length < 12 || withDdi.length > 13) return null;
  return withDdi;
}
// Chave do Gemini lida exclusivamente do secret do Supabase (NUNCA hardcoded no codigo).
// Configurar com: supabase secrets set GEMINI_API_KEY=AIza... --project-ref ouqwbbermlzqqvtqwlul
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = "gemini-3.6-flash";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const SEPARADOR = "━━━━━━━━━━━━━━━━━━━━━";

// Valores que a familia digita quando quer dizer "nao ha nada aqui". O campo e
// texto livre, entao chegam "n", "nao ", "Não " e ate "teste" — todos ja vistos
// em producao. Tratar so "nao"/"não" deixava passar `🔔 Apoio necessario: n`.
const NEGATIVAS = new Set(["", "n", "na", "nao", "não", "no", "nenhum", "nenhuma", "teste", "-", "--"]);
function ehVazioOuNegativo(v) {
  return NEGATIVAS.has(String(v ?? "").trim().toLowerCase().replace(/[.!]+$/, ""));
}

// Termos que NAO podem aparecer no texto que vai pro professor. Sao os dados
// desta anamnese especifica — nao uma lista fixa de doencas, que envelheceria e
// nunca cobriria o que a familia escreveu com as palavras dela.
function termosProibidos(a) {
  const termos = [];
  const push = (v)=>{
    const s = String(v ?? "").trim();
    if (s.length >= 4 && !ehVazioOuNegativo(s)) termos.push(s);
  };
  (Array.isArray(a.diagnosticos) ? a.diagnosticos : []).forEach(push);
  push(a.cuidado_medico);
  push(a.medicacao_continua);
  return termos;
}

function briefingVazou(briefing, termos) {
  const alvo = (briefing || "").toLowerCase();
  for (const t of termos){
    const termo = t.toLowerCase();
    if (alvo.includes(termo)) return t;
    // Texto livre longo ("Tratamento psiquiatrico de depressao e ansiedade")
    // dificilmente reaparece inteiro, mas as palavras clinicas dele sim. Cada
    // palavra com 6+ letras conta: e assim que "psiquiatrico" e "depressao"
    // sao pegos mesmo quando a IA reescreve a frase em volta.
    for (const palavra of termo.split(/\W+/)){
      if (palavra.length >= 6 && alvo.includes(palavra)) return palavra;
    }
  }
  return null;
}

function buildEstrutura(a) {
  const isLamk = a.tipo_formulario === "LAMK";
  const isEmla = a.tipo_formulario === "EMLA";
  const tipoLabel = isLamk ? "LA Music Kids" : "LA Music School";
  let perfilLine;
  if (a.perfil_baby) {
    perfilLine = "Sem perfil ainda — bebê (até 24 meses)";
  } else if (a.temperamento_codinome) {
    perfilLine = `${a.temperamento_codinome} (${a.temperamento_primario} + ${a.temperamento_secundario})`;
  } else {
    perfilLine = "Pendente";
  }
  const arr = (v)=>Array.isArray(v) ? v.filter(Boolean).map(String) : [];
  const possuiLabel = {
    sim: "Sim",
    nao: "Não",
    planejando: "Planejando comprar"
  };
  const out = [
    "📋 *NOVO ALUNO — PERFIL PREENCHIDO*",
    SEPARADOR,
    "",
    `👤 *Aluno:* ${a.nome_aluno || "—"}`,
    `🎸 *Curso:* ${a.cursos_escolhidos || "—"}`,
    `📍 *Unidade:* ${a.unidade?.nome || "—"}`,
    `📝 *Tipo:* ${tipoLabel}`,
    "",
    `🧠 *Temperamento:* ${perfilLine}`
  ];
  if (isEmla) {
    const objs = arr(a.objetivos);
    if (objs.length > 0) {
      out.push("", `🎯 *Objetivos:* ${objs.slice(0, 5).join(", ")}`);
    }
  } else if (isLamk) {
    const motivo = arr(a.motivo_procura_pais);
    if (motivo.length > 0) {
      out.push("", `💡 *Motivo dos pais:* ${motivo.slice(0, 5).join(", ")}`);
    }
    const metas = arr(a.metas_pais);
    if (metas.length > 0) {
      out.push(`🎯 *Metas dos pais:* ${metas.slice(0, 5).join(", ")}`);
    }
  }
  if (a.tempo_disponivel_estudo) {
    out.push(`⏰ *Tempo de estudo:* ${a.tempo_disponivel_estudo}`);
  }
  if (a.possui_instrumento) {
    const k = String(a.possui_instrumento).toLowerCase();
    out.push(`🏠 *Instrumento em casa:* ${possuiLabel[k] || a.possui_instrumento}`);
  }
  if (isEmla) {
    if (a.nivel_conhecimento_musical) {
      out.push("", `🎵 *Nível musical:* ${a.nivel_conhecimento_musical}`);
    }
    if (a.nivel_habilidade_instrumento) {
      out.push(`🎸 *Nível instrumento:* ${a.nivel_habilidade_instrumento}`);
    }
    const generos = arr(a.generos_musicais);
    if (generos.length > 0) {
      out.push(`🎧 *Gêneros:* ${generos.slice(0, 5).join(", ")}`);
    }
  }
  if (isLamk && a.comunicacao_crianca) {
    out.push("", `💬 *Comunicação:* ${a.comunicacao_crianca}`);
  }
  // O bloco `⚠️ *Diagnostico:*` MORAVA AQUI e foi removido de proposito. O que
  // o professor precisa — como apoiar — vem traduzido no briefing, e a
  // coordenacao continua com o dado completo na ficha.
  //
  // `necessidade_apoio` tambem nao vai mais cru: e texto livre da familia, e
  // pode conter o rotulo. Vira sinal para a IA traduzir.
  out.push("", `📝 *Obs:* ${a.observacoes_entrevistador || "Nenhuma"}`);
  return out.join("\n");
}
function calcAgeYears(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  let years = now.getFullYear() - d.getFullYear();
  if (now.getMonth() < d.getMonth() || now.getMonth() === d.getMonth() && now.getDate() < d.getDate()) {
    years--;
  }
  return Math.max(0, years);
}
function sanitizeForAI(a, respostas, idadeAnos) {
  // Remove campos sensiveis antes de enviar pra IA
  const { filiacao: _f, situacao_responsaveis: _s, aluno: _aluno, ...rest } = a;
  return {
    aluno: {
      nome: a.nome_aluno,
      idade_anos: idadeAnos,
      curso: a.cursos_escolhidos,
      unidade: a.unidade?.nome,
      tipo_formulario: a.tipo_formulario
    },
    temperamento: {
      codinome: a.temperamento_codinome,
      primario: a.temperamento_primario,
      secundario: a.temperamento_secundario,
      baby: a.perfil_baby
    },
    musical: {
      possui_instrumento: a.possui_instrumento,
      tempo_disponivel_estudo: a.tempo_disponivel_estudo,
      nivel_conhecimento_musical: a.nivel_conhecimento_musical,
      nivel_habilidade_instrumento: a.nivel_habilidade_instrumento,
      generos_musicais: a.generos_musicais,
      instrumentos_toca: a.instrumentos_toca,
      experiencia_anterior: a.experiencia_anterior,
      interesse_bandas: a.interesse_bandas
    },
    objetivos: {
      objetivos: a.objetivos,
      motivo_procura_pais: a.motivo_procura_pais,
      metas_pais: a.metas_pais,
      tempo_para_metas: a.tempo_para_metas
    },
    ambiente_lamk: a.tipo_formulario === "LAMK" ? {
      comunicacao_crianca: a.comunicacao_crianca,
      sono_crianca: a.sono_crianca,
      exposicao_telas: a.exposicao_telas,
      estereotipias: a.estereotipias,
      musicos_na_familia: a.musicos_na_familia,
      interesse_instrumento_cantar: a.interesse_instrumento_cantar,
      fonte_exposicao_musical: a.fonte_exposicao_musical
    } : undefined,
    // O bloco `saude` continua chegando na IA: sem ele, ela nao tem como
    // TRADUZIR a necessidade de apoio, e a traducao e o produto. O que garante
    // que o rotulo nao volte na saida e o `briefingVazou`, nao esta confianca.
    saude: {
      diagnosticos: a.diagnosticos,
      cuidado_medico: a.cuidado_medico,
      medicacao_continua: a.medicacao_continua,
      necessidade_apoio: a.necessidade_apoio
    },
    observacoes_entrevistador: a.observacoes_entrevistador,
    respostas_comportamentais: respostas
  };
}
async function chamarGemini(prompt) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const r = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      contents: [
        {
          parts: [
            {
              text: prompt
            }
          ]
        }
      ],
      generationConfig: {
        // No Gemini 3.x o RACIOCINIO sai do mesmo orcamento do texto. Com 800 o
        // briefing vinha cortado no meio da frase ("...Ap") e mesmo assim
        // `briefing_ok` dizia true — verde de quem nao mediu. A secao de
        // privacidade deste prompt fez o modelo pensar mais, e 800 deixou de
        // caber. 4096 e o mesmo teto que o extrator de experimentais usa.
        maxOutputTokens: 4096,
        temperature: 0.7
      }
    })
  });
  if (!r.ok) {
    const t = await r.text();
    console.error(`[gemini] HTTP ${r.status}: ${t.slice(0, 300)}`);
    return "";
  }
  const j = await r.json();
  const cand = j?.candidates?.[0];
  const parts = cand?.content?.parts ?? [];
  // Concat all text-bearing parts (Gemini 3 pode incluir thoughtSignature siblings)
  const texto = parts.map((p)=>typeof p?.text === "string" ? p.text : "").join("\n").trim();
  // Resposta cortada nao e resposta. Devolver meio briefing ao professor e pior
  // do que nao devolver: parece completo e nao esta.
  if (cand?.finishReason && cand.finishReason !== "STOP") {
    console.error(`[gemini] finishReason=${cand.finishReason} — descartando (${texto.length} chars, pensamento=${j?.usageMetadata?.thoughtsTokenCount ?? "?"})`);
    return "";
  }
  return texto;
}
async function gerarBriefing(a, respostas, idadeAnos) {
  if (!GEMINI_API_KEY) return { texto: "", vazou: null, tentativas: 0 };
  const isLamk = a.tipo_formulario === "LAMK";
  const dadosLimpos = sanitizeForAI(a, respostas, idadeAnos);
  const temApoio = !ehVazioOuNegativo(a.necessidade_apoio)
    || (Array.isArray(a.diagnosticos) && a.diagnosticos.some((d)=>!ehVazioOuNegativo(d)))
    || !ehVazioOuNegativo(a.cuidado_medico);
  const prompt = `Você é o assistente pedagógico da LA Music, uma rede de escolas de música no Rio de Janeiro.

Com base nos dados da anamnese abaixo, gere um BRIEFING PEDAGÓGICO curto para o professor que vai dar aula pra esse aluno.

O briefing deve:
- Português brasileiro, tom profissional mas acessível
- Formatado para WhatsApp (use *negrito* com asteriscos, NUNCA use markdown # ou **)
- Máximo 10-12 linhas
- Focado em AÇÕES PRÁTICAS pro professor
- Interpretar o temperamento em linguagem simples (o professor não sabe o que é "colérico" — explique como a pessoa SE COMPORTA)
- Dar 2-3 dicas concretas de como conduzir as primeiras aulas

Referência dos temperamentos:
- CAZUZA (Colérico): Determinado, líder, impaciente. Gosta de desafios e resolver sozinho. Pode ser teimoso. Dica: metas claras e desafios progressivos.
- SLASH (Sanguíneo): Extrovertido, empolgado, disperso. Aprende na prática, perde foco. Dica: aulas dinâmicas, variedade, elogie o entusiasmo.
- FRANK (Fleumático): Tranquilo, reservado, observador. Precisa de tempo. Dica: ambiente seguro, sem pressa, respeite o ritmo.
- AMY (Melancólico): Sensível, detalhista, perfeccionista. Se cobra muito. Dica: valorize o processo, feedback gentil.

${isLamk ? "IMPORTANTE: é uma criança (LA Music Kids). Considere comunicação, telas, sono e estereotipias." : "IMPORTANTE: é adolescente/adulto (LA Music School). Considere autonomia, gostos musicais e nivelamento."}

════════════════════════════════════════════════
REGRA DE PRIVACIDADE — A MAIS IMPORTANTE DESTE PROMPT

O bloco "saude" existe para você TRADUZIR, não para repetir. O professor NUNCA
pode ler o nome de um diagnóstico, de uma condição médica ou de um medicamento.
Ele precisa saber o que FAZER na aula.

Está PROIBIDO escrever: nome de diagnóstico ou sigla (TEA, TDAH, TOD, dislexia,
etc.), nome de condição médica ou tratamento, nome de medicamento, e as
palavras "diagnóstico", "laudo", "transtorno", "síndrome" e "medicação".

Em vez disso, escreva a NECESSIDADE em linguagem de sala de aula:
  ✗ "Tem TEA nível 1"           ✓ "Responde melhor a uma rotina previsível: avise antes de mudar de atividade"
  ✗ "Faz tratamento para ansiedade"  ✓ "Pode se cobrar demais; comece por algo que ela já consiga executar bem"
  ✗ "Tem dislexia"              ✓ "Prefira demonstrar e tocar junto a depender de leitura de partitura"

Se o texto da família não deixar claro o que fazer, escreva algo geral e útil
("vale combinar com a coordenação como adaptar") em vez de nomear a condição.
════════════════════════════════════════════════

ESTRUTURA SUGERIDA (use exatamente esse formato, com emojis e *negrito*):
🧠 *Nome, idade — Curso*

*Como ela/ele aprende:* (2-3 linhas, perfil em linguagem prática)

${temApoio ? "🤝 *Como apoiar:* (1-2 linhas — o que FAZER na aula, seguindo a regra de privacidade acima. Nunca o nome da condição.)\n\n" : ""}🎯 *O que esperam:* (resumo do que os pais/aluno querem)

💡 *Primeiras aulas:*
- (dica 1 acionável)
- (dica 2 acionável)
- (dica 3 acionável)

🎵 (frase motivacional curta de 1 linha)

REGRAS:
- NÃO mencionar filiação (adotivo/biológico) nem situação conjugal dos pais
${temApoio ? "- Inclua o bloco 🤝 *Como apoiar*, sempre traduzido em ação" : "- NÃO inclua o bloco 🤝 *Como apoiar*: não há necessidade registrada"}
- Termine com uma frase motivacional curta pro professor

DADOS DO ALUNO (JSON, ignore campos null):
${JSON.stringify(dadosLimpos)}

RESPOSTAS COMPORTAMENTAIS (pergunta_numero, resposta_posicao). Posição: 1=Colérico, 2=Sanguíneo, 3=Fleumático, 4=Melancólico.
${JSON.stringify(respostas)}

Responda APENAS com o briefing formatado, sem introdução ou comentários.`;
  const proibidos = termosProibidos(a);
  try {
    let texto = await chamarGemini(prompt);
    let vazou = briefingVazou(texto, proibidos);
    let tentativas = 1;
    if (vazou) {
      // Uma segunda chance, com o termo exato que ela deixou escapar. Medido em
      // producao: a IA repetia o rotulo em 1 de 3 mesmo com a regra escrita.
      console.error(`[privacidade] briefing vazou "${vazou}" — regerando`);
      texto = await chamarGemini(`${prompt}\n\nATENÇÃO: sua resposta anterior continha "${vazou}", que é PROIBIDO. Reescreva dizendo o que o professor deve FAZER, sem nomear nada.`);
      vazou = briefingVazou(texto, proibidos);
      tentativas = 2;
    }
    if (vazou) {
      // Fail closed: sem briefing é pior do que com briefing, mas vazar dado de
      // saúde de criança é MUITO pior do que os dois.
      console.error(`[privacidade] briefing vazou "${vazou}" de novo — DESCARTADO`);
      return { texto: "", vazou, tentativas };
    }
    return { texto, vazou: null, tentativas };
  } catch (e) {
    console.error("[gemini] exception:", e);
    return { texto: "", vazou: null, tentativas: 0 };
  }
}
function montarMensagemFinal(estrutura, briefing, _token) {
  let msg = estrutura;
  if (briefing) {
    msg += `\n\n${SEPARADOR}\n💡 *INSIGHTS PEDAGÓGICOS*\n${SEPARADOR}\n\n${briefing}\n\n${SEPARADOR}`;
  }
  // O LINK DA FICHA COMPLETA FOI REMOVIDO DAQUI (Alf decidiu em 05/08/2026).
  //
  // Ele apontava para `${PUBLIC_BASE_URL}/perfil/<share_token>`, e a pagina le
  // por `get_anamnese_publica` / `get_anamnese_by_token` — as duas SECURITY
  // DEFINER com EXECUTE para `anon`. Testado com a chave publica e SEM login
  // nenhum: HTTP 200 devolvendo 42 e 49 campos, com `diagnosticos`,
  // `cuidado_medico`, `medicacao_continua` e `necessidade_apoio`.
  //
  // Ou seja: fechar so o texto desta mensagem era meia fronteira. O token
  // viajava dentro dela, e mensagem de WhatsApp e encaminhavel — bastava um
  // repasse para o dado de saude de um menor sair do time pedagogico.
  //
  // O `share_token` continua existindo e a rota autenticada segue servindo a
  // coordenacao. O que mudou e que ele nao vai mais no WhatsApp do professor.
  //
  // ⚠️ Os links JA ENVIADOS continuam valendo: os tokens nao foram rotacionados
  // (rotacionar quebraria a pagina para quem usa legitimamente). Se isso
  // incomodar, a rotacao e uma decisao a parte.
  msg += "\n\n_Informações confidenciais — uso exclusivo do time pedagógico LA Music._";
  msg += "\n_Precisa de mais detalhe sobre esse aluno? Fale com a coordenação._";
  return msg;
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: cors
  });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "method not allowed"
    }), {
      status: 405,
      headers: {
        ...cors,
        "Content-Type": "application/json"
      }
    });
  }
  try {
    const { anamnese_id, dry_run = false } = await req.json();
    if (!anamnese_id) {
      return new Response(JSON.stringify({
        error: "anamnese_id obrigatorio"
      }), {
        status: 400,
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }
    const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const { data: anamnese, error: anaErr } = await supabase.from("anamneses").select(`
          id,
          aluno_id,
          tipo_formulario,
          nome_aluno,
          cursos_escolhidos,
          diagnosticos,
          necessidade_apoio,
          cuidado_medico,
          medicacao_continua,
          comunicacao_crianca,
          sono_crianca,
          exposicao_telas,
          estereotipias,
          musicos_na_familia,
          interesse_instrumento_cantar,
          fonte_exposicao_musical,
          observacoes_entrevistador,
          perfil_baby,
          temperamento_primario,
          temperamento_secundario,
          temperamento_codinome,
          nivel_conhecimento_musical,
          nivel_habilidade_instrumento,
          generos_musicais,
          instrumentos_toca,
          experiencia_anterior,
          interesse_bandas,
          objetivos,
          motivo_procura_pais,
          metas_pais,
          tempo_disponivel_estudo,
          tempo_para_metas,
          possui_instrumento,
          share_token,
          unidade:unidades(id, nome),
          aluno:alunos!aluno_id(
            id,
            nome,
            data_nascimento,
            professor_atual_id,
            professor:professores!professor_atual_id(id, nome, telefone_whatsapp)
          )
        `).eq("id", anamnese_id).single();
    if (anaErr || !anamnese) {
      return new Response(JSON.stringify({
        error: "anamnese nao encontrada",
        details: anaErr?.message
      }), {
        status: 404,
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }
    if (!anamnese.aluno_id) {
      return new Response(JSON.stringify({
        skipped: "pre-matricula sem aluno vinculado"
      }), {
        status: 200,
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }
    const professor = anamnese.aluno?.professor;
    if (!professor) {
      return new Response(JSON.stringify({
        skipped: "aluno sem professor atual"
      }), {
        status: 200,
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }
    // respostas do perfil comportamental (para o prompt da IA)
    const { data: respostas } = await supabase.from("anamnese_respostas_perfil").select("pergunta_numero, resposta_posicao").eq("anamnese_id", anamnese.id).order("pergunta_numero");
    const idadeAnos = calcAgeYears(anamnese.aluno?.data_nascimento);
    const estrutura = buildEstrutura(anamnese);
    const briefingRes = await gerarBriefing(anamnese, respostas || [], idadeAnos);
    const briefing = briefingRes.texto;
    const message = montarMensagemFinal(estrutura, briefing, anamnese.share_token ?? null);

    // Ultima linha de defesa: a mensagem INTEIRA, ja montada, nao pode conter
    // termo proibido. Cobre tambem a estrutura — se um campo novo aparecer no
    // formulario amanha e alguem o imprimir sem pensar, isto acusa antes de o
    // WhatsApp sair.
    const vazamentoFinal = briefingVazou(message, termosProibidos(anamnese));
    if (vazamentoFinal) {
      console.error(`[privacidade] MENSAGEM FINAL vazou "${vazamentoFinal}" — nao enfileira`);
      return new Response(JSON.stringify({
        status: "bloqueado_privacidade",
        motivo: "mensagem final continha termo de saude protegido",
        anamnese_id: anamnese.id,
        professor_id: professor.id
      }), {
        status: 200,
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }

    const telefone = normalizePhone(professor.telefone_whatsapp);
    const jid = telefone ? `${telefone}@s.whatsapp.net` : null;
    if (dry_run) {
      return new Response(JSON.stringify({
        dry_run: true,
        status: telefone ? "would_enqueue" : "sem_whatsapp",
        anamnese_id: anamnese.id,
        professor_id: professor.id,
        professor_telefone: professor.telefone_whatsapp,
        jid,
        briefing_ok: Boolean(briefing),
        briefing_chars: briefing.length,
        briefing_tentativas: briefingRes.tentativas,
        briefing_vazou: briefingRes.vazou,
        message_chars: message.length,
        message_preview: message
      }), {
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }

    if (!telefone || !jid) {
      const erroMsg = professor.telefone_whatsapp ? `telefone invalido: ${professor.telefone_whatsapp}` : null;
      await supabase.from("notificacao_log").insert({
        tipo: "anamnese_professor",
        destinatario_tipo: "professor",
        destinatario_id: professor.id,
        canal: "whatsapp",
        mensagem: message,
        status: "sem_whatsapp",
        erro_mensagem: erroMsg,
        enviado_at: null
      });
      return new Response(JSON.stringify({
        status: "sem_whatsapp",
        professor_id: professor.id,
        professor_telefone: professor.telefone_whatsapp,
        sent_to: null,
        briefing_ok: Boolean(briefing),
        briefing_chars: briefing.length
      }), {
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }

    const { data: existingQueue, error: existingErr } = await supabase
      .from(QUEUE_TABLE)
      .select("id,status,message_id,enviada_em,notificacao_log_id")
      .eq("anamnese_id", anamnese.id)
      .eq("professor_id", professor.id)
      .in("status", [
        "sol_pendente",
        "sol_enviando",
        "enviada"
      ])
      .maybeSingle();
    if (existingErr) throw existingErr;
    if (existingQueue) {
      return new Response(JSON.stringify({
        status: existingQueue.status,
        queued: true,
        duplicate: true,
        queue_id: existingQueue.id,
        notificacao_log_id: existingQueue.notificacao_log_id,
        message_id: existingQueue.message_id,
        enviada_em: existingQueue.enviada_em,
        professor_id: professor.id,
        sent_to: jid,
        briefing_ok: Boolean(briefing),
        briefing_chars: briefing.length
      }), {
        headers: {
          ...cors,
          "Content-Type": "application/json"
        }
      });
    }

    const { data: logRow, error: logErr } = await supabase
      .from("notificacao_log")
      .insert({
        tipo: "anamnese_professor",
        destinatario_tipo: "professor",
        destinatario_id: professor.id,
        canal: "whatsapp",
        mensagem: message,
        status: "pendente",
        erro_mensagem: null,
        enviado_at: null
      })
      .select("id")
      .single();
    if (logErr) throw logErr;

    const { data: queued, error: queueErr } = await supabase
      .from(QUEUE_TABLE)
      .insert({
        anamnese_id: anamnese.id,
        professor_id: professor.id,
        professor_nome: professor.nome,
        telefone_whatsapp: professor.telefone_whatsapp,
        jid,
        mensagem: message,
        status: "sol_pendente",
        agendada_para: new Date().toISOString(),
        notificacao_log_id: logRow.id,
        metadata: {
          aluno_id: anamnese.aluno_id,
          aluno_nome: anamnese.nome_aluno,
          tipo_formulario: anamnese.tipo_formulario,
          unidade_nome: anamnese.unidade?.nome ?? null,
          source: "notificar-anamnese"
        }
      })
      .select("id,status")
      .single();
    if (queueErr) throw queueErr;

    return new Response(JSON.stringify({
      status: queued.status,
      queued: true,
      queue_id: queued.id,
      notificacao_log_id: logRow.id,
      professor_id: professor.id,
      professor_telefone: professor.telefone_whatsapp,
      sent_to: jid,
      briefing_ok: Boolean(briefing),
      briefing_chars: briefing.length
    }), {
      headers: {
        ...cors,
        "Content-Type": "application/json"
      }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: String(e)
    }), {
      status: 500,
      headers: {
        ...cors,
        "Content-Type": "application/json"
      }
    });
  }
});
