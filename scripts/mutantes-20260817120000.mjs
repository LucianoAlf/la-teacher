#!/usr/bin/env node
// Mutacoes da RPC "resumo de aulas do professor" (consulta letiva, Fase 1).
//
// Roda num PostgreSQL Docker descartavel. O bootstrap monta a ARMADILHA de
// verdade: cada aula operacional tem DUAS linhas em aulas_emusys (aula_emusys_id
// e id de EVENTO), e um dos registros aponta pra linha PAR — o caso que o dado
// de producao NAO alcanca (na semana do Valdo o join ingenuo e o corrigido dao
// os mesmos 17, entao so o fixture prova a diferenca).
//
// O ensaio Docker usa o PREAMBULO do .test.sql + o bloco DOCKER-DML: as
// asercoes remotas dependem do dado de producao (Valdo = 36 aulas) e nao valem
// aqui. Exige baseline verde e cada mutante morrendo POR ASSERCAO.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql'
const TEST = 'supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql'
const IMAGE = process.env.MUTANTE_CONSULTA_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')

function extrairEntre(texto, inicio, fim, rotulo) {
  const a = texto.indexOf(inicio)
  const b = texto.indexOf(fim)
  if (a === -1 || b === -1) throw new Error(`${rotulo} nao encontrado no teste`)
  return texto.slice(a + inicio.length, b)
}

const preambulo = extrairEntre(teste, 'PREAMBULO-INICIO', 'PREAMBULO-FIM', 'preambulo')
const testeDocker = extrairEntre(
  teste, 'RESUMO-AULAS-DOCKER-DML-TESTS-INICIO', 'RESUMO-AULAS-DOCKER-DML-TESTS-FIM', 'bloco docker')

// Mundo minimo que a RPC le. `unidades`, `aulas_emusys`, `fabio_registros_aula`
// e o fn_aula_operacional_id — tudo fake, mas com a MESMA forma do real.
const bootstrap = `
-- Os roles do Supabase nao existem num postgres cru; a migration faz
-- revoke/grant neles.
do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end
$roles$;

create table public.unidades (id uuid primary key, nome text);
insert into public.unidades values
  ('11111111-1111-1111-1111-111111111111','Campo Grande'),
  ('22222222-2222-2222-2222-222222222222','Recreio');

create table public.aulas_emusys (
  id integer primary key,
  professor_id integer,
  unidade_id uuid,
  data_aula date,
  cancelada boolean default false
);
-- A ARMADILHA: cada aula operacional tem DUAS linhas (id de evento).
-- 4 operacionais vivas (3 Campo Grande + 1 Recreio) = 8 linhas cruas,
-- + 1 operacional cancelada (2 linhas) que NAO pode entrar na conta.
insert into public.aulas_emusys values
  (1,36,'11111111-1111-1111-1111-111111111111',date '2026-08-11',false),
  (2,36,'11111111-1111-1111-1111-111111111111',date '2026-08-11',false),
  (3,36,'11111111-1111-1111-1111-111111111111',date '2026-08-12',false),
  (4,36,'11111111-1111-1111-1111-111111111111',date '2026-08-12',false),
  (5,36,'11111111-1111-1111-1111-111111111111',date '2026-08-13',false),
  (6,36,'11111111-1111-1111-1111-111111111111',date '2026-08-13',false),
  (7,36,'22222222-2222-2222-2222-222222222222',date '2026-08-14',false),
  (8,36,'22222222-2222-2222-2222-222222222222',date '2026-08-14',false),
  (9,36,'11111111-1111-1111-1111-111111111111',date '2026-08-15',true),
  (10,36,'11111111-1111-1111-1111-111111111111',date '2026-08-15',true);

-- Colapsa o par: id impar e o operacional; o par aponta pro impar anterior.
create or replace function public.fn_aula_operacional_id(p_aula_id integer)
returns integer language sql stable as $f$
  select case when p_aula_id % 2 = 0 then p_aula_id - 1 else p_aula_id end
$f$;

create table public.fabio_registros_aula (
  id serial primary key,
  aula_id integer,
  parent_id integer,
  status text,
  professor_id integer
);
insert into public.fabio_registros_aula (aula_id, parent_id, status, professor_id) values
  (1, null, 'gravado_emusys', 36),
  (3, null, 'confirmado', 36),
  (5, null, 'rascunho', 36),
  -- O registro que aponta pra linha de EVENTO (id par), nao pro operacional.
  -- Existe de verdade: 2 de 149 troncos em 60 dias. Sem esta linha o fixture
  -- nao alcanca o caso e o mutante do join ingenuo passaria por morto.
  (8, null, 'gravado_emusys', 36);
`

const mutantes = [
  {
    // Conta linha crua: 8 em vez de 4. E o defeito que devolveria 74 pro Valdo.
    nome: 'conta linha crua (some o fn_aula_operacional_id da agenda)',
    ancora: `        coalesce(public.fn_aula_operacional_id(ae.id), ae.id) as aula_op,`,
    substituicao: `        ae.id as aula_op,`,
  },
  {
    // Aula cancelada entra na conta: 5 em vez de 4.
    nome: 'inclui aula cancelada na contagem',
    ancora: `        and coalesce(ae.cancelada, false) = false\n`,
    substituicao: '',
  },
  {
    // Sem o distinct, o colapso nao dedupe: volta a contar as duas linhas.
    nome: 'remove o distinct (o colapso deixa de deduplicar)',
    ancora: `      select distinct\n`,
    substituicao: `      select\n`,
  },
  {
    // Rascunho passa a contar como registrada: 4 em vez de 3.
    nome: 'qualquer status conta como registrada (rascunho entra)',
    ancora: `                  and r.status in ('confirmado', 'gravado_emusys')`,
    substituicao: `                  and r.status is not null`,
  },
  {
    // Vaza aula de outro professor.
    nome: 'remove o filtro por professor (vaza agenda de outro)',
    ancora: `      where ae.professor_id = p_professor_id\n`,
    substituicao: `      where (ae.professor_id = p_professor_id or true)\n`,
  },
  {
    // O recorte por unidade para de recortar.
    nome: 'recorte por unidade deixa de recortar',
    ancora: `        and (p_unidade is null or u.nome ilike p_unidade)`,
    substituicao: `        and true`,
  },
  {
    // A FRONTEIRA DO FINANCEIRO: injeta coluna financeira no retorno.
    // Morre no passo de catalogo (o corpo passa a conter 'valor_').
    nome: 'injeta coluna financeira no retorno (fronteira do financeiro)',
    ancora: `      'total_aulas', count(*),`,
    substituicao: `      'total_aulas', count(*),\n      'valor_hora_aula', 120,`,
  },
  {
    // O JOIN INGENUO: o registro que aponta pra linha de evento some.
    // 3 registradas viram 2. Este e o mutante que o Alf pediu.
    nome: 'join ingenuo no registro (o tronco no id de evento some)',
    ancora: `                where coalesce(public.fn_aula_operacional_id(r.aula_id), r.aula_id) = b.aula_op`,
    substituicao: `                where r.aula_id = b.aula_op`,
  },
]

function executar(args, input) {
  return spawnSync('docker', args, {
    cwd: process.cwd(),
    encoding: 'utf8',
    input,
    maxBuffer: 4 * 1024 * 1024,
  })
}

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function mutar(mutante) {
  const ocorrencias = contar(fonte, mutante.ancora)
  if (ocorrencias !== 1) {
    throw new Error(`${mutante.nome}: ancora apareceu ${ocorrencias} vez(es)`)
  }
  return fonte.replace(mutante.ancora, mutante.substituicao)
}

function esperarPronto(container) {
  for (let tentativa = 0; tentativa < 40; tentativa += 1) {
    const pronto = executar([
      'exec', container, 'pg_isready', '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'postgres',
    ])
    if (pronto.status === 0) return
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 250)
  }
  throw new Error('PostgreSQL descartavel nao ficou pronto por TCP')
}

function executarEnsaio(container, migration) {
  const sql = `begin;\n${migration}\n${preambulo}\n${testeDocker}\nrollback;`
  const resultado = executar([
    'exec', '-i', container,
    'psql', '-h', '127.0.0.1', '-p', '5432', '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-U', 'postgres', '-d', 'postgres',
  ], sql)
  const saida = `${resultado.stdout ?? ''}${resultado.stderr ?? ''}`.trim()
  const linhaResumo = saida.split(/\r?\n/u).reverse().find((linha) => linha.includes('"falhas"'))
  let resumo = null
  try {
    resumo = linhaResumo ? JSON.parse(linhaResumo) : null
  } catch {
    resumo = null
  }
  return { codigo: resultado.status, erro: resultado.error?.message ?? null, resumo, saida }
}

function mostrarFalha(nome, resultado) {
  console.log(`FALHA  ${nome}`)
  if (resultado.erro) console.log(`       executor: ${resultado.erro}`)
  if (resultado.saida) console.log(resultado.saida)
}

const container = `la-teacher-consulta-aulas-mutantes-${process.pid}-${Date.now()}`
let iniciado = false
let mortos = 0
let invalido = false

try {
  const inicio = executar([
    'run', '--rm', '--detach', '--name', container,
    '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', IMAGE,
  ])
  if (inicio.status !== 0) {
    throw new Error(inicio.error?.message ?? inicio.stderr ?? 'docker run falhou')
  }
  iniciado = true
  esperarPronto(container)

  const pronto = executar([
    'exec', '-i', container,
    'psql', '-h', '127.0.0.1', '-p', '5432', '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-U', 'postgres', '-d', 'postgres',
  ], bootstrap)
  if (pronto.status !== 0) {
    throw new Error(pronto.error?.message ?? pronto.stderr ?? 'bootstrap local falhou')
  }

  const baseline = executarEnsaio(container, fonte)
  if (baseline.codigo !== 0 || baseline.resumo?.falhas !== 0) {
    mostrarFalha('baseline deveria estar verde', baseline)
    invalido = true
  } else {
    console.log('OK     baseline verde')
  }

  if (!invalido) {
    for (const mutante of mutantes) {
      let resultado
      try {
        resultado = executarEnsaio(container, mutar(mutante))
      } catch (erro) {
        console.log(`FALHA  ${mutante.nome}: ${erro.message}`)
        invalido = true
        continue
      }
      if (resultado.codigo === 0 && resultado.resumo?.falhas > 0) {
        mortos += 1
        console.log(`OK     morto: ${mutante.nome}`)
      } else {
        mostrarFalha(`sobreviveu ou ensaio invalido: ${mutante.nome}`, resultado)
        invalido = true
      }
    }
  }
} catch (erro) {
  console.log(`FALHA  ambiente local: ${erro.message}`)
  invalido = true
} finally {
  if (iniciado) executar(['rm', '--force', container])
}

console.log(`\n${mortos}/${mutantes.length} mutantes mortos`)
process.exit(invalido || mortos !== mutantes.length ? 1 : 0)
