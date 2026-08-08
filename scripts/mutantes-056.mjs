// Mutantes da 056 — o código de acesso do professor.
//
// Z3 é o que eu mais quero morto e o que menos parece defeito: se "não liberado"
// e "número desconhecido" derem respostas DIFERENTES, qualquer pessoa descobre
// quem trabalha na escola testando número por número. O caminho feliz continua
// funcionando, os testes continuam verdes, e a porta fica aberta.
//
// Z1 é o silencioso: sem as variantes, o professor que digita o número sem o 55
// recebe "não consegui enviar" — e todo mundo vai procurar defeito no WhatsApp.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/056-codigo-de-acesso-do-professor.sql'
const TESTE = 'supabase/migrations/056-codigo-de-acesso-do-professor.test.sql'
const TEMP = 'supabase/migrations/_mutante-056.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'Z1 — a busca volta a exigir o número exato do cadastro',
    pega: 'passo "as quatro formas do mesmo numero acham a mesma pessoa"',
    de: "     and regexp_replace(coalesce(p.telefone_whatsapp, ''), '\\D', '', 'g') = any (v_variantes)",
    para: "     and regexp_replace(coalesce(p.telefone_whatsapp, ''), '\\D', '', 'g') = v_digitos",
  },
  {
    // Variante do 9 do celular: é a que pega quem foi cadastrado no padrão
    // antigo (DDD + 8 dígitos).
    nome: 'Z2 — as variantes esquecem o 9 do celular',
    pega: 'passo "a variante com 55 e com 9 gera as quatro formas"',
    de: `  if length(local) = 11 and substr(local, 3, 1) = '9' then
    saida := saida || (left(local, 2) || substr(local, 4));
    saida := saida || ('55' || left(local, 2) || substr(local, 4));`,
    para: `  if false then
    saida := saida || (left(local, 2) || substr(local, 4));
    saida := saida || ('55' || left(local, 2) || substr(local, 4));`,
  },
  {
    // A resposta que entrega a lista de funcionários, um número por vez.
    nome: 'Z3 — "não liberado" passa a ser distinguível de "não existe"',
    pega: 'passo "professor nao liberado responde IGUAL a numero desconhecido"',
    de: `  if v_prof.usuario_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'nao_encontrado');
  end if;`,
    para: `  if v_prof.usuario_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_acesso_liberado');
  end if;`,
  },
  {
    nome: 'Z4 — professor inativo consegue código',
    pega: 'passo "professor inativo tambem nao entra"',
    de: '   where p.ativo\n',
    para: '   where true\n',
  },
  {
    nome: 'Z5 — o limite de 3 em 15 minutos some',
    pega: 'passo "o quarto pedido em 15min e barrado"',
    de: '  if v_recentes >= 3 then',
    para: '  if v_recentes >= 999 then',
  },
  {
    // Janela infinita: quem pediu 3 códigos no mês passado nunca mais entra.
    nome: 'Z6 — a janela do limite deixa de ser janela',
    pega: 'passo "envio de uma hora atras nao conta pro limite"',
    de: "     and c.criado_em > now() - interval '15 minutes'",
    para: "     and c.criado_em > now() - interval '30 days'",
  },
  {
    // Devolver o número digitado em vez do cadastrado: o UAZAPI pode não
    // entregar na variante sem o 55, e a mensagem some sem erro.
    nome: 'Z7 — devolve o telefone digitado em vez do cadastrado',
    pega: 'passo "devolve o telefone do cadastro, nao o digitado"',
    de: "    'telefone',      v_prof.telefone_whatsapp,   -- o do CADASTRO, não o digitado",
    para: "    'telefone',      v_digitos,",
  },
  {
    nome: 'Z8 — o rastro do envio nasce sem validade',
    pega: 'passo "registrar envio deixa rastro com validade"',
    de: "          p_ip_hint, p_user_agent, now() + interval '1 hour')",
    para: '          p_ip_hint, p_user_agent, null)',
  },
  {
    // GRANT ativo: `create or replace function` preserva privilégio, então só
    // omitir o revoke viraria no-op depois de aplicada.
    nome: 'Z9 — qualquer autenticado pede código pra qualquer número',
    pega: 'passo "autenticado nao pede codigo pra ninguem"',
    de: 'revoke all on function public.fn_pedir_codigo_de_acesso(text, text, text) from public, anon, authenticated;',
    para: 'grant execute on function public.fn_pedir_codigo_de_acesso(text, text, text) to authenticated;',
  },
  {
    nome: 'Z10 — a tabela de códigos fica legível pelo app',
    pega: 'passo "e nao le a tabela de codigos"',
    de: 'revoke all on table public.professor_acesso_codigos from public, anon, authenticated;',
    para: 'grant select on table public.professor_acesso_codigos to authenticated;',
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
    console.log(`       procurava: ${JSON.stringify(m.de.slice(0, 90))}`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    previstos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
