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
    // A recencia mora no WHERE do UPDATE justamente para nao ter janela entre
    // ler e escrever. Tirar a condicao devolve a regressao do contexto.
    nome: 'leitura mais velha sobrescreve a mais nova',
    pega: 'passo 16',
    de:
      '   where id = p_lead_experimental_id\n' +
      "     and (public.fn_texto_para_bigint(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id') is null\n" +
      "          or public.fn_texto_para_bigint(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id') < v_novo_id);",
    para: '   where id = p_lead_experimental_id;',
  },
  {
    // Passo 20 e nao 19: na linha que JA tem contexto, a guarda de recencia
    // recusaria o payload de qualquer jeito e este mutante sobrevivia. So a
    // linha virgem isola a guarda de procedencia.
    nome: 'aceita payload sem procedencia (perde a rastreabilidade)',
    pega: 'passo 20',
    de: '  if v_novo_id is null then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'so procedencia ja conta como conteudo',
    pega: 'passo 7',
    de: '  v_tem_algo := coalesce(',
    para: '  v_tem_algo := true or coalesce(',
  },
  {
    // O esqueleto do schema com objetos vazios -- o modo de falha mais provavel
    // de um LLM. Contar a chave em vez do conteudo apagava extracao boa.
    nome: 'esqueleto de objetos vazios conta como conteudo',
    pega: 'passo 9',
    de: '    else (select count(*) > 0',
    para: '    else (select count(*) >= 0',
  },
  {
    // Um nivel mais fundo: chaves internas presentes, valores null/vazios.
    nome: 'campos null/vazios contam como conteudo',
    pega: 'passo 11',
    de:
      "           where jsonb_typeof(e.valor) <> 'null'\n" +
      "             and e.valor <> '\"\"'::jsonb\n" +
      "             and e.valor <> '{}'::jsonb\n" +
      "             and e.valor <> '[]'::jsonb)",
    para: ')',
  },
  {
    nome: 'selecao traz quem nao tem telefone',
    pega: 'passo 25',
    de: "     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null\n",
    para: '',
  },
  {
    nome: 'janela ignora a data (varredura cega)',
    pega: 'passos 26 e 27',
    de: '   where le.data_experimental between current_date and current_date + p_dias',
    para: '   where le.data_experimental >= current_date - 3650',
  },
  {
    // Se extraido_ate_id volta sempre NULL a edge function rele a conversa
    // inteira toda rodada, para sempre. Nao ha erro, so desperdicio silencioso.
    nome: 'extraido_ate_id volta sempre null (releitura integral eterna)',
    pega: 'passo 30',
    de: "         public.fn_texto_para_bigint(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id')",
    para: '         null::bigint',
  },
  {
    // Uma unica linha com lixo em contexto_ia derrubava a selecao inteira.
    nome: 'cast cru na selecao (uma linha suja derruba todo mundo)',
    pega: 'passo 24',
    de: "         public.fn_texto_para_bigint(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id')",
    para: "         nullif(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint",
  },
  {
    // `returns boolean` que levanta excecao quebrou o contrato com a edge function.
    nome: 'cast cru na gravacao (id nao-numerico levanta excecao)',
    pega: 'passo 22',
    de: "  v_novo_id := public.fn_texto_para_bigint(p_contexto -> 'procedencia' ->> 'ultima_mensagem_id');",
    para: "  v_novo_id := nullif(p_contexto -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint;",
  },
  {
    nome: 'a gravacao fica exposta ao anon',
    pega: 'passo 36',
    de: 'revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon, authenticated;',
    para: '',
  },
  {
    // O Supabase concede EXECUTE explicitamente a anon, authenticated e
    // service_role por default -- revogar de `public` nao alcanca nenhum deles.
    // Conferir so o anon deixava este mutante passar.
    nome: 'a gravacao fica exposta ao authenticated',
    pega: 'passo 38',
    de: 'revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon, authenticated;',
    para: 'revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon;',
  },
  {
    // O campo `observacoes` e do Emusys, que o reescreve a cada webhook.
    // Escrever la faz a extracao sumir no proximo evento.
    nome: 'grava em observacoes (colide com o Emusys)',
    pega: 'passo 23',
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
