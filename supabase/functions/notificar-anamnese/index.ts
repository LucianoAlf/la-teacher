// supabase/functions/notificar-anamnese/index.ts
// Edge Function: prepara resumo + briefing pedagogico (Gemini) e enfileira para Sol/Hermes.
// Body esperado: { anamnese_id: number, dry_run?: boolean }
//
// ─────────────────────────────────────────────────────────────────────────────
// O QUE O PROFESSOR RECEBE DE SAUDE (05/08/2026)
//
// A REGRA: o que a familia informou de saude VAI para o professor, e o briefing
// diz o que fazer com isso na aula.
//
// Cheguei aqui pelo caminho errado, e o registro importa mais que o codigo.
//
// De manha eu cortei o bloco de saude inteiro, por privacidade. O Alf reverteu,
// e o argumento derruba o meu: se a familia RELATOU na anamnese, ela espera que
// o professor saiba. O professor descobrir numa conversa com o pai que ninguem
// o avisou e pior por todos os lados — para a crianca, para ele e para a
// escola. E parte disto nem e conducao de aula, e seguranca fisica: no banco ha
// "Anafilaxia a formiga" e "Cardiopata". Esconder isso de quem fica sozinho uma
// hora por semana com a crianca e o oposto de proteger.
//
// O QUE SOBROU DA PASSAGEM CONSERVADORA, e que valia a pena:
//
//   • `sinaisDeSaude` so imprime campo com CONTEUDO. Antes saia
//     `Medicacao: nao / Cuidado medico: nao / Apoio necessario: nao` — tres
//     linhas de nada, no meio das quais a informacao real se perdia.
//   • O briefing nao repete o rotulo: ele diz o que FAZER. O professor ja leu a
//     linha logo acima; repetir nao ajuda ninguem.
//
// O QUE FOI EMBORA, e por que:
//
//   Havia uma varredura deterministica que descartava o briefing se ele citasse
//   o diagnostico. Ela existia porque o prompt sozinho nao segurava — medido:
//   1 de 3 briefings repetia o rotulo mesmo com a proibicao em maiusculas.
//   Com a saude indo na estrutura, nao ha o que varrer: bloquear o briefing por
//   citar o que o professor acabou de ler seria teatro, e descartaria
//   orientacao util ("como ela e cardiopata, evite respiracao intensa").
//
//   O que continua fora nao depende de varredura: `sanitizeForAI` nao manda
//   filiacao nem situacao conjugal dos pais para a IA. Ela nao pode citar o que
//   nunca recebeu — estrutura, nao instrucao.
//
// O link da ficha completa continua fora daqui (ver `montarMensagemFinal`), e
// isso e outra coisa: nao e sobre esconder saude, e sobre nao mandar por
// WhatsApp uma credencial de acesso a ficha inteira.
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

// O que a familia informou de saude, ja limpo do ruido. Devolve [] quando nao
// ha nada — e "nada" inclui os "n", "nao ", "teste" que chegam nesses campos de
// texto livre, e que viravam linhas inuteis tipo `Medicacao: nao`.
function sinaisDeSaude(a) {
  const itens = [];
  const add = (rotulo, v)=>{
    const s = String(v ?? "").trim();
    if (s && !ehVazioOuNegativo(s)) itens.push({ rotulo, valor: s });
  };
  const diags = (Array.isArray(a.diagnosticos) ? a.diagnosticos : [])
    .map((d)=>String(d ?? "").trim())
    .filter((d)=>d && !ehVazioOuNegativo(d));
  if (diags.length) itens.push({ rotulo: "Diagnóstico", valor: diags.join(", ") });
  add("Cuidado médico", a.cuidado_medico);
  add("Medicação contínua", a.medicacao_continua);
  add("Apoio necessário", a.necessidade_apoio);
  return itens;
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
  // SAUDE VAI, SIM — e o Alf corrigiu isto em 05/08/2026, com razao.
  //
  // Eu tinha cortado o bloco inteiro por privacidade. O argumento que derruba
  // isso: se a familia RELATOU na anamnese, ela espera que o professor saiba.
  // O professor descobrir numa conversa com o pai que ninguem o avisou e pior
  // por todos os lados. E parte disto nem e conducao de aula, e seguranca
  // fisica: no banco ha "Anafilaxia a formiga" e "Cardiopata" — esconder de
  // quem fica sozinho uma hora por semana com a crianca e o oposto de
  // proteger.
  //
  // O que continua valendo do conserto anterior e o COMO: nada de despejo de
  // campo vazio. Antes saia `Medicacao: nao / Cuidado medico: nao / Apoio
  // necessario: nao` — tres linhas de nada que faziam a informacao de verdade
  // se perder no meio. `sinaisDeSaude` so devolve o que tem conteudo, e o
  // briefing complementa com o que FAZER na aula.
  const saude = sinaisDeSaude(a);
  if (saude.length) {
    out.push("", "⚠️ *Saúde e necessidades*");
    for (const s of saude) out.push(`• *${s.rotulo}:* ${s.valor}`);
  }
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
    // O bloco `saude` chega na IA para ela dizer o que FAZER com aquilo na
    // aula. O professor ja recebe os dados na estrutura, entao aqui o valor e
    // a orientacao, nao a repeticao.
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
  if (!GEMINI_API_KEY) return { texto: "", tentativas: 0 };
  const isLamk = a.tipo_formulario === "LAMK";
  const dadosLimpos = sanitizeForAI(a, respostas, idadeAnos);
  const temApoio = sinaisDeSaude(a).length > 0;
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
SOBRE O BLOCO "saude" — LEIA COM ATENÇÃO

O professor JÁ RECEBEU, logo acima deste briefing, o que a família informou de
saúde, com as palavras dela. Se a família escreveu que a criança é autista, o
professor leu isso. Você NÃO precisa esconder, e NÃO deve fingir que não sabe.

Seu trabalho aqui é o passo seguinte: dizer o que FAZER na aula. Repetir o
rótulo sozinho não ajuda ninguém — o professor já tem essa linha.

  ✗ inútil:  "Ela tem TEA nível 1."
  ✓ útil:    "Responde melhor a uma rotina previsível: diga no começo o que vão
              fazer e avise antes de trocar de atividade."

  ✗ inútil:  "Faz tratamento para ansiedade."
  ✓ útil:    "Pode se cobrar demais; comece por algo que ela já execute bem e
              feche a aula com uma pequena vitória."

Pode nomear a condição quando isso tornar a orientação mais clara ("como ela é
cardiopata, evite exercícios de respiração muito intensos"). O que não pode é
o briefing virar uma repetição da lista que ele acabou de ler.

Se o que a família escreveu não deixar claro o que fazer, diga isso com
honestidade — "vale combinar com a coordenação como adaptar" — em vez de
inventar uma adaptação que você não tem como saber se serve.
════════════════════════════════════════════════

ESTRUTURA SUGERIDA (use exatamente esse formato, com emojis e *negrito*):
🧠 *Nome, idade — Curso*

*Como ela/ele aprende:* (2-3 linhas, perfil em linguagem prática)

${temApoio ? "🤝 *Como apoiar:* (1-2 linhas — o que FAZER na aula por causa do que a família relatou. Ação, não repetição do rótulo.)\n\n" : ""}🎯 *O que esperam:* (resumo do que os pais/aluno querem)

💡 *Primeiras aulas:*
- (dica 1 acionável)
- (dica 2 acionável)
- (dica 3 acionável)

🎵 (frase motivacional curta de 1 linha)

REGRAS:
- NÃO mencionar filiação (adotivo/biológico) nem situação conjugal dos pais
${temApoio ? "- Inclua o bloco 🤝 *Como apoiar*, sempre em forma de AÇÃO" : "- NÃO inclua o bloco 🤝 *Como apoiar*: não há nada registrado"}
- Termine com uma frase motivacional curta pro professor

DADOS DO ALUNO (JSON, ignore campos null):
${JSON.stringify(dadosLimpos)}

RESPOSTAS COMPORTAMENTAIS (pergunta_numero, resposta_posicao). Posição: 1=Colérico, 2=Sanguíneo, 3=Fleumático, 4=Melancólico.
${JSON.stringify(respostas)}

Responda APENAS com o briefing formatado, sem introdução ou comentários.`;
  // A VARREDURA DE ROTULO SAIU DAQUI, e vale registrar por que ela existiu.
  //
  // Enquanto a regra era "o professor nunca le o nome da condicao", o prompt
  // sozinho nao segurava: medido nas mensagens ja geradas, 1 de 3 briefings
  // repetia o rotulo e 1 de 4 repetia a condicao medica literal, COM a proibicao
  // escrita em maiusculas. Por isso havia uma varredura deterministica que
  // regerava e, na segunda falha, descartava o briefing.
  //
  // Com a saude indo na estrutura por decisao do Alf, nao ha mais o que varrer:
  // o professor ja leu a linha logo acima. Bloquear o briefing por citar o que
  // o proprio professor acabou de ler seria teatro — e pior, descartaria
  // orientacao util ("como ela e cardiopata, evite respiracao intensa").
  //
  // O que continua protegido nao depende de varredura: `sanitizeForAI` nao
  // manda filiacao nem situacao conjugal dos pais para a IA. Ela nao pode citar
  // o que nunca recebeu — estrutura, nao instrucao.
  try {
    const texto = await chamarGemini(prompt);
    return { texto, tentativas: 1 };
  } catch (e) {
    console.error("[gemini] exception:", e);
    return { texto: "", tentativas: 0 };
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
  // "uso exclusivo do time pedagogico" se anulava: o professor E do time
  // pedagogico, entao a frase autorizava justamente quem estava lendo a
  // repassar adiante. "Coordenacao" fecha — o professor recebe porque precisa,
  // nao porque pode distribuir. Correcao do Alf em 05/08/2026.
  msg += "\n\n_Informações confidenciais — uso exclusivo da coordenação da LA Music._";
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
        briefing_saude_itens: sinaisDeSaude(anamnese).length,
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
