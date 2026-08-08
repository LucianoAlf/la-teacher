// Mutantes da 059 — quem já entrou de verdade.
//
// V1 é o defeito real: ler `usuarios.ultimo_acesso`, coluna que ninguém escreve
// (0 de 29 em produção). V2 é a versão "prudente" do mesmo defeito — o coalesce
// que parece defensivo e devolve a mentira sempre que o Auth não tem data.
//
// Os mutantes rodam contra DOIS testes: o da 059 (a verdade do acesso) e o da
// 058 (a ordem por urgência e a guarda de admin). A 059 reescreve a mesma função
// da 058, então uma reescrita desatenta pode derrubar a fila sem que o teste
// novo perceba. Morre se QUALQUER um dos dois acusar.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/059-quem-ja-entrou-de-verdade.sql'
const TESTES = [
  'supabase/migrations/059-quem-ja-entrou-de-verdade.test.sql',
  'supabase/migrations/058-a-fila-do-painel-e-por-urgencia.test.sql',
]
const TEMP = 'supabase/migrations/_mutante-059.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — volta a ler a coluna que ninguem escreve (o defeito da 057)',
    pega: 'passo "quem entrou traz a data do auth"',
    de: `            'ultimo_acesso', au.last_sign_in_at,`,
    para: `            'ultimo_acesso', u.ultimo_acesso,`,
  },
  {
    // O mesmo defeito vestido de cautela: quem nunca logou volta a exibir a
    // data velha. É o mutante que o teste só mata porque a fixture grava
    // valores DIFERENTES nos dois lados.
    nome: 'V2 — coalesce "defensivo" traz a mentira de volta quando o auth e vazio',
    pega: 'passo "liberado que nunca entrou continua vazio"',
    de: `            'ultimo_acesso', au.last_sign_in_at,`,
    para: `            'ultimo_acesso', coalesce(au.last_sign_in_at, u.ultimo_acesso),`,
  },
  {
    // Junção interna: quem ainda não tem acesso desaparece do painel — ou seja,
    // some exatamente quem o painel existe pra liberar.
    nome: 'V3 — a juncao com o auth vira inner e some com quem falta liberar',
    pega: 'passo "a juncao nova nao derrubou ninguem"',
    de: `        left join auth.users     au  on au.id = u.auth_user_id`,
    para: `        join auth.users     au  on au.id = u.auth_user_id`,
  },
  {
    nome: 'V4 — a reescrita derruba a guarda de admin',
    pega: 'passo "professor comum continua sem ver o painel"',
    de: `  if v_perfil is distinct from 'admin' then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;`,
    para: '',
  },
  {
    // Regressão da 058: a fila volta a ser alfabética. Só o teste da 058 pega.
    nome: 'V5 — a reescrita perde a ordem por urgencia (regressao da 058)',
    pega: 'teste da 058, passo "quem tem mais experimental vem primeiro"',
    de: 'order by ja_tem, exp_7d desc, nome',
    para: 'order by ja_tem, nome',
  },
  {
    // Regressão da 057: sem a marca de WhatsApp o botão Liberar fica habilitado
    // pra quem não tem número, e o convite morre calado.
    nome: 'V6 — a reescrita perde a marca de quem tem whatsapp (regressao da 057)',
    pega: 'teste da 058, passo "e o painel continua marcando quem tem whatsapp"',
    de: `            'tem_whatsapp',  (nullif(btrim(coalesce(p.telefone_whatsapp, '')), '') is not null),`,
    para: `            'tem_whatsapp',  false,`,
  },
  {
    nome: 'V7 — a permissao some na reescrita e o painel para pra todo mundo',
    pega: 'ambos os testes (o painel deixa de responder ao authenticated)',
    de: 'grant execute on function public.app_professores_para_liberar() to authenticated;',
    para: 'revoke execute on function public.app_professores_para_liberar() from authenticated;',
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
  // Morre se QUALQUER um dos testes acusar.
  let acusou = null
  for (const teste of TESTES) {
    try {
      execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, teste], { stdio: 'pipe' })
    } catch {
      acusou = teste.replace(/^.*\//, '')
      break
    }
  }
  if (acusou) {
    previstos++
    console.log(`OK     morto por ${acusou}: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
