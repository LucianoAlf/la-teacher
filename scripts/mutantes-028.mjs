import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/028-fabio-le-contexto-experimental.sql'
const TESTE = 'supabase/migrations/028-fabio-le-contexto-experimental.test.sql'
const TEMP = 'supabase/migrations/_mutante-028.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O `||` faz o JSON cru entrar por baixo da lista de permissao: dinheiro e
    // recado interno atravessam. Nao inventa coluna nova nem quebra a sintaxe --
    // um mutante que morre por erro de SQL nao prova que o teste ve o vazamento.
    nome: 'a view devolve o JSON cru (dinheiro atravessa)',
    pega: 'passos 7 e 8',
    de: '        jsonb_strip_nulls(jsonb_build_object(',
    para: '        jsonb_strip_nulls(le.contexto_ia || jsonb_build_object(',
  },
  {
    nome: 'o PORQUE do sinal de conversao passa (expoe o preco)',
    pega: 'passo 9',
    de: "            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao'),",
    para:
      "            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao',\n" +
      "            'porque', le.contexto_ia -> 'para_a_devolutiva' ->> 'porque'),",
  },
  {
    // O alerta e o unico objeto escrito por LLM que chega inteiro se ninguem
    // listar campo a campo.
    nome: 'alerta passa cru (chave inventada pelo LLM atravessa)',
    pega: 'passo 12',
    de:
      "          'alertas', (select jsonb_agg(jsonb_build_object('tipo',  al ->> 'tipo',\n" +
      "                                                          'texto', al ->> 'texto'))\n" +
      '                        from jsonb_array_elements(\n' +
      "                               case when jsonb_typeof(le.contexto_ia -> 'alertas') = 'array'\n" +
      "                                    then le.contexto_ia -> 'alertas'\n" +
      "                                    else '[]'::jsonb end) as al),",
    para: "          'alertas', le.contexto_ia -> 'alertas',",
  },
  {
    // A observacao da Isadora diz "6 meses" desde nov/2025. Ler idade do texto e
    // responder a idade de um ano atras.
    nome: 'idade lida do texto em vez de calculada da data',
    pega: 'passo 13',
    de:
      "        case when public.fn_texto_para_data(le.contexto_ia -> 'recepcao' ->> 'data_nascimento') is not null\n" +
      '             then extract(year from age(current_date,\n' +
      "                    public.fn_texto_para_data(le.contexto_ia -> 'recepcao' ->> 'data_nascimento')))::integer\n" +
      '        end                       as idade,',
    para: "        (le.contexto_ia -> 'recepcao' ->> 'idade_declarada')::text::integer as idade,",
  },
  {
    // Cast cru numa VIEW nao estraga so a linha suja: derruba a consulta inteira,
    // e ninguem mais tem contexto.
    nome: 'cast cru da data (uma linha suja derruba a view toda)',
    pega: 'passos 14 e 15',
    de: "        case when public.fn_texto_para_data(le.contexto_ia -> 'recepcao' ->> 'data_nascimento') is not null",
    para: "        case when (le.contexto_ia -> 'recepcao' ->> 'data_nascimento')::date is not null",
  },
  {
    nome: 'join por lead_experimentais.aluno_id (perde 238 de 319)',
    pega: 'passos 1 a 6',
    de: '   join leads l on l.id = le.lead_id',
    para: '   join leads l on l.id = le.lead_id and le.aluno_id is not null',
  },
  {
    nome: 'prontuario nao devolve o bloco experimental',
    pega: 'passo 16',
    de: "      || jsonb_build_object('experimental', coalesce(v_experimental, '{}'::jsonb));",
    para: ';',
  },
  {
    // O vazamento silencioso: o contexto de uma familia chega no prontuario de
    // outra, e o professor nao tem como saber que aquilo nao e do aluno dele.
    nome: 'o bloco experimental ignora de quem e o aluno',
    pega: 'passo 22',
    de: '     where e.aluno_id = p_aluno_id',
    para: '     where true',
  },
  {
    // Revogar so de `public` nao alcanca anon nem authenticated: o
    // ALTER DEFAULT PRIVILEGES do projeto concede SELECT aos dois diretamente.
    nome: 'a view fica exposta ao anon e ao authenticated',
    pega: 'passos 23 e 24',
    de: 'revoke all on table public.vw_fabio_contexto_experimental from public, anon, authenticated;',
    // GRANT ativo pelo mesmo motivo da 027: `create or replace view` preserva
    // privilegio, e omitir o revoke nao muda nada depois de aplicada.
    para: 'grant select on table public.vw_fabio_contexto_experimental to anon, authenticated;',
  },
  {
    nome: 'contexto de aluno alheio entra no prontuario',
    pega: 'passo 21 (defesa em 2 camadas — pode sobreviver)',
    esperaSobreviver: true,
    de: '  if v_cadastro is not null then',
    para: '  if true then',
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
  const previsto = m.esperaSobreviver ? passou : !passou
  if (previsto) {
    previstos++
    console.log(`OK   ${m.esperaSobreviver ? 'sobreviveu como previsto' : 'morto'}: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  ${m.esperaSobreviver ? 'MORREU e devia sobreviver' : 'SOBREVIVEU'}: ${m.nome}  (${m.pega})`)
  }
}
try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes com o resultado previsto`)
process.exitCode = previstos === MUTANTES.length ? 0 : 1
