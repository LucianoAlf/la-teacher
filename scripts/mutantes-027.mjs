import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/027-contexto-experimental.sql'
const TESTE = 'supabase/migrations/027-contexto-experimental.test.sql'
const TEMP = 'supabase/migrations/_mutante-027.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'extracao vazia sobrescreve extracao boa (fail open)',
    pega: 'passos 7 e 8',
    de: '  if not v_tem_algo then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'leitura mais velha sobrescreve a mais nova',
    pega: 'passo 11',
    de: '  if v_atual_id is not null and v_novo_id <= v_atual_id then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'aceita payload sem procedencia (perde a rastreabilidade)',
    pega: 'passo 14',
    de: '  if v_novo_id is null then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'so procedencia ja conta como conteudo',
    pega: 'passo 7',
    de: "  v_tem_algo := (p_contexto -> 'recepcao'",
    para: "  v_tem_algo := true or (p_contexto -> 'recepcao'",
  },
  {
    nome: 'selecao traz quem nao tem telefone',
    pega: 'passo 17',
    de: "     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null\n",
    para: '',
  },
  {
    nome: 'janela ignora a data (varredura cega)',
    pega: 'passos 18 e 19',
    de: '   where le.data_experimental between current_date and current_date + p_dias',
    para: '   where le.data_experimental >= current_date - 3650',
  },
  {
    nome: 'a gravacao fica exposta ao anon',
    pega: 'passo 21',
    de: 'revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon, authenticated;',
    para: '',
  },
  {
    // O campo `observacoes` e do Emusys, que o reescreve a cada webhook.
    // Escrever la faz a extracao sumir no proximo evento.
    nome: 'grava em observacoes (colide com o Emusys)',
    pega: 'passo 15',
    de: '     set contexto_ia    = p_contexto,\n         contexto_ia_em = now()',
    para: "     set observacoes    = p_contexto::text,\n         contexto_ia_em = now()",
  },
]

let previstos = 0
for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`AVISO  "${m.nome}" — ancora nao encontrada, mutante NAO aplicado`)
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try { execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' }) } catch { passou = false }
  if (!passou) { previstos++; console.log(`OK   morto: ${m.nome}  (${m.pega})`) }
  else console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
}
try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos`)
process.exitCode = previstos === MUTANTES.length ? 0 : 1
